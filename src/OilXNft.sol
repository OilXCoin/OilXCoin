// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "./OilXEnumDeclaration.sol";
import "./WithdrawContracts.sol";

abstract contract NftMetadataRenderer {
  function getTokenURI(address _addressNft, uint256 _tokenId)
    public
    view
    virtual
    returns (bytes memory);
}

/*
* @title OilXNft
* @author OilXCoin.io Dev Team
* @notice Release Tests
*/
contract OilXNft is
  ERC721,
  IERC4906,
  ERC721Enumerable,
  AccessControl,
  WithdrawContractsAccessControl
{
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant REWARD_ROLE = keccak256("REWARD_ROLE");
  bytes32 public constant META_UPDATER = keccak256("META_UPDATER");

  uint256 private _nextTokenId;
  uint8 public constant feeDecimals = 18;

  /**
   * contract for rendering onchain or offchain metadata
   */
  address public addressMetaRenderer;

  /**
   * variables to set the final OilXCoin ERC-20 token contract.
   *   Only the OilXCoin contract can update the token sale and fee claimer contract address.
   */
  address public addressOilXCoin;
  address public addressTokenSaleClaimer;
  address public addressFeeClaimer;
  bool public isAddressOilXCoinSet = false;
  bool public isRewardProgramClosed = false;

  event OilXClaimed(uint256 indexed tokenId, uint256 amount);
  event ClaimedFeeIncreased(uint256 indexed tokenId, uint256 feeAmount);
  event RewardsBlackNFT(uint256 indexed tokenId, uint256 amount);
  event MintOilXNFT(
    address indexed to,
    uint256 indexed tokenId,
    OilXNftTokenType tokenType,
    uint256 indexed amountOilX
  );
  event AddressOilXCoinChanged(address indexed oldAddress, address indexed newAddress);
  event AddressFeeClaimerChanged(address indexed oldAddress, address indexed newAddress);
  event AddressTokenSaleClaimerChanged(address indexed oldAddress, address indexed newAddress);
  event RewardProgrammClosed();

  /**
   * How many tokens are still up for purchase?
   */
  mapping(OilXNftTokenType => uint256) public remainingToken;

  /**
   * How many tokens of a type have been sold?
   */
  mapping(OilXNftTokenType => uint256) public soldTokenType;

  /**
   * What token type (PLATINUM, GOLD, SILVER, BLACK) is the tokenid?
   */
  mapping(uint256 => OilXNftTokenType) public tokenIdTokenType;

  /**
   * How many tokens can token-id redeem? (e.g. token id 1 can redeem 100.000 tokens)
   */
  mapping(uint256 => uint256) public tokenIdOilXClaimable;

  /**
   * How many erc20 tokens were sold in total?
   * This is important for the ERC20 token claim contract
   */
  uint256 public totalOilXCoinSold;

  /**
   *   How many Rewards are available for BLACK NFTs
   */
  uint256 public totalOilXCoinReward;

  /**
   * OilX amount for each NFT to calculate fees
   */
  mapping(uint256 => uint256) public tokenIdOilXAmount;

  /**
   * Fee amount the NFT token-id has been already claimed
   */
  mapping(uint256 => uint256) public tokenIdOilXFeeClaimed;

  /**
   * @notice Constructor
   * @param defaultAdmin The address of the default admin
   */
  constructor(address defaultAdmin)
    ERC721("OilXNft", "OILX")
    WithdrawContractsAccessControl(defaultAdmin)
  {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

    remainingToken[OilXNftTokenType.DIAMOND] = 5 * 1_000_000;
    remainingToken[OilXNftTokenType.PLATINUM] = 20 * 100_000;
    remainingToken[OilXNftTokenType.GOLD] = 5_000_000;
    remainingToken[OilXNftTokenType.SILVER] = 8_000_000;

    addressMetaRenderer = address(this);
  }

  /**
   * @notice Returns ID of Black NFT for address
   * @param holder The address of the NFT owner
   * @return tokenId The ID of the black NFT, or 0 when no black NFT found
   */
  function getHolderBlackTokenID(address holder) public view returns (uint256 tokenId) {
    uint256 balance = balanceOf(holder);
    uint256 blackNFTid;
    for (uint256 i = 0; i < balance; i++) {
      blackNFTid = tokenOfOwnerByIndex(holder, i);
      if (tokenIdTokenType[blackNFTid] == OilXNftTokenType.BLACK) return uint256(blackNFTid); //OXO-10
    }
    return 0;
  }

  /**
   * @notice mint a new OilX NFT
   * @param to The address of the new NFT owner
   * @param tokenType The type of the NFT (PLATINUM, GOLD, SILVER, BLACK)
   * @param oilXTokenClaimable The amount of OILX tokens the NFT can claim
   */
  function safeMint(address to, OilXNftTokenType tokenType, uint256 oilXTokenClaimable)
    public
    onlyRole(MINTER_ROLE)
  {
    require(oilXTokenClaimable > 0, "zero claimaible token makes no sense"); //OXC-08

    if (tokenType == OilXNftTokenType.SILVER) {
      require(oilXTokenClaimable % 1000 == 0, "SILVER NFT can only claim a mutiple of 1,000 OILX.");
      require(oilXTokenClaimable <= 9000, "SILVER NFT can claim maxium 9,000 OILX.");
      require(
        remainingToken[OilXNftTokenType.SILVER] >= oilXTokenClaimable,
        "Not enough OILX for SILVER NFT left."
      );
    } else if (tokenType == OilXNftTokenType.GOLD) {
      require(oilXTokenClaimable % 10_000 == 0, "GOLD NFT can only claim a mutiple of 10,000 OILX.");
      require(oilXTokenClaimable <= 90_000, "GOLD NFT can claim maxium 90,000 OILX.");
      require(
        remainingToken[OilXNftTokenType.GOLD] >= oilXTokenClaimable,
        "Not enough OILX for GOLD NFT left."
      );
    } else if (tokenType == OilXNftTokenType.PLATINUM) {
      require(oilXTokenClaimable == 100_000, "PLATINUM NFT can only claim exact of 100,000 OILX.");
      require(
        remainingToken[OilXNftTokenType.PLATINUM] >= oilXTokenClaimable,
        "Not enough OILX for PLATINUM NFT left."
      );
    } else if (tokenType == OilXNftTokenType.DIAMOND) {
      require(
        oilXTokenClaimable == 1_000_000, "DIAMOND NFT can only claim exact of 1,000,000 OILX."
      );
      require(
        remainingToken[OilXNftTokenType.DIAMOND] >= oilXTokenClaimable,
        "Not enough OILX for DIAMOND NFT left."
      );
    } else if (tokenType == OilXNftTokenType.BLACK) {
      // black NFT already exists for address?
      if (getHolderBlackTokenID(to) != 0) revert("BLACK NFT already exists for address");
      // Rewards program closed?
      require(!isRewardProgramClosed, "Rewards program closed");
      require(oilXTokenClaimable <= 1_000_000, "BLACK NFT maximum OILX amount exceeded.");
    } else {
      revert("Invalid NFT type");
    }

    uint256 tokenId = _nextTokenId++;
    // _safeMint(to, tokenId); // OXO-11
    tokenIdTokenType[tokenId] = tokenType;
    tokenIdOilXClaimable[tokenId] = oilXTokenClaimable;
    tokenIdOilXAmount[tokenId] = oilXTokenClaimable; // OilX amount for each NFT to calculate Fees
    emit MintOilXNFT(to, tokenId, tokenType, oilXTokenClaimable);

    if (tokenType != OilXNftTokenType.BLACK) {
      remainingToken[tokenType] -= oilXTokenClaimable;
      soldTokenType[tokenType]++;
      totalOilXCoinSold += oilXTokenClaimable;
    } else {
      if (tokenId == 0) revert("TokenID 0 should not be a BlackNFT");
      totalOilXCoinReward += oilXTokenClaimable;
      require(totalOilXCoinReward <= 20_000_000, "totalRewards exceed 20_000_000"); //NTC-01
    }
    _safeMint(to, tokenId); // OXO-11
  }

  /**
   * @notice returns claimable OILX and resets to 0, for a given tokenId
   * @param tokenId ID of an OilXNFT
   * @return The amount of OILX which can be claimed
   */
  function resetClaimableOilX(uint256 tokenId) public returns (uint256) {
    require(
      msg.sender == addressTokenSaleClaimer,
      "only token sale claimer contract can use this function"
    );
    require(_ownerOf(tokenId) != address(0), "operator query for nonexistent token");
    require(tokenIdOilXClaimable[tokenId] > 0, "OilXNft: no OilXCoin to claim");

    /* important oilXtoClaim is NOT in 18 decimals */
    uint256 oilXToClaim = tokenIdOilXClaimable[tokenId];
    tokenIdOilXClaimable[tokenId] = 0;

    emit OilXClaimed(tokenId, oilXToClaim);
    emit MetadataUpdate(tokenId);
    return oilXToClaim;
  }

  /**
   * @notice OilXCoin token contract can set the address of the token sale claimer contract
   * @param newAddress The address of the new token sale claimer contract
   */
  function setAddressTokenSaleClaimer(address newAddress) public {
    require(msg.sender == addressOilXCoin, "only OilXCoin contract can use this function");
    require(newAddress != address(0), "new address is the zero address");
    emit AddressTokenSaleClaimerChanged(addressTokenSaleClaimer, newAddress);
    addressTokenSaleClaimer = newAddress;
  }

  /**
   * @notice increase BLACK NFT OilX amount for Token ID
   * @param tokenId The ID of the Black NFT to increase OilX Rewards
   * @param oilXAmount The amount of OILX to increase
   */
  function increaseOilXRewards(uint256 tokenId, uint256 oilXAmount) public onlyRole(REWARD_ROLE) {
    require(!isRewardProgramClosed, "Reward program closed");
    require(oilXAmount > 0, "zero amount makes no sense"); //OXC-08
    require(
      tokenIdTokenType[tokenId] == OilXNftTokenType.BLACK, "only BLACK NFT can collect OilX rewards"
    );

    tokenIdOilXAmount[tokenId] += oilXAmount;
    require(tokenIdOilXAmount[tokenId] <= 1_000_000, "BLACK NFT maximum OILX amount exceeded.");

    tokenIdOilXClaimable[tokenId] += oilXAmount;
    totalOilXCoinReward += oilXAmount;
    require(totalOilXCoinReward <= 20_000_000, "totalRewards exceed 20_000_000"); //NTC-01
    emit RewardsBlackNFT(tokenId, oilXAmount);
    emit MetadataUpdate(tokenId);
  }

  function closeRewardProgram() public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(!isRewardProgramClosed, "Reward program already closed");
    isRewardProgramClosed = true;
    emit RewardProgrammClosed();
  }

  /**
   * @notice increase amount of claimed ERC-20 fees for NFT. Function will be called by the fee
   * claiming contract
   * @param tokenId The ID of the NFT to increase the claimed fee amount
   * @param feeAmount The amount of ERC-20 fees to increase
   */
  function increaseClaimedOilXFee(uint256 tokenId, uint256 feeAmount) public {
    /* important oilXAmount is in 18 decimals */
    require(msg.sender == addressFeeClaimer, "only fee claimer contract can use this function");
    require(_ownerOf(tokenId) != address(0), "operator query for nonexistent token");
    require(tokenIdTokenType[tokenId] != OilXNftTokenType.BLACK, "BLACK NFT cannot claim fees");

    tokenIdOilXFeeClaimed[tokenId] += feeAmount;

    emit ClaimedFeeIncreased(tokenId, feeAmount);
    emit MetadataUpdate(tokenId);
  }

  /**
   * @notice OilXCoin token contract can set the address of the fee claimer contract
   * @param newAddress The address of the new fee claimer contract
   */
  function setAddressFeeClaimer(address newAddress) public {
    require(msg.sender == addressOilXCoin, "only OilXCoin contract can use this function");
    require(newAddress != address(0), "new address is the zero address");
    emit AddressFeeClaimerChanged(addressFeeClaimer, newAddress);
    addressFeeClaimer = newAddress;
  }

  /**
   * @notice set OilXCoin ERC-20 token contract address once
   * @param finalAddress The address of the OilXCoin ERC-20 token contract
   */
  function setAddressOilXCoin(address finalAddress) public {
    if (isAddressOilXCoinSet) {
      require(msg.sender == addressOilXCoin, "only OilXCoin contract can use this function");
    } else {
      require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "only admin can use this function");
    }

    require(finalAddress != address(0), "new address is the zero address");
    emit AddressOilXCoinChanged(addressOilXCoin, finalAddress);
    addressOilXCoin = finalAddress;
    isAddressOilXCoinSet = true;
  }

  /**
   * @notice Contract for rendering onchain or offchain metadata
   * @param newAddr The address of the contract implementing the NftMeta interface / abstract
   * contract above
   */
  function updateMetaData(address newAddr) public onlyRole(META_UPDATER) {
    require(newAddr != address(0), "OilXCoinNFT: address zero invalid"); //OXO-05
    addressMetaRenderer = newAddr;
    if (totalSupply() > 0) emit BatchMetadataUpdate(0, totalSupply() - 1);
  }

  /**
   * @notice "empty" TokenURI function to be overridden by the metadata rendering contract
   * @param addressNft of this NFT contract for callbacks
   * @param tokenId The ID of the NFT to update the metadata
   */
  function getTokenURI(address addressNft, uint256 tokenId) public view returns (bytes memory) {
    address renderer = OilXNft(addressNft).addressMetaRenderer();
    return abi.encodePacked(
      "Metadata not bound",
      Strings.toHexString(addressNft),
      " ",
      Strings.toHexString(renderer),
      " ",
      Strings.toString(tokenId)
    );
  }

  /**
   * @notice ERC-721 Standard TokenURI function
   * @param tokenId The ID of the NFT to update the metadata
   */
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireOwned(tokenId);
    NftMetadataRenderer metadataRenderer = NftMetadataRenderer(addressMetaRenderer);

    bytes memory data = metadataRenderer.getTokenURI(address(this), tokenId);

    return string(abi.encodePacked("data:application/json;base64,", Base64.encode(data)));
  }

  // The following functions are overrides required by Solidity.

  function _update(address to, uint256 tokenId, address auth)
    internal
    override(ERC721, ERC721Enumerable)
    returns (address)
  {
    return super._update(to, tokenId, auth);
  }

  function _increaseBalance(address account, uint128 value)
    internal
    override(ERC721, ERC721Enumerable)
  {
    super._increaseBalance(account, value);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(IERC165, ERC721, ERC721Enumerable, AccessControl)
    returns (bool)
  {
    // https://eips.ethereum.org/EIPS/eip-4906  IERC4906 Events
    return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
  }
}
