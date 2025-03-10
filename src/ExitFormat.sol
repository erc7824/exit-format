// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Ideally this would be imported from @connect/vector-withdraw-helpers
// And the interface would match this one (note WithdrawData calldata wd has become bytes calldata cD)
interface WithdrawHelper {
    function execute(bytes calldata cD, uint256 actualAmount) external;
}

library ExitFormat {
    // An Exit is an array of SingleAssetExit (one for each asset)
    // Exit = SingleAssetExit[]

    // A SingleAssetExit specifies
    // * an asset address (0 implies the native asset of the chain: on mainnet, this is ETH)
    // * custom assetMetadata
    //   containing
    //   - AssetType enum value
    //   - metadata for that token
    // * an allocations array
    struct SingleAssetExit {
        address asset;
        AssetMetadata assetMetadata;
        Allocation[] allocations;
    }

    // AssetMetadata allows for different token standards
    // that require additional data than just a token contract address
    // * assetType specifies one of the supported asset types
    // * metadata is a differently encoded metadata depending on the token type.
    //   This is untyped to allow for extensions in future as different token standards emerge
    struct AssetMetadata {
        AssetType assetType;
        bytes metadata;
    }

    // Enum of different (non-native) token types the SingleAssetExit can contain
    // Default - Either an ERC20 token or the chain's native asset, specified by
    //           the oken address 0x00. Requires no metadata.
    // ERC721 - NFT assets managed by a contract implementing IERC721.
    //          This requires the metadata to be an encoded `TokenIdExitMetadata`
    // ERC1155 - Fungible or non-fungible assets managed by a contract implementing IERC1155.
    //          This requires the metadata to be an encoded `TokenIdExitMetadata`
    // Qualified - Assets that are fully qualified and pinned to a specific chain and assetHolder.
    //             This requires the metadata to be an encoded `QualifiedAssetMetaData`
    enum AssetType {
        Default,
        ERC721,
        ERC1155,
        Qualified
    }

    // Metadata structure for ERC721 and ERC1155 exits
    struct TokenIdExitMetadata {
        uint256 tokenId;
    }

    // allocations is an ordered array of Allocation.
    // The ordering is important, and may express e.g. a priority order for the exit
    // (which would make a material difference to the final state in the case of running out of gas or funds)
    // Allocations = Allocation[]

    enum AllocationType {
        simple,
        withdrawHelper,
        guarantee
    }

    // An Allocation specifies
    // * a destination, referring either to an ethereum address or an application-specific identifier
    // * an amount of asset
    // * an allocationType, which directs calling code on how to interpret the allocation
    // * custom metadata (optional field, can be zero bytes). This can be used flexibly by different protocols.
    struct Allocation {
        bytes32 destination;
        uint256 amount;
        uint8 allocationType;
        bytes metadata;
    }

    /**
     * specifies the decoding format for metadata bytes fields
     * received with the WithdrawHelper flag
     */
    struct WithdrawHelperMetaData {
        address callTo;
        bytes callData;
    }

    /**
     * specifies the decoding format for metadata bytes fields
     * received with the Qualified flag
     */
    struct QualifiedAssetMetaData {
        uint256 chainID;
        address assetHolder;
    }

    // We use underscore parentheses to denote an _encodedVariable_
    function encodeExit(SingleAssetExit[] memory exit) internal pure returns (bytes memory) {
        return abi.encode(exit);
    }

    function decodeExit(bytes memory _exit_) internal pure returns (SingleAssetExit[] memory) {
        return abi.decode(_exit_, (SingleAssetExit[]));
    }

    function encodeAllocation(Allocation memory allocation) internal pure returns (bytes memory) {
        return abi.encode(allocation);
    }

    function decodeAllocation(bytes memory _allocation_) internal pure returns (Allocation memory) {
        return abi.decode(_allocation_, (Allocation));
    }

    function exitsEqual(SingleAssetExit[] memory exitA, SingleAssetExit[] memory exitB) internal pure returns (bool) {
        return _bytesEqual(encodeExit(exitA), encodeExit(exitB));
    }

    /**
     * @notice Executes an exit by paying out assets and calling external contracts
     * @dev Executes an exit by paying out assets and calling external contracts
     * @param exit The exit to be paid out.
     */
    function executeExit(ExitFormat.SingleAssetExit[] memory exit) internal {
        for (uint256 assetIndex = 0; assetIndex < exit.length; assetIndex++) {
            executeSingleAssetExit(exit[assetIndex]);
        }
    }

    /**
     * @notice Executes a single asset exit by paying out the asset and calling external contracts
     * @dev Executes a single asset exit by paying out the asset and calling external contracts
     * @param singleAssetExit The single asset exit to be paid out.
     */
    function executeSingleAssetExit(ExitFormat.SingleAssetExit memory singleAssetExit) internal {
        address asset = singleAssetExit.asset;

        if (_isForeignAsset(singleAssetExit)) {
            return;
        }

        for (uint256 j = 0; j < singleAssetExit.allocations.length; j++) {
            require(_isAddress(singleAssetExit.allocations[j].destination), "Destination is not a zero-padded address");
            address payable destination = payable(address(uint160(uint256(singleAssetExit.allocations[j].destination))));
            uint256 amount = singleAssetExit.allocations[j].amount;
            if (asset == address(0)) {
                (bool success,) = destination.call{value: amount}(""); //solhint-disable-line avoid-low-level-calls
                require(success, "Could not transfer ETH");
            } else {
                if (
                    // ERC20 Token
                    singleAssetExit.assetMetadata.assetType == AssetType.Default
                ) {
                    IERC20(asset).transfer(destination, amount);
                } else if (
                    // ERC721 Token
                    singleAssetExit.assetMetadata.assetType == AssetType.ERC721
                ) {
                    require(amount == 1, "Amount must be 1 for an ERC721 exit");
                    uint256 tokenId = abi.decode(singleAssetExit.assetMetadata.metadata, (TokenIdExitMetadata)).tokenId;
                    IERC721(asset).safeTransferFrom(address(this), destination, tokenId);
                } else if (
                    // ERC1155 Token
                    singleAssetExit.assetMetadata.assetType == AssetType.ERC1155
                ) {
                    uint256 tokenId = abi.decode(singleAssetExit.assetMetadata.metadata, (TokenIdExitMetadata)).tokenId;
                    IERC1155(asset).safeTransferFrom(
                        address(this),
                        destination,
                        tokenId,
                        amount,
                        singleAssetExit.allocations[j].metadata // the metadata from the allocation is passed to the safeTransferFrom call
                    );
                } else {
                    revert("unsupported asset");
                }
            }
            if (singleAssetExit.allocations[j].allocationType == uint8(AllocationType.withdrawHelper)) {
                WithdrawHelperMetaData memory wd = _parseWithdrawHelper(singleAssetExit.allocations[j].metadata);
                WithdrawHelper(wd.callTo).execute(wd.callData, amount);
            }
        }
    }

    /**
     * @notice Inspects a single asset exit to detect if it is foreign to this assetHolder.
     * @dev Inspects a single asset exit to detect if it is foreign to this assetHolder.
     * @param singleAssetExit The single asset exit under inspection.
     */
    function _isForeignAsset(SingleAssetExit memory singleAssetExit) internal view returns (bool) {
        if (singleAssetExit.assetMetadata.assetType == AssetType.Qualified) {
            QualifiedAssetMetaData memory expectedLocation =
                abi.decode(singleAssetExit.assetMetadata.metadata, (QualifiedAssetMetaData));

            return expectedLocation.chainID != block.chainid || expectedLocation.assetHolder != address(this);
        } else {
            // All unqualified assets are local by assumption.
            return false;
        }
    }

    /**
     * @notice Checks whether given destination is a valid Ethereum address
     * @dev Checks whether given destination is a valid Ethereum address
     * @param destination the destination to be checked
     */
    function _isAddress(bytes32 destination) internal pure returns (bool) {
        return uint96(bytes12(destination)) == 0;
    }

    /**
     * @notice Returns a callTo address and callData from metadata bytes
     * @dev Returns a callTo address and callData from metadata bytes
     */
    function _parseWithdrawHelper(bytes memory metadata) internal pure returns (WithdrawHelperMetaData memory) {
        return abi.decode(metadata, (WithdrawHelperMetaData));
    }

    /**
     * @notice Check for equality of two byte strings
     * @dev Check for equality of two byte strings
     * @param _preBytes One bytes string
     * @param _postBytes The other bytes string
     * @return true if the bytes are identical, false otherwise.
     */
    function _bytesEqual(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        // copied from https://www.npmjs.com/package/solidity-bytes-utils/v/0.1.1
        bool success = true;

        /* solhint-disable no-inline-assembly */
        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for { let cc := add(_postBytes, 0x20) }
                // the next line is the loop condition:
                // while(uint256(mc < end) + cb == 2)
                eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }
        /* solhint-disable no-inline-assembly */

        return success;
    }
}
