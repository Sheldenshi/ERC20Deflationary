const ExampleToken = artifacts.require("ExampleToken");

module.exports = async function (deployer) {
  await deployer.deploy(ExampleToken);
};
