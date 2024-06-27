const { ethers, run } = require("hardhat");

async function main() {
  const easAddressForBaseSepolia = "0x4200000000000000000000000000000000000021";
  const MyNouns = await hre.ethers.getContractFactory("MyNouns");
  console.log("Deploying MyNouns Contract...");
  const myNouns = await MyNouns.deploy({
    gasPrice: 30000000000,
  });
  await myNouns.waitForDeployment();
  const myNounsAddress = await myNouns.getAddress();
  console.log("MyNouns Contract Address:", myNounsAddress);
  console.log("----------------------------------------------------------");

  // Tokenized Noun
  const TokenizedNoun = await hre.ethers.getContractFactory("TokenizedNoun");
  console.log("Deploying TokenizedNoun Contract...");
  const tokenizedNoun = await TokenizedNoun.deploy(
    easAddressForBaseSepolia,
    myNounsAddress,
    {
      gasPrice: 33000000000,
    }
  );
  await tokenizedNoun.waitForDeployment();
  const tokenizedNounAddress = await tokenizedNoun.getAddress();
  console.log("Vault Contract Address:", tokenizedNounAddress);
  console.log("----------------------------------------------------------");

  // Fractional Noun
  const FractionalNoun = await hre.ethers.getContractFactory("FractionalNoun");
  console.log("Deploying FractionalNoun Contract...");
  const fractionalNoun = await FractionalNoun.deploy(tokenizedNounAddress, {
    gasPrice: 33000000000,
  });
  await fractionalNoun.waitForDeployment();
  const fractionalNounAddress = await fractionalNoun.getAddress();
  console.log("FractionalNoun Contract Address:", fractionalNounAddress);
  console.log("----------------------------------------------------------");

  // Update Fractional Noun Contract Address in Tokenized Contract

  console.log(
    "Updating Fractional Noun Contract Address in Tokenized Contract..."
  );
  const tokenizedContractInstance = await tokenizedNoun.attach(
    tokenizedNounAddress
  );

  const updateFNounContractAddressInTNounTx =
    await tokenizedContractInstance.setFractionalNounContract(
      fractionalNounAddress
    );
  await updateFNounContractAddressInTNounTx.wait();
  console.log("Contract updated successfully.");
  console.log("----------------------------------------------------------");

  // Verify MyNouns
  console.log("Verifying MyNouns...");
  await run("verify:verify", {
    address: myNounsAddress,
    constructorArguments: [],
  });
  console.log("----------------------------------------------------------");

  // Verify Tokenized Noun
  console.log("Verifying TokenizedNoun...");
  await run("verify:verify", {
    address: tokenizedNounAddress,
    constructorArguments: [easAddressForBaseSepolia, myNounsAddress],
  });
  console.log("----------------------------------------------------------");

  // Verify Fractional Noun
  console.log("Verifying Fractional Noun...");
  await run("verify:verify", {
    address: fractionalNounAddress,
    constructorArguments: [tokenizedNounAddress],
  });
  console.log("----------------------------------------------------------");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// CLI command to deploy all contracts at once
// yarn hardhat run scripts/DeployAll.js --network baseSepolia
// yarn hardhat verify --network baseSepolia DEPLOYED_CONTRACT_ADDRESS
