#!/usr/bin/env node
// Headless wallet generation for the local RAILGUN demo, reusing the terminal
// wallet's own compiled modules (dist/) so the new wallet lands in the same
// keychain the TUI reads. Run via scripts/tw-create-wallet.sh (cd's into the
// durable cache so .railgun.db / .zKeyChains resolve correctly).
//
// Prints: wallet name, public 0x address, 0zk (railgun) address, and the
// mnemonic (shown once — back it up; the seed is never stored in plaintext).
'use strict';
const path = require('node:path');

const TW_SRC = path.resolve(__dirname, '..', 'railgun-cache', 'tw-src');
process.chdir(TW_SRC);

const { HDNodeWallet, Mnemonic } = require(path.join(TW_SRC, 'node_modules/ethers'));

const { setInputProvider } = require(path.join(TW_SRC, 'dist/core/input.js'));
const { initRailgunEngine } = require(path.join(TW_SRC, 'dist/railgun/engine/engine.js'));
const {
  initializeKeychainSystem,
  initilizeFreshWallet,
} = require(path.join(TW_SRC, 'dist/railgun/wallet/wallet-init.js'));
const {
  getCurrentWalletPublicAddress,
  getCurrentRailgunAddress,
  getCurrentWalletName,
} = require(path.join(TW_SRC, 'dist/railgun/wallet/wallet-util.js'));
const { walletManager } = require(path.join(TW_SRC, 'dist/railgun/wallet/wallet-manager.js'));
const { saveKeychainFile } = require(path.join(TW_SRC, 'dist/railgun/wallet/wallet-cache.js'));
const { setRemoteConfig } = require(path.join(TW_SRC, 'dist/railgun/network/network-util.js'));
const { fallbackRemoteConfig } = require(path.join(TW_SRC, 'dist/config/config-overrides.js'));
const configDefaults = require(path.join(TW_SRC, 'dist/config/config-defaults.js')).default;
const { NetworkName } = require(path.join(
  TW_SRC,
  'node_modules/@railgun-community/shared-models',
));

const PASSWORD = process.env.TW_PASSWORD || '';
if (PASSWORD.length < 8) {
  console.error(
    'TW_PASSWORD is required (min 8 chars). Use the same password the terminal wallet uses.',
  );
  process.exit(1);
}
const walletName = (process.argv[2] || '').trim() || 'wallet';
const importMnemonic = (process.env.TW_MNEMONIC || '').trim();

let generatedMnemonic = '';
const provider = {
  async promptPassword() {
    return PASSWORD;
  },
  async promptNewWallet() {
    let mnemonic;
    if (importMnemonic) {
      if (!Mnemonic.isValidMnemonic(importMnemonic)) {
        throw new Error('TW_MNEMONIC is not a valid mnemonic');
      }
      mnemonic = importMnemonic;
    } else {
      mnemonic = HDNodeWallet.createRandom().mnemonic.phrase;
    }
    generatedMnemonic = mnemonic;
    return { mnemonic, walletName, derivationIndex: 0 };
  },
  async promptRpcEndpoints() {
    return undefined;
  },
  async confirm() {
    return true;
  },
  notify(message) {
    console.error(`[tw-create-wallet] ${message}`);
  },
  async select() {
    return undefined;
  },
  async multiSelect() {
    return undefined;
  },
  async input() {
    return undefined;
  },
};
setInputProvider(provider);

(async () => {
  setRemoteConfig(fallbackRemoteConfig);
  await initRailgunEngine();
  walletManager.keyChain = await initializeKeychainSystem();
  walletManager.saltedPassword = walletManager.keyChain.salt;
  if (!walletManager.keyChain.wallets) {
    walletManager.keyChain.wallets = {};
  }
  const wallet = await initilizeFreshWallet(false);
  if (!wallet) {
    console.error('wallet creation failed');
    process.exit(1);
  }

  const publicAddress = HDNodeWallet.fromMnemonic(
    Mnemonic.fromPhrase(generatedMnemonic),
    "m/44'/60'/0'/0/0",
  ).address;
  walletManager.keyChain.wallets[walletName].publicAddress = publicAddress;
  // Boot the TUI straight onto the local chain: without this the keychain has
  // no currentNetwork, the wallet opens on Ethereum, and the funded balance on
  // anvil is invisible until the user manually switches network.
  walletManager.keyChain.currentNetwork = NetworkName.Hardhat;
  saveKeychainFile(walletManager.keyChain, configDefaults.engine.keyChainPath);

  console.log(`name:    ${getCurrentWalletName()}`);
  console.log(`public:  ${getCurrentWalletPublicAddress()}`);
  console.log(`0zk:     ${getCurrentRailgunAddress()}`);
  console.log(`mnemonic:${generatedMnemonic}`);
  process.exit(0);
})().catch((err) => {
  console.error(`failed: ${err && err.message ? err.message : err}`);
  process.exit(1);
});
