'use strict';

const ESTile = artifacts.require("ESTile");
const ESTilePack = artifacts.require("ESTilePack");
const ESTileWrapper = artifacts.require("ESTileWrapper");
const NamingContract = artifacts.require("NamingContract");
const EscapeToken = artifacts.require("EscapeToken");

global.artifacts = artifacts;
global.web3 = web3;

async function main() {
    const newtworkType = await web3.eth.net.getNetworkType();
    const networkId = await web3.eth.net.getId();
    console.log("network type:"+newtworkType);
    console.log("network id:"+networkId);

    const tilePack = await ESTilePack.deployed();
    const tile = await ESTile.deployed();
    const escape = await EscapeToken.deployed();
    const wrapper = await ESTileWrapper.deployed();
  
    console.log("ESTile        = ", tile.address);
    console.log("ESTilePack    = ", tilePack.address);
    console.log("EscapeToken   = ", escape.address);
    console.log("ESTileWrapper = ", wrapper.address);

    // await tilePack.mint("0xD4F8fdD249ba41323880CefECEBca2Ab590D571F", 1, 10, "0x0");
    // console.log("Done minting...");

    await tile.mint("0xD4F8fdD249ba41323880CefECEBca2Ab590D571F", 4, 1, "0x0");
    console.log("Done minting...");
}

// For truffle exec
module.exports = function(callback) {
    main().then(() => callback()).catch(err => callback(err))
};