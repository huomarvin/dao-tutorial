// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * FakeNFTMarketplace对应的接口
 */
interface IFakeNFTMarketplace {
    /// @dev 返回一个NFT的价格
    function getPrice() external view returns (uint256);

    /// @dev 返回一个NFT是否已经被购买
    /// @return 返回一个布尔值 - 如果可用，返回true，否则返回false
    function available(uint256 _tokenId) external view returns (bool);

    /// @dev 从NFTMarketplace购买一个NFT
    /// @param _tokenId - 要购买的假NFT的tokenID
    function purchase(uint256 _tokenId) external payable;
}

/**
 * CryptoDevsNFT对应的接口
 */
interface ICryptoDevsNFT {
    /// @dev balanceOf返回给定地址拥有的NFT数量
    /// @param owner - 要获取NFT数量的地址
    /// @return 返回NFT的数量
    function balanceOf(address owner) external view returns (uint256);

    /// @dev tokenOfOwnerByIndex返回给定地址拥有的NFT的tokenID
    /// @param owner - NFT所属的地址
    /// @param index - 要获取的NFT在拥有的NFT数组中的索引
    /// @return 返回NFT的tokenID
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256);
}

contract CryptoDevsDAO is Ownable {
    // 创建一个名为Vote的枚举，包含投票的可能选项
    enum Vote {
        YAY, // YAY = 0
        NAY // NAY = 1
    }
    // 创建一个ID到Proposal的映射
    mapping(uint256 => Proposal) public proposals;
    // 用于跟踪已创建的提案数量
    uint256 public numProposals;
    IFakeNFTMarketplace nftMarketplace;
    ICryptoDevsNFT cryptoDevsNFT;
    // 创建一个名为Proposal的结构体，包含所有相关信息
    struct Proposal {
        // 从FakeNFTMarketplace购买的NFT的tokenID
        uint256 nftTokenId;
        // 用于跟踪提案的截止日期
        uint256 deadline;
        // yayVotes - 该提案的赞成票数
        uint256 yayVotes;
        // nayVotes - 该提案的反对票数
        uint256 nayVotes;
        // executed - 该提案是否已执行。在截止日期超过之前不能执行。
        bool executed;
        // voters - 一个CryptoDevsNFT tokenID到布尔值的映射，表示该NFT是否已经用于投票
        mapping(uint256 => bool) voters;
    }

    // 创建一个可支付的构造函数，用于初始化FakeNFTMarketplace和CryptoDevsNFT的合约实例
    // 可支付的构造函数允许在部署时接收ETH存款
    constructor(address _nftMarketplace, address _cryptoDevsNFT) payable {
        nftMarketplace = IFakeNFTMarketplace(_nftMarketplace);
        cryptoDevsNFT = ICryptoDevsNFT(_cryptoDevsNFT);
    }

    // 创建一个只允许由拥有至少1个CryptoDevsNFT的人调用的修饰符
    modifier nftHolderOnly() {
        require(cryptoDevsNFT.balanceOf(msg.sender) > 0, "NOT_A_DAO_MEMBER");
        _;
    }

    /// @dev createProposal允许CryptoDevsNFT持有者在DAO中创建新提案
    /// @param _nftTokenId - 要从FakeNFTMarketplace购买的NFT的tokenID
    /// @return 返回新创建的提案的索引
    function createProposal(
        uint256 _nftTokenId
    ) external nftHolderOnly returns (uint256) {
        require(nftMarketplace.available(_nftTokenId), "NFT_NOT_FOR_SALE");
        Proposal storage proposal = proposals[numProposals];
        proposal.nftTokenId = _nftTokenId;
        // 设置提案的投票截止日期为（当前时间+5分钟）
        proposal.deadline = block.timestamp + 5 minutes;
        numProposals++;
        return numProposals - 1;
    }

    // 创建一个修饰符，只允许在给定提案的截止日期尚未超过时调用函数
    modifier activeProposalOnly(uint256 proposalIndex) {
        require(
            proposals[proposalIndex].deadline > block.timestamp,
            "DEADLINE_EXCEEDED"
        );
        _;
    }

    /// @dev voteOnProposal允许CryptoDevsNFT持有者对活动提案进行投票
    /// @param proposalIndex - 要在提案数组中投票的提案的索引
    /// @param vote - 他们想要投票的投票类型
    function voteOnProposal(
        uint256 proposalIndex,
        Vote vote
    ) external nftHolderOnly activeProposalOnly(proposalIndex) {
        Proposal storage proposal = proposals[proposalIndex];

        uint256 voterNFTBalance = cryptoDevsNFT.balanceOf(msg.sender);
        uint256 numVotes = 0;

        // 计算由投票者拥有的NFT数量，这些NFT尚未用于投票此提案
        for (uint256 i = 0; i < voterNFTBalance; i++) {
            uint256 tokenId = cryptoDevsNFT.tokenOfOwnerByIndex(msg.sender, i);
            if (proposal.voters[tokenId] == false) {
                numVotes++;
                proposal.voters[tokenId] = true;
            }
        }
        require(numVotes > 0, "ALREADY_VOTED");

        if (vote == Vote.YAY) {
            proposal.yayVotes += numVotes;
        } else {
            proposal.nayVotes += numVotes;
        }
    }

    // 创建一个修饰符，只允许在给定提案的截止日期已超过且提案尚未执行时调用函数 
    // 用于执行提案
    modifier inactiveProposalOnly(uint256 proposalIndex) {
        require(
            proposals[proposalIndex].deadline <= block.timestamp,
            "DEADLINE_NOT_EXCEEDED"
        );
        require(
            proposals[proposalIndex].executed == false,
            "PROPOSAL_ALREADY_EXECUTED"
        );
        _;
    }

    /// @dev executeProposal 允许任何CryptoDevsNFT持有者在超过提案截止日期后执行提案
    /// @param proposalIndex - 要在提案数组中执行的提案的索引
    function executeProposal(
        uint256 proposalIndex
    ) external nftHolderOnly inactiveProposalOnly(proposalIndex) {
        Proposal storage proposal = proposals[proposalIndex];

        // 如果提案的赞成票数多于反对票数，则从FakeNFTMarketplace购买NFT
        if (proposal.yayVotes > proposal.nayVotes) {
            uint256 nftPrice = nftMarketplace.getPrice();
            require(address(this).balance >= nftPrice, "NOT_ENOUGH_FUNDS");
            nftMarketplace.purchase{value: nftPrice}(proposal.nftTokenId);
        }
        proposal.executed = true;
    }

    /// @dev withdrawEther 允许合约所有者（部署者）从合约中提取ETH
    function withdrawEther() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "Nothing to withdraw, contract balance empty");
        (bool sent, ) = payable(owner()).call{value: amount}("");
        require(sent, "FAILED_TO_WITHDRAW_ETHER");
    }

    // The following two functions allow the contract to accept ETH deposits
    // directly from a wallet without calling a function
    receive() external payable {}

    fallback() external payable {}
}
