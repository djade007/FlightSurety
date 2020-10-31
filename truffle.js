var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "hip tumble supply ice amateur argue equal warm monster copy blast steak";

module.exports = {
    networks: {
        development: {
            provider: function () {
                return new HDWalletProvider(mnemonic, "http://127.0.0.1:8545/", 0, 50);
            },
            network_id: '*',
            gas: 9999999
        }
    },
    compilers: {
        solc: {
            version: "^0.4.24"
        }
    }
};
