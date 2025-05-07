// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IOilXCoinNFT.sol";
import "./WithdrawContracts.sol";

interface INftOXC is IOilXCoinNFT {
  function ownerOf(uint256 tokenId) external view returns (address owner);
  function totalSupply() external view returns (uint256);
  function balanceOf(address owner) external view returns (uint256);
  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
  function safeMint(address to) external;
}

/**
 * @title NftMinter
 * @notice Contract for minting NFTs with timestamp tracking
 * @dev grant NFT minter role to this contract and remove minter role form old salescontract and
 * batchminter, grant this MINTER_ROLE to new salescontract
 */
contract NftMinter is WithdrawContractsAccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  INftOXC oilXNftContract;
  bool public allowBatchMint;

  mapping(uint256 => uint256) public NftMintTs;

  event MintOilXNFT(
    address indexed to,
    uint256 indexed tokenId,
    OilXNftTokenType tokenType,
    uint256 indexed amountOilX
  );

  event MintOilXCoinNftTs(
    address indexed to, uint256 indexed tokenId, uint256 indexed amountOilXCoin, uint256 timestamp
  );

  /**
   * for ABI decode event from NFT
   */
  event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

  struct Basket {
    OilXNftTokenType purchaseNFTtype;
    uint32 quantity;
    uint32 amountOilX;
  }

  /**
   * @notice Emitted when batch minting is enabled or disabled
   * @param enabled The new state of batch minting
   */
  event BatchMintEnabled(bool enabled);

  /**
   * @notice Emitted when NFT contract address is updated
   * @param oldAddress Previous NFT contract address
   * @param newAddress New NFT contract address
   */
  event NFTContractAddressUpdated(address indexed oldAddress, address indexed newAddress);

  /**
   * @notice Emitted when NFT is minted with timestamp
   * @param to Address receiving the NFT
   * @param tokenId ID of minted NFT
   * @param timestamp Block timestamp when NFT was minted
   */
  event NFTMintedWithTimestamp(address indexed to, uint256 indexed tokenId, uint256 timestamp);

  constructor(address _addressOilXNft, address _admin, address _minter)
    WithdrawContractsAccessControl(_admin)
  {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MINTER_ROLE, _minter);
    oilXNftContract = INftOXC(_addressOilXNft);
    allowBatchMint = true;
  }

  function getNFTAddress() public view returns (address) {
    return address(oilXNftContract);
  }

  function setOnOff(bool _allowBatchMint) public onlyRole(DEFAULT_ADMIN_ROLE) {
    allowBatchMint = _allowBatchMint;
  }

  /**
   * @notice Mints multiple NFTs in a single transaction
   * @param to The address that will own the minted NFTs
   * @param basket An array of Basket structs containing the NFT type and quantity
   * @dev Requires batchmint to be enabled and valid address
   */
  function batchmint(address to, Basket[] memory basket) public onlyRole(MINTER_ROLE) {
    require(allowBatchMint, "Error: batchmint is off");
    require(to != address(0), "Error: address is zero");

    for (uint8 i = 0; i < basket.length; i++) {
      /* mint NFTs for each basket position */
      for (uint8 amount = 0; amount < basket[i].quantity; amount++) {
        safeMintTs(to, basket[i].purchaseNFTtype, basket[i].amountOilX);
      }
    }
  }

  /**
   * @notice Mints a new NFT with timestamp tracking
   * @param to The address that will own the minted NFT
   * @param tokenType The type of NFT to mint (PLATINUM, GOLD, SILVER, BLACK)
   * @param oilXTokenClaimable The amount of OILX tokens that can be claimed with this NFT
   * @dev Mints NFT via nftContract.safeMint() and records timestamp
   * @dev Emits MintOilXCoinNftTs event with token details and timestamp
   */
  function safeMintTs(address to, OilXNftTokenType tokenType, uint256 oilXTokenClaimable)
    public
    onlyRole(MINTER_ROLE)
  {
    uint256 nextTokenId = oilXNftContract.totalSupply();
    NftMintTs[nextTokenId] = block.timestamp; //OIA-10
    emit MintOilXCoinNftTs(to, nextTokenId, oilXTokenClaimable, block.timestamp);

    oilXNftContract.safeMint(to, tokenType, oilXTokenClaimable);
    uint256 newSupply = oilXNftContract.totalSupply();
    require(newSupply == nextTokenId + 1, "nothing minted");
    require(to == oilXNftContract.ownerOf(nextTokenId), "token belongs to other address");
    // uint256 balance = nftEnumerable.balanceOf(to);
    // require(balance > 0, "Nothing minted");
    // uint256 tokenId = nftEnumerable.tokenOfOwnerByIndex(to, balance - 1);
    // require(totalSupply == tokenId, "Token ID mismatch");
  }

  /**
   * @notice Retrieves the timestamp when an NFT was minted
   * @param tokenId The ID of the NFT to check
   * @return The timestamp when the NFT was minted
   * @dev Requires the NFT to exist and be minted
   */
  function getNftMintTs(uint256 tokenId) public view returns (uint256) {
    require(oilXNftContract.ownerOf(tokenId) != address(0), "token not minted");
    return NftMintTs[tokenId];
  }
}
