const { ethers, run } = require("hardhat");

async function main() {
  const easAddressForBaseSepolia = "0x4200000000000000000000000000000000000021";
  const myNounsAddress = "0x5539dFfaFe2785Ae0B1301001076c11f3af4eB67";
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
  console.log("Tokenized Noun Address:", tokenizedNounAddress);
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
