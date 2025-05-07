// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Enumerable} from "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import "./IOilXCoinNFT.sol";
import {OilXCoin} from "./OilXCoin.sol";
import "./WithdrawContracts.sol";
import "./IVesting.sol";
import "./ICOdates.sol";

interface INftMintDate {
  function getNftMintTs(uint256 tokenId) external view returns (uint256);
}

interface IOilXCoinNftWrapper is IOilXCoinNFT, IERC721, IERC721Enumerable {
  // get token type from token id
  function tokenIdTokenType(uint256 tokenId) external view returns (OilXNftTokenType);
  // get blackNft amount
  function totalOilXCoinReward() external view returns (uint256);
}

/*
* @title OilXCoin Token Sale Claimer Contract
* @author OilXCoin.io Dev Team
* @notice This contract is responsible for claiming the OilXCoin tokens for the NFT holders
*/
contract NftTokenClaimerContract is WithdrawContractsAccessControl {
  using SafeERC20 for IERC20; //WCO-01

  bytes32 public constant CLAIMING_PAUSER_ROLE = keccak256("CLAIMING_PAUSER_ROLE");

  // OilXNft contract
  IOilXCoinNftWrapper public oilxNft;
  // OilXCoin contract
  OilXCoin public oilxCoinToken;
  // NftMinter contract
  INftMintDate public mintDates;

  bool public nftClaimingPaused; // pause the claiming process for EBIT scenario needs
  mapping(uint256 => uint256) public mVestingEndingTime;
  mapping(uint256 => bool) public nftBlocklist; // blocklist for NFTs
  uint256 public totalClaimedOilXCoin; // total OilXCoin claimed

  // mapping(uint256 => bool) public tokenIdHasClaimed;

  event TokenClaimed(address indexed _to, uint256 _amount);
  event nftBlocklisted(uint256 indexed _tokenId, bool _blocklisted);
  event ClaimingPaused(bool indexed _paused);
  event newTokenVestingEnd(uint256 indexed _tokenId, uint256 _endingTime);

  /**
   * @dev claim can only done by Owner and sent to his address
   * @param owner address of the owner
   * @param tokenId ID of the NFT
   */
  error claimOnlyOwner(address owner, uint256 tokenId);

  error NftClaimIsVested(uint256 tokenId, uint256 mintDate, uint256 vestingEndTime);

  /* 
     * @notice constructor, ownable contract, msg.sender is the owner
     * @param _oilxNftAddress address of OilXNft contract
     * @param _oilxCoinTokenAddress address of OilXCoin contract
     * @param _timelockController address of TimelockController as Defaultadmin
    */
  constructor(
    address _oilxNftAddress,
    address _oilxCoinTokenAddress,
    address _timelockController,
    address _mintDates
  ) WithdrawContractsAccessControl(_timelockController) {
    oilxNft = IOilXCoinNftWrapper(_oilxNftAddress);
    oilxCoinToken = OilXCoin(_oilxCoinTokenAddress);
    mintDates = INftMintDate(_mintDates);
    _grantRole(DEFAULT_ADMIN_ROLE, _timelockController);
  }

  /**
   * @notice pause the claiming process
   * @param _paused boolean is claiming paused?
   */
  function pauseNftClaiming(bool _paused) public onlyRole(CLAIMING_PAUSER_ROLE) {
    nftClaimingPaused = _paused;
    emit ClaimingPaused(_paused);
  }

  /**
   * @notice blocklist an NFT
   * @param tokenId uint256 tokenId of the NFT
   * @param blocklisted boolean is NFT blocklisted?
   */
  function blocklistNft(uint256 tokenId, bool blocklisted) public onlyRole(DEFAULT_ADMIN_ROLE) {
    nftBlocklist[tokenId] = blocklisted;
    emit nftBlocklisted(tokenId, blocklisted);
  }

  /* setVestingEndingTime
     * @notice set the vesting ending time for a specific NFT
     * @param tokenId ID of the NFT
     * @param endingTime ending time for the vesting
    */
  function setVestingEndingTime(uint256 tokenId, uint256 endingTime)
    public
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    mVestingEndingTime[tokenId] = endingTime;
    emit newTokenVestingEnd(tokenId, endingTime); //OXO-08
  }

  /* getVestingEndingTime
     * @notice get the vesting ending time for a specific NFT
     * @param tokenId ID of the NFT
     * @return ending time for the vesting
    */
  function getClaimableVestingEndingTime(uint256 tokenId, uint256 mintDate)
    private
    view
    returns (uint256)
  {
    // invidual vesting ending time for given NFT ?
    uint256 vEnd = mVestingEndingTime[tokenId];

    // if not set, calculate from NFT type
    if (vEnd == 0) {
      OilXNftTokenType nftType = oilxNft.tokenIdTokenType(tokenId);

      //Vesting Ending Time starting from mint or circulation date
      uint256 vestingStart;
      if (mintDate <= dayStartOfCirculation) vestingStart = dayStartOfCirculation;
      else vestingStart = mintDate;

      //Vesting Ending Time starting from claiming
      if (nftType == OilXNftTokenType.SILVER) vEnd = vestingStart + 30 days;
      else if (nftType == OilXNftTokenType.GOLD) vEnd = vestingStart + 60 days;
      else if (nftType == OilXNftTokenType.PLATINUM) vEnd = vestingStart + 90 days;
      else if (nftType == OilXNftTokenType.DIAMOND) vEnd = vestingStart + 365 days;
      else if (nftType == OilXNftTokenType.BLACK) vEnd = vestingStart + 365 days;
      else revert("unknown token type!");
    }
    return vEnd;
  }

  /*
     * @notice get the vesting information for a specific NFT
     * @dev mint date is stored in NftMinter contract
     * @param tokenId ID of the NFT
     * @return mintdate mint date of the NFT
     * @return vestingEndTime vesting ending time of the NFT
    */
  function getVestingInformation(uint256 tokenId)
    public
    view
    returns (uint256 mintdate, uint256 vestingEndTime)
  {
    mintdate = mintDates.getNftMintTs(tokenId);
    vestingEndTime = getClaimableVestingEndingTime(tokenId, mintdate);
    return (mintdate, vestingEndTime);
  }

  /*  @dev @OilXCoin claim
        @notice claim OilXCoin Entitlement for NFT holder 
        @param tokenId ID of the NFT
    */
  function claim(uint256 tokenId) public {
    // require(msg.sender == oilxNft.ownerOf(tokenId), "claim must be done by owner!");
    if (msg.sender != oilxNft.ownerOf(tokenId)) {
      revert claimOnlyOwner(oilxNft.ownerOf(tokenId), tokenId);
    }
    require(!nftClaimingPaused, "claiming is paused!");
    require(!nftBlocklist[tokenId], "NFT is blocklisted!");

    (uint256 mintDate, uint256 vestingEndTime) = getVestingInformation(tokenId);
    if (vestingEndTime > block.timestamp) {
      revert NftClaimIsVested(tokenId, mintDate, vestingEndTime);
    }

    // tokenIdHasClaimed[tokenId] = true;

    uint256 amountToClaim = oilxNft.resetClaimableOilX(tokenId); //Claim OilXCoin in NFT Contract
    require(amountToClaim > 0, "Claimer: OilXCoinNFT has no claimable OilXCoin");
    amountToClaim = amountToClaim * 10 ** oilxCoinToken.decimals(); //convert to "wei"
    // IERC20(address(oilxCoinToken)).safeTransfer(oilxNft.ownerOf(tokenId), amountToClaim);
    totalClaimedOilXCoin += amountToClaim;
    oilxCoinToken.NftClaimerMint(oilxNft.ownerOf(tokenId), amountToClaim);
    emit TokenClaimed(oilxNft.ownerOf(tokenId), amountToClaim);
  }

  function getLockedAmountOilXCoin() public view returns (uint256) {
    //contract doesn't hold any funds to claim, funds are reserved in ERC-20 contract
    return 0;
    // uint256 totalNeededOilXCoin = 20_000_000;
    // // 20_000_000 OilXCoin and Rewards
    // totalNeededOilXCoin =
    //   (20_000_000 + oilxNft.totalOilXCoinReward()) * 10 ** oilxCoinToken.decimals();
    // totalNeededOilXCoin = totalNeededOilXCoin - totalClaimedOilXCoin;
    // return totalNeededOilXCoin;
  }

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
