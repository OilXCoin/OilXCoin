  // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WithdrawContractsAccessControl} from "./WithdrawContracts.sol";
import "./IVesting.sol";
import "./ICOdates.sol";

/*
* @dev Since the vested amount isn’t visible in the wallet, this ERC-20 implementation can be
integrated to make the amounts visible.*/
abstract contract displayERC20 {
  string public constant name = "vested OilXcoin";
  string public constant symbol = "vOXC";
  uint8 public constant decimals = 18;

  function transfer(address _to, uint256 _value) public returns (bool) {
    revert("Not a real token - for display info only");
  }

  function approve(address _spender, uint256 _value) public returns (bool) {
    revert("Not a real token - for display info only");
  }

  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    revert("Not a real token - for display info only");
  }

  /// @dev Overridden in the vesting contract
  function balanceOf(address _owner) public view virtual returns (uint256 balance) {
    return 0;
  }

  function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
    return 0;
  }
}
/*
* @title OilXCoin Vesting Contract
* @author OilXCoin.io Dev Team
* @notice ICO tokens are vested for a certain period; this contract implements that logic. 
*/

contract VestingContract is IVesting, displayERC20, WithdrawContractsAccessControl {
  bytes32 public constant VESTING_EDITOR_ROLE = keccak256("VESTING_EDITOR_ROLE");

  bool public checkICOVesting = true;

  mapping(address => uint256) public ICOVestingAmount;

  event vestedICOAmount(address indexed wallet, uint256 vestedAmount, uint256 vestedAmount2);

  constructor(address defaultAdmin) WithdrawContractsAccessControl(defaultAdmin) {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(VESTING_EDITOR_ROLE, defaultAdmin);
  }

  /**
   * @notice Get the vested amount for a wallet
   * @param from the wallet address
   * @return The actual vested amount
   */
  function getVestedAmount(address from) public view returns (uint256) {
    uint256 vestedAmount = 0;

    // check ICO vested amounts
    if (checkICOVesting) {
      if (ICOVestingAmount[from] > 0) {
        vestedAmount += getICOvestedAmount(ICOVestingAmount[from], block.timestamp); //VCO-05
      }
    }
    return vestedAmount;
  }

  /// @notice ICO vesting in 10 phases, 10% each
  function getICOvestedAmount(uint256 amount, uint256 timestamp)
    public
    view
    returns (uint256 vestedAmount)
  {
    if (timestamp < day250701) return amount;
    else if (timestamp < day250801) return amount * 90 / 100;
    else if (timestamp < day250901) return amount * 80 / 100;
    else if (timestamp < day251001) return amount * 70 / 100;
    else if (timestamp < day251101) return amount * 60 / 100;
    else if (timestamp < day251201) return amount * 50 / 100;
    else if (timestamp < day260101) return amount * 40 / 100;
    else if (timestamp < day260201) return amount * 30 / 100;
    else if (timestamp < day260301) return amount * 20 / 100;
    else if (timestamp < day260401) return amount * 10 / 100;
    else return 0;
  }

  /// @notice Adds the amount of tokens for vesting purchased during the ICO
  function addICOVestingAmount(address wallet, uint256 amount) public onlyRole(VESTING_EDITOR_ROLE) {
    // require(checkICOVesting, "OilXCoin: ICO vesting is disabled"); //VCO-03
    ICOVestingAmount[wallet] += amount;
    emit ICOVestingAmountAdded(wallet, amount);
  }

  /// @dev Deactivates the check to save gas
  function setCheckICOVesting(bool _checkICOVesting) public onlyRole(DEFAULT_ADMIN_ROLE) {
    checkICOVesting = _checkICOVesting;
  }
  /**
   * @notice Emulates the vested amount as a “virtual” balance to enable display as a token in
   * wallets
   * @dev Returns the vested amount to be displayed as an ERC-20 token in wallets
   * @param _owner Wallet owner’s address to query
   * @return balance The actual vested amount
   */

  function balanceOf(address _owner) public view override returns (uint256 balance) {
    return getVestedAmount(_owner);
  }
}
