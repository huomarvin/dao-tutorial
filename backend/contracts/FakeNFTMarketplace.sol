// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract FakeNFTMarketplace {
    /// @dev 维护一个映射，将假的TokenID映射到所有者地址
    mapping(uint256 => address) public tokens;
    /// @dev 为每个假的NFT设置购买价格
    uint256 nftPrice = 0.1 ether;

    /// @dev 接收ETH并将给定tokenId的所有者标记为调用者地址
    /// @param _tokenId 假的NFT的tokenID
    function purchase(uint256 _tokenId) external payable {
        require(msg.value == nftPrice, "This NFT costs 0.1 ether");
        tokens[_tokenId] = msg.sender;
    }

    /// @dev 获取NFT的单位定价
    function getPrice() external view returns (uint256) {
        return nftPrice;
    }

    /// @dev 判断给定的tokenID是否已经被购买
    /// @param _tokenId 假的NFT的tokenID
    function available(uint256 _tokenId) external view returns (bool) {
        /// 判断该tokenID是否已经被购买
        if (tokens[_tokenId] == address(0)) {
            return true;
        }
        return false;
    }
}
