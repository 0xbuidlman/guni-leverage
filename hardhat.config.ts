import "hardhat-typechain"
import "@nomiclabs/hardhat-waffle"
import "hardhat-contract-sizer"
import "hardhat-abi-exporter"
import "hardhat-gas-reporter"
import * as dotenv from "dotenv";
import { HardhatUserConfig } from "hardhat/types"


dotenv.config()

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.FORK_ARCHIVE_RPC_URL
      }
    }
  },

  abiExporter: {
    path: "./abi",
    clear: false,
    flat: true,
    // only: [],
    // except: []
  },
  gasReporter: {
    coinmarketcap: '',
    currency: "ETH",
  },
  defaultNetwork: "hardhat",
  mocha: {
    timeout: 100000,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  typechain: {
    outDir: "src/types",
    target: "ethers-v5",
  }
}

export default config
