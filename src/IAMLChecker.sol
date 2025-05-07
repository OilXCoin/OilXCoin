// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAMLChecker {
  function checkAMLTransferAllowed(address from, address to, address sender, uint256 amount)
    external
    view
    returns (bool);
}
