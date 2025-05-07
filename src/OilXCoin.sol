// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

//        .#      @
//       .@@@    @@@.
//      %@@@@@ =@% =@#
//     @@@@@@@@@     @@
//    @@@@@@@@@   =.  @@
//   @@@@@@@@@  .###   @@          *@@@@:   -@@. @@=   .##*   @@@    @@@@@      #@@@@.   #@@  @@@    @@
// .@@@@@@@@@  .#####   @@       @@@@=#@@@. -@@  @@=     ###.@@@   @@@@*@@@@  @@@@=#@@@  #@@  @@@@   @@
// @@@@@@@@@   #######   @@     :@@     %@@ -@@  @@=      ### @   @@@        =@@     @@@ #@@  @@@@@  @@
// @@@@@@@@@  #########  #@     :@@      @@ -@@  @@=      *###.   @@@        #@@     @@@ #@@  @@ :@@.@@
// @@@@@@@@@  #########  #@      @@@.  #@@@ -@@  @@+    .###-##+  .@@@   @@@  @@@   %@@* #@@  @@   @@@@
// @@@@@@@@@  .#######. .@@       .@@@@@@   -@@  @@@@@@.###  .###.  @@@@@@%    =@@@@@@   #@@  @@   .@@@
//  @@@@@@@@@:         .@@.
//   =@@@@@@@@@@     @@@.
//      :@@@@%..@@@@@.
//
// Disclaimer:
// The OilXCoin is issued as a ledger-based security under article 973d of the
// Swiss Code of Obligations. The tokenization terms of the OilXCoin are available
// under the following link: https://oilxcoin.io/terms

import {
  ERC20Upgradeable,
  ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlUpgradeable} from
  "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./WithdrawContractsAccessControlUpgradeable.sol";
import "./IOilXCoinNFT.sol";
import "./OilXNft.sol"; //NTC-01
import "./IAMLChecker.sol";
import "./IVesting.sol";
import "./INttToken.sol";
import "./TimelockControllerUpgradeable.sol";

/*
* @title OilXCoin Base Contract
* @author OilXCoin.io Dev Team
* @notice This contract enhances the standard ERC-20 functionality   
*/
abstract contract OilXCoinBase is Initializable, AccessControlUpgradeable, INttToken {
  uint256 public constant maxOilXCoinSupply = 100_000_000 * 10 ** 18;

  // OilXCoin Roles
  bytes32 public constant FEE_CHANGER_ROLE = keccak256("FEE_CHANGER_ROLE");
  bytes32 public constant FEE_EXEMPTIONLIST_ROLE = keccak256("FEE_EXEMPTIONLIST_ROLE");
  bytes32 public constant BLOCKLIST_REPORTER_ROLE = keccak256("BLOCKLIST_REPORTER_ROLE");
  bytes32 public constant BLOCKLIST_REMOVER_ROLE = keccak256("BLOCKLIST_REMOVER_ROLE");
  bytes32 public constant BRIDGE_MANAGER_ROLE = keccak256("BRIDGE_MANAGER_ROLE");
  bytes32 public constant BRIDGE_BURN_ROLE = keccak256("BRIDGE_BURN_ROLE");
  bytes32 public constant BRIDGE_MINT_ROLE = keccak256("BRIDGE_MINT_ROLE");

  // OilXCoin Events
  event FeeChanged(uint256 indexed oldFeeAmount, uint256 indexed newFeeAmount);
  event FeeAddressExemption(address indexed _address, bool hasExemption);
  event BlockListedAddressReported(address indexed _address);
  event BlockListedAddressRemoved(address indexed _address);
  event FeeClaimerContractChanged(address indexed oldFeeClaimer, address indexed newFeeClaimer);
  event NFTTokenClaimerContractChanged(
    address indexed oldNFTTokenClaimer, address indexed newNFTTokenClaimer
  );
  event AMLCheckerChanged(address indexed oldAMLChecker, address indexed newAMLChecker);
  event VestingContractChanged(
    address indexed oldVestingContract, address indexed newVestingContract
  );
  event CrossChainTransfer(address indexed account, uint256 value);

  /* error messages */
  error InsufficientUnvestedAmount(
    address account,
    uint256 unvestedAmount,
    uint256 vestedAmount,
    uint256 totalBalance,
    uint256 needed
  );

  error AddressIsBlocklisted(address account);
  error InvalidTransferAmount(uint256 value, uint256 totalSupply, uint256 bridgeBalance);

  /// @custom:storage-location erc7201:oilxcoin.storage.ERC20
  struct DataStorage {
    address addressNFT;
    uint256 defaultFeePoints;
    uint256 totalFeesAmount;
    address addressFeeClaimerContract;
    address addressNFTTokenClaimerContract;
    address addressAMLCheckerContract;
    address addressVestingContract;
    mapping(address => bool) feeExemptionlistFrom;
    mapping(address => bool) feeExemptionlistTo;
    mapping(address => bool) blocklistedAddresses;
    address NttBridgeManager;
    uint256 balanceBridges;
    uint256 reservedAmountNftClaimer;
  }

  // keccak256(abi.encode(uint256(keccak256("oilxcoin.storage.ERC20")) - 1)) &
  // ~bytes32(uint256(0xff))
  bytes32 private constant ERC7201_OILXCOIN_DATASTORAGE =
    0xeeef7df4ddfbef5d7d7d97729114dc8258dc3c78d21de8ca65f6cf78d1b50400;

  function getOilXCoinDataStorage() internal pure returns (DataStorage storage $) {
    assembly {
      $.slot := ERC7201_OILXCOIN_DATASTORAGE
    }
  }

  /**
   * @notice Bridges allow users to interact with different blockchains seamlessly.
   * OilXCoin uses a native token bridge: since our total token supply is fixed,
   * tokens are burned (reduced) on the originating chain and minted (generated)
   * on the target chain.
   */
  function setMinter(address newMinter) public override onlyRole(BRIDGE_MANAGER_ROLE) {
    if (newMinter == address(0)) revert InvalidMinterZeroAddress();

    /* apply role to new NttBridgeManager and remove old one */
    DataStorage storage $ = getOilXCoinDataStorage();
    require(newMinter != $.NttBridgeManager, "OilXCoin: newMinter address already used"); //OXC-04
    //OXO-02 new roles
    _grantRole(BRIDGE_BURN_ROLE, newMinter);
    _grantRole(BRIDGE_MINT_ROLE, newMinter);
    _revokeRole(BRIDGE_BURN_ROLE, $.NttBridgeManager);
    _revokeRole(BRIDGE_MINT_ROLE, $.NttBridgeManager);

    emit NewMinter($.NttBridgeManager, newMinter);
    $.NttBridgeManager = newMinter;
  }

  /**
   * @notice set transfer fee rate, feepoints are 1/10000 of the amount. e.g. 75 = 0.00075 = 0.75%,
   * @param newFeePoints 10000 = 1.00 = 100% ; 1 = 0.0001 = 0.01%
   */
  function setFeePoints(uint256 newFeePoints) public onlyRole(FEE_CHANGER_ROLE) {
    require(newFeePoints <= 75, "OilXCoin: max. FeePoints 0.75%");
    DataStorage storage $ = getOilXCoinDataStorage();
    require($.addressFeeClaimerContract != address(0), "OilXCoin: FeeClaimer address is zero");
    emit FeeChanged($.defaultFeePoints, newFeePoints);
    $.defaultFeePoints = newFeePoints;
  }

  /**
   * @notice set fee exemption for a "from" address
   * @param from address to be exempted fees when transfered from
   * @param hasExemption true if address is exempted from fees
   */
  function setFeeExemptionFrom(address from, bool hasExemption)
    public
    onlyRole(FEE_EXEMPTIONLIST_ROLE)
  {
    getOilXCoinDataStorage().feeExemptionlistFrom[from] = hasExemption;
    emit FeeAddressExemption(from, hasExemption);
  }

  /**
   * @notice set fee exemption for a "to" address
   * @param to address to be exempted fees when transfered to
   * @param hasExemption true if address is exempted from fees
   */
  function setFeeExemptionTo(address to, bool hasExemption) public onlyRole(FEE_EXEMPTIONLIST_ROLE) {
    getOilXCoinDataStorage().feeExemptionlistTo[to] = hasExemption;
    emit FeeAddressExemption(to, hasExemption);
  }

  /**
   * @notice add address to blocklist
   * @param _address address to be blocked for all transfers
   */
  function blocklistAddressReport(address _address) public onlyRole(BLOCKLIST_REPORTER_ROLE) {
    getOilXCoinDataStorage().blocklistedAddresses[_address] = true;
    emit BlockListedAddressReported(_address);
  }

  /**
   * @notice remove address from blocklist
   * @param _address address to be removed from blocklist
   */
  function blocklistAddressRemove(address _address) public onlyRole(BLOCKLIST_REMOVER_ROLE) {
    getOilXCoinDataStorage().blocklistedAddresses[_address] = false;
    emit BlockListedAddressRemoved(_address);
  }

  /**
   * @notice set the address of the FeeClaimer contract
   * @param newFeeClaimer address of the FeeClaimer contract
   */
  function setFeeClaimerContract(address newFeeClaimer) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(newFeeClaimer != address(0), "OilXCoin: FeeClaimer address is zero");
    DataStorage storage $ = getOilXCoinDataStorage();
    require($.addressFeeClaimerContract == address(0), "OilXCoin: FeeClaimer address already set"); // OXC-06
    setFeeExemptionFrom(newFeeClaimer, true); // set fee exemption for FeeClaimer
    setFeeExemptionTo(newFeeClaimer, true); // set fee exemption for FeeClaimer
    emit FeeClaimerContractChanged($.addressFeeClaimerContract, newFeeClaimer);
    $.addressFeeClaimerContract = newFeeClaimer;
    IOilXCoinNFT($.addressNFT).setAddressFeeClaimer(newFeeClaimer);
  }

  /**
   * @notice set the address of the NFTTokenClaimer contract
   * @param newNFTTokenClaimer address of the NFTTokenClaimer contract
   */
  function _setNFTTokenClaimerContract(address newNFTTokenClaimer) internal {
    require(newNFTTokenClaimer != address(0), "OilXCoin: NFTTokenClaimer address is zero");
    DataStorage storage $ = getOilXCoinDataStorage();
    setFeeExemptionFrom(newNFTTokenClaimer, true); // set fee exemption for NFTTokenClaimer
    setFeeExemptionTo(newNFTTokenClaimer, true); // set fee exemption for
    emit NFTTokenClaimerContractChanged($.addressNFTTokenClaimerContract, newNFTTokenClaimer);
    $.addressNFTTokenClaimerContract = newNFTTokenClaimer;
    IOilXCoinNFT($.addressNFT).setAddressTokenSaleClaimer(newNFTTokenClaimer);
  }

  /**
   * @notice set the address of the AMLChecker contract
   * @param newAMLChecker address of the AMLChecker contract
   */
  function setAMLCheckerContract(address newAMLChecker) public onlyRole(DEFAULT_ADMIN_ROLE) {
    DataStorage storage $ = getOilXCoinDataStorage();
    emit AMLCheckerChanged($.addressAMLCheckerContract, newAMLChecker);
    $.addressAMLCheckerContract = newAMLChecker;
  }

  /**
   * @notice set the address of the Vesting contract
   * @param newVestingContract address of the Vesting contract
   */
  function setVestingContract(address newVestingContract) public onlyRole(DEFAULT_ADMIN_ROLE) {
    DataStorage storage $ = getOilXCoinDataStorage();
    emit VestingContractChanged($.addressVestingContract, newVestingContract);
    $.addressVestingContract = newVestingContract;
  }

  //*** getter for datastorage ***/
  function getNFTAddress() external view returns (address) {
    return getOilXCoinDataStorage().addressNFT;
  }

  function getDefaultFeePoints() external view returns (uint256) {
    return getOilXCoinDataStorage().defaultFeePoints;
  }

  function getTotalFeesAmount() external view returns (uint256) {
    return getOilXCoinDataStorage().totalFeesAmount;
  }

  function getFeeClaimerContract() external view returns (address) {
    return getOilXCoinDataStorage().addressFeeClaimerContract;
  }

  function getNFTTokenClaimerContract() external view returns (address) {
    return getOilXCoinDataStorage().addressNFTTokenClaimerContract;
  }

  function getAMLCheckerContract() external view returns (address) {
    return getOilXCoinDataStorage().addressAMLCheckerContract;
  }

  function getVestingContract() external view returns (address) {
    return getOilXCoinDataStorage().addressVestingContract;
  }

  function getFeeExemptionFrom(address from) external view returns (bool) {
    return getOilXCoinDataStorage().feeExemptionlistFrom[from];
  }

  function getFeeExemptionTo(address to) external view returns (bool) {
    return getOilXCoinDataStorage().feeExemptionlistTo[to];
  }

  function getBlocklistedAddresses(address blocklistedAddress) external view returns (bool) {
    return getOilXCoinDataStorage().blocklistedAddresses[blocklistedAddress];
  }

  function getBridgeManager() external view returns (address) {
    return getOilXCoinDataStorage().NttBridgeManager;
  }

  /**
   * @notice get the balance of tokens on bridges
   * @return BridgeBalances the total amount of tokens on bridges
   * @dev this function is used by the bridge to check the total amount of tokens on bridges,
   *      to avoid minting more tokens than total max. supply
   */
  function getBridgeBalances() public view returns (uint256) {
    return getOilXCoinDataStorage().balanceBridges;
  }

  /**
   * @notice calculate the fee for a transfer
   * @param amount The amount of tokens to transfer
   * @param _from The address of the sender
   * @param _to The address of the receiver
   * @return The fee amount
   */
  function calculateFee(uint256 amount, address _from, address _to) public view returns (uint256) {
    DataStorage storage $ = getOilXCoinDataStorage();
    if (_from == address(0) || _to == address(0)) return 0; //OXX-01 mint and burn are feeless
    if ($.feeExemptionlistFrom[_from] || $.feeExemptionlistTo[_to]) return 0;
    uint256 feePoints = $.defaultFeePoints;
    uint256 fee = amount * feePoints / 10_000;
    return fee;
  }
}

/**
 * @title OilXCoin
 * @notice This contract is the main contract for the OilXCoin token.
 * @dev This contract extends base contract with upgradeable features
 */
contract OilXCoin is
  OilXCoinBase,
  ERC20Upgradeable,
  ERC20PausableUpgradeable,
  UUPSUpgradeable,
  WithdrawContractsAccessControlUpgradeable,
  TimelockControllerUpgradable
{
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE"); //OXO-01 OXC-02

  event OilXCoinMinted(address indexed _account, uint256 indexed _amount); //OXC-02
  event UpgradeAuthorized(address indexed newImplementation); //OXO-08
  event NftClaimerMinted(address indexed _account, uint256 indexed _amount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _adminAddress, address _nftAddress, address _timeLockController)
    public
    initializer
  {
    require(_adminAddress != address(0), "OilXCoin: adminAddress is zero"); // OXO-05
    require(_nftAddress != address(0), "OilXCoin: nftAddress is zero"); // OXO-05
    require(_timeLockController != address(0), "OilXCoin: timeLockController is zero"); // OXO-05
    __ERC20_init("OilXCoin", "OXC");
    __ERC20Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    // assign permanent Roles to TimeLockController and Admin
    _grantRole(DEFAULT_ADMIN_ROLE, _timeLockController);
    _grantRole(DEFAULT_ADMIN_ROLE, _adminAddress);
    _grantRole(BLOCKLIST_REMOVER_ROLE, _timeLockController);
    _grantRole(BLOCKLIST_REPORTER_ROLE, _adminAddress);

    _grantRole(FEE_CHANGER_ROLE, _timeLockController);
    _grantRole(FEE_EXEMPTIONLIST_ROLE, _timeLockController);

    _grantRole(MINTER_ROLE, _timeLockController);
    _grantRole(PAUSER_ROLE, _adminAddress);
    _grantRole(UPGRADER_ROLE, _timeLockController);
    _grantRole(WITHDRAWCONTRACT_ROLE, _timeLockController);
    _grantRole(UPGRADER_ROLE, _adminAddress); //ugprade process already includes timelock feature
    _grantRole(UPGRADE_PROPOSER_ROLE, _adminAddress);
    _grantRole(UPGRADE_CANCELLER_ROLE, _adminAddress);

    // assign temporary Roles to Admin for deployment
    _grantRole(FEE_CHANGER_ROLE, _adminAddress);
    _grantRole(FEE_EXEMPTIONLIST_ROLE, _adminAddress);

    // OilXCoin Initialization
    DataStorage storage $ = super.getOilXCoinDataStorage();
    $.addressNFT = _nftAddress;
    $.reservedAmountNftClaimer = 40_000_000 * 10 ** decimals(); // OIA-09
    // Initialize TimelockController
    super.initializeTimelockController(24 hours, _adminAddress, _adminAddress); //OXO-03
  }

  /**
   * @notice pause entire transfer transactions
   *
   */
  function pause() public onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice unpause entire transfer transactions
   *
   */
  function unpause() public onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  /**
   * @notice mint function is used by the bridge, mintOilXCoin is for creating new tokens
   *         but with a cap of 100m total supply (maxOilXCoinSupply) on all chains
   * @param _account address to be transfered to
   * @param _value amount for transfer
   */
  function mintOilXCoin(address _account, uint256 _value) public onlyRole(MINTER_ROLE) {
    uint256 maxSupplyWithoutNftClaimer =
      maxOilXCoinSupply - super.getOilXCoinDataStorage().reservedAmountNftClaimer;
    if (
      (_value > maxSupplyWithoutNftClaimer)
        || (_value + totalSupply() + super.getBridgeBalances() > maxSupplyWithoutNftClaimer)
    ) revert InvalidTransferAmount(_value, totalSupply(), super.getBridgeBalances());

    DataStorage storage $ = getOilXCoinDataStorage();
    uint256 feePoints = $.defaultFeePoints;
    $.defaultFeePoints = 0; // set fee to zero for minting
    _mint(_account, _value); // increase total supply  OXC-02
    $.defaultFeePoints = feePoints; // reset fee to default
    emit OilXCoinMinted(_account, _value);
  }

  /**
   * @notice set the address of the NFTTokenClaimer contract
   * @param newNFTTokenClaimer address of the NFTTokenClaimer contract
   * @dev   function moved to transfer funds for NTC-01
   */
  function setNFTTokenClaimerContract(address newNFTTokenClaimer)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(newNFTTokenClaimer != address(0), "OilXCoin: NFTTokenClaimer address is zero");
    DataStorage storage $ = getOilXCoinDataStorage();
    address oldClaimer = $.addressNFTTokenClaimerContract;
    // one time setter NTC-01, OXO-02
    require(oldClaimer == address(0), "OilXCoin: NFTTokenClaimer address already set");

    // funding TokenSaleClaimer
    // mintOilXCoin(newNFTTokenClaimer, 20_000_000 * 10 ** decimals());
    $.reservedAmountNftClaimer = 20_000_000 * 10 ** decimals();

    //NTC-01 Reward Program must be closed before, than transfer rewards to TokenSaleClaimer
    require(
      OilXNft(getOilXCoinDataStorage().addressNFT).isRewardProgramClosed(),
      "Reward Program must be closed before"
    );
    uint256 totalRewards = OilXNft(getOilXCoinDataStorage().addressNFT).totalOilXCoinReward();
    require(totalRewards <= 20_000_000, "totalRewards exceed 20_000_000");
    // mintOilXCoin(newNFTTokenClaimer, totalRewards * 10 ** decimals());
    $.reservedAmountNftClaimer += totalRewards * 10 ** decimals();
    super._setNFTTokenClaimerContract(newNFTTokenClaimer);
  }

  /**
   * @notice get the reserved amount for NFTTokenClaimer contract
   * @return reservedAmountNftClaimer the reserved amount for NFTTokenClaimer contract
   */
  function getReservedAmountNftClaimer() public view returns (uint256) {
    return getOilXCoinDataStorage().reservedAmountNftClaimer;
  }

  /**
   * @notice mint function for NFTTokenClaimer contract
   * @param _account address to be transfered to
   * @param _amount amount for transfer
   */
  function NftClaimerMint(address _account, uint256 _amount) public {
    DataStorage storage $ = getOilXCoinDataStorage();
    require(
      msg.sender == $.addressNFTTokenClaimerContract,
      "OilXCoin: only NFTTokenClaimer can call this function"
    );
    require(_amount <= $.reservedAmountNftClaimer, "OilXCoin: insufficient reserved amount");
    $.reservedAmountNftClaimer -= _amount;
    _mint(_account, _amount); // increase total supply
    emit NftClaimerMinted(_account, _amount);
  }

  /**
   * @notice Bridges allow users to interact with different blockchains seamlessly.
   * OilXCoin uses a native token bridge: since our total token supply is fixed,
   * tokens are burned (reduced) on the originating chain and minted (generated)
   * on the target chain.
   */

  /**
   * @notice wormhole bridge native token transfer calls mint function
   * @param _account address to be transfered to
   * @param _amount amount for transfer
   */
  function mint(address _account, uint256 _amount) public override onlyRole(BRIDGE_MINT_ROLE) {
    TransferFromBridge(_account, _amount);
  }

  /**
   * @notice wormhole bridge native token transfer calls burn function
   * @param _amount amount for transfer from message sender
   */
  function burn(uint256 _amount) public override onlyRole(BRIDGE_BURN_ROLE) {
    TransferToBridge(msg.sender, _amount);
  }

  /**
   * @notice transfer amount to another blockchain, decrease total supply
   * @param account address to be transfered from
   * @param value amount for transfer
   */
  function TransferToBridge(address account, uint256 value) public onlyRole(BRIDGE_BURN_ROLE) {
    if (value == 0) revert InvalidTransferAmount(value, totalSupply(), super.getBridgeBalances());
    if (value > balanceOf(account)) {
      revert ERC20InsufficientBalance(account, balanceOf(account), value);
    }
    // not the sender? allowance check and reduce allowance...
    if (account != msg.sender) _spendAllowance(account, msg.sender, value);
    super.getOilXCoinDataStorage().balanceBridges +=
      value - calculateFee(value, account, address(0)); // OXC-02 increase balance on bridges
    _burn(account, value); // decrease total supply
    // _update(account, address(0), value); // decrease total supply
    emit CrossChainTransfer(account, value);
  }

  /**
   * @notice transfer amount from another to this blockchain, increase total supply
   * @param account address to be transfered to
   * @param value amount for transfer
   */
  function TransferFromBridge(address account, uint256 value) public onlyRole(BRIDGE_MINT_ROLE) {
    // calculate max supply without reserved amount for NFTTokenClaimer
    uint256 maxSupplyWithoutNftClaimer =
      maxOilXCoinSupply - super.getOilXCoinDataStorage().reservedAmountNftClaimer;
    if (
      (value > maxSupplyWithoutNftClaimer) || (value + totalSupply() > maxSupplyWithoutNftClaimer)
    ) revert InvalidTransferAmount(value, totalSupply(), super.getBridgeBalances());
    super.getOilXCoinDataStorage().balanceBridges -= value; //OXC-02 decrease balance on bridges

    _mint(account, value); // increase total supply
    // _update(address(0), account, value); // increase total supply
    emit CrossChainTransfer(account, value);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
    super.authorizeUpgradeTimelockController(newImplementation); //OXO-03
    emit UpgradeAuthorized(newImplementation); //OXO-08
  }

  // The following functions are overrides required by Solidity.
  function _update(address from, address to, uint256 value)
    internal
    override(ERC20Upgradeable, ERC20PausableUpgradeable)
  {
    /* OilXCoin before transfer checks */
    DataStorage storage $ = super.getOilXCoinDataStorage();

    /* check if sender or receiver is blocklisted */
    //require(!$.blocklistedAddresses[from], "OilXCoin: from is blocklisted");
    if ($.blocklistedAddresses[from]) revert AddressIsBlocklisted(from);
    // require(!$.blocklistedAddresses[to], "OilXCoin: receiver is blocklisted");
    if ($.blocklistedAddresses[to]) revert AddressIsBlocklisted(to);
    // require(!$.blocklistedAddresses[msg.sender], "OilXCoin: sender is blocklisted");
    if ($.blocklistedAddresses[msg.sender]) revert AddressIsBlocklisted(msg.sender);

    /* call external AML checker contract */
    if ($.addressAMLCheckerContract != address(0)) {
      require(
        IAMLChecker($.addressAMLCheckerContract).checkAMLTransferAllowed(
          from, to, msg.sender, value
        ),
        "OilXCoin: AML check failed"
      );
    }

    /**
     * @dev check available amount, to avoid returning InssufficientsUnvestedAmount
     *       or only the feeValue instead of total amount
     */
    uint256 fromBalance = balanceOf(from);
    if (from != address(0) && fromBalance < value) {
      revert ERC20InsufficientBalance(from, fromBalance, value);
    }

    /* check vested amount */
    if ($.addressVestingContract != address(0) && from != address(0)) {
      uint256 vestedAmount = IVesting($.addressVestingContract).getVestedAmount(from);
      uint256 availableAmount = balanceOf(from) - vestedAmount;
      // require(value <= availableAmount, "OilXCoin: insufficient unvested funds");
      if (value > availableAmount && vestedAmount > 0) {
        revert InsufficientUnvestedAmount(
          from, availableAmount, vestedAmount, balanceOf(from), value
        );
      }
    }

    /* OilXCoin calculate fee and transfer to fee claimer contract */
    //if ($.addressFeeClaimerContract != address(0)) {
    if ($.defaultFeePoints > 0) {
      uint256 feeValue = calculateFee(value, from, to);
      if (feeValue > 0) {
        /* transfer transfer fee to FeeClaimer Contract */
        super._update(from, $.addressFeeClaimerContract, feeValue);
        $.totalFeesAmount += feeValue;
        value -= feeValue;
      }
    }

    /* Standard ERC-20 balances update */
    super._update(from, to, value);
  }
}
