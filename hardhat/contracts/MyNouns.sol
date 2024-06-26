// SPDX-License-Identifier: mujahid002
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract MyNounTokens is ERC721, Ownable {
    constructor() ERC721("MyNounTokens", "MNT") Ownable(_msgSender()) {
        for (uint256 i = 0; i < 100; ++i) {
            _safeMint(_msgSender(), i);
        }
    }

    function _baseURI() internal pure override returns (string memory) {
        return "For Demo Testing!";
    }
}
