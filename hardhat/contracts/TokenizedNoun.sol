// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {IEAS, Attestation} from "@ethereum-attestation-service/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "@ethereum-attestation-service/eas-contracts/contracts/resolver/SchemaResolver.sol";
import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error TokenizedNoun__InvalidAddress();
error TokenizedNoun__NotOwner();
error TokenizedNoun__NotApproved();
error TokenizedNoun__TransferFailed();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract TokenizedNoun is SchemaResolver, ERC721Enumerable, Ownable {
    struct NounDetails {
        uint256 eachFNounPrice;
        uint48 endTimestamp;
        uint8 divisor;
    }

    address private s_nounContractAddress;
    // 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03
    address private s_fractionalNounContractAddress;

    mapping(uint256 => NounDetails) private s_tNounIdDetails;
    mapping(uint256 => uint256) private s_tNounIdToCollectedAmount;

    constructor(IEAS _eas, address _nounContractAddress)
        SchemaResolver(_eas)
        ERC721("TokenizedNoun", "tNOUN")
        Ownable(_msgSender())
    {
        s_nounContractAddress = _nounContractAddress;
    }

    function onAttest(Attestation calldata attestation, uint256 nounId)
        internal
        override
        returns (bool)
    {
        uint256 tNounId = nounId;
        if (checkContractIsOwnerForNounId(nounId)) {
            if (ownerOf(tNounId) != attestation.attester) return false;
            if (getNounDetails(nounId).endTimestamp > 0) return false;
            return true;
        } else {
            bool approved = _approveNoun(attestation.attester, nounId);
            if (approved) {
                (bool checkTransfer, ) = s_nounContractAddress.call(
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)",
                        attestation.attester,
                        address(this),
                        nounId
                    )
                );
                if (!checkTransfer) return false;
                _safeMint(attestation.attester, tNounId);

                return true;
            } else {
                return false;
            }
        }
    }

    function onRevoke(
        Attestation calldata, /*attestation*/
        uint256 /* tNounId*/
    ) internal pure override returns (bool) {
        return false;
    }

    function tNounIdDetails(
        uint256 tNounId,
        uint256 setNounPrice,
        uint8 parts
    ) public {
        if (s_fractionalNounContractAddress == address(0)) revert();
        if (parts < 2 || parts > 255) revert();
        if (ownerOf(tNounId) != _msgSender()) revert();
        setNounDetails(tNounId, setNounPrice, parts);
        (bool fNounMintStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature(
                "mintFNounToOwner(address,uint256)",
                _msgSender(),
                tNounId
            )
        );
        if (!fNounMintStatus) revert();
    }

    function withdrawNoun(uint256 tNounId) public payable {
        if (s_fractionalNounContractAddress == address(0)) revert();
        if (uint48(block.timestamp) < getNounEndTime(tNounId)) revert();
        if (ownerOf(tNounId) != _msgSender()) revert();

        uint256 nounId = tNounId;

        uint256 totalValue = calculateTotalValue(tNounId);

        if (totalValue != msg.value) revert();

        (bool checkStatus, ) = s_fractionalNounContractAddress.call(
            abi.encodeWithSignature("burnFNounId(uint256)", tNounId)
        );
        if (checkStatus) {
            s_tNounIdToCollectedAmount[tNounId] += msg.value;
            delete s_tNounIdDetails[tNounId];
            _burn(tNounId);
            // Transfer the token using low-level call
            (bool successTransfer, ) = s_nounContractAddress.call(
                abi.encodeWithSignature(
                    "safetransferFrom(address,address,uint256)",
                    address(this),
                    _msgSender(),
                    nounId
                )
            );
            if (!successTransfer) revert();
        } else {
            revert();
        }
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://tnouns/tokens/";
    }

    function setFractionalNounContract(address _fNounContractAddress)
        public
        onlyOwner
    {
        s_fractionalNounContractAddress = _fNounContractAddress;
    }

    function setNounDetails(
        uint256 tNounId,
        uint256 nounTokenPrice,
        uint8 totalParts
    ) private {
        NounDetails memory newNounDetails = NounDetails({
            eachFNounPrice: nounTokenPrice,
            endTimestamp: uint48(block.timestamp + 52 weeks),
            divisor: totalParts
        });

        s_tNounIdDetails[tNounId] = newNounDetails;
    }

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

    function calculateTotalValue(uint256 tNounId)
        public
        view
        returns (uint256 totalValue)
    {
        uint256 tokenPrice = getNounDetails(tNounId).eachFNounPrice;

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

    function getFractionalNounContractAddress() view public returns(address){
        return s_fractionalNounContractAddress;
    } 

    function getNounDetails(uint256 tNounId)
        public
        view
        returns (NounDetails memory)
    {
        return s_tNounIdDetails[tNounId];
    }

    function geteachFNounPriceForNoun(uint256 tNounId)
        public
        view
        returns (uint256)
    {
        return s_tNounIdDetails[tNounId].eachFNounPrice;
    }

    function getNounEndTime(uint256 tNounId) public view returns (uint48) {
        return s_tNounIdDetails[tNounId].endTimestamp;
    }

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
        if (!successOwnerOf) revert TokenizedNoun__InvalidAddress();

        address owner = abi.decode(dataOwnerOf, (address));
        if (owner != userAddress) revert TokenizedNoun__NotOwner();

        // Check approval using low-level call
        (
            bool successGetApproved,
            bytes memory dataGetApproved
        ) = s_nounContractAddress.staticcall(
                abi.encodeWithSignature("getApproved(uint256)", nounId)
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
                nounId
            )
        );
        if (!checkTransfer) revert TokenizedNoun__TransferFailed();

        status = true;
    }
}
