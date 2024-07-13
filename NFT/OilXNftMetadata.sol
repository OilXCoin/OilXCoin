// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./OilXNft.sol";
import "./WithdrawContracts.sol";

contract OilXNftMetadata is WidthdrawContractsOwnable {
    constructor() WidthdrawContractsOwnable(msg.sender) {}
    string private _mediaUrl = "https://oilxcoin.io/nft-media/";

    function getTokenTypeString(OilXNftTokenType tokenType) private pure returns (string memory strType) {
        string memory strTokenType;
        if (tokenType == OilXNftTokenType.DIAMOND) {
            strTokenType = "DIAMOND";
        } else if (tokenType == OilXNftTokenType.PLATINUM) {
            strTokenType = "PLATINUM";
        } else if (tokenType == OilXNftTokenType.GOLD) {
            strTokenType = "GOLD";
        } else if (tokenType == OilXNftTokenType.SILVER) {
            strTokenType = "SILVER";
        } else if (tokenType == OilXNftTokenType.BLACK) {
            strTokenType = "BLACK";
        } else {
            revert("Invalid NFT type");
        }

        return strType = strTokenType;
    }

    function getTokenTypeNumberString(OilXNftTokenType tokenType) private pure returns (string memory strType) {
        string memory strTokenType;
        if (tokenType == OilXNftTokenType.DIAMOND) {
            strTokenType = "0";
        } else if (tokenType == OilXNftTokenType.PLATINUM) {
            strTokenType = "1";
        } else if (tokenType == OilXNftTokenType.GOLD) {
            strTokenType = "2";
        } else if (tokenType == OilXNftTokenType.SILVER) {
            strTokenType = "3";
        } else if (tokenType == OilXNftTokenType.BLACK) {
            strTokenType = "4";
        } else {
            revert("Invalid NFT type");
        }

        return strType = strTokenType;
    }

    function convertAmountToString(uint256 amount) private pure returns (string memory strAmount) {
        string memory strAmountText = Strings.toString(amount);
        return strAmount = strAmountText;
    }

    function addMetadataAttributeDisplayType(
        string memory traitType,
        string memory value,
        string memory displayType
    ) private pure returns (string memory strAttribute) {
        // string memory strAttribute;
        strAttribute = string(
            abi.encodePacked(
                "{",
                '"display_type": "',
                displayType,
                '",',
                '"trait_type": "',
                traitType,
                '",',
                '"value": ',
                value,
                "}"
            )
        );
        return strAttribute;
    }

    function addMetadataAttributeString(string memory traitType, string memory value)
        private
        pure
        returns (string memory strAttribute)
    {
        // string memory strAttribute;
        strAttribute = string(abi.encodePacked("{", '"trait_type": "', traitType, '",', '"value": "', value, '"', "}"));
        return strAttribute;
    }

    function addMetadataAttributeNumber(string memory traitType, string memory value)
        private
        pure
        returns (string memory strAttribute)
    {
        // string memory strAttribute;
        strAttribute = string(abi.encodePacked("{", '"trait_type": "', traitType, '",', '"value": ', value, "}"));
        return strAttribute;
    }

    function generateTexts(
        OilXNftTokenType tokenType,
        uint256 oilXAmount,
        uint256 oilXClaimed,
        uint256 oilXFee,
        uint256 tokenId,
        address contractAddress
    ) private pure returns (string memory title, string memory description) {
        string memory strOilXamountText = convertAmountToString(oilXAmount);
        string memory strOilXamountClaimedText = convertAmountToString(oilXClaimed);
        string memory strOilfeeText = convertAmountToString(oilXFee);
        string memory contractAddr = Strings.toHexString(contractAddress);

        title = string(abi.encodePacked("OilXCoin ", getTokenTypeString(tokenType), " NFT (", strOilXamountText, " OILX Entitlement)"));


        description = string(
            abi.encodePacked(
                "This NFT entitles its holder to a one-off claim of its corresponding number of OilXCoin tokens. Once OILX has been launched,",
                " these tokens can be claimed under https://oilxcoin.io. Once the vesting period has expired these tokens can be traded freely.",
                " The terms of the NFT can be found under https://oilxcoin.io/en/nft/term-sheet.\\n\\n",
                "Contract Address: ",
                contractAddr,
                " | This NFT has Token ID: ",
                Strings.toString(tokenId)
            ));

        description = string(
            abi.encodePacked( description,
                "\\nVoucher value: ",
                strOilXamountText,
                " OILX | claimed: ",
                strOilXamountClaimedText,
                " OILX | Fees claimed: ",
                strOilfeeText,
                " OILX"
                "\\n\\n DISCLAIMER: Due diligence is imperative prior to executing any NFT transactions. Ensure that all wallet and smart contract addresses",
                " are correct. DeXentra GmbH does not assume any liability for imitations or errors made in",
                " the transaction process."
            )
        );
    }

    function getMetaAttributes(
        OilXNftTokenType tokenType,
        uint256 oilXamount,
        uint256 oilXclaimed,
        uint256 oilXfee,
        uint256 tokenId
    ) private pure returns (string memory strAttributes) {
        string memory strOilXamountText = convertAmountToString(oilXamount);
        string memory strOilXamountClaimedText = convertAmountToString(oilXclaimed);
        string memory strOilfeeText = convertAmountToString(oilXfee);
        string memory strTokenType = getTokenTypeString(tokenType);
        strAttributes = string(
            abi.encodePacked(
                addMetadataAttributeString("Collection", "OilXCoin"),
                ",",
                addMetadataAttributeDisplayType("Token ID", Strings.toString(tokenId), "number"),
                ",",
                addMetadataAttributeNumber("OilX amount", strOilXamountText),
                ",",
                addMetadataAttributeNumber("Claimed", strOilXamountClaimedText), 
                ",",
                addMetadataAttributeNumber("Fees claimed", strOilfeeText),
                ",",
                addMetadataAttributeString("NFT type", strTokenType)
            )
        );

        return strAttributes;
    }

    function getDataBytes(
        string memory strTitle,
        string memory strDescription,
        string memory imageUrl,
        string memory animationUrl,
        string memory jsonAttributes
    ) private view returns (bytes memory data) {
        data = abi.encodePacked(
            "{",
            '"name": "',
            strTitle,
            '",',
            '"description": "',
            strDescription,
            '",',
            '"image": "',
            imageUrl,
            '",',
            '"animation_url": "',
            animationUrl,
            '"',
            ',"attributes": [',
            jsonAttributes,
            "]}"
        );

        return data;
    }

    function getTokenURI(address addressNft, uint256 tokenId) public view returns (bytes memory) {
        OilXNft nft = OilXNft(addressNft);

        string memory strTokenTyp;
        strTokenTyp = getTokenTypeString(nft.tokenIdTokenType(tokenId));

        uint256 claimedFee = nft.tokenIdOilXFeeClaimed(tokenId) / 10 ** nft.feeDecimals();
        uint256 claimedOilX = nft.tokenIdOilXAmount(tokenId) - nft.tokenIdOilXClaimable(tokenId);

        (string memory strTitle, string memory strDescription) = generateTexts(
            nft.tokenIdTokenType(tokenId),
            nft.tokenIdOilXAmount(tokenId),
            claimedOilX,
            claimedFee,
            tokenId,
            addressNft
        );

        string memory imageUrl = string(
            abi.encodePacked(
                _mediaUrl,
                getTokenTypeNumberString(nft.tokenIdTokenType(tokenId)),
                "/",
                Strings.toString(nft.tokenIdOilXAmount(tokenId)),
                "/",
                Strings.toString(claimedOilX),
                "/",
                Strings.toString(claimedFee),
                "/media.svg"
            )
        );

        string memory animationUrl = string(
            abi.encodePacked(
                _mediaUrl,
                getTokenTypeNumberString(nft.tokenIdTokenType(tokenId)),
                "/",
                Strings.toString(nft.tokenIdOilXAmount(tokenId)),
                "/",
                Strings.toString(claimedOilX),
                "/",
                Strings.toString(claimedFee),
                "/media.html"
            )
        );

        string memory jsonAttributes = getMetaAttributes(
            nft.tokenIdTokenType(tokenId), nft.tokenIdOilXAmount(tokenId), claimedOilX, claimedFee, tokenId
        );

        bytes memory data = getDataBytes(strTitle, strDescription, imageUrl, animationUrl, jsonAttributes);

        return data;
    }
}
