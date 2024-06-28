// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

error FractionalNoun__InvalidAddress();
error FractionalNoun__InsufficientParts();
error FractionalNoun__InvalidValue();
error FractionalNoun__Unauthorized();
error FractionalNoun__ZeroAmount();
error FractionalNoun__InsufficientBalance();
error FractionalNoun__WithdrawalFailed();
error FractionalNoun__UnableToCallTNounContract();
error FractionalNoun__UnableToCallGetPriceTNounContract();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract FractionalNoun is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    address private s_tokenizedNounContractAddress;

    mapping(uint256 => uint256) private s_collectedAmount;
    mapping(uint256 => EnumerableSet.AddressSet) private s_fTokenIdToOwners;

    /**
     * @dev Initializes the FractionalNoun contract.
     * @param _tokenizedNounContractAddress The address of the tokenized noun contract.
     */
    constructor(address _tokenizedNounContractAddress)
        ERC1155("https://fnouns/tokens/")
        Ownable(_msgSender())
    {
        s_tokenizedNounContractAddress = _tokenizedNounContractAddress;
    }

    /**
     * @dev Modifier to ensure that only the tokenized noun contract can call the function.
     */
    modifier onlyTokenizedNounContract() {
        if (_msgSender() != s_tokenizedNounContractAddress)
            revert FractionalNoun__Unauthorized();
        _;
    }

    /*****************************
        STATE UPDATE FUNCTIONS
    ******************************/

    /**
     * @dev Mint a fractional Noun token to the owner's address.
     * @param userAddress The address to mint the token to.
     * @param tNounId The unique identifier for the tokenized noun.
     */
    function mintFNounToOwner(address userAddress, uint256 tNounId)
        public
        onlyTokenizedNounContract
    {
        // Ensure there are enough parts available to mint
        uint8 totalParts = getNounParts(tNounId);
        if (uint8(totalSupply(tNounId)) >= totalParts)
            revert FractionalNoun__InsufficientParts();

        // Add the address to the list of fractional owners
        addAddress(tNounId, userAddress);

        // Mint one fractional Noun token to the owner
        _mint(userAddress, tNounId, 1, "");
    }

    /**
     * @dev Mint a specified amount of fractional Noun tokens to the sender.
     * @param tNounId The unique identifier for the tokenized noun.
     * @param amount The amount of tokens to mint.
     */
    function mintFNoun(uint256 tNounId, uint8 amount)
        public
        payable
        nonReentrant
    {
        // Ensure amount to mint is not zero
        if (amount == 0) revert FractionalNoun__ZeroAmount();

        // Ensure there are enough parts available to mint
        uint8 totalParts = getNounParts(tNounId);
        uint8 currentSupply = uint8(totalSupply(tNounId));
        if (amount > totalParts - currentSupply)
            revert FractionalNoun__InsufficientParts();

        // Get the price of the fractional Noun token
        (
            bool successPrice,
            bytes memory dataPrice
        ) = s_tokenizedNounContractAddress.staticcall(
                abi.encodeWithSignature("getFNounPrice(uint256)", tNounId)
            );
        if (!successPrice)
            revert FractionalNoun__UnableToCallGetPriceTNounContract();
        uint256 tokenPrice = abi.decode(dataPrice, (uint256));

        // Validate the sent Ether amount matches the expected price
        uint256 inputAmount = amount * tokenPrice;
        if (inputAmount != msg.value) revert FractionalNoun__InvalidValue();

        // Add the collected Ether to the contract's balance
        s_collectedAmount[tNounId] += msg.value;

        // Add sender to the list of fractional owners if not already added
        if (!containsAddress(tNounId, _msgSender())) {
            addAddress(tNounId, _msgSender());
        }

        // Mint the specified amount of fractional Noun tokens to the sender
        _mint(_msgSender(), tNounId, amount, "");
    }

    /**
     * @dev Burn all fractional Noun tokens associated with a specific tokenized Noun ID.
     * @param tNounId The unique identifier for the tokenized noun.
     */
    function burnFNounId(uint256 tNounId) public onlyTokenizedNounContract {
        // Retrieve all user addresses, token IDs, and balances
        uint256 length = getAddressCount(tNounId);
        address[] memory userAddresses = getAllAddresses(tNounId);
        uint256[] memory ids = getIds(tNounId, length);
        uint256[] memory values = balanceOfBatch(userAddresses, ids);

        // Validate arrays consistency
        if (
            userAddresses.length != ids.length ||
            ids.length != values.length ||
            userAddresses.length != values.length
        ) revert();

        // Burn all tokens held by each user
        for (uint256 i = 0; i < length; ++i) {
            _burn(userAddresses[i], ids[i], values[i]);
        }
    }

    /**
     * @dev Withdraw Ether collected for a specific tokenized Noun ID.
     * @param tNounId The unique identifier for the tokenized noun.
     * @param amount The amount of Ether to withdraw.
     */
    function withdraw(uint256 tNounId, uint256 amount) public nonReentrant {
        // Ensure amount to withdraw is not zero
        if (amount == 0) revert FractionalNoun__ZeroAmount();

        // Validate sender is the owner of the tokenized Noun
        (
            bool successOwnerOf,
            bytes memory dataOwnerOf
        ) = s_tokenizedNounContractAddress.staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", tNounId)
            );
        if (!successOwnerOf) revert FractionalNoun__InvalidAddress();
        address ownerAddress = abi.decode(dataOwnerOf, (address));
        if (ownerAddress != _msgSender()) revert("Invalid Address");

        // Validate sufficient balance for withdrawal
        if (s_collectedAmount[tNounId] < amount)
            revert FractionalNoun__InsufficientBalance();

        // Transfer Ether to the sender
        (bool success, ) = _msgSender().call{value: amount}("");
        if (success) {
            s_collectedAmount[tNounId] -= amount;
        } else {
            revert FractionalNoun__WithdrawalFailed();
        }
    }

    /**
     * @dev Set a new base URI for all token URIs.
     * @param newURI The new base URI to set.
     */
    function setURI(string memory newURI) public onlyOwner {
        _setURI(newURI);
    }

    /**
     * @dev Set the address of the tokenized Noun contract.
     * @param newTokenizedNounAddress The new address of the tokenized Noun contract.
     */
    function setTokenizedNounContractAddress(address newTokenizedNounAddress)
        public
        onlyOwner
    {
        s_tokenizedNounContractAddress = newTokenizedNounAddress;
    }

    /*****************************
        GETTER FUNCTIONS
    ******************************/

    /**
     * @dev Get the amount of collected Ether for a specific tokenized Noun ID.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return uint256 The amount of collected Ether.
     */
    function getCollectedAmount(uint256 tNounId) public view returns (uint256) {
        return s_collectedAmount[tNounId];
    }

    /**
     * @dev Get the number of parts a tokenized Noun is divided into.
     * @param tNounId The unique identifier for the tokenized noun.
     * @return uint8 The number of parts.
     */
    function getNounParts(uint256 tNounId) public view returns (uint8) {
        // Call the tokenized Noun contract to retrieve the divisor (number of parts)
        (bool success, bytes memory data) = s_tokenizedNounContractAddress
            .staticcall(
                abi.encodeWithSignature("getNounDivisor(uint256)", tNounId)
            );
        if (!success) revert FractionalNoun__UnableToCallTNounContract();
        return abi.decode(data, (uint8));
    }

    /**
     * @dev Get the current address of the tokenized Noun contract.
     * @return address The address of the tokenized Noun contract.
     */
    function getTokenizedNounContractAddress() public view returns (address) {
        return s_tokenizedNounContractAddress;
    }

    /**
     * @dev Create an array of token IDs of a given length, all initialized to a specific ID.
     * @param id The token ID to replicate.
     * @param length The length of the array.
     * @return ids uint256[] An array of token IDs.
     */
    function getIds(uint256 id, uint256 length)
        public
        pure
        returns (uint256[] memory ids)
    {
        ids = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            ids[i] = id;
        }
    }

    /*****************************
        HELPER FUNCTIONS
    ******************************/

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value
    ) public {
        // if (!exists(id)) revert();
        // if (balanceOf(_msgSender(), id) < value) revert();
        // removeAddress(id, _msgSender());
        // addAddress(id, to);
        // _safeTransferFrom(from, to, id, value, "");
        revert("tNoun: Transfer Not Allowed!");
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override {
        revert("tNoun: Transfer Not Allowed!");
    }

    /**
     * @dev Add an address to the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @param addr The address to add.
     */
    function addAddress(uint256 key, address addr) public {
        s_fTokenIdToOwners[key].add(addr);
    }

    /**
     * @dev Remove an address from the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @param addr The address to remove.
     */
    function removeAddress(uint256 key, address addr) public {
        s_fTokenIdToOwners[key].remove(addr);
    }

    /**
     * @dev Get the number of addresses in the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @return uint256 The number of addresses.
     */
    function getAddressCount(uint256 key) public view returns (uint256) {
        return s_fTokenIdToOwners[key].length();
    }

    /**
     * @dev Get the address at a specific index in the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @param index The index of the address to retrieve.
     * @return address The address at the specified index.
     */
    function getAddressAt(uint256 key, uint256 index)
        public
        view
        returns (address)
    {
        return s_fTokenIdToOwners[key].at(index);
    }

    /**
     * @dev Get all addresses in the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @return address[] An array containing all addresses in the set.
     */
    function getAllAddresses(uint256 key)
        public
        view
        returns (address[] memory)
    {
        uint256 length = s_fTokenIdToOwners[key].length();
        address[] memory addresses = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            addresses[i] = s_fTokenIdToOwners[key].at(i);
        }
        return addresses;
    }

    /**
     * @dev Check if an address exists in the Enumerable Set associated with a specific key.
     * @param key The key identifier for the Enumerable Set.
     * @param addr The address to check for existence.
     * @return bool True if the address exists in the set, false otherwise.
     */
    function containsAddress(uint256 key, address addr)
        public
        view
        returns (bool)
    {
        return s_fTokenIdToOwners[key].contains(addr);
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
