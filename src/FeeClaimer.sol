// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {OilXNft} from "./OilXNft.sol";
import {OilXCoin} from "./OilXCoin.sol";
import "./OilXEnumDeclaration.sol";
import "./WithdrawContracts.sol";

/*
* @title OilXCoin Fee Claimer Contract
* @author OilXCoin.io Dev Team
* @notice this contract is responsible for claiming the royalties for the NFT holders and the
transfer fees*/
contract OilXFeeClaimer is WithdrawContractsAccessControl {
  using SafeERC20 for IERC20; //WCO-01

  bytes32 public constant BLOCKLIST_NFT_ROLE = keccak256("BLOCKLIST_NFT_ROLE");

  OilXNft public oilxNft;
  OilXCoin public oilxCoinToken;

  uint256 public transferFeesClaimed; // all fees that has been claimed yet (without NFT royalties)
  uint256 public totalNFTRoyaltiesClaimed; // all royalties that has been claimed by NFT holders yet
  bool public nftClaimingPaused; // pause the claiming process for EBIT scenario needs
  mapping(uint256 => bool) public nftBlocklist; // blocklist for NFTs, avoid claiming
  address public transferFeeClaimerAddress; // allowed address for claim transfer fees

  event RoyaltyClaimed(address indexed _to, uint256 _amount);
  event TransferFeeClaimed(uint256 _amount);
  event nftBlocklisted(uint256 indexed _tokenId, bool _blocklisted);
  event ClaimingPaused(bool indexed _paused);
  event TransferFeeClaimerAddressChanged(address indexed _oldClaimer, address indexed _newClaimer);

  /**
   * @notice constructor
   * @param oilxNftAddress address OilXNft contract address
   * @param oilxCoinTokenAddress address OilXCoin contract address
   * @param TimelockControllerAddress address Timelock controller address
   */
  constructor(
    address oilxNftAddress,
    address oilxCoinTokenAddress,
    address TimelockControllerAddress
  ) WithdrawContractsAccessControl(TimelockControllerAddress) {
    _grantRole(DEFAULT_ADMIN_ROLE, TimelockControllerAddress);
    oilxNft = OilXNft(oilxNftAddress);
    oilxCoinToken = OilXCoin(oilxCoinTokenAddress);
  }

  /*  setter and getter functions */
  /**
   * @return total royalties (12% of total fees)
   */
  function getTotalRoyalties() public view returns (uint256) {
    return oilxCoinToken.getTotalFeesAmount() * 12 / 100; // 12% of total fees = royalties
  }

  /**
   * @return total claimed transactionfees & royalties
   */
  function getTotalClaimed() public view returns (uint256) {
    return transferFeesClaimed + totalNFTRoyaltiesClaimed;
  }

  /**
   * @notice pause the claiming process
   * @param _paused boolean is claiming paused?
   */
  function pauseNftClaiming(bool _paused) public onlyRole(DEFAULT_ADMIN_ROLE) {
    nftClaimingPaused = _paused;
    emit ClaimingPaused(_paused); //OXO-08
  }

  /**
   * @notice blocklist an NFT
   * @param tokenId uint256 tokenId of the NFT
   * @param blocklisted boolean is NFT blocklisted?
   */
  function blocklistNft(uint256 tokenId, bool blocklisted) public onlyRole(BLOCKLIST_NFT_ROLE) {
    nftBlocklist[tokenId] = blocklisted;
    emit nftBlocklisted(tokenId, blocklisted);
  }

  /**
   * @notice set the address that can claim the transfer fees
   * @param _address address to set
   */
  function setTransferFeeClaimerAddress(address _address) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(_address != address(0), "OilXCoin: invalid transfer fee claimer address"); // OXO-05
    emit TransferFeeClaimerAddressChanged(transferFeeClaimerAddress, _address); //OXO-08
    transferFeeClaimerAddress = _address;
  }

  /**
   * claiming functions
   */

  /**
   * @notice the total amount of OilXCoin that must be available to this contract, used to calculate
   * the withdrawable amount
   * @return uint256 locked amount of OilXCoin
   */
  function getLockedAmountOilXCoin() public view returns (uint256) {
    uint256 totalNeededOilXCoin;
    // totalNeededOilXCoin = oilxCoinToken.getTotalFeesAmount( ) - transferFeesClaimed -
    // totalNFTRoyaltiesClaimed;
    totalNeededOilXCoin = oilxCoinToken.getTotalFeesAmount() - getTotalClaimed();
    return totalNeededOilXCoin;
  }

  /**
   * @notice get the maximum claimable transfer fees for the owner
   * @return claimableTransferFees uint256 claimable fees
   */
  function getUnClaimedTransferFeeAmount() public view returns (uint256) {
    uint256 totalTransferFees = oilxCoinToken.getTotalFeesAmount();
    totalTransferFees = totalTransferFees - getTotalRoyalties(); //12% for NFT holder
    uint256 claimableTransferFees = totalTransferFees - transferFeesClaimed;
    return claimableTransferFees;
  }

  /**
   * @notice get the total and unclaimed royalties for the NFT holder
   * @param tokenId uint256 tokenId of the NFT
   * @return nfttotalRoyalty uint256 total royalty for the given NFT
   * @return nftClaimableRoyalty uint256 claimable royalty for the given NFT
   */
  function getUnclaimedNFTRoyaltyAmount(uint256 tokenId)
    public
    view
    returns (uint256 nfttotalRoyalty, uint256 nftClaimableRoyalty)
  {
    /* get NFT Informations: type for multiplier, base amount of OilXCoin and already claimed
    royalties*/
    OilXNftTokenType nftType = oilxNft.tokenIdTokenType(tokenId);
    uint256 nftOilXCoinAmount = oilxNft.tokenIdOilXAmount(tokenId);
    uint256 nftAlreadyClaimedRoyalties = oilxNft.tokenIdOilXFeeClaimed(tokenId);

    /* based on NFT type calculate the multiplier */
    uint256 multiplier;
    if (nftType == OilXNftTokenType.SILVER) multiplier = 10;
    else if (nftType == OilXNftTokenType.GOLD) multiplier = 12;
    else if (nftType == OilXNftTokenType.PLATINUM) multiplier = 14;
    else if (nftType == OilXNftTokenType.DIAMOND) multiplier = 16;
    else revert("unknown token type!");

    /* total royalty is based on nft type and orginal base amount of OilXCoin */
    nfttotalRoyalty = calculateRoyalty(getTotalRoyalties(), nftOilXCoinAmount, multiplier);

    /* reduce total royalty of this NFT by already claimed royalties */
    nftClaimableRoyalty = nfttotalRoyalty - nftAlreadyClaimedRoyalties;
    return (nfttotalRoyalty, nftClaimableRoyalty);
  }

  /**
   * @notice claim and transfer specific amount of royalties to the NFT holder
   * @param tokenId uint256 tokenId of the NFT
   */
  function claimNFTRoyalty(uint256 tokenId, uint256 amount) public {
    require(msg.sender == oilxNft.ownerOf(tokenId), "claim must be done by owner!");
    require(!nftClaimingPaused, "claiming is paused!");
    require(!nftBlocklist[tokenId], "NFT is blocklisted!");
    require(amount > 0, "claiming zero makes no sense"); //OXC-08
    (, uint256 maxClaimable) = getUnclaimedNFTRoyaltyAmount(tokenId);
    require(amount <= maxClaimable, "amount exceeds claimable amount!");

    /* increase the claimed royalties for this NFT, store information into NFT */
    oilxNft.increaseClaimedOilXFee(tokenId, amount);
    totalNFTRoyaltiesClaimed += amount;
    emit RoyaltyClaimed(oilxNft.ownerOf(tokenId), amount);

    /* transfer royalties to the NFT holder */
    IERC20(address(oilxCoinToken)).safeTransfer(oilxNft.ownerOf(tokenId), amount); // WCO-01
  }

  /**
   * @notice claim and transfer all available royalties to the NFT holder
   * @param tokenId uint256 tokenId of the NFT
   */
  function claimAllNFTRoyalty(uint256 tokenId) public {
    (, uint256 maxClaimable) = getUnclaimedNFTRoyaltyAmount(tokenId);
    claimNFTRoyalty(tokenId, maxClaimable);
  }

  /**
   * @notice claim the transfer fees for the owner
   * @param _amount uint256 amount to send
   */
  function claimTransferFees(uint256 _amount) public {
    require(msg.sender == transferFeeClaimerAddress, "only allowed address can claim fees");
    require(_amount > 0, "claiming zero makes no sense"); //OXC-08
    require(_amount <= getUnClaimedTransferFeeAmount(), "amount exceeds claimable amount!");
    transferFeesClaimed += _amount;
    IERC20(oilxCoinToken).safeTransfer(transferFeeClaimerAddress, _amount);
    emit TransferFeeClaimed(_amount);
  }

  /**
   * @notice This function calculates the proportional amount available for these NFT properties
   * using the balance of all fees for NFT holders (12% transaction fee), based on the respective
   * base amount and NFT type
   * @param totalRoyalty uint256 total royalties for all NFT holders, 12% of total transfer fees
   * @param OilXCoinAmountBase uint256 the base amount of OilXCoin that the NFT holds as a voucher
   * @param NFTTypeMultiplier uint256 Multiplier (1.0, 1.2, 1.4 & 1.6x) based on NFT token type
   * @return amountRoyalty uint256 total royalty for the given NFT, payout will be recuded by
   * already claimed royalties
   */
  function calculateRoyalty(
    uint256 totalRoyalty,
    uint256 OilXCoinAmountBase,
    uint256 NFTTypeMultiplier
  ) public pure returns (uint256) {
    /* The maximum possible amount of OilXCoin is 20 million. The multiplier of the respective NFT
    types results in a calculation basis for 24.8M shares */
    uint256 TotalSilver = 8_000_000 * 10 * 10 ** 17;
    uint256 TotalGold = 5_000_000 * 12 * 10 ** 17;
    uint256 TotalPlatin = 2_000_000 * 14 * 10 ** 17;
    uint256 TotalDiamond = 5_000_000 * 16 * 10 ** 17;
    uint256 TotalShares = TotalSilver + TotalGold + TotalPlatin + TotalDiamond; // 24,800,000

    /* The amount of the original OilXCoin voucher of the NFT is increased by the NFT type
    multiplier. Due to the missing decimal point in the multiplier, we use 10 to the power of 17, 
    in the same calculation process, to get the royalties base amount with 18 decimal places. */
    uint256 RoyalityAmountBase = OilXCoinAmountBase * NFTTypeMultiplier * 10 ** 17;

    /* add temporarily 18 decimal places for accuracy in the calculation, and calculate the 24.8
    millionth share of the royalties, */
    uint256 amountRoyaltyPerShare = (totalRoyalty * 10 ** 36) / TotalShares;

    /* calculate royality amount for the NFT RoyalityBaseAmount and reduce the temporary 18 decimals*/
    uint256 amountRoyalty = RoyalityAmountBase * amountRoyaltyPerShare / 10 ** 36;

    return amountRoyalty;
  }

  /* override functions */
  // override erc20 withdraw function, to avoid to high amounts of OilXCoin are withdrawn
  function withdrawERC20(address _tokenAddress, address _to)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20 token = IERC20(_tokenAddress);
    uint256 balance = token.balanceOf(address(this));

    // only withdraw free disposable OilXCoin tokens
    if (_tokenAddress == address(oilxCoinToken)) {
      uint256 lockedAmount = getLockedAmountOilXCoin();
      require(balance > lockedAmount, "locked amount is higher than balance");
      balance = balance - lockedAmount;
      require(balance > 0, "no tokens to withdraw");
      emit WithdrawERC20(_tokenAddress, _to, balance);
      token.safeTransfer(_to, balance); // WCO-01
    } else {
      super.withdrawERC20(_tokenAddress, _to);
    }
  }
}
