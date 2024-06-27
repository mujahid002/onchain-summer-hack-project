// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract MyNouns is ERC721, Ownable {
    uint256 private s_nounId;

    constructor() ERC721("MyNounTokens", "MNT") Ownable(_msgSender()) {
        s_nounId = 10;
        for (uint256 i = 0; i < 10; ++i) {
            _safeMint(_msgSender(), i);
        }
    }

    function mintNouns(address to, uint256 amount) public onlyOwner {
        s_nounId += amount;
        for (uint256 i = 0; i < amount; ++i) {
            _safeMint(to, i);
        }
    }

    function getTokenId() public view returns (uint256) {
        return s_nounId;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "For Testing Only!";
    }
}
