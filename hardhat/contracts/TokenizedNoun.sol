// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {IEAS, Attestation} from "@ethereum-attestation-service/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "@ethereum-attestation-service/eas-contracts/contracts/resolver/SchemaResolver.sol";
import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error TokenizedNoun__InvalidAddress();
error TokenizedNoun__NotOwner();
error TokenizedNoun__NotApproved();
error TokenizedNoun__TransferFailed();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract TokenizedNoun is SchemaResolver, ERC721Enumerable, Ownable {
    struct NounDetails {
        uint256 tokenId;
        uint256 eachTokenPrice;
        uint48 endTimestamp;
        uint8 divisor;
    }
    uint256 private s_tNounId;

    address private s_nounContractAddress;
    address private s_fractionalNounContractAddress;
    // IERC721 private s_nounContractAddress;
    // 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03

    mapping(uint256 => NounDetails) private s_tNounIdToNoun;

    constructor(IEAS _eas, address _nounContractAddress)
        SchemaResolver(_eas)
        ERC721("TokenizedNoun", "tNOUN")
        Ownable(_msgSender())
    {
        // s_nounContractAddress = IERC721(_nounContractAddress);
        s_nounContractAddress = _nounContractAddress;
    }

    function setFractionalNounContract(address _fNounContractAddress)
        public
        onlyOwner
    {
        s_fractionalNounContractAddress = _fNounContractAddress;
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
        return "https://tnouns/tokens/";
    }

    function mintTNoun(
        uint256 nounTokenId,
        uint256 setNounPrice,
        uint8 parts
    ) public {
        if (parts < 2 || parts > 255) revert();
        if (s_fractionalNounContractAddress == address(0)) revert();
        if (!transferNoun(_msgSender(), nounTokenId))
            revert TokenizedNoun__TransferFailed();
        uint256 tNounId = gettNounId();
        setNounDetails(tNounId, nounTokenId, setNounPrice, parts);
        s_tNounId += 1;
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

    function withdrawNoun(uint256 tNounId) public payable {
        if (s_fractionalNounContractAddress == address(0)) revert();
        if (uint48(block.timestamp) < getNounEndTime(tNounId)) revert();
        if (ownerOf(tNounId) != _msgSender()) revert();

        uint256 totalValue = calculateTotalValue(tNounId);

        if (totalValue != msg.value) revert();

        (bool checkStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature("burnFNounId(uint256)", tNounId)
        );
        if (!checkStatus) revert();
    }

    function calculateTotalValue(uint256 tNounId)
        public
        view
        returns (uint256 totalValue)
    {
        uint256 tokenPrice = getNounDetails(tNounId).eachTokenPrice;

        (
            bool checkStatus,
            bytes memory totalSupplyInBytes
        ) = s_fractionalNounContractAddress.staticcall(
                abi.encodeWithSignature("totalSupply(uint256)", tNounId)
            );
        if (!checkStatus) revert();

        uint256 values = abi.decode(totalSupplyInBytes, (uint256));
        totalValue = (values * tokenPrice) / (10**18);
    }

    function gettNounId() public view returns (uint256) {
        return s_tNounId;
    }

    function setNounDetails(
        uint256 tNounId,
        uint256 nounTokenId,
        uint256 nounTokenPrice,
        uint8 totalParts
    ) private {
        NounDetails memory newNounDetails = NounDetails({
            tokenId: nounTokenId,
            eachTokenPrice: nounTokenPrice,
            endTimestamp: uint48(block.timestamp + 52 weeks),
            divisor: totalParts
        });

        s_tNounIdToNoun[tNounId] = newNounDetails;
    }

    function transferNoun(address userAddress, uint256 nounTokenId)
        private
        returns (bool status)
    {
        status = false;
        // Check ownership using low-level call
        (bool successOwnerOf, bytes memory dataOwnerOf) = s_nounContractAddress
            .staticcall(
                abi.encodeWithSignature("ownerOf(uint256)", nounTokenId)
            );
        if (!successOwnerOf) revert TokenizedNoun__InvalidAddress();

        address owner = abi.decode(dataOwnerOf, (address));
        if (owner != userAddress) revert TokenizedNoun__NotOwner();

        // Check approval using low-level call
        (
            bool successGetApproved,
            bytes memory dataGetApproved
        ) = s_nounContractAddress.staticcall(
                abi.encodeWithSignature("getApproved(uint256)", nounTokenId)
            );
        if (!successGetApproved) revert TokenizedNoun__InvalidAddress();

        address approvedAddress = abi.decode(dataGetApproved, (address));
        if (approvedAddress != address(this))
            revert TokenizedNoun__NotApproved();

        (bool checkTransfer, ) = s_nounContractAddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                userAddress,
                address(this),
                nounTokenId
            )
        );
        if (!checkTransfer) revert TokenizedNoun__TransferFailed();

        status = true;
    }

    function getNounDetails(uint256 tNounId)
        public
        view
        returns (NounDetails memory)
    {
        return s_tNounIdToNoun[tNounId];
    }

    function getNounTokenId(uint256 tNounId) public view returns (uint256) {
        return s_tNounIdToNoun[tNounId].tokenId;
    }

    function getEachTokenPriceForNoun(uint256 tNounId)
        public
        view
        returns (uint256)
    {
        return s_tNounIdToNoun[tNounId].eachTokenPrice;
    }

    function getNounEndTime(uint256 tNounId) public view returns (uint48) {
        return s_tNounIdToNoun[tNounId].endTimestamp;
    }

    function getNounDivisor(uint256 tNounId) public view returns (uint8) {
        return s_tNounIdToNoun[tNounId].divisor;
    }

    // function _safeTransfer(
    //     address from,
    //     address to,
    //     uint256 tokenId,
    //     bytes memory data
    // ) internal virtual override {
    //     revert();
    // }

    // function safeTransferFrom(
    //     address from,
    //     address to,
    //     uint256 tokenId,
    //     bytes memory data
    // ) public virtual override(ERC721, IERC721) {
    //     revert();
    // }

    // function transferFrom(
    //     address from,
    //     address to,
    //     uint256 tokenId
    // ) public virtual override(ERC721, IERC721) {
    //     revert();
    // }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        return super.tokenURI(tokenId);
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
