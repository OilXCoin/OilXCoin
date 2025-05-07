// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WithdrawContractsAccessControl} from "./WithdrawContracts.sol";
import "./IAMLChecker.sol";

/*
* @title OilXCoin AML Checker
* @author OilXCoin.io Dev Team
* @notice implements the AMLChecker Interface
*/
contract AMLChecker is IAMLChecker, WithdrawContractsAccessControl {
  event AMLLimitChanged(address indexed _address, uint256 _amount);

  mapping(address => uint256) public AMLLimit;

  /// @param defaultAdmin The address of the timelock controller
  constructor(address defaultAdmin) WithdrawContractsAccessControl(defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
  }

  function setAMLLimit(address addr, uint256 limit) public onlyRole(DEFAULT_ADMIN_ROLE) {
    AMLLimit[addr] = limit;
    emit AMLLimitChanged(addr, limit); //OXO-08
  }

  function AMLCheckPassed(address addr, uint256 amount) public view returns (bool) {
    // aml limit is 0 means no limit
    if (amount >= AMLLimit[addr] && AMLLimit[addr] != 0) return false;
    return true;
  }

  function checkAMLTransferAllowed(address from, address to, address sender, uint256 amount)
    external
    view
    returns (bool)
  {
    // check if from to and sender passes AMLCheckPassed
    if (
      !AMLCheckPassed(from, amount) || !AMLCheckPassed(to, amount)
        || !AMLCheckPassed(sender, amount)
    ) return false;
    return true;
  }
}
