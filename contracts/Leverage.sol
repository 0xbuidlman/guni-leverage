// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import "./interfaces/VatLike.sol";
import "./interfaces/UniPoolLike.sol";
import "./interfaces/SpotLike.sol";
import "./interfaces/GUNITokenLike.sol";
import "./interfaces/GUNIRouterLike.sol";
import "./interfaces/GUNIResolverLike.sol";
import "./interfaces/GemJoinLike.sol";
import "./interfaces/DaiJoinLike.sol";
import "./interfaces/CurveSwapLike.sol";
import "./interfaces/IERC20Ext.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Leverage is IERC3156FlashBorrower, Initializable {

    uint256 constant RAY = 10 ** 27;

    enum Action {WIND, UNWIND}

    VatLike public  vat;
    bytes32 public  ilk;
    GemJoinLike public  join;
    DaiJoinLike public  daiJoin;
    SpotLike public  spotter;
    GUNITokenLike public  guni;
    IERC20Ext public  dai;
    IERC20Ext public  otherToken;
    IERC3156FlashLender public  lender;
    CurveSwapLike public  curve;
    GUNIRouterLike public  router;
    GUNIResolverLike public  resolver;
    int128 public  curveIndexDai;
    int128 public  curveIndexOtherToken;
    uint256 public  otherTokenTo18Conversion;
    
    /// @notice инициализация прокси, вызвать после создания прокси-контракта
    function initialize(
        GemJoinLike _join,
        DaiJoinLike _daiJoin,
        SpotLike _spotter,
        IERC20Ext _otherToken,
        IERC3156FlashLender _lender,
        CurveSwapLike _curve,
        GUNIRouterLike _router,
        GUNIResolverLike _resolver, 
        int128 _curveIndexDai,
        int128 _curveIndexOtherToken
    ) external initializer {
        vat = VatLike(_join.vat()); // адрес Vat Core
        ilk = _join.ilk(); //тип залога, в данном случае, получаем из Gem G-UNI Pool. Gem это адаптер для DAI Модуль, в котором находятся активы незаблокированные Vault, и которые могут использваться в качестве залога
        join = _join; // адаптер для залога, в терминологии MakerDAO, Gem
        daiJoin = _daiJoin; // адрес DAI модуля, через который происходит выпуск и погашение DAI
        spotter = _spotter; // адрес с spotter модуля, через который получаем информация с оракула, rate и spot price
        guni = GUNITokenLike(_join.gem()); //адрес G-UNI LP токена
        dai = IERC20Ext(_daiJoin.dai()); //адрес DAI
        otherToken = _otherToken; //адрес USDC
        lender = _lender; //адрес модуля Flash Mint
        curve = _curve; //адрес пула Curve, 3-pool
        router = _router; //router UniSwap V3
        resolver = _resolver; //resolver для G-UNI
        curveIndexDai = _curveIndexDai; //индекс актива DAI в пуле Curve
        curveIndexOtherToken = _curveIndexOtherToken; //индекс актива USDC в пуле Curve
        otherTokenTo18Conversion = 10 ** (18 - _otherToken.decimals()); //так USDC имеет точность 6 знаков, а DAI 18, то получаем параметра для нормализации вычислений.
        
        VatLike(_join.vat()).hope(address(_daiJoin));
    }


    /// @notice получить данные для открытия позиции
    /// @param usr адрес пользователя
    /// @param principal сумма на балансе

    /// @dev вернет
    ///  estimatedDaiRemaining - сумма которая останется на баланса после открытия позиции
    ///  estimatedGuniAmount - сумма G-UNI полученная в процессе открытия позиции
    ///  estimatedDebt - примерная в DAI к погашению Vault, иными словами долг.
    function getWindEstimates(address usr, uint256 principal) public view returns (uint256 estimatedDaiRemaining, uint256 estimatedGuniAmount, uint256 estimatedDebt) {
        uint256 leveragedAmount;
        {
            (,uint256 mat) = spotter.ilks(ilk);
            leveragedAmount = principal*RAY/(mat - RAY); //размер полученного через FlashMint заема
        }

        uint256 swapAmount;
        {
            (uint256 sqrtPriceX96,,,,,,) = UniPoolLike(guni.pool()).slot0();
            (, swapAmount) = resolver.getRebalanceParams(
                address(guni),
                guni.token0() == address(dai) ? leveragedAmount : 0,
                guni.token1() == address(dai) ? leveragedAmount : 0,
                ((((sqrtPriceX96*sqrtPriceX96) >> 96) * 1e18) >> 96) * otherTokenTo18Conversion
            );
        }


        /// получаем параметры G-UNI
        uint256 daiBalance;
        {
            (,, estimatedGuniAmount) = guni.getMintAmounts(guni.token0() == address(dai) ? leveragedAmount - swapAmount : curve.get_dy(curveIndexDai, curveIndexOtherToken, swapAmount), guni.token1() == address(otherToken) ? curve.get_dy(curveIndexDai, curveIndexOtherToken, swapAmount) : leveragedAmount - swapAmount);
            (,uint256 rate, uint256 spot,,) = vat.ilks(ilk);
            (uint256 ink, uint256 art) = vat.urns(ilk, usr);
            estimatedDebt = ((estimatedGuniAmount + ink) * spot / rate - art) * rate / RAY;
            daiBalance = dai.balanceOf(usr);
        }


        /// Проверяем достаточно ли DAI к погашению Flash Mint для открытия позиции

        require(leveragedAmount <= estimatedDebt + daiBalance, "not-enough-dai");

        estimatedDaiRemaining = estimatedDebt + daiBalance - leveragedAmount;
    }


    /// @notice получить данные для закрытия позиции в зависимости от суммы залога и непогашенной задолженности Vault
    /// @param ink - залог на балансе Vault
    /// @param art - непогашенная задолженность

    /// @dev  estimatedDaiRemaining потенциальный профит
    function getUnwindEstimates(uint256 ink, uint256 art) public view returns (uint256 estimatedDaiRemaining) {
        (,uint256 rate,,,) = vat.ilks(ilk);
        (uint256 bal0, uint256 bal1) = guni.getUnderlyingBalances();
        uint256 totalSupply = guni.totalSupply();
        bal0 = bal0 * ink / totalSupply;
        bal1 = bal1 * ink / totalSupply;
        uint256 dy = curve.get_dy(curveIndexOtherToken, curveIndexDai, guni.token0() == address(dai) ? bal1 : bal0);

        return (guni.token0() == address(dai) ? bal0 : bal1) + dy - art * rate / RAY;
    }

    /// @notice получить данные для закрытия позиции  для конкретного пользователя
    /// @param usr адрес пользователя
    /// @dev  estimatedDaiRemaining потенциальный профит
    function getUnwindEstimates(address usr) external view returns (uint256 estimatedDaiRemaining) {
        (uint256 ink, uint256 art) = vat.urns(ilk, usr);
        return getUnwindEstimates(ink, art);
    }


    /// @notice получить размер плеча исходя из текущих параметров
    function getLeverageBPS() external view returns (uint256) {
        (,uint256 mat) = spotter.ilks(ilk);
        return 10000 * RAY/(mat - RAY);
    }


    /// @notice получить сколько DAI будет на балансе пользователя после открытия и закрытия позиции
    /// @param usr адрес пользователя
    /// @param principal баланс относительно которого выдаем плечо
    function getEstimatedCostToWindUnwind(address usr, uint256 principal) external view returns (uint256) {
        (, uint256 estimatedGuniAmount, uint256 estimatedDebt) = getWindEstimates(usr, principal);
        (,uint256 rate,,,) = vat.ilks(ilk);
        return dai.balanceOf(usr) - getUnwindEstimates(estimatedGuniAmount, estimatedDebt * RAY / rate);
    }


    /// @notice открытие позиции
    /// @param principal баланс пользователя, относительно которого строим плечо (leverage)
    /// @param minWalletDai минимальная сумма, которая должна остаться на кошельке пользователя после открытия позиции. Своебразный slippage control.
    function wind(
        uint256 principal,
        uint256 minWalletDai
    ) external {
        bytes memory data = abi.encode(Action.WIND, msg.sender, minWalletDai);
        (,uint256 mat) = spotter.ilks(ilk); //получаем liquidation ratio для типа залога ilk, в нашем случае G-UNI
        initFlashLoan(data, principal*RAY/(mat - RAY)); //плечо берем относительно liquidation ratio
    }


    /// @notice закрытие позиции
    function unwind(
        uint256 minWalletDai // минимальная сумма, которая должна остаться на кошельке пользователя после открытия позиции. Своебразный slippage control.
    ) external {
        bytes memory data = abi.encode(Action.UNWIND, msg.sender, minWalletDai);
        (,uint256 rate,,,) = vat.ilks(ilk); //получаем rate, это мультипликатор долга с учетем stability fees MCD
        (, uint256 art) = vat.urns(ilk, msg.sender); //urns это конкретрный vault, а art это непогашенная задолженность. Задолженность это DAI, которые надо вернуть, чтобы вернуть залог.
        initFlashLoan(data, art*rate/RAY); //необходимую сумму для flash mint, расчитываем исходя из суммы конечной задолженности MCD Vault с учетом stability fees.
    }


    ///@notice запрашивает у Flash Mint модуля необходимую сумму DAI
    function initFlashLoan(bytes memory data, uint256 amount) internal {
        uint256 _allowance = dai.allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(address(dai), amount);
        uint256 _repayment = amount + _fee;
        dai.approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, address(dai), amount, data);
    }


    ///@notice это callback, который вызывает Flash Mint модуль, после получения запроса на Flash Mint
    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );

        // в зависимости от параметров закрытие/открытие позиции производим определенные действия.
        (Action action, address usr, uint256 minWalletDai) = abi.decode(data, (Action, address, uint256));
        if (action == Action.WIND) {
            // открытие позиции 
            _wind(usr, amount + fee, minWalletDai);
        } else if (action == Action.UNWIND) {
            // закрытие позиции
            _unwind(usr, amount, fee, minWalletDai);
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @notice открытие позиции
    /// @param  usr это адрес владельца Vault
    /// @param minWalletDai минимальная сумма, которая должна остаться на кошельке пользователя после открытия позиции. Своебразный slippage control.
    function _wind(address usr, uint256 totalOwed, uint256 minWalletDai) internal {
        // через G-UNI пул получаем расчет параметров, сколько нужно обменять DAI на USDC, чтобы пул G-UNI был сбалансированный
        uint256 swapAmount;
        {
            (uint256 sqrtPriceX96,,,,,,) = UniPoolLike(guni.pool()).slot0();
            (, swapAmount) = resolver.getRebalanceParams(
                address(guni),
                IERC20Ext(guni.token0()).balanceOf(address(this)),
                IERC20Ext(guni.token1()).balanceOf(address(this)),
                ((((sqrtPriceX96*sqrtPriceX96) >> 96) * 1e18) >> 96) * otherTokenTo18Conversion
            );
        }

        // Обмениваем через Curve, DAI на USDC
        dai.approve(address(curve), swapAmount);
        curve.exchange(curveIndexDai, curveIndexOtherToken, swapAmount, 0);

        // Добавляем ликвидность на G-UNI пул и получаем USDC
        uint256 guniBalance;
        {
            uint256 bal0 = IERC20Ext(guni.token0()).balanceOf(address(this));
            uint256 bal1 = IERC20Ext(guni.token1()).balanceOf(address(this));
            dai.approve(address(router), bal0);
            otherToken.approve(address(router), bal1);
            (,, guniBalance) = router.addLiquidity(address(guni), bal0, bal1, 0, 0, address(this));
            dai.approve(address(router), 0);
            otherToken.approve(address(router), 0);
        }

        // создаем или модифицируем Vault
        {   
            // даем соответвующие разрешение
            guni.approve(address(join), guniBalance);

            // заходим в Gem. Gem списываем определенное количества G-UNI токенов от имени пользователя
            join.join(address(usr), guniBalance);
            

            // получаем параметры rate, spot (цена по отношению к доллару) для данного типа залога
            (,uint256 rate, uint256 spot,,) = vat.ilks(ilk);
            (uint256 ink, uint256 art) = vat.urns(ilk, usr); //запришваем у MCD Vault, ink - баланс залога, art - непогашенная задолженность

            uint256 dart = (guniBalance + ink) * spot / rate - art; //вычитываем art непогашенную задолженность, так как dart суммируется с текущей задолженностью


            //модифицируем Vault

            // передаем параметры
            // ilk - типа залога
            //  следующие параметры означают, пользователь чей vault создаем/модифицируем, с баланса Gem пользователя списываем и передаем DAI на адрес контракта
            /// guniBalance - количество G-UNI которое блокируем    
            vat.frob(ilk, address(usr), address(usr), address(this), int256(guniBalance), int256(dart));
            
            ///забираем DAI на контракт
            daiJoin.exit(address(this), vat.dai(address(this)) / RAY);
        }

        /// получаем общий баланс DAI
        uint256 daiBalance = dai.balanceOf(address(this));

        /// если есть профит передаем пользователю
        if (daiBalance > totalOwed) {
            dai.transfer(usr, daiBalance - totalOwed);

        /// если нет списываем необходимую сумму, чтобы транзакция прошла успешно, иными словами погасить flash mint
        } else if (daiBalance < totalOwed) {
            dai.transferFrom(usr, address(this), totalOwed - daiBalance);
        }

        // если остались USDC передаем пользователю
        otherToken.transfer(usr, otherToken.balanceOf(address(this)));


        // простейший slippage контроль, на то чтобы на балансе пользователя оставалось минимальное количество DAI

        require(dai.balanceOf(address(usr)) + otherToken.balanceOf(address(this)) >= minWalletDai, "slippage");
    }


    /// @notice закрытие позиции
    /// @param amount сумма DAI к погашению
    /// @param fee комиссия за использование flash mint
    function _unwind(address usr, uint256 amount, uint256 fee, uint256 minWalletDai) internal {
        // Гасим CDP и забираем G-UNI
        (uint256 ink, uint256 art) = vat.urns(ilk, usr);

        dai.approve(address(daiJoin), amount);

        /// переводим DAI в DAI Pool
        daiJoin.join(address(this), amount);


        /// меняем Vault, гасим задолженность и залог
        vat.frob(ilk, address(usr), address(this), address(this), -int256(ink), -int256(art));

        /// выходим из Gem и забираем залог в  G-UNI
        join.exit(address(this), ink);

        // Сжигаем G-UNI и забраем ликвидность
        guni.approve(address(router), ink);
        router.removeLiquidity(address(guni), ink, 0, 0, address(this));

        // Меняем USDC на DAI
        uint256 swapAmount = otherToken.balanceOf(address(this));
        otherToken.approve(address(curve), swapAmount);
        curve.exchange(curveIndexOtherToken, curveIndexDai, swapAmount, 0);

        uint256 daiBalance = dai.balanceOf(address(this));
        uint256 totalOwed = amount + fee;

        /// профит отдаем пользователю
        if (daiBalance > totalOwed) {
            // Send extra dai to user
            dai.transfer(usr, daiBalance - totalOwed);
        } else if (daiBalance < totalOwed) {
            ///если профита нет, чтобы погасить заем списываем с баланса пользователя
            dai.transferFrom(usr, address(this), totalOwed - daiBalance);
        }

        // пересылаем оставшийся DAI на баланс пользователя
        otherToken.transfer(usr, otherToken.balanceOf(address(this)));

        // простейший slippage контроль, на то чтобы на балансе пользователя оставалось минимальное количество DAI
        require(dai.balanceOf(address(usr)) + otherToken.balanceOf(address(this)) >= minWalletDai, "slippage");
    }
}
