// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./WithdrawContracts.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IVesting.sol";

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

/// @dev mint function in OilXCoin
interface iToken {
  function mintOilXCoin(address to, uint256 amount) external;
}

/// @title OilXCoin Sales Contract
/// @notice This contract allows users to purchase OilXCoin in exchange for ETH or supported ERC-20
/// tokens.
///         Different ICO stages are predefined, each offering more favorable pricing conditions.
/// @dev Handles the minting of OilXCoin tokens based on the payment and current ICO stage.
abstract contract ICOSalesContract is WithdrawContractsOwnable {
  using SafeERC20 for IERC20;

  uint8 internal constant _decimals = 18;
  uint256 internal constant priceTolerance = 300; // 3%

  struct icoStage {
    uint256 stage;
    uint256 startDate;
    uint256 endDate;
    uint256 usdPrice;
    uint256 raisedAmount;
    uint256 targetAmount;
  }

  struct exchangeRate {
    string symbol;
    address tokenContractAddress;
    uint256 exchangeRate;
    uint8 decimals;
  }

  struct order {
    address payer;
    address recipient;
    uint256 timestamp;
    uint256 oilXCoinAmount;
    address paymentTokenAddress;
    uint256 paymentTokenAmount;
  }

  mapping(uint256 => order) public orderbook; // stores purchases information
  mapping(string => address) public tokenAddressBySymbol; // mapping from symbol to payment token

  icoStage[] public icoStages;
  exchangeRate[] public exchangeRates;

  // ETH rate via oracle; defines the maximum accepted exchange rate
  uint256 private _maxRateETH2USD;
  uint256 private _fixedEth2UsdRate;
  uint256 private _totalOrders;
  address public addressChainlinkOracleETH;
  address public tokenContractAddress; // OilXCoin
  address public vestingContractAddress; // Vesting Contract/Interfaced
  address public salesWalletAddress; // receives payment

  uint256 public startDate; // start date of the ICO in UTC timestamp
  uint256 public endDate; // end date of the ICO in UTC timestamp
  uint256 public maxTokenForSale; // max token for sale
  uint256 public minPurchaseAmount; // min purchase amount
  uint256 public targetAmount;
  uint256 public totalRaisedAmount;

  event OffchainPurchaseCompleted(address indexed buyer, uint256 oilXCoinAmount, uint256 offerId);

  /* check if all necessary contracts are set */
  modifier checkSaleOpen() {
    require(block.timestamp >= startDate, "ICO not started");
    require(block.timestamp <= endDate, "ICO ended");
    require(maxTokenForSale > 0, "no remaining tokens for sale");
    require(address(tokenContractAddress) != address(0), "token contract not set");
    require(address(vestingContractAddress) != address(0), "vesting contract not set");
    require(address(salesWalletAddress) != address(0), "sales wallet not set");
    require(icoStages.length > 0, "ICO stages not set");
    require(_maxRateETH2USD > 0, "max rate ETH2USD not set");
    _;
  }

  /**
   * @notice Constructor for the ICOSalesContract
   * @param _adminAddress The address of the admin
   * @param _addressTokenContract The address of the OilXCoin token contract
   * @param _addressVestingContract The address of the vesting contract
   * @param _addressSalesWallet The address of the sales wallet (receives payment)
   * @param _minPurchaseAmount The minimum purchase amount in OilXCoin
   * @param _maxTokenForSale The maximum token for sale
   */
  constructor(
    address _adminAddress,
    address _addressTokenContract,
    address _addressVestingContract,
    address _addressSalesWallet,
    uint256 _minPurchaseAmount,
    uint256 _maxTokenForSale
  ) WithdrawContractsOwnable(_adminAddress) {
    require(_adminAddress != address(0), "admin address not set");
    require(_addressTokenContract != address(0), "token contract not set");
    require(_addressVestingContract != address(0), "vesting contract not set");
    require(_addressSalesWallet != address(0), "sales wallet not set");
    require(_maxTokenForSale > 0, "max token for sale not set");

    tokenContractAddress = _addressTokenContract;
    vestingContractAddress = _addressVestingContract;
    salesWalletAddress = _addressSalesWallet;

    minPurchaseAmount = _minPurchaseAmount;
    maxTokenForSale = _maxTokenForSale;
    targetAmount = _maxTokenForSale;
  }

  function decimals() public pure returns (uint8) {
    return _decimals;
  }

  function round(uint256 _value, uint8 _valuedecimals, uint8 _precision)
    public
    pure
    returns (uint256)
  {
    uint256 factor = 10 ** (_valuedecimals - _precision);
    uint256 result = (_value + factor / 2) / factor * factor; // method to round up
    require(result > 0, "rounding caused zero value"); //OIA-08
    return result;
  }

  //* setters **/
  function setSalesWalletAddress(address salesWallet) public onlyOwner {
    require(salesWallet != address(0), "zero address not allowed");
    salesWalletAddress = salesWallet;
  }

  function setChainLinkOracle(address address_) public onlyOwner {
    // depends on chain, can be deactivated by setting to address(0)
    addressChainlinkOracleETH = address_;
  }

  function setExchangeRateETHmax(uint256 maxValue) public onlyOwner {
    // sanity check
    require(maxValue > 0, "invalid max value");
    _maxRateETH2USD = maxValue;
  }

  /**
   * @notice fallback if no oracle is available
   * @param rate The ETH2USD rate in 18 decimals
   */
  function setEth2UsdRate(uint256 rate) public onlyOwner {
    require(rate > 0, "invalid rate");
    _fixedEth2UsdRate = rate;
  }

  function increaseMaxTokenForSale(uint256 amount) public onlyOwner {
    require(amount > 0, "invalid amount");
    maxTokenForSale += amount;
    targetAmount += amount;
  }

  function setTotalRaisedAmount(uint256 amount) public onlyOwner {
    // when contract is replaced, to "restore" the total raised amount in the new contract
    require(totalRaisedAmount == 0, "total raised amount already set");
    require(amount > 0, "invalid amount");
    require(amount <= targetAmount, "amount exceeds target amount");
    totalRaisedAmount = amount;
    maxTokenForSale = targetAmount - totalRaisedAmount;
  }

  /**
   * @notice Deletes an exchange rate for a payment token
   * @param _paymentTokenAddress The address of the payment token
   */
  function deleteExchangeRate(address _paymentTokenAddress) public onlyOwner {
    for (uint256 i = 0; i < exchangeRates.length; i++) {
      if (exchangeRates[i].tokenContractAddress == _paymentTokenAddress) {
        tokenAddressBySymbol[exchangeRates[i].symbol] = address(0);
        delete exchangeRates[i];
        return;
      }
    }
  }

  /**
   * @notice Sets the exchange rate for a payment token
   * @param _symbol The symbol of the payment token
   * @param _paymentTokenAddress The address of the payment token
   * @param _exchangeRate The exchange rate of the payment token in 18 decimals (how many OXC per 1
   * payment token)
   */
  function setExchangeRate(
    string memory _symbol,
    address _paymentTokenAddress,
    uint256 _exchangeRate
  ) public onlyOwner {
    require(_exchangeRate > 0, "invalid exchange rate");
    require(_paymentTokenAddress != address(0), "invalid payment token");

    if (tokenAddressBySymbol[_symbol] == address(0)) {
      tokenAddressBySymbol[_symbol] = _paymentTokenAddress;
    } else {
      require(tokenAddressBySymbol[_symbol] == _paymentTokenAddress, "symbol already in use");
    }

    for (uint256 i = 0; i < exchangeRates.length; i++) {
      if (exchangeRates[i].tokenContractAddress == _paymentTokenAddress) {
        // if (_exchangeRate == 0) delete exchangeRates[i];
        exchangeRates[i].exchangeRate = _exchangeRate;
        return;
      }
    }

    // new record
    uint8 _tokenDecimals = ERC20(_paymentTokenAddress).decimals();
    exchangeRates.push(
      exchangeRate({
        symbol: _symbol,
        tokenContractAddress: _paymentTokenAddress,
        exchangeRate: _exchangeRate,
        decimals: _tokenDecimals
      })
    );
  }

  function getRateETH2USD() public view returns (uint256) {
    // ETH 2 USD rate - on testnet chainlink not exists
    uint256 rate;
    if (addressChainlinkOracleETH != address(0)) {
      ChainlinkOracle oracle = ChainlinkOracle(addressChainlinkOracleETH);
      (, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
      require(block.timestamp - updatedAt <= 3600, "Stale price"); //OIA-02
      rate = uint256(answer);
      rate = rate * 10 ** (decimals() - 8); // convert from 10**8 to 10**18
    } else {
      rate = _fixedEth2UsdRate; // Fallback if no oracle is available on the desired chain
    }
    require(rate > 0, "ETH2USD rate invalid");
    return rate;
  }

  function getOrder(uint256 _orderId) public view returns (order memory) {
    return orderbook[_orderId];
  }

  function getContractFromSymbol(string memory _symbol) public view returns (address) {
    require(tokenAddressBySymbol[_symbol] != address(0), "token not found");
    return tokenAddressBySymbol[_symbol];
  }

  function getExchangeRate(address _paymentTokenAddress) public view returns (exchangeRate memory) {
    /* native coin */
    if (_paymentTokenAddress == address(0)) {
      uint256 _eth2usd = getRateETH2USD();
      require(_eth2usd <= _maxRateETH2USD, "ETH2USD rate too high");
      return exchangeRate({
        symbol: "ETH",
        tokenContractAddress: address(0),
        exchangeRate: _eth2usd,
        decimals: 18
      });
    }

    /* ERC-20 token for exchange */
    for (uint256 i = 0; i < exchangeRates.length; i++) {
      if (exchangeRates[i].tokenContractAddress == _paymentTokenAddress) return exchangeRates[i];
    }
    revert("exchange rate not found");
  }

  /**
   * @notice Calculates the price of OilXCoin in a given payment token
   * @param _paymentTokenAddress The address of the payment token
   * @param _spend The amount of payment token to spend, returns amount of purchasing OilXCoin
   * @param _purchase The amount of OilXCoin to purchase, returns amount of payment token needed
   * @return The calculated price in the specified payment token
   * @dev This function calculates the price of OilXCoin in a given payment token based on the
   * current ICO stage and the exchange rate of the payment token to USD.
   * It requires either the spend amount or the purchase amount to be set, but not both.
   */
  //*

  function calculatePrice(address _paymentTokenAddress, uint256 _spend, uint256 _purchase)
    public
    view
    returns (uint256)
  {
    require((_spend == 0) != (_purchase == 0), "only spend or purchase amount must be set");

    icoStage memory stage = getCurrentStage();
    require(
      stage.startDate <= block.timestamp && block.timestamp <= stage.endDate, "ICO not active"
    );
    require(stage.usdPrice > 0, "invalid stage price");

    exchangeRate memory rate = getExchangeRate(_paymentTokenAddress);

    if (_spend > 0) {
      uint256 _amount = _spend * rate.exchangeRate / 10 ** rate.decimals;
      _amount = _amount * 10 ** decimals() / stage.usdPrice;
      return round(_amount, decimals(), 4);
    } else {
      uint256 _price = _purchase * stage.usdPrice / 10 ** decimals();
      _price = _price * 10 ** rate.decimals / rate.exchangeRate;
      return round(_price, rate.decimals, 4);
    }
  }

  //* Function to handle ICO stages */
  /**
   * @notice Sets the start date for the ICO
   * @dev Requires start time to be at 1 PM UTC (13:00)
   * @param _timestamp Unix timestamp for ICO start date
   */
  function setStartDate(uint256 _timestamp) public onlyOwner {
    // real szenario
    setStartDate2(_timestamp, false, 1 days);
  }

  /// @dev Public for testing; sets up individual stages
  function setStartDate2(uint256 _timestamp, bool _demomode, uint256 _stageDuration)
    private
    onlyOwner
  {
    // Convert timestamp to hours in UTC
    // if (!_demomode) uint256 hourOfDay = (_timestamp % 86_400) / 3600;
    // require(hourOfDay == 13, "ICO stages must start at 1 PM UTC");

    // e.g. startDate = 2025-04-23 1pm UTC = unix epoch timestamp 1745413200
    startDate = _timestamp;
    createStages(_demomode, _stageDuration);
  }

  //* @dev normally create 1 stage per day, demo mode for testing shorter intervals
  function createStages(bool _demomode, uint256 _stageDuration) private {
    // Clear existing stages
    delete icoStages;
    uint256 stageEndDate;
    uint256 stageStartDate;
    for (uint256 i = 0; i < 20; i++) {
      // Calculate start date for this stage
      // Each stage starts at 1PM UTC and ends at 12:59 PM UTC next day

      if (!_demomode) {
        stageStartDate = startDate + (i * 1 days);
        stageEndDate = stageStartDate + 1 days - 1; // Subtract 1 seconds end on 12:59:59 PM
      } else {
        stageStartDate = startDate + (i * _stageDuration);
        stageEndDate = stageStartDate + _stageDuration - 1; // Subtract 1 seconds
      }

      // Calculate price for this stage (increasing by $0.01 each stage)
      uint256 stagePrice = getStagePrice(i + 1);

      // Create and push new stage
      icoStages.push(
        icoStage({
          stage: i + 1,
          startDate: stageStartDate,
          endDate: stageEndDate,
          usdPrice: stagePrice,
          raisedAmount: 0,
          targetAmount: 0
        })
      );
    }
    endDate = stageEndDate;
  }

  /// @dev calculates the price for a given stage
  function getStagePrice(uint256 _stage) internal pure returns (uint256) {
    uint256 centPrice;
    // First 5 stages at $0.85 - Phase 1
    if (_stage <= 5) centPrice = 85; // $0.85

    // Stages 6-15 increase by $0.01 each stage - Phase 2
    else if (_stage >= 6 && _stage <= 15) centPrice = 85 + (_stage - 5); // $0.86 to $0.95

    // Stages 16 and above - Phase 3
    else centPrice = 100; // $1.00

    return centPrice * 10 ** decimals() / 100;
  }

  /**
   * @notice Returns all ICO stages
   * @return An array of icoStage structs representing all ICO stages
   */
  function getICOstages() public view returns (icoStage[] memory) {
    return icoStages;
  }

  /**
   * @notice Returns the current ICO stage
   * @return An icoStage struct representing the current stage
   */
  function getCurrentStage() public view returns (icoStage memory) {
    uint256 currentTime = block.timestamp;
    for (uint256 i = 0; i < icoStages.length; i++) {
      if (icoStages[i].startDate <= currentTime && currentTime <= icoStages[i].endDate) {
        icoStage memory stage;
        stage = icoStages[i];
        // Expose raised and target amount for frontend display
        stage.raisedAmount = totalRaisedAmount;
        stage.targetAmount = targetAmount;
        return stage;
      }
    }
    revert("no active stage");
  }

  /**
   * @notice Creates vesting entries for a buyer
   * @param _buyer The address of the buyer
   * @param _oilXCoinAmount The amount of OilXCoin to be vested
   */
  function createVestingEntries(address _buyer, uint256 _oilXCoinAmount) private {
    IVesting vestingContract = IVesting(vestingContractAddress);
    vestingContract.addICOVestingAmount(_buyer, _oilXCoinAmount);
  }

  /**
   * @notice Completes an offchain purchase
   * @param _buyer The address of the buyer
   * @param _oilXCoinAmount The amount of OilXCoin to be purchased
   * @param _offerId The backend ID of the offer
   */
  function completeOffchainPurchase(address _buyer, uint256 _oilXCoinAmount, uint256 _offerId)
    public
    onlyOwner
  {
    require(_buyer != address(0), "buyer address is 0");
    require(_oilXCoinAmount > 0, "oilXCoinAmount is 0");
    require(_offerId > 0, "offerId is 0");

    /* record purchase in orderbook */
    orderbook[_totalOrders] = order({
      payer: _buyer,
      recipient: _buyer,
      timestamp: block.timestamp,
      oilXCoinAmount: _oilXCoinAmount,
      paymentTokenAddress: address(this), // own address as indicator for offchain purchase
      paymentTokenAmount: _offerId // reference to backend offer ID
    });
    _totalOrders++;

    /* mint OilXCoin Tokens and create vesting entries*/
    maxTokenForSale -= _oilXCoinAmount;
    totalRaisedAmount += _oilXCoinAmount;
    createVestingEntries(_buyer, _oilXCoinAmount);
    iToken(tokenContractAddress).mintOilXCoin(_buyer, _oilXCoinAmount);
    emit OffchainPurchaseCompleted(_buyer, _oilXCoinAmount, _offerId);
  }

  /**
   * @notice Internal function to handle the purchase of OilXCoin
   * @param _payer The address of the payer (msg.sender)
   * @param _recipient The address of the recipient
   * @param _oilXCoinAmount The amount of OilXCoin to be purchased
   * @param _paymentTokenAddress The address of the payment token
   * @param _paymentTokenAmount The amount of payment token to be spent
   * @return success True if the purchase was successful, false otherwise
   * @return orderId Incremental order ID for querying the order book
   */
  function _internalpurchase(
    address payable _payer,
    address _recipient,
    uint256 _oilXCoinAmount,
    address _paymentTokenAddress,
    uint256 _paymentTokenAmount
  ) internal checkSaleOpen returns (bool success, uint256 orderId) {
    require(_oilXCoinAmount >= minPurchaseAmount, "min purchase amount not reached");
    require(_oilXCoinAmount <= maxTokenForSale, "max token for sale exceeded");
    require(getExchangeRate(_paymentTokenAddress).exchangeRate > 0, "invalid payment token");

    /* check if ICO is active */
    icoStage memory stage = getCurrentStage();
    require(
      stage.startDate <= block.timestamp && block.timestamp <= stage.endDate, "ICO not active"
    );
    require(stage.usdPrice > 0, "invalid stage price");

    /* check if exchange rate is in tolerance */
    uint256 totalForeignCurrency = calculatePrice(_paymentTokenAddress, 0, _oilXCoinAmount);
    require(totalForeignCurrency > 0, "payment token amount is zero"); //OIA-08
    uint256 maxPrice = totalForeignCurrency * (10_000 + priceTolerance) / 10_000;
    uint256 minPrice = totalForeignCurrency * (10_000 - priceTolerance) / 10_000;

    require(
      _paymentTokenAmount >= minPrice && _paymentTokenAmount <= maxPrice,
      "hot market: exchange rate out of tolerance"
    );

    /* record purchase in orderbook */
    orderbook[_totalOrders] = order({
      payer: _payer,
      recipient: _recipient,
      timestamp: block.timestamp,
      oilXCoinAmount: _oilXCoinAmount,
      paymentTokenAddress: _paymentTokenAddress,
      paymentTokenAmount: _paymentTokenAmount
    });
    _totalOrders++;

    if (_paymentTokenAddress == address(0)) {
      //bought with native Coin / ETH
      require(msg.value >= _paymentTokenAmount, "not enough ETH funds send");
      /* transfer ether to sales wallet */
      (success,) = payable(salesWalletAddress).call{value: _paymentTokenAmount}(""); //transfer
      require(success, "ETH payment to sales wallet failed");

      /* mint OilXCoin Tokens and create vesting entries*/
      maxTokenForSale -= _oilXCoinAmount;
      totalRaisedAmount += _oilXCoinAmount;
      createVestingEntries(_recipient, _oilXCoinAmount); //OIA-10
      iToken(tokenContractAddress).mintOilXCoin(_recipient, _oilXCoinAmount);

      uint256 amountToPayback = msg.value - _paymentTokenAmount; //withdraw remaining ETH
      if (amountToPayback > 0) {
        (success,) = _payer.call{value: amountToPayback}("");
        require(success, "Failed to refund Ether");
      }
    } else {
      //bought with ERC-20 token
      /* transfer payment token to sales wallet */
      maxTokenForSale -= _oilXCoinAmount;
      totalRaisedAmount += _oilXCoinAmount;
      IERC20(_paymentTokenAddress).safeTransferFrom(_payer, salesWalletAddress, _paymentTokenAmount);

      /* mint OilXCoin Tokens and create vesting entries*/
      createVestingEntries(_recipient, _oilXCoinAmount);
      iToken(tokenContractAddress).mintOilXCoin(_recipient, _oilXCoinAmount);

      if (msg.value > 0) {
        (success,) = _payer.call{value: msg.value}(""); // Withdraw accidentally sent ETH
        require(success, "Failed to refund Ether");
      }
    }

    return (true, _totalOrders - 1);
  }
}

/**
 * @title ICOSalesContractSigned
 * @notice This contract extends the ICOSalesContract and allows signed purchases
 * @dev each signature can only be used once
 */
contract ICOSalesContractSigned is ICOSalesContract, ReentrancyGuard {
  using ECDSA for bytes32;

  bytes constant prefix = "\x19Ethereum Signed Message:\n";

  mapping(address => bool) public salesSigner; //list of authorized signers
  mapping(bytes => uint256) public signatureUsed; //list of used signatures

  event purchase2(
    address indexed buyer,
    bytes signature,
    uint256 indexed orderId,
    uint256 oilXCoinAmount,
    address paymentTokenAddress,
    uint256 paymentTokenAmount,
    uint256 validUntil
  );

  /**
   * @notice Error indicating that a signature has already been used
   * @param signature The signature that was used
   * @param timestamp The timestamp when the signature was used
   */
  error SignatureAlreadyUsed(bytes signature, uint256 timestamp);

  /**
   * @notice Constructor for the ICOSalesContractSigned
   * @param _adminAddress The address of the admin
   * @param _addressTokenContract The address of the OilXCoin token contract
   * @param _addressVestingContract The address of the vesting contract
   * @param _addressSalesWallet The address of the sales wallet
   * @param _minPurchaseAmount The minimum purchase amount
   * @param _maxTokenForSale The maximum token for sale
   */
  constructor(
    address _adminAddress,
    address _addressTokenContract,
    address _addressVestingContract,
    address _addressSalesWallet,
    uint256 _minPurchaseAmount,
    uint256 _maxTokenForSale
  )
    ICOSalesContract(
      _adminAddress,
      _addressTokenContract,
      _addressVestingContract,
      _addressSalesWallet,
      _minPurchaseAmount,
      _maxTokenForSale
    )
  {}

  /**
   * @notice Sets a sales signer
   * @param signer The address of the signer to be added
   * @param isSigner True if the signer is authorized, false otherwise
   */
  function setSalesSigner(address signer, bool isSigner) public onlyOwner {
    salesSigner[signer] = isSigner;
  }

  function getMessage2Sign(
    address _buyer,
    uint256 _oilXCoinAmount,
    address _paymentTokenAddress,
    uint256 _paymentTokenAmount,
    uint256 _validUntil
  ) public view returns (bytes memory) {
    return abi.encodePacked(
      _buyer,
      _oilXCoinAmount,
      _paymentTokenAddress,
      _paymentTokenAmount,
      _validUntil,
      block.chainid,
      address(this)
    );
  }

  /// @notice Recovers the signer of a message
  function getMessageSigner(bytes memory message, bytes memory signature)
    public
    pure
    returns (address)
  {
    bytes32 hash = keccak256(abi.encodePacked(prefix, Strings.toString(message.length), message));
    return hash.recover(signature);
  }

  /* 
   * @notice purchase with signed message or offer
  * @dev signed purchases allow a price deviation of up to 3% between the displayed cart total and
  the actual execution price.
   * @param _buyer The address of the buyer
   * @param _oilXCoinAmount The amount of OilXCoin to be purchased
   * @param _paymentTokenAddress The address of the payment token
   * @param _paymentTokenAmount The amount of payment token to be spent
   * @param _validUntil The timestamp until which the signature is valid
   * @param signature The signature provided by an authorized signer
   */
  function purchaseSigned(
    address _buyer,
    uint256 _oilXCoinAmount,
    address _paymentTokenAddress,
    uint256 _paymentTokenAmount,
    uint256 _validUntil,
    bytes memory signature
  ) public payable nonReentrant {
    require(msg.sender == _buyer, "caller must be the buyer"); //OIA-19

    /* check signature for authorized signer */
    bytes memory unsignedMessage = getMessage2Sign(
      _buyer, _oilXCoinAmount, _paymentTokenAddress, _paymentTokenAmount, _validUntil
    );
    address signer = getMessageSigner(unsignedMessage, signature);

    require(salesSigner[signer], "invalid signer or signature");

    /* check purchase signed conditions */
    require(block.timestamp <= _validUntil, "offer or signature expired");
    if (signatureUsed[signature] != 0) {
      /* signatures cannot be reused to prevent duplicate execution */
      revert SignatureAlreadyUsed(signature, signatureUsed[signature]);
    }
    signatureUsed[signature] = block.timestamp; //OIA-10

    /* interal purchase, mint OilXCoin and create vesting entries, transfer payment */
    (bool success, uint256 orderId) = _internalpurchase(
      payable(msg.sender), _buyer, _oilXCoinAmount, _paymentTokenAddress, _paymentTokenAmount
    ); //OIA-19
    require(success, "purchase failed");

    emit purchase2(
      _buyer,
      signature,
      orderId,
      _oilXCoinAmount,
      _paymentTokenAddress,
      _paymentTokenAmount,
      _validUntil
    );
  }
}
