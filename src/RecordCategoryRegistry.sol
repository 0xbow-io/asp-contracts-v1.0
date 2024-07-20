// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*  OpenZeppelin Imports */
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
/*  Zk-kit Imports */
import {InternalLeanIMT, LeanIMTData} from "zk-kit.solidity/packages/lean-imt/contracts/InternalLeanIMT.sol";

/**
 * @title   RecordCategoryRegistry contract
 * @notice  This contract can be deployed by any ASP to support
 *          onchain protocol integrations.
 * @notice  ⚠️ This contract is not audited and should be used with caution.
 * @dev This contract stores the categories for all known records
 *      hashes for a given scope.
 *      Set of record hashes within a scope is used to ccnstruct a
 *      lean-IMT (Incremental Merkle Tree).
 * @dev ⚠️ This contract implements roles to control certain actions
 *      such as creating stores and inserting / updating new records.
 *      Default admin role is set to the deployer of the contract.
 *      Admin also has the ability to grant the store adnmin role.
 *
 * @author  oxbow.io (https://github.com/0xbow-io/asp-store-v1)
 */
contract RecordCategoryRegistry is AccessControlDefaultAdminRules {
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;
    using InternalLeanIMT for LeanIMTData;

    error SenderIsNotAdmin(address sender);
    error InsufficientRole(address sender, bytes32 role);

    /// @notice Emitted when a record category is set or updated
    /// @param scope The protocol scope identifier
    /// @param root The new Merkle root after the update
    /// @param totalRecords The total number of records after the
    event Update(uint256 scope, uint256 root, uint256 totalRecords);

    /// @dev role identifier used to grant addresses ability to
    ///      update records in the store & recordTrees,
    bytes32 public constant STORE_ADMIN_ROLE = keccak256("STORE_ADMIN_ROLE");

    /// @notice Mapping of protocol scopes to their record categories
    /// @dev This mapping stores the category bitmaps for each record hash within a protocol scope
    /// @dev The outer mapping key is the protocol scope (uint256)
    /// @dev The inner mapping uses EnumerableMap.Bytes32ToBytes32Map xfor efficient enumeration
    /// @dev Record hashes (bytes32) are mapped to their category bitmaps (bytes32)
    /// @dev Each bit in the category bitmap represents a specific category that is defined by ASP / protocol
    /// @dev Using EnumerableMap library for easy iteration over the set of record hashes
    /// @dev For example:
    ///      - bit 0 (000..00): pending fee
    ///      - bit 1 (000..01): denied
    ///      - bit 2 (000..10): approved
    /// @notice  ⚠️ records cannot be removed or deleted.
    mapping(uint256 scope => EnumerableMap.Bytes32ToBytes32Map recCatMap)
        private _scopeRecordCategories;

    /// @notice Mapping of protocol scopes to their Merkle trees of record hashes
    /// @dev This mapping stores Merkle trees for efficient proof generation of record inclusion
    /// @dev The key is the protocol scope (uint256)
    /// @dev The value is a LeanIMTData struct, representing a Lean Incremental Merkle Tree
    /// @dev Each leaf in the Merkle tree corresponds to a record hash
    /// @dev This structure allows for:
    ///      - Efficient updates when new records are added
    ///      - Generation of inclusion proofs for any record
    ///      - Verification that a record belongs to a specific protocol scope
    /// @dev ⚠️ The Lean IMT library does not provide a straightfoward method to
    ///     iterate through the tree leaf nodes.
    ///     Instead iterate through recCatMap will iterate through the leaf nodes.
    ///     using the at(..) function from EnumerableMap.Bytes32ToBytes32Map library.
    mapping(uint256 scope => LeanIMTData merkleTree)
        private _scopeRecordMerkleTrees;

    /*//////////////////////////////////////////////////////////////////////////
                            ***MODIFIERS***
    //////////////////////////////////////////////////////////////////////////*/
    /// @dev modifier to check that the caller has the admin role
    modifier AdminOnly() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert SenderIsNotAdmin(msg.sender);
        }
        _;
    }

    /// @dev modifier to check that the caller has a specific role
    /// @param role is the role to check for
    modifier SufficientRole(bytes32 role) {
        if (!hasRole(role, msg.sender)) {
            revert InsufficientRole(msg.sender, role);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            ***CONTRACT CONSTRUCTOR***
    //////////////////////////////////////////////////////////////////////////*/
    constructor()
        AccessControlDefaultAdminRules(
            3 days,
            msg.sender /// Explicit initial `DEFAULT_ADMIN_ROLE` holder
        )
    {
        /// Grant the contract deployer the ability to create stores
        GrantStoreAdminRole(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            ***ADMIN FUNCTIONS***
    //////////////////////////////////////////////////////////////////////////*/
    /// @dev GrantStoreCreatorRole grants the STORE_ADMIN_ROLE to an address
    /// @param account the address to grant the role to
    function GrantStoreAdminRole(address account) public AdminOnly {
        grantRole(STORE_ADMIN_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            ***STORE_ADMIN_ROLE FUNCTIONS***
    //////////////////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets or updates the category for a record within a specific protocol scope
     *
     * @dev This function adds a new record or updates an existing one's category, and
     *     updates the Merkle tree if necessary.
     *
     * @param scope The unique identifier of the protocol instance
     * @param recordHash The hash of the record event
     * @param categoryBitmap A bytes32 representing the categories as a bitmap
     * @custom:access ⚠️ Restricted to accounts with STORE_ADMIN_ROLE
     **/
    function SetCategoryForRecord(
        uint256 calldata scope,
        bytes32 calldata recordHash,
        bytes32 calldata categoryBitmap
    ) public SufficientRole(STORE_ADMIN_ROLE) {
        // get current merkle root
        uint256 root = _scopeRecordMerkleTrees[scope]._root();
        /// .set() will return true/false if recordHash is an existing key
        /// if not an existing key, it means the record hash is new
        if (!_scopeRecordCategories[scope].set(recordHash, categoryBitmap)) {
            /// update the merkle tree with the new record hash
            /// and apply the new root value
            root = _scopeRecordMerkleTrees[scope]._insert(recordHash);
        }
        /// announce update by emitting an Update event
        emit Update(scope, root, _scopeRecordCategories[scope].length());
    }

    /*//////////////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
}