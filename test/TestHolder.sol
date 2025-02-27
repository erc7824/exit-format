// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract TestHolder is ERC721Holder, ERC1155Holder {
    receive() external virtual payable {
        // contract may receive ether
    }
}
