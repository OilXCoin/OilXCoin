// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVesting {
  event ICOVestingAmountAdded(address indexed wallet, uint256 amount);

  function getVestedAmount(address from) external view returns (uint256);
  function addICOVestingAmount(address wallet, uint256 amount) external;
}
