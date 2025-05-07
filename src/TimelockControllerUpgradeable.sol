// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from
  "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/*
* @title Contract to TimeLock Upgradeable Contracts
* @author OilXCoin.io Dev Team
* @notice OXO-03 centralized control of contract upgrade 
* @dev based on OpenZeppelin TimelockControllerUpgradeable.sol
*/
contract TimelockControllerUpgradable is Initializable, AccessControlUpgradeable {
  bytes32 public constant UPGRADE_PROPOSER_ROLE = keccak256("UPGRADE_PROPOSER_ROLE");
  bytes32 public constant UPGRADE_CANCELLER_ROLE = keccak256("UPGRADE_CANCELLER_ROLE");

  /// @custom:storage-location erc7201:oilxcoin.storage.TimelockController
  struct TimelockControllerStorage {
    uint256 minDelay;
    address proposedImplementation;
    uint256 proposedUpgradeTimestamp;
  }

  // ERC-7201 namespace
  bytes32 private constant TimelockControllerStorageLocation =
    0x15e15d905bfcc836e0fad51df6d17d3941b2fd37c12b14d3a8107be9f9647300;

  function _getTimelockControllerStorage()
    private
    pure
    returns (TimelockControllerStorage storage $)
  {
    assembly {
      $.slot := TimelockControllerStorageLocation
    }
  }

  /**
   * @dev Emitted when the minimum delay for future operations is modified.
   */
  event MinDelayChange(uint256 indexed oldDuration, uint256 indexed newDuration);

  /**
   * @dev Emitted when a new upgrade is proposed.
   */
  event UpgradeProposed(address indexed implementation, uint256 indexed timestamp);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initialize the contract with the minimum delay and the proposer and canceller roles.
   * @param _minDelay The minimum delay before an upgrade can be executed.
   * @param _proposer The address that can propose an upgrade.
   * @param _canceller The address that can cancel a proposed upgrade.
   */
  function initializeTimelockController(uint256 _minDelay, address _proposer, address _canceller)
    public
    virtual
    initializer
  {
    if (_minDelay == 0) _minDelay = 24 hours;
    _getTimelockControllerStorage().minDelay = _minDelay;
    _grantRole(UPGRADE_PROPOSER_ROLE, _proposer);
    _grantRole(UPGRADE_CANCELLER_ROLE, _canceller);
  }

  /**
   * @notice Set the time delay before a proposed upgrade can be executed.
   * @param _minDelay The new delay time in seconds.
   */
  function setMinDelay(uint256 _minDelay) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_minDelay >= 3600 * 24, "minium delay for upgrade must be at least 1 day"); //TCU-01
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    emit MinDelayChange($.minDelay, _minDelay);
    $.minDelay = _minDelay;
  }

  /**
   * @notice Propose a new upgrade to the contract.
   * @param _newImplementation The address of the new implementation contract.
   */
  function proposeUpgrade(address _newImplementation) public onlyRole(UPGRADE_PROPOSER_ROLE) {
    require(_newImplementation != address(0), "Invalid implementation address");
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    $.proposedImplementation = _newImplementation;
    $.proposedUpgradeTimestamp = block.timestamp + $.minDelay;
    emit UpgradeProposed(_newImplementation, $.proposedUpgradeTimestamp);
  }

  /**
   * @notice Cancel a proposed upgrade to the contract.
   */
  function cancelUpgrade() public onlyRole(UPGRADE_CANCELLER_ROLE) {
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    require($.proposedUpgradeTimestamp != 0, "No upgrade proposed");
    $.proposedImplementation = address(0);
    $.proposedUpgradeTimestamp = 0;
  }

  function isUpgradeAuthorized(address _newImplementation) public view returns (bool) {
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    return (
      _newImplementation == $.proposedImplementation
        && block.timestamp >= $.proposedUpgradeTimestamp && $.proposedUpgradeTimestamp != 0
    );
  }

  function getProposedUpgradeInfo() public view returns (address implementation, uint256 timestamp) {
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    return ($.proposedImplementation, $.proposedUpgradeTimestamp);
  }

  function authorizeUpgradeTimelockController(address newImplementation) internal {
    TimelockControllerStorage storage $ = _getTimelockControllerStorage();
    require($.proposedImplementation != address(0), "No upgrade proposed");
    require($.proposedUpgradeTimestamp != 0, "No upgrade proposed");
    require(newImplementation == $.proposedImplementation, "Implementation address mismatch");
    require(block.timestamp >= $.proposedUpgradeTimestamp, "Timelock period not elapsed");

    // Reset the proposed upgrade data
    $.proposedImplementation = address(0);
    $.proposedUpgradeTimestamp = 0;
  }
}
