// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

// Importing required contracts and libraries
import {IEAS, Attestation} from "@ethereum-attestation-service/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "@ethereum-attestation-service/eas-contracts/contracts/resolver/SchemaResolver.sol";
import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Custom errors for better gas efficiency and clearer error messages
error TokenizedNoun__NotOwner();
error TokenizedNoun__NotApproved();
error TokenizedNoun__TransferFailed();
error TokenizedNoun__InvalidInputAmount();
error TokenizedNoun__InvalidInputAddress();
error TokenizedNoun__InvalidCaller();
error TokenizedNoun__NounIsLocked();
error TokenizedNoun__UnableToCallFNounContract();
error TokenizedNoun__UnableToTransferNoun();
error TokenizedNoun__UnableToGetAddresses();
error TokenizedNoun__UnableToDistributeAmount();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract TokenizedNoun is
    SchemaResolver,
    ERC721Enumerable,
    Ownable,
    ReentrancyGuard
{
    // Structure to hold details about each tokenized noun
    struct NounDetails {
        uint256 eachFNounPrice;
        uint48 endTimestamp;
        uint8 divisor;
    }

    // Addresses for the original noun contract and the fractional noun contract
    address private s_nounContractAddress;
    // 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03 (Official Noun Contract Address)
    address private s_fractionalNounContractAddress;

    // Mappings to store noun details and collected amounts for each tokenized noun ID
    mapping(uint256 => NounDetails) private s_tNounIdDetails;
    mapping(uint256 => uint256) private s_tNounIdToCollectedAmount;

    // Constructor to initialize the contract with the attestation service and the noun contract address
    constructor(IEAS _eas, address _nounContractAddress)
        SchemaResolver(_eas)
        ERC721("TokenizedNoun", "tNOUN")
        Ownable(_msgSender())
    {
        s_nounContractAddress = _nounContractAddress;
    }

    /**
     * @dev Handles the attestation event. This function is called when an attestation is made.
     * @param attestation The attestation data.
     * @param nounId The unique identifier for the noun.
     * @return bool Returns true if the attestation is successful, otherwise false.
     */
    function onAttest(Attestation calldata attestation, uint256 nounId)
        internal
        override
        returns (bool)
    {
        uint256 tNounId = nounId;
        // Check if the contract is the owner of the given nounId
        if (checkContractIsOwnerForNounId(nounId)) {
            // Verify that the attester is the owner of the tNounId
            if (ownerOf(tNounId) != attestation.attester) return false;
            // Ensure the noun's end timestamp is zero
            if (getNounDetails(nounId).endTimestamp > 0) return false;
            return true;
        } else {
            // Attempt to approve the attestation
            bool approved = _approveNoun(attestation.attester, nounId);
            if (approved) {
                // Transfer the noun from the attester to the contract
                (bool checkTransfer, ) = s_nounContractAddress.call(
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)",
                        attestation.attester,
                        address(this),
                        nounId
                    )
                );
                // Return false if the transfer fails
                if (!checkTransfer) return false;
                // Mint a new token for the attester
                _safeMint(attestation.attester, tNounId);

                return true;
            } else {
                return false;
            }
        }
    }

    /**
     * @dev Handles the revocation event. This function is called when an attestation is revoked.
     * @return bool Always returns false as revocation is not supported.
     */
    function onRevoke(
        Attestation calldata, /*attestation*/
        uint256 /* tNounId*/
    ) internal pure override returns (bool) {
        return false;
    }

    /**
     * @dev Sets the details for a tokenized noun, including the price and number of parts.
     *      Mints fractional tokens for the owner.
     * @param tNounId The unique identifier for the tokenized noun.
     * @param setNounPrice The price to be set for the noun.
     * @param parts The number of parts to divide the noun into (must be between 2 and 255).
     */
    function setTNounIdDetails(
        uint256 tNounId,
        uint256 setNounPrice,
        uint8 parts
    ) public {
        // Ensure the fractional noun contract address is set
        if (s_fractionalNounContractAddress == address(0))
            revert TokenizedNoun__InvalidInputAddress();

        // Ensure the number of parts is within the allowed range
        if (parts < 2 || parts > 255)
            revert TokenizedNoun__InvalidInputAmount();

        // Ensure the caller is the owner of the tokenized noun
        if (ownerOf(tNounId) != _msgSender())
            revert TokenizedNoun__InvalidCaller();

        // Set the noun details
        setNounDetails(tNounId, setNounPrice, parts);

        // Mint fractional tokens for the owner
        (bool fNounMintStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature(
                "mintFNounToOwner(address,uint256)",
                _msgSender(),
                tNounId
            )
        );
        // Revert if the minting fails
        if (!fNounMintStatus) revert TokenizedNoun__UnableToCallFNounContract();
    }

    /**
     * @dev Withdraws a tokenized noun and its associated value, burns the fractional tokens, and transfers the original noun back to the owner.
     * @param tNounId The unique identifier for the tokenized noun.
     */
    function withdrawNoun(uint256 tNounId) public payable nonReentrant {
        // Ensure the fractional noun contract address is set
        if (s_fractionalNounContractAddress == address(0))
            revert TokenizedNoun__InvalidInputAddress();

        // Ensure the noun is not locked
        if (uint48(block.timestamp) <= getNounEndTime(tNounId))
            revert TokenizedNoun__NounIsLocked();

        // Ensure the caller is the owner of the tokenized noun
        if (ownerOf(tNounId) != _msgSender())
            revert TokenizedNoun__InvalidCaller();

        uint256 nounId = tNounId;
        uint256 totalValue = calculateTotalValue(tNounId);

        // Ensure the value sent matches the total value required
        if (totalValue != msg.value) revert TokenizedNoun__InvalidInputAmount();

        // Burn the fractional tokens
        (bool checkStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature("burnFNounId(uint256)", tNounId)
        );
        if (!checkStatus) revert TokenizedNoun__UnableToCallFNounContract();

        s_tNounIdToCollectedAmount[tNounId] += msg.value;
        delete s_tNounIdDetails[tNounId];

        // Burn the tokenized noun
        _burn(tNounId);

        // Distribute the collected amount
        // distributeFunds(tNounId, totalValue);

        // Transfer the original noun back to the owner
        (bool transferSuccess, ) = s_nounContractAddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                _msgSender(),
                nounId
            )
        );
        if (!transferSuccess) revert TokenizedNoun__UnableToTransferNoun();
    }

    /**
     * @dev Distributes the collected amount among all fractional owners of the tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @param totalCollectedAmount The total amount collected to be distributed.
     */
    function distributeFunds(uint256 tNounId, uint256 totalCollectedAmount)
        public
        onlyOwner
    {
        // Get the list of addresses of all fractional owners
        (
            bool checkAddresses,
            bytes memory addressesListInBytes
        ) = s_fractionalNounContractAddress.staticcall(
                abi.encodeWithSignature("getAllAddresses(uint256)", tNounId)
            );
        if (!checkAddresses) revert TokenizedNoun__UnableToGetAddresses();

        address[] memory userAddresses = abi.decode(
            addressesListInBytes,
            (address[])
        );

        uint256 addressesLength = userAddresses.length;

        // Calculate distribution amount
        uint256 baseDistribution = totalCollectedAmount / addressesLength;

        for (uint256 i = 0; i < addressesLength; ++i) {
            (bool checkTransfer, ) = userAddresses[i].call{
                value: baseDistribution
            }("");
            if (!checkTransfer)
                revert TokenizedNoun__UnableToDistributeAmount();
        }
        delete s_tNounIdToCollectedAmount[tNounId];
    }

    /**
     * @dev Returns the base URI for token metadata.
     * @return string The base URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "https://tnouns/tokens/";
    }

    /**
     * @dev Sets the address of the fractional noun contract.
     * @param _fNounContractAddress The address of the fractional noun contract.
     */
    function setFractionalNounContract(address _fNounContractAddress)
        public
        onlyOwner
    {
        s_fractionalNounContractAddress = _fNounContractAddress;
    }

    /**
     * @dev Sets the details for a tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @param nounTokenPrice The price to be set for the noun.
     * @param totalParts The total number of parts to divide the noun into.
     */
    function setNounDetails(
        uint256 tNounId,
        uint256 nounTokenPrice,
        uint8 totalParts
    ) private {
        NounDetails memory newNounDetails = NounDetails({
            eachFNounPrice: nounTokenPrice,
            endTimestamp: uint48(block.timestamp + 1 seconds), // Example: Set end timestamp after 1 second for testing
            divisor: totalParts
        });

        s_tNounIdDetails[tNounId] = newNounDetails;
    }

    /**
     * @dev Compares if the end timestamp for a tokenized noun has passed.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return bool Returns true if the end timestamp has passed, otherwise false.
     */
    function compareEndTimePassed(uint256 tNounId) public view returns (bool) {
        return getNounEndTime(tNounId) < uint48(block.timestamp);
    }

    /**
     * @dev Checks if the contract is the owner of the given tokenized noun ID in the original noun contract.
     * @param nounId The unique identifier for the noun.
     * @return bool Returns true if the contract is the owner, otherwise false.
     */
    function checkContractIsOwnerForNounId(uint256 nounId)
        public
        view
        returns (bool)
    {
        (bool callOwnerOf, bytes memory addressInBytes) = s_nounContractAddress
            .staticcall(abi.encodeWithSignature("ownerOf(uint256)", nounId));
        if (!callOwnerOf) return false;

        address nounOwner = abi.decode(addressInBytes, (address));

        if (nounOwner == address(this)) return true;
        return false;
    }

    /**
     * @dev Calculates the total value of a tokenized noun based on its token price and total supply.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return totalValue The total value of the tokenized noun.
     */
    function calculateTotalValue(uint256 tNounId)
        public
        view
        returns (uint256 totalValue)
    {
        // Get the token price from noun details
        uint256 tokenPrice = getNounDetails(tNounId).eachFNounPrice;

        // Retrieve the total supply of fractional tokens for the tokenized noun
        (
            bool checkStatus,
            bytes memory totalSupplyInBytes
        ) = s_fractionalNounContractAddress.staticcall(
                abi.encodeWithSignature("totalSupply(uint256)", tNounId)
            );
        if (!checkStatus) revert TokenizedNoun__UnableToGetAddresses();

        uint256 totalSupply = abi.decode(totalSupplyInBytes, (uint256));
        totalValue = totalSupply * tokenPrice;
    }

    /**
     * @dev Checks if the caller is approved to manage a specific tokenized noun.
     * @param userAddress The address to check for approval.
     * @param nounId The unique identifier for the noun.
     * @return bool Returns true if the caller is approved, otherwise false.
     */
    function _approveNoun(address userAddress, uint256 nounId)
        internal
        view
        returns (bool)
    {
        // Check ownership using low-level call
        (bool successOwnerOf, bytes memory dataOwnerOf) = s_nounContractAddress
            .staticcall(abi.encodeWithSignature("ownerOf(uint256)", nounId));
        if (!successOwnerOf) return false;

        address owner = abi.decode(dataOwnerOf, (address));
        if (owner != userAddress) return false;

        // Check approval using low-level call
        (
            bool successGetApproved,
            bytes memory dataGetApproved
        ) = s_nounContractAddress.staticcall(
                abi.encodeWithSignature("getApproved(uint256)", nounId)
            );
        if (!successGetApproved) return false;

        address approvedAddress = abi.decode(dataGetApproved, (address));
        if (approvedAddress != address(this)) return false;

        return true;
    }

    /**
     * @dev Retrieves the address of the fractional noun contract.
     * @return address The address of the fractional noun contract.
     */
    function getFractionalNounContractAddress() public view returns (address) {
        return s_fractionalNounContractAddress;
    }

    /**
     * @dev Retrieves the address of the original noun contract.
     * @return address The address of the original noun contract.
     */
    function getNounContractAddress() public view returns (address) {
        return s_nounContractAddress;
    }

    /**
     * @dev Retrieves the details of a tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return NounDetails The details (price, end timestamp, divisor) of the tokenized noun.
     */
    function getNounDetails(uint256 tNounId)
        public
        view
        returns (NounDetails memory)
    {
        return s_tNounIdDetails[tNounId];
    }

    /**
     * @dev Retrieves the price of fractional tokens associated with a tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return uint256 The price of each fractional token.
     */
    function getFNounPrice(uint256 tNounId) public view returns (uint256) {
        return s_tNounIdDetails[tNounId].eachFNounPrice;
    }

    /**
     * @dev Retrieves the end timestamp of a tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return uint48 The end timestamp of the tokenized noun.
     */
    function getNounEndTime(uint256 tNounId) public view returns (uint48) {
        return s_tNounIdDetails[tNounId].endTimestamp;
    }

    /**
     * @dev Retrieves the divisor (number of parts) of a tokenized noun.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return uint8 The divisor (number of parts) of the tokenized noun.
     */
    function getNounDivisor(uint256 tNounId) public view returns (uint8) {
        return s_tNounIdDetails[tNounId].divisor;
    }

    function tokenURI(uint256 nounId)
        public
        view
        override
        returns (string memory)
    {
        return super.tokenURI(nounId);
    }

    function _update(
        address to,
        uint256 nounId,
        address auth
    ) internal override returns (address) {
        return super._update(to, nounId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // For Testing only!

    function mintTNoun(
        uint256 nounId,
        uint256 setNounPrice,
        uint8 parts
    ) public {
        if (parts < 2 || parts > 255) revert();
        if (s_fractionalNounContractAddress == address(0)) revert();
        if (!transferNoun(_msgSender(), nounId))
            revert TokenizedNoun__TransferFailed();
        uint256 tNounId = nounId;
        setNounDetails(tNounId, setNounPrice, parts);
        (bool fNounMintStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature(
                "mintFNounToOwner(address,uint256)",
                _msgSender(),
                tNounId
            )
        );
        if (!fNounMintStatus) revert();
        _safeMint(_msgSender(), tNounId);
    }

    function transferNoun(address userAddress, uint256 nounId)
        private
        returns (bool status)
    {
        status = false;
        // Check ownership using low-level call
        (bool successOwnerOf, bytes memory dataOwnerOf) = s_nounContractAddress
            .staticcall(abi.encodeWithSignature("ownerOf(uint256)", nounId));
        if (!successOwnerOf) revert TokenizedNoun__InvalidInputAddress();

        address owner = abi.decode(dataOwnerOf, (address));
        if (owner != userAddress) revert TokenizedNoun__NotOwner();

        // Check approval using low-level call
        (
            bool successGetApproved,
            bytes memory dataGetApproved
        ) = s_nounContractAddress.staticcall(
                abi.encodeWithSignature("getApproved(uint256)", nounId)
            );
        if (!successGetApproved) revert TokenizedNoun__InvalidInputAddress();

        address approvedAddress = abi.decode(dataGetApproved, (address));
        if (approvedAddress != address(this))
            revert TokenizedNoun__NotApproved();

        (bool checkTransfer, ) = s_nounContractAddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                userAddress,
                address(this),
                nounId
            )
        );
        if (!checkTransfer) revert TokenizedNoun__TransferFailed();

        status = true;
    }
}
