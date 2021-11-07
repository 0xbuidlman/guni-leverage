import { ethers, network, waffle } from "hardhat";
import { expect } from "chai";
import { throws } from "assert";


const vat = ethers.utils.getAddress(process.env.VAT)
const pip = ethers.utils.getAddress(process.env.PIP)
const join = ethers.utils.getAddress(process.env.JOIN)
const daiJoin = ethers.utils.getAddress(process.env.DAI_JOIN)
const spotter = ethers.utils.getAddress(process.env.SPOTTER)
const otherToken = ethers.utils.getAddress(process.env.OTHER_TOKEN)
const lender = ethers.utils.getAddress(process.env.LENDER)
const curve = ethers.utils.getAddress(process.env.CURVE)
const router = ethers.utils.getAddress(process.env.ROUTER)
const resolver = ethers.utils.getAddress(process.env.RESOLVER)


const caller = ethers.utils.getAddress(process.env.CALLER)


describe("Leverage", function () {
    before(async function () {
        this.Proxy = await ethers.getContractFactory("LeverageProxy");
        this.ProxyAdmin = await ethers.getContractFactory("LeverageProxyAdmin");
        this.Leverage = await ethers.getContractFactory("Leverage");

        this.caller =  await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [caller],
        });

        this.caller = await ethers.getSigner(caller);

        this.owner = (await ethers.getSigners())[1];
    })

    beforeEach(async function () {
        // proxy admin
        this.proxyAdmin = await this.ProxyAdmin.deploy();
        this.leverageImpl = await this.Leverage.deploy();

        this.proxy = await this.Proxy.deploy(
            this.leverageImpl.address,
            this.proxyAdmin.address
        );

        this.leverage = await ethers.getContractAt("Leverage", this.proxy.address);
        
        this.vat = await ethers.getContractAt("VatLike", vat);
        
        this.daiJoin = await ethers.getContractAt("DaiJoinLike", daiJoin);

        this.dai = await ethers.getContractAt("IERC20", await this.daiJoin.dai())

        await this.leverage.initialize(
            join,
            daiJoin,
            spotter,
            otherToken,
            lender,
            curve,
            router,
            resolver,
            0,
            1
        )
    })

    it("should open position", async function () {
        const principal = ethers.utils.parseEther("4.356") //await this.dai.balanceOf(this.caller.address)

        await this.owner.sendTransaction({
            to: this.caller.address,
            value: ethers.utils.parseEther("10")
        });

        await this.vat.connect(this.caller).hope(this.leverage.address)
        await this.dai.connect(this.caller).approve(this.leverage.address, principal)
        await this.leverage.connect(this.caller).wind(principal, 0)

        //await this.leverage.connect(this.caller).unwind(0)
        await this.vat.connect(this.caller).nope(this.leverage.address)

        const estimates = await this.leverage.getWindEstimates(this.caller.address, principal)

        console.log(estimates)
    });
})