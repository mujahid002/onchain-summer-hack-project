// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {IEAS, Attestation} from "@ethereum-attestation-service/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "@ethereum-attestation-service/eas-contracts/contracts/resolver/SchemaResolver.sol";
import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract TokenisedNoun is SchemaResolver, ERC721Enumerable, Ownable {
    struct NounDetails {
        // address userAddress;
        uint256 tokenId;
        uint256 tokenPrice;
        // uint48 endTimestamp;
        uint8 divisor;
    }
    uint256 private s_tTokenId;

    address private s_nounContract;
    // IERC721 private s_nounContract;
    // 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03

    mapping(uint256 => NounDetails) private s_tTokenIdToNoun;

    constructor(IEAS _eas, address _nounContractAddress)
        SchemaResolver(_eas)
        ERC721("TokenisedNoun", "TNN")
        Ownable(msg.sender)
    {
        // s_nounContract = IERC721(_nounContractAddress);
        s_nounContract = _nounContractAddress;
    }

    function onAttest(
        Attestation calldata, /*attestation*/
        uint256 /*value*/
    ) internal pure override returns (bool) {
        return true;
    }

    function onRevoke(
        Attestation calldata, /*attestation*/
        uint256 /*value*/
    ) internal pure override returns (bool) {
        return true;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://t-nouns/tokens/";
    }

    function safeMint(address to) public onlyOwner {
        // uint256 tokenId = s_tTokenId++;
        // _safeMint(to, tokenId);
    }

    function mintTNoun(
        address userAddress,
        uint256 nounTokenId,
        uint256 setNounPrice,
        uint8 parts
    ) public {
        if (!transferNoun(userAddress, nounTokenId)) revert();
        uint256 tTokenId = getTTokenId();
        setNounDetails(tTokenId, nounTokenId, setNounPrice, parts);
        s_tTokenId += 1;
        _safeMint(userAddress, tTokenId);
    }

    function getTTokenId() public view returns (uint256) {
        return s_tTokenId;
    }

    function setNounDetails(
        uint256 tNounId,
        uint256 nounTokenId,
        uint256 nounTokenPrice,
        uint8 totalParts
    ) private {
        NounDetails memory newNounDetails = NounDetails({
            tokenId: nounTokenId,
            tokenPrice: nounTokenPrice,
            divisor: totalParts
        });

        s_tTokenIdToNoun[tNounId] = newNounDetails;
    }

    function transferNoun(address userAddress, uint256 nounTokenId)
        public
        returns (bool status)
    {
        // bool status = false;
        status = false;
        // Check ownership using low-level call
        (bool successOwnerOf, bytes memory dataOwnerOf) = s_nounContract
            .staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", nounTokenId)
            );
        if (!successOwnerOf) revert();

        address owner = abi.decode(dataOwnerOf, (address));
        if (owner != userAddress) revert();

        // Check approval using low-level call
        (bool successGetApproved, bytes memory dataGetApproved) = s_nounContract
            .staticcall(
                abi.encodeWithSignature("getApproved(uint256)", nounTokenId)
            );
        if (!successGetApproved) revert();

        address approvedAddress = abi.decode(dataGetApproved, (address));
        if (approvedAddress != address(this)) revert();
        (bool checkTransfer, ) = s_nounContract.call(
            abi.encodeWithSignature(
                "transferfrom(address,address,uint256)",
                userAddress,
                address(this),
                nounTokenId
            )
        );
        if (!checkTransfer) revert();

        status = true;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        return super._update(to, tokenId, auth);
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
}
