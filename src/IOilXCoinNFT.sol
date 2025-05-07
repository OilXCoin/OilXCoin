// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OilXEnumDeclaration.sol";

/**
 * @dev OilXCoin Interfaces for contract interactions
 */

/*
* @title OilXNft
* @author OilXCoin.io Dev Team
* @notice Interface for OilXNft
*/
interface IOilXCoinNFT {
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
  event AddressNFTTokenClaimerChanged(address indexed oldAddress, address indexed newAddress);
  event RewardProgrammClosed();

  /**
   * @notice mint a new OilX NFT
   * @param to The address of the new NFT owner
   * @param tokenType The type of the NFT (PLATINUM, GOLD, SILVER, BLACK)
   * @param oilXTokenClaimable The amount of OILX tokens the NFT can claim
   */
  function safeMint(address to, OilXNftTokenType tokenType, uint256 oilXTokenClaimable) external;

  /**
   * @notice returns claimable OILX and resets to 0, for a given tokenId
   * @param tokenId ID of an OilXNFT
   * @return The amount of OILX which can be claimed
   */
  function resetClaimableOilX(uint256 tokenId) external returns (uint256);

  /**
   * @notice OilXCoin token contract can set the address of the token sale claimer contract
   * @param newAddress The address of the new token sale claimer contract
   */
  function setAddressTokenSaleClaimer(address newAddress) external;

  function increaseOilXRewards(uint256 tokenId, uint256 oilXAmount) external;
  function closeRewardProgram() external;

  /**
   * @notice increase amount of claimed ERC-20 fees for NFT. Function will be called by the fee
   * claiming contract
   * @param tokenId The ID of the NFT to increase the claimed fee amount
   * @param feeAmount The amount of ERC-20 fees to increase
   */
  function increaseClaimedOilXFee(uint256 tokenId, uint256 feeAmount) external;

  /**
   * @notice OilXCoin token contract can set the address of the fee claimer contract
   * @param newAddress The address of the new fee claimer contract
   */
  function setAddressFeeClaimer(address newAddress) external;

  /**
   * @notice set OilXCoin ERC-20 token contract address once
   * @param finalAddress The address of the OilXCoin ERC-20 token contract
   */
  function setAddressOilXCoin(address finalAddress) external;

  function updateMetaData(address newAddr) external;
}
