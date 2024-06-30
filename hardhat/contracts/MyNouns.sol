// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {ERC721Enumerable, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract MyNouns is ERC721Enumerable, Ownable {
    uint256 private s_nounId;

    constructor() ERC721("MyNounTokens", "MNT") Ownable(_msgSender()) {
        s_nounId = 10;
        for (uint256 i = 0; i < 10; ++i) {
            _safeMint(_msgSender(), i);
        }
    }

    function mintNoun(address to) public onlyOwner {
        uint256 nounId=getNounId();
        s_nounId+=1;
        _safeMint(to, nounId);
    }
    function burnNoun(uint256 nounId) public onlyOwner {
                _burn(nounId);

    }

    function getNounId() public view returns (uint256) {
        return s_nounId;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://noun.pics/";
    }

    function tokenURI(uint256 nounId)
        public
        view
        override
        returns (string memory)
    {
        return super.tokenURI(nounId);
    }
}
