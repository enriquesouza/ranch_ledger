const hre = require("hardhat");

async function main() {

  const bovine = await hre.ethers.deployContract("BovineTracking");

  await bovine.waitForDeployment();

  console.log(
    `Deployed to ${bovine.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
