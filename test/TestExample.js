// test/SimpleToken.test.js
// SPDX-License-Identifier: MIT

// Based on https://github.com/OpenZeppelin/openzeppelin-solidity/blob/v2.5.1/test/examples/SimpleToken.test.js

const { expect } = require('chai');

// Import utilities from Test Helpers
const { BN, expectEvent, expectRevert, constants } = require('@openzeppelin/test-helpers');

// Load compiled artifacts
const Example = artifacts.require('Example');

// Start test block
contract('Example', function ([ creator, other ]) {

  const NAME = 'Example Token';
  const SYMBOL = 'EXT';
  const TOTAL_SUPPLY = new BN('100000000000');

  beforeEach(async function () {
    this.token = await Example.new({ from: creator });
  });

  it('has a total supply', async function () {
    // Use large integer comparisons
    expect(await this.token.totalSupply()).to.be.bignumber.equal(TOTAL_SUPPLY);
  });

  it('has a name', async function () {
    expect(await this.token.name()).to.be.equal(NAME);
  });

  it('has a symbol', async function () {
    expect(await this.token.symbol()).to.be.equal(SYMBOL);
  });

  it('assigns the initial total supply to the creator', async function () {
    expect(await this.token.balanceOf(creator)).to.be.bignumber.equal(TOTAL_SUPPLY);
  });
});