// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Import the contracts under test. Adjust the paths if needed.
import "../src/ExitFormat.sol";
import "./TestConsumer.sol";
import "./TestERC20.sol";
import "./TestERC721.sol";
import "./TestERC1155.sol";

contract ExitFormatTest is Test {
    TestConsumer public testConsumer;
    // Use an arbitrary address for “alice”
    address public alice = address(0x1234);

    // ========== HELPERS ==========

    // Wrap a single Allocation into an array.
    function _toAllocationArray(ExitFormat.Allocation memory alloc)
        internal
        pure
        returns (ExitFormat.Allocation[] memory arr)
    {
        arr = new ExitFormat.Allocation[](1);
        arr[0] = alloc;
    }

    // Wrap a SingleAssetExit in an array.
    function _toExitArray(ExitFormat.SingleAssetExit memory sae)
        internal
        pure
        returns (ExitFormat.SingleAssetExit[] memory arr)
    {
        arr = new ExitFormat.SingleAssetExit[](1);
        arr[0] = sae;
    }

    // Create a “simple” exit (an exit with one allocation and no extra metadata)
    function makeSimpleExit(
        address asset,
        address destination,
        uint256 amount,
        ExitFormat.AssetMetadata memory assetMetadata
    ) internal pure returns (ExitFormat.SingleAssetExit memory) {
        ExitFormat.Allocation memory alloc = ExitFormat.Allocation({
            destination: bytes32(uint256(uint160(destination))),
            amount: amount,
            allocationType: uint8(ExitFormat.AllocationType.simple),
            metadata: ""
        });
        ExitFormat.SingleAssetExit memory sae = ExitFormat.SingleAssetExit({
            asset: asset,
            assetMetadata: assetMetadata,
            allocations: _toAllocationArray(alloc)
        });
        return sae;
    }

    // Helper to construct a qualified single asset exit.
    // The ExitFormat.QualifiedAssetMetaData is defined in ExitFormat.sol as:
    //    struct QualifiedAssetMetaData { uint256 chainID; address assetHolder; }
    function getQualifiedSAE(
        uint256 _chainID,
        address _assetHolder,
        address _destination,
        uint256 _amount
    ) internal pure returns (ExitFormat.SingleAssetExit memory) {
        // Pack the qualified metadata.
        ExitFormat.QualifiedAssetMetaData memory qual = ExitFormat.QualifiedAssetMetaData({
            chainID: _chainID,
            assetHolder: _assetHolder
        });
        bytes memory meta = abi.encode(qual);
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.Qualified,
            metadata: meta
        });
        return makeSimpleExit(address(0), _destination, _amount, assetMetadata);
    }

    // ========== SETUP ==========

    function setUp() public {
        testConsumer = new TestConsumer();
    }

    // ========== TESTS ==========

    function testEncodeAllocation() public {
        // Create an allocation:
        // destination: 0x00000000000000000000000096f7123E3A80C9813eF50213ADEd0e4511CB820f
        // amount: 1; allocationType: simple; metadata: empty.
        ExitFormat.Allocation memory allocation = ExitFormat.Allocation({
            destination: bytes32(uint256(uint160(0x96f7123E3A80C9813eF50213ADEd0e4511CB820f))),
            amount: 1,
            allocationType: uint8(ExitFormat.AllocationType.simple),
            metadata: ""
        });
        // Use TestConsumer’s wrapper to encode
        bytes memory encoded = testConsumer.encodeAllocation(allocation);

        // Expected encoding copied
        bytes memory expected = hex"0000000000000000000000000000000000000000000000000000000000000020"
        hex"00000000000000000000000096f7123e3a80c9813ef50213aded0e4511cb820f"
        hex"0000000000000000000000000000000000000000000000000000000000000001"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000080"
        hex"0000000000000000000000000000000000000000000000000000000000000000";

        assertEq(keccak256(encoded), keccak256(expected), "Allocation encoding mismatch");
    }

    function testEncodeExit() public {
        // Build a single-element exit using a “null” asset metadata (default type and empty metadata).
        ExitFormat.AssetMetadata memory nullAssetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.Default,
            metadata: ""
        });

        ExitFormat.Allocation memory alloc = ExitFormat.Allocation({
            destination: bytes32(uint256(uint160(0x96f7123E3A80C9813eF50213ADEd0e4511CB820f))),
            amount: 1,
            allocationType: uint8(ExitFormat.AllocationType.simple),
            metadata: ""
        });

        ExitFormat.SingleAssetExit memory sae = ExitFormat.SingleAssetExit({
            asset: address(0),
            assetMetadata: nullAssetMetadata,
            allocations: _toAllocationArray(alloc)
        });

        ExitFormat.SingleAssetExit[] memory exitArr = new ExitFormat.SingleAssetExit[](1);
        exitArr[0] = sae;

        bytes memory encodedExit = testConsumer.encodeExit(exitArr);

        // Expected encoding
        bytes memory expected = hex"0000000000000000000000000000000000000000000000000000000000000020"
        hex"0000000000000000000000000000000000000000000000000000000000000001"
        hex"0000000000000000000000000000000000000000000000000000000000000020"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000060"
        hex"00000000000000000000000000000000000000000000000000000000000000c0"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000040"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000001"
        hex"0000000000000000000000000000000000000000000000000000000000000020"
        hex"00000000000000000000000096f7123e3a80c9813ef50213aded0e4511cb820f"
        hex"0000000000000000000000000000000000000000000000000000000000000001"
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"0000000000000000000000000000000000000000000000000000000000000080"
        hex"0000000000000000000000000000000000000000000000000000000000000000";

        assertEq(keccak256(encodedExit), keccak256(expected), "Exit encoding mismatch");
    }

    function testExitsEqual() public {
        ExitFormat.AssetMetadata memory nullAssetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.Default,
            metadata: ""
        });

        ExitFormat.Allocation memory alloc = ExitFormat.Allocation({
            destination: bytes32(uint256(uint160(0x96f7123E3A80C9813eF50213ADEd0e4511CB820f))),
            amount: 1,
            allocationType: uint8(ExitFormat.AllocationType.simple),
            metadata: ""
        });

        ExitFormat.SingleAssetExit memory saeA = ExitFormat.SingleAssetExit({
            asset: address(0),
            assetMetadata: nullAssetMetadata,
            allocations: _toAllocationArray(alloc)
        });

        ExitFormat.SingleAssetExit[] memory exitA = _toExitArray(saeA);
        ExitFormat.SingleAssetExit[] memory exitB = _toExitArray(saeA);

        // Change asset for a difference.
        ExitFormat.SingleAssetExit memory saeC = ExitFormat.SingleAssetExit({
            asset: address(1),
            assetMetadata: nullAssetMetadata,
            allocations: _toAllocationArray(alloc)
        });
        ExitFormat.SingleAssetExit[] memory exitC = _toExitArray(saeC);

        bool eqAB = testConsumer.exitsEqual(exitA, exitB);
        bool eqAC = testConsumer.exitsEqual(exitA, exitC);
        assertTrue(eqAB, "Exits A and B should be equal");
        assertFalse(eqAC, "Exits A and C should not be equal");
    }

    function testExecuteNativeAssetExit() public {
        // Test native asset (ETH) exit execution.
        uint256 amount = 1; // 1 wei
        // Fund testConsumer with 2 wei.
        (bool sent, ) = address(testConsumer).call{value: 2} ("");
        require(sent, "Funding testConsumer failed");

        // Create a native asset exit with default asset metadata.
        ExitFormat.AssetMetadata memory nullAssetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.Default,
            metadata: ""
        });
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(0), alice, amount, nullAssetMetadata);

        // Execute as a single asset exit.
        testConsumer.executeSingleAssetExit(sae);
        // Check that alice’s balance increased by amount.
        assertEq(alice.balance, amount, "Alice did not receive native asset exit amount");

        // Now, execute using executeExit (array version).
        testConsumer.executeExit(_toExitArray(sae));
        assertEq(alice.balance, amount * 2, "Alice did not receive total native asset exit amount");
    }

    function testExecuteERC20AssetExit() public {
        // Deploy a simple ERC20 token with an initial supply.
        uint256 initialSupply = 1000 ether;
        TestERC20 token = new TestERC20(initialSupply);
        // Transfer all tokens from this contract (deployer) to testConsumer.
        token.transfer(address(testConsumer), initialSupply);
        assertEq(token.balanceOf(address(this)), 0, "Deployer should have 0 tokens");
        assertEq(token.balanceOf(address(testConsumer)), initialSupply, "TestConsumer should hold tokens");

        // Create an ERC20 exit (using Default asset metadata).
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.Default,
            metadata: ""
        });
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(token), address(this), initialSupply, assetMetadata);

        // Execute the ERC20 exit.
        testConsumer.executeSingleAssetExit(sae);
        assertEq(token.balanceOf(address(this)), initialSupply, "Deployer should receive tokens back");
        assertEq(token.balanceOf(address(testConsumer)), 0, "TestConsumer should have 0 tokens after exit");
    }

    function testExecuteERC721AssetExit() public {
        // Deploy an ERC721 token (the TestERC721 contract mints token IDs 11 and 22).
        TestERC721 token = new TestERC721();
        uint256 tokenId = 11;
        // Transfer tokenId 11 from this contract to testConsumer.
        token.transferFrom(address(this), address(testConsumer), tokenId);
        assertEq(token.ownerOf(tokenId), address(testConsumer), "TestConsumer should own the token");

        // Prepare the ERC721 exit:
        // For ERC721 exits the amount must be 1 and the metadata encodes the token ID.
        bytes memory tokenMeta = abi.encode(tokenId);
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC721,
            metadata: tokenMeta
        });
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(token), address(this), 1, assetMetadata);

        testConsumer.executeSingleAssetExit(sae);
        assertEq(token.ownerOf(tokenId), address(this), "ERC721 token not transferred correctly");
    }

    function testERC721ExitAmountFails() public {
        TestERC721 token = new TestERC721();
        uint256 tokenId = 11;
        // Transfer token to testConsumer.
        token.transferFrom(address(this), address(testConsumer), tokenId);
        bytes memory tokenMeta = abi.encode(tokenId);
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC721,
            metadata: tokenMeta
        });
        // Create an exit with an invalid amount (>1) for ERC721.
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(token), address(this), 10, assetMetadata);
        vm.expectRevert(bytes("Amount must be 1 for an ERC721 exit"));
        testConsumer.executeSingleAssetExit(sae);
    }

    function testERC721InvalidTokenIdFails() public {
        TestERC721 token = new TestERC721();
        uint256 invalidTokenId = 999;
        bytes memory tokenMeta = abi.encode(invalidTokenId);
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC721,
            metadata: tokenMeta
        });
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(token), address(this), 1, assetMetadata);
        // Expect a revert (the underlying ERC721 call should fail).
        vm.expectRevert();
        testConsumer.executeSingleAssetExit(sae);
    }

    function testExecuteERC1155AssetExit() public {
        uint256 initialSupply = 1000 ether;
        TestERC1155 token = new TestERC1155(initialSupply);
        uint256 tokenId = 11;
        // Transfer tokens (of tokenId 11) from this contract to testConsumer.
        token.safeTransferFrom(address(this), address(testConsumer), tokenId, initialSupply, "");
        assertEq(token.balanceOf(address(this), tokenId), 0, "Owner should have 0 tokens");
        assertEq(token.balanceOf(address(testConsumer), tokenId), initialSupply, "TestConsumer should hold tokens");

        // Prepare the ERC1155 exit.
        bytes memory tokenMeta = abi.encode(tokenId);
        ExitFormat.AssetMetadata memory assetMetadata = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC1155,
            metadata: tokenMeta
        });
        ExitFormat.SingleAssetExit memory sae = makeSimpleExit(address(token), address(this), initialSupply, assetMetadata);

        testConsumer.executeSingleAssetExit(sae);
        assertEq(token.balanceOf(address(this), tokenId), initialSupply, "Owner should receive tokens");
        assertEq(token.balanceOf(address(testConsumer), tokenId), 0, "TestConsumer should hold 0 tokens");
    }

    function testMultipleERC1155Exits() public {
        uint256 initialSupply = 1000 ether;
        TestERC1155 token = new TestERC1155(initialSupply);
        uint256 tokenAId = 11;
        uint256 tokenBId = 22;
        // Transfer tokens for both token IDs to testConsumer.
        token.safeTransferFrom(address(this), address(testConsumer), tokenAId, initialSupply, "");
        token.safeTransferFrom(address(this), address(testConsumer), tokenBId, initialSupply, "");
        assertEq(token.balanceOf(address(testConsumer), tokenAId), initialSupply, "Token A balance mismatch");
        assertEq(token.balanceOf(address(testConsumer), tokenBId), initialSupply, "Token B balance mismatch");

        // Create two exits—one for each token.
        bytes memory tokenAMeta = abi.encode(tokenAId);
        ExitFormat.AssetMetadata memory assetMetadataA = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC1155,
            metadata: tokenAMeta
        });
        ExitFormat.SingleAssetExit memory saeA = makeSimpleExit(address(token), address(this), initialSupply, assetMetadataA);

        bytes memory tokenBMeta = abi.encode(tokenBId);
        ExitFormat.AssetMetadata memory assetMetadataB = ExitFormat.AssetMetadata({
            assetType: ExitFormat.AssetType.ERC1155,
            metadata: tokenBMeta
        });
        ExitFormat.SingleAssetExit memory saeB = makeSimpleExit(address(token), address(this), initialSupply, assetMetadataB);

        ExitFormat.SingleAssetExit[] memory exits = new ExitFormat.SingleAssetExit[](2);
        exits[0] = saeA;
        exits[1] = saeB;

        testConsumer.executeExit(exits);
        assertEq(token.balanceOf(address(this), tokenAId), initialSupply, "Owner token A balance incorrect after exit");
        assertEq(token.balanceOf(address(this), tokenBId), initialSupply, "Owner token B balance incorrect after exit");
        assertEq(token.balanceOf(address(testConsumer), tokenAId), 0, "TestConsumer token A balance should be 0");
        assertEq(token.balanceOf(address(testConsumer), tokenBId), 0, "TestConsumer token B balance should be 0");
    }

    function testQualifiedAssets() public {
        uint256 amount = 1;
        // Fund testConsumer with a native asset (ETH).
        (bool sent, ) = address(testConsumer).call{value: amount}("");
        require(sent, "Funding testConsumer failed");

        // Bad case: wrong chain ID (use 1 instead of block.chainid)
        ExitFormat.SingleAssetExit memory saeBadChain = getQualifiedSAE(1, address(testConsumer), address(this), amount);
        testConsumer.executeSingleAssetExit(saeBadChain);
        // Since the exit is “foreign”, no transfer should occur.
        assertEq(address(this).balance, 0, "Qualified exit with bad chain ID should not transfer funds");

        // Bad case: wrong asset holder (using this contract instead of testConsumer)
        ExitFormat.SingleAssetExit memory saeBadHolder = getQualifiedSAE(block.chainid, address(this), address(this), amount);
        testConsumer.executeSingleAssetExit(saeBadHolder);
        assertEq(address(this).balance, 0, "Qualified exit with bad asset holder should not transfer funds");

        // Success case: correctly qualified exit.
        ExitFormat.SingleAssetExit memory saeGood = getQualifiedSAE(block.chainid, address(testConsumer), address(this), amount);
        testConsumer.executeSingleAssetExit(saeGood);
        assertEq(address(this).balance, amount, "Qualified exit with correct parameters failed");
    }

    // Allow this contract to receive ETH.
    receive() external payable {}
}
