const ExampleToken = artifacts.require('ExampleToken');

module.exports = async function (deployer) {
  await deployer.deploy(ExampleToken,'ExampleToken', 'EXT', '100000000000');
  const token = await ExampleToken.deployed();           
};
