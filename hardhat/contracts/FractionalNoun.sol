// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

error FractionalNoun__InvalidAddress();
error FractionalNoun__InsufficientParts();
error FractionalNoun__InvalidValue();
error FractionalNoun__Unauthorized();
error FractionalNoun__ZeroAmount();
error FractionalNoun__InsufficientBalance();
error FractionalNoun__WithdrawalFailed();
error FractionalNoun__UnableToCallTNounContract();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract FractionalNoun is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    address private s_tokenizedNounContractAddress;

    mapping(uint256 => uint256) private s_collectedAmount;
    mapping(uint256 => EnumerableSet.AddressSet) private s_fTokenIdToOwners;

    constructor(address _tokenizedNounContractAddress) ERC1155("https://fnouns/tokens/") Ownable(_msgSender()) {
        s_tokenizedNounContractAddress=_tokenizedNounContractAddress;
    }

    modifier onlyTokenizedNounContract() {
        if (msg.sender != s_tokenizedNounContractAddress)
            revert FractionalNoun__Unauthorized();
        _;
    }


    function setURI(string memory newURI) public onlyOwner {
        _setURI(newURI);
    }

    function mintFNounToOwner(address userAddress, uint256 tNounId)
        public
        onlyTokenizedNounContract
    {
        uint8 totalParts = getNounParts(tNounId);
        if (totalSupply(tNounId) >= totalParts)
            revert FractionalNoun__InsufficientParts();
        addAddress(tNounId, userAddress);
        _mint(userAddress, tNounId, 1, "");
    }

    function mintFNoun(uint256 tNounId, uint256 _amount)
        public
        payable
        nonReentrant
    {
        if (_amount == 0) revert FractionalNoun__ZeroAmount();
        uint8 amount=uint8(_amount);
        uint8 totalParts = getNounParts(tNounId);
        uint8 currentSupply = uint8(totalSupply(tNounId));
        if (amount > totalParts - currentSupply)
            revert FractionalNoun__InsufficientParts();

        (
            bool successPrice,
            bytes memory dataPrice
        ) = s_tokenizedNounContractAddress.staticcall(
                abi.encodeWithSignature(
                    "getEachTokenPriceForNoun(uint256)",
                    tNounId
                )
            );
        if (!successPrice) revert FractionalNoun__InvalidAddress();
        uint256 tokenPrice = abi.decode(dataPrice, (uint256));
        if ((_amount * tokenPrice)/(10**18) != msg.value)
            revert FractionalNoun__InvalidValue();

        s_collectedAmount[tNounId] += msg.value;
        if (!containsAddress(tNounId, _msgSender())) {
            addAddress(tNounId, _msgSender());
        }
        _mint(msg.sender, tNounId, amount, "");
    }


    function burnFNounId(uint256 tNounId) public onlyTokenizedNounContract {
        uint256 length = getAddressCount(tNounId);
        address[] memory userAddresses = getAllAddresses(tNounId);
        uint256[] memory ids = getIds(tNounId, length);
        uint256[] memory values = balanceOfBatch(userAddresses, ids);
        for (uint256 i = 0; i < length; ++i) {
            _burn(userAddresses[i], ids[i], values[i]);
        }
    }

    function withdraw(uint256 tNounId,uint256 amount) public nonReentrant {
        if (amount == 0) revert FractionalNoun__ZeroAmount();
        (
            bool successOwnerOf,
            bytes memory dataOwnerOf
        ) = s_tokenizedNounContractAddress.staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", tNounId)
            );
        if (!successOwnerOf) revert FractionalNoun__InvalidAddress();
        address ownerAddress = abi.decode(dataOwnerOf, (address));
        if(ownerAddress!=_msgSender()) revert("Invalid Address");
        if (s_collectedAmount[tNounId] < amount)
            revert FractionalNoun__InsufficientBalance();

        (bool success, ) = msg.sender.call{value: amount}("");
        if (success) {
            s_collectedAmount[tNounId] -= amount;
        } else {
            revert FractionalNoun__WithdrawalFailed();
        }
    }

    function getNounParts(uint256 tNounId) public view returns (uint8) {
        (bool success, bytes memory data) = s_tokenizedNounContractAddress
            .staticcall(
                abi.encodeWithSignature("getNounDivisor(uint256)", tNounId)
            );
        if (!success) revert FractionalNoun__UnableToCallTNounContract();
        return abi.decode(data, (uint8));
    }

    function getTokenizedNounContractAddress() view public returns(address){
        return s_tokenizedNounContractAddress;
    } 

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

    function addAddress(uint256 key, address addr) public {
        s_fTokenIdToOwners[key].add(addr);
    }

    function removeAddress(uint256 key, address addr) public {
        s_fTokenIdToOwners[key].remove(addr);
    }

    function getAddressCount(uint256 key) public view returns (uint256) {
        return s_fTokenIdToOwners[key].length();
    }

    function getAddressAt(uint256 key, uint256 index)
        public
        view
        returns (address)
    {
        return s_fTokenIdToOwners[key].at(index);
    }

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

    function setTokenizedNounContractAddress(address tokenizedNounAddress)
        public
        onlyOwner
    {
        s_tokenizedNounContractAddress = tokenizedNounAddress;
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
