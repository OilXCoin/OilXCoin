// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/*
* @title Contract to Recover Tokens or ETH sent by mistake to the contract
* @author OilXCoin.io Dev Team
* @notice Release Tests
*/
contract WidthdrawContractsOwnable is Ownable {
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    event WithdrawERC20(address indexed tokenAddress, address indexed to, uint256 amount);
    event WithdrawERC721(address indexed tokenAddress, address indexed to, uint256 tokenId);
    event WithdrawERC1155(address indexed tokenAddress, address indexed to, uint256 tokenId, uint256 amount);
    event WithdrawETH(address indexed to, uint256 amount);

    /**
     * @dev Withdraw all ERC20 tokens from the contract
     * @param _tokenAddress Address of the ERC20 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC20(address _tokenAddress, address _to) public onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        emit WithdrawERC20(_tokenAddress, _to, balance);
        token.transfer(_to, balance);
    }

    /**
     * @dev Withdraw all ERC721 tokens from the contract
     * @param _tokenAddress Address of the ERC721 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC721(address _tokenAddress, address _to, uint256 _tokenId) public onlyOwner {
        emit WithdrawERC721(_tokenAddress, _to, _tokenId);
        IERC721(_tokenAddress).safeTransferFrom(address(this), _to, _tokenId);
    }

    /**
     * @dev Withdraw all ERC1155 tokens from the contract
     * @param _tokenAddress Address of the ERC1155 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC1155(address _tokenAddress, address _to, uint256 _tokenId) public onlyOwner {
        IERC1155 token = IERC1155(_tokenAddress);
        uint256 balance = token.balanceOf(address(this), _tokenId);
        emit WithdrawERC1155(_tokenAddress, _to, _tokenId, balance);
        token.safeTransferFrom(address(this), _to, _tokenId, balance, "");
    }

    /**
     * @dev Withdraw all ETH from the contract
     */
    function withdrawETH(address payable _to) public onlyOwner {
        uint256 balance = address(this).balance;
        emit WithdrawETH(_to, balance);
        _to.transfer(balance);
    }
}

/*
* @title Contract to Recover Tokens or ETH sent by mistake to the contract
* @author OilXCoin.io Dev Team
* @notice Release Tests
*/
contract WidthdrawContractsAccessControl is AccessControl {
    bytes32 public constant WITHDRAWCONTRACT_ROLE = keccak256("WITHDRAWCONTRACT_ROLE");

    constructor(address _initialOwner) {
        _grantRole(WITHDRAWCONTRACT_ROLE, _initialOwner);
    }

    event WithdrawERC20(address indexed tokenAddress, address indexed to, uint256 amount);
    event WithdrawERC721(address indexed tokenAddress, address indexed to, uint256 tokenId);
    event WithdrawERC1155(address indexed tokenAddress, address indexed to, uint256 tokenId, uint256 amount);
    event WithdrawETH(address indexed to, uint256 amount);

    /**
     * @dev Withdraw all ERC20 tokens from the contract
     * @param _tokenAddress Address of the ERC20 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC20(address _tokenAddress, address _to) public onlyRole(WITHDRAWCONTRACT_ROLE) {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        emit WithdrawERC20(_tokenAddress, _to, balance);
        token.transfer(_to, balance);
    }

    /**
     * @dev Withdraw all ERC721 tokens from the contract
     * @param _tokenAddress Address of the ERC721 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC721(address _tokenAddress, address _to, uint256 _tokenId)
        public
        onlyRole(WITHDRAWCONTRACT_ROLE)
    {
        emit WithdrawERC721(_tokenAddress, _to, _tokenId);
        IERC721(_tokenAddress).safeTransferFrom(address(this), _to, _tokenId);
    }

    /**
     * @dev Withdraw all ERC1155 tokens from the contract
     * @param _tokenAddress Address of the ERC1155 contract
     * @param _to Address to send the tokens to
     */
    function withdrawERC1155(address _tokenAddress, address _to, uint256 _tokenId)
        public
        onlyRole(WITHDRAWCONTRACT_ROLE)
    {
        IERC1155 token = IERC1155(_tokenAddress);
        uint256 balance = token.balanceOf(address(this), _tokenId);
        emit WithdrawERC1155(_tokenAddress, _to, _tokenId, balance);
        token.safeTransferFrom(address(this), _to, _tokenId, balance, "");
    }

    /**
     * @dev Withdraw all ETH from the contract
     */
    function withdrawETH(address payable _to) public onlyRole(WITHDRAWCONTRACT_ROLE) {
        uint256 balance = address(this).balance;
        emit WithdrawETH(_to, balance);
        _to.transfer(balance);
    }
}
