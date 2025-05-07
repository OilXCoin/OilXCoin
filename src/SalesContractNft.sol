// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./OilXEnumDeclaration.sol";
import "./WithdrawContracts.sol";
import "./NftMinter.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; //OIA-10

abstract contract ChainlinkOracle {
  function latestAnswer() public view virtual returns (int256);

  function latestRoundData()
    public
    view
    virtual
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

/* 
* @title OilXCoin NFT Sales Contract
* @notice This contract allows users to purchase OilXCoin NFTs by paying Ether. 
*         Each NFT represents a specified amount of OilXCoin tokens.
*/
contract SalesContractNft is WithdrawContractsOwnable, ReentrancyGuard {
  NftMinter nftMinter;

  address internal _oilXCoinContractAddress;
  address internal _salesWalletAddress;

  uint256 internal _exchangeRatePerOxcInUsd;
  uint256 internal _maxRateETH2USD;
  uint256 internal _minRateETH2USD;
  uint256 public totalOrders;

  uint256 private _exchangeRateETHUSDfixed;
  bool private _useexchangeRateETHUSDfixed; // Chainlink not exists on testnet
  address internal _addressChainlinkOracle;

  bool privateSaleOnly = true;

  event Purchase(
    address indexed to,
    OilXNftTokenType nftType,
    uint32 quantity,
    uint32 amountOXC,
    uint256 orderId,
    uint256 orderPos
  );

  /**
   * for ABI decode event in webshop
   */
  event MintOilXNFT(
    address indexed to,
    uint256 indexed tokenId,
    OilXNftTokenType tokenType,
    uint256 indexed amountOXC
  );

  /**
   * for ABI decode event in webshop
   */
  event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

  // store order information
  struct Basket {
    OilXNftTokenType purchaseNFTtype;
    uint32 quantity;
    uint32 amountOXC;
  }

  struct Order {
    address buyer;
    uint256 timestamp;
    uint256 exchangeRate;
    uint256 totalAmount;
    uint256 numPositions;
    mapping(uint256 => Basket) positions;
  }

  mapping(uint256 => Order) public orderbook;

  /*
  * @notice Constructor for the SalesContractNft contract
  * @param _addressNftMinter The address of the NftMinter contract
  * @dev NftMinter contract stores mint date for each NFT for vesting
  */
  constructor(address _addressNftMinter, address _salesWallet, address _owner)
    WithdrawContractsOwnable(_owner)
  {
    require(_addressNftMinter != address(0), "nft minter address not set");
    require(_salesWallet != address(0), "sales wallet address not set");
    require(_owner != address(0), "owner address not set");

    _salesWalletAddress = _salesWallet; //receives ETH from sales
    nftMinter = NftMinter(_addressNftMinter);

    // Chainlink Oracle address for ETH/USD rate
    _addressChainlinkOracle = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    _useexchangeRateETHUSDfixed = false;
    _exchangeRateETHUSDfixed = 1750 * 10 ** decimals(); // price approx at 22.04.2025
    _maxRateETH2USD = 3000 * 10 ** decimals(); // 1 ETH = 3000 US$
    _minRateETH2USD = 1500 * 10 ** decimals();
    _exchangeRatePerOxcInUsd = 1 * 10 ** decimals(); // 1 OXC = 1 US$
  }

  function decimals() public pure returns (uint8) {
    return 18;
  }

  function getRateETH2USD() public view returns (uint256) {
    // ETH 2 USD rate - on testnet chainlink not exists
    uint256 rate;
    if (_useexchangeRateETHUSDfixed) {
      rate = uint256(_exchangeRateETHUSDfixed);
    } else {
      ChainlinkOracle oracle = ChainlinkOracle(_addressChainlinkOracle);
      (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
      require(block.timestamp - updatedAt <= 3600, "Stale price"); //OIA-02
      rate = uint256(answer);
      rate = rate * 10 ** (decimals() - 8); // convert from 10**8 to 10**18
    }
    require(rate > 0, "ETH2USD rate invalid");
    return rate;
  }

  function getRatePerOxcInUsd() public view returns (uint256) {
    return (_exchangeRatePerOxcInUsd);
  }

  function setExchangeRateOilXCoin(uint256 _newrate) public onlyOwner {
    require(_newrate > 0, "exchange rate USD / OilXCoin OXC must be greater than 0"); //OIA-03
    _exchangeRatePerOxcInUsd = _newrate;
  }

  // @dev tolerance for ETH2USD rate
  function setExchangeRateETHmin(uint256 minValue) public onlyOwner {
    _minRateETH2USD = minValue;
  }

  // @dev fallback for manual exchange rate
  function setexchangeRateETHUSDfixed(uint256 value) public onlyOwner {
    _exchangeRateETHUSDfixed = value;
  }

  // @dev fallback for manual exchange rate
  function setuseexchangeRateETHUSDfixed(bool value) public onlyOwner {
    _useexchangeRateETHUSDfixed = value;
  }

  // @dev tolerance for ETH2USD rate
  function setExchangeRateETHmax(uint256 maxValue) public onlyOwner {
    _maxRateETH2USD = maxValue;
  }

  function setChainLinkOracle(address address_) public onlyOwner {
    // depends on chain, can be deactivated by setting to address(0)
    _addressChainlinkOracle = address_;
  }

  /*
  * @notice read order basket from orderbook
  * @param orderId The ID of the order
  * @return basket The basket of the order
  */
  function getOrderBasket(uint256 orderId) public view returns (Basket[] memory) {
    Basket[] memory basket = new Basket[](orderbook[orderId].numPositions);

    for (uint256 i = 0; i < orderbook[orderId].numPositions; i++) {
      basket[i] = orderbook[orderId].positions[i];
    }
    return basket;
  }

  /*
  * @notice get the contract address
  * @return _oilXCoinContractAddress The address of the OilXCoin NFT contract
  */
  function getContractAddress() public view returns (address) {
    return _oilXCoinContractAddress;
  }

  /*
  * @notice set the sales wallet address
  * @param salesWallet The address of the sales wallet
  */
  function setSalesWalletAddress(address salesWallet) public onlyOwner {
    require(salesWallet != address(0), "zero address not allowed");
    _salesWalletAddress = salesWallet;
  }

  function getSalesWalletAddress() public view returns (address) {
    return _salesWalletAddress;
  }

  /// @dev purchase NFTs with ETH directly
  function purchase(address to, Basket[] memory basket) public payable nonReentrant {
    require(!privateSaleOnly, "Error: private sale only");
    uint256 rateETHUSD = getRateETH2USD();
    uint256 rateOxcUsd = getRatePerOxcInUsd();

    // ETH / USD out of range?
    require(rateETHUSD >= _minRateETH2USD, "Error: exchange rate ETH/USD below minimum");
    require(rateETHUSD <= _maxRateETH2USD, "Error: exchange rate ETH/USD above maximum");

    // calculate total amount in USD, basis Salesrate for OXC
    uint256 remainingFundsUSD = (msg.value * rateETHUSD) / 10 ** decimals();

    // Order Head
    uint256 orderId = totalOrders;
    totalOrders++; //OIA-10
    orderbook[orderId].buyer = msg.sender;
    orderbook[orderId].timestamp = block.timestamp;
    orderbook[orderId].exchangeRate = rateETHUSD;

    for (uint8 i = 0; i < basket.length; i++) {
      /* save basket information */
      Basket memory pos = Basket(basket[i].purchaseNFTtype, basket[i].quantity, basket[i].amountOXC);
      orderbook[orderId].positions[orderbook[orderId].numPositions] = pos;
      orderbook[orderId].numPositions++;

      emit Purchase(
        to,
        basket[i].purchaseNFTtype,
        basket[i].quantity,
        basket[i].amountOXC,
        orderId,
        orderbook[orderId].numPositions - 1
      );

      /* mint NFTs for each basket position */
      for (uint8 amount = 0; amount < basket[i].quantity; amount++) {
        /* amountOXC sent without 18 decimals, but rateOXCUSD has 18 decimals */
        uint256 buyOilXCoinAmount = basket[i].amountOXC * rateOxcUsd;
        require(remainingFundsUSD >= buyOilXCoinAmount, "Error: not enough funds sent"); // funds in
          // US$!
        orderbook[orderId].totalAmount += buyOilXCoinAmount; // Order Total Amount in US$
        // use NFT minter contract to store mint date for vesting
        remainingFundsUSD -= buyOilXCoinAmount; //OIA-10
        nftMinter.safeMintTs(to, basket[i].purchaseNFTtype, basket[i].amountOXC);
      }
    }

    // rate has 18 decimals, add decimals again!
    uint256 remainingFundsETH = (remainingFundsUSD * 10 ** decimals()) / rateETHUSD;
    // withdraw to sales wallet
    payable(getSalesWalletAddress()).transfer(address(this).balance - remainingFundsETH);
    // withdraw remaining funds
    (bool success,) = msg.sender.call{value: remainingFundsETH}("");
    require(success, "Failed to withdraw remaining funds");
  }

  /*
  * @notice Defines if sales are allowed directly or require a signed message
  * @param value The value to set private sale only
  */
  function setPrivateSaleOnly(bool value) public onlyOwner {
    privateSaleOnly = value;
  }
}

/*
* @title SalesContractNftPurchaseWithOffer
* @notice This contract allows to purchase through signed offers from the webshop
* @dev private sale only with signed offers*/
contract SalesContractNftPurchaseWithOffer is SalesContractNft {
  using ECDSA for bytes32;

  bytes constant prefix = "\x19Ethereum Signed Message:\n";

  address SalesSigner;
  mapping(bytes => uint256) public signatureUsed; //list of used signatures

  event LogHash(bytes32 indexed msg);
  event LogMessage(bytes msg);
  event OfferTotalAmount(uint256 totalOilX, uint256 sendETH, uint256 estETH);
  event NewSalesSigner(address indexed oldSigner, address indexed newSigner);

  event PurchaseOffer(
    address indexed _to,
    OilXNftTokenType nftType,
    uint32 quantity,
    uint32 amountOilXCoin,
    uint256 orderID,
    uint256 orderPos,
    uint256 totalAmount,
    string signer
  );

  event LogNumber(
    uint256 number, uint256 number2, uint256 number3, uint256 number4, uint256 number5
  );

  /**
   * @notice Error indicating that a signature has already been used
   * @param signature The signature that was used
   * @param timestamp The timestamp when the signature was used
   */
  error SignatureAlreadyUsed(bytes signature, uint256 timestamp);

  /**
   * @notice Constructor for the SalesContractNftPurchaseWithOffer contract
   * @param _addressOilXNft The address of the OilXNft contract
   * @param _salesWallet The address of the sales wallet
   * @param _owner The address of the owner of the contract
   */
  constructor(address _addressOilXNft, address _salesWallet, address _owner)
    SalesContractNft(_addressOilXNft, _salesWallet, _owner)
  {}

  /**
   * @notice Sets the sales signer address, only one signer is possible
   * @param newSigner The new sales signer address
   */
  function setSalesSigner(address newSigner) public onlyOwner {
    require(newSigner != address(0), "zero address not allowed");
    emit NewSalesSigner(SalesSigner, newSigner);
    SalesSigner = newSigner;
  }

  /**
   * @notice Creates a message for the sales signer
   * @param to The address of the buyer
   * @param totalAmount The total amount of the sale
   * @param basket The basket of the sale
   * @param validUntilBlockTimeStamp The valid until block time stamp
   * @param confirmLowPrice Whether to confirm a lower price than the estimated price
   * @return The message for the sales signer to sign
   */
  function createSignerMessage(
    address to,
    uint256 totalAmount,
    Basket[] memory basket,
    uint256 validUntilBlockTimeStamp,
    bool confirmLowPrice
  ) public view returns (bytes memory) {
    uint256 oxcTotal;

    //* OIA-04 hashing strings removed *//
    bytes memory message;
    for (uint256 i = 0; i < basket.length; i++) {
      message = abi.encode(
        message, uint256(basket[i].purchaseNFTtype), basket[i].quantity, basket[i].amountOXC
      );

      oxcTotal += basket[i].quantity * basket[i].amountOXC; //total amount of OXC in basket
    }

    message =
      abi.encode(to, totalAmount, message, validUntilBlockTimeStamp, block.chainid, address(this));

    /**
     * calculcation:
     *  oxcTotal = TotalOXC amount without decimals
     *  usdTotal = oxcTotal * getRatePerOxcInUsd() --> price for OXC in USD$ with 18 decimals
     *  ethTotal = usdTotal * 10 ** decimals() / getRateETH2USD() --> price in ETH with 18 decimals
     *  ethTotal = ethTotal * 97 / 100; // 3% tolerance
     */
    uint256 exchangeRate = getRateETH2USD();
    require(exchangeRate >= _minRateETH2USD, "Error: exchange rate ETH/USD below minimum");
    require(exchangeRate <= _maxRateETH2USD, "Error: exchange rate ETH/USD above maximum");
    uint256 usdTotal = oxcTotal * getRatePerOxcInUsd(); //OIA-16
    uint256 ethTotal = usdTotal * 10 ** decimals() / exchangeRate; //now in ETH (wei)
    ethTotal = ethTotal * 97 / 100; // 3% tolerance
    //emit LogNumber(oxcTotal, usdTotal, ethTotal, totalAmount, 0);
    if (ethTotal > totalAmount && !confirmLowPrice) revert("totalAmount out of tolerance");
    return message;
  }

  function verifySignature(bytes memory message, bytes memory signature) public returns (bool) {
    address signer = SalesSigner; // public key/wallet address
    bytes32 hash = keccak256(abi.encodePacked(prefix, Strings.toString(message.length), message));
    emit LogHash(hash);
    address recoveredSigner = hash.recover(signature);
    return signer == recoveredSigner;
  }

  function offerValid(
    address to,
    uint256 totalAmount,
    Basket[] memory basket,
    uint256 validUntilBlockTimeStamp,
    bytes memory signature
  ) internal returns (bool) {
    bytes memory unsignedMsg =
      createSignerMessage(to, totalAmount, basket, validUntilBlockTimeStamp, false); //OIA-06
    emit LogMessage(unsignedMsg);

    return verifySignature(unsignedMsg, signature);
  }

  /**
   * @notice Purchase NFTs with a signed offer
   * @param to The address of the buyer
   * @param totalAmount The total amount of the sale in ETH (wei)
   * @param basket The basket of the sale
   * @param validUntilBlockTimeStamp The valid until block time stamp
   * @param signature The signature of the sales signer for createSignerMessage
   */
  function purchaseWithOffer(
    address to,
    uint256 totalAmount,
    Basket[] memory basket,
    uint256 validUntilBlockTimeStamp,
    bytes memory signature
  ) public payable nonReentrant {
    /* offer still valid? */
    require(
      offerValid(to, totalAmount, basket, validUntilBlockTimeStamp, signature),
      "Signature check failed."
    );
    require(validUntilBlockTimeStamp > block.timestamp, "Offer expired.");
    if (signatureUsed[signature] != 0) {
      //OIA-05
      /* signatures cannot be reused to prevent duplicate execution */
      revert SignatureAlreadyUsed(signature, signatureUsed[signature]);
    }
    require(msg.value >= totalAmount, "not enough funds send."); // sell for fix price!

    // ETH / USD out of range?
    uint256 exchangeRate = getRateETH2USD();
    require(exchangeRate >= _minRateETH2USD, "Error: exchange rate ETH/USD below minimum");
    require(exchangeRate <= _maxRateETH2USD, "Error: exchange rate ETH/USD above maximum");

    // Order Head
    uint256 orderId = totalOrders;
    totalOrders++; //OIA-10
    orderbook[orderId].buyer = msg.sender;
    orderbook[orderId].timestamp = block.timestamp;
    orderbook[orderId].exchangeRate = exchangeRate;
    signatureUsed[signature] = block.timestamp; //OIA-05

    uint256 _rateOxcUsd = getRatePerOxcInUsd();
    for (uint256 i = 0; i < basket.length; i++) {
      /* save basket information */
      Basket memory pos = Basket(basket[i].purchaseNFTtype, basket[i].quantity, basket[i].amountOXC);
      orderbook[orderId].positions[orderbook[orderId].numPositions] = pos;
      orderbook[orderId].numPositions++;

      emit Purchase(
        to,
        basket[i].purchaseNFTtype,
        basket[i].quantity,
        basket[i].amountOXC,
        orderId,
        orderbook[orderId].numPositions - 1
      );

      for (uint256 amount = 0; amount < basket[i].quantity; amount++) {
        // Order Total OilXCoin OXC Amount in US$ with 18 decimals
        orderbook[orderId].totalAmount += (basket[i].amountOXC * _rateOxcUsd);
        /* mint NFTs for each basket position */
        nftMinter.safeMintTs(to, basket[i].purchaseNFTtype, basket[i].amountOXC);
      }
    }

    /**
     * calculate eth amount to be sent to sales wallet
     *  orderbook[orderId].totalAmount = TotalOilXCoin OXC Amount in US$ with 18 decimals
     *  estimatedETH = orderbook[orderId].totalAmount * 10 ** decimals() / exchangeRate;
     *                 Exchange rate has 18 decimals
     *  estimatedETH = ETH in wei
     */
    uint256 estimatedETH = orderbook[orderId].totalAmount * 10 ** decimals() / exchangeRate;
    estimatedETH = estimatedETH * 97 / 100; // 3% tolerance OIA-20
    if (estimatedETH > totalAmount) revert("totalAmount out of tolerance"); // OIA-20

    emit OfferTotalAmount(orderbook[orderId].totalAmount, totalAmount, estimatedETH);
    payable(getSalesWalletAddress()).transfer(totalAmount); // withdrawal to sales wallet

    if (msg.value - totalAmount > 0) payable(msg.sender).transfer(msg.value - totalAmount); // send
      // the rest back
  }

  function getValidToBlockTime(uint256 offset) public view returns (uint256) {
    return block.timestamp + offset;
  }

  function getStringLength(string memory string_) private pure returns (uint256) {
    return bytes(string_).length;
  }
}
