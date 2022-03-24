//SPDX-License-Identifier: UNLICENSED

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./IterableMapping.sol";

pragma solidity ^0.8.10;

contract NFTStaking is Ownable, KeeperCompatible {
    using IterableMapping for IterableMapping.Map;
    using SafeMath for uint256;
    using SafeMath for uint16;

    struct User {
        uint16 totalNFTDeposited;
        uint256 lastClaimTime;
        uint256 lastDepositTime;
        uint256 totalClaimed;
    }

    struct Pool {
        uint256 rewardPerNFT;
        uint256 rewardInterval;
        uint16 lockPeriodInDays;
        uint256 totalDeposit;
        uint256 totalRewardDistributed;
        uint256 startDate;
        uint256 endDate;
    }

    IERC20 public token;
    IERC721 public nft;

    mapping(uint8 => mapping(address => User)) public users;

    IterableMapping.Map internal nftInfo;

    uint256 internal counter;
    uint256 public lastAutoProcessTimestamp;

    Pool[] public poolInfo;

    event Stake(address indexed addr, uint256 amount);
    event Claim(address indexed addr, uint256 amount);

    constructor(address _token, address _nft) {
        token = IERC20(_token);
        nft = IERC721(_nft);

        lastAutoProcessTimestamp = block.timestamp;
    }

    function add(
        uint256 _rewardPerNFT,
        uint256 _rewardInterval,
        uint16 _lockPeriodInDays,
        uint256 _endDate
    ) external onlyOwner {
        poolInfo.push(
            Pool({
                rewardPerNFT: _rewardPerNFT,
                rewardInterval: _rewardInterval,
                lockPeriodInDays: _lockPeriodInDays,
                endDate: _endDate,
                startDate: block.timestamp,
                totalDeposit: 0,
                totalRewardDistributed: 0
            })
        );
    }

    function set(
        uint8 _pid,
        uint256 _rewardPerNFT,
        uint256 _rewardInterval,
        uint16 _lockPeriodInDays,
        uint256 _endDate
    ) public onlyOwner {
        Pool storage pool = poolInfo[_pid];

        pool.rewardPerNFT = _rewardPerNFT;
        pool.rewardInterval = _rewardInterval;
        pool.lockPeriodInDays = _lockPeriodInDays;
        pool.endDate = _endDate;
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory performData 
        )
    {
        if (
            (block.timestamp - lastAutoProcessTimestamp) > 1 days || counter != 0
        ) {
            upkeepNeeded = true;
        } else {
            upkeepNeeded = false;
        }

        performData; //silence warning
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        //100 distribution per call
        if ((block.timestamp - lastAutoProcessTimestamp) >= 1 days) {

            if (counter == 0) {
                counter = 1;
            }

            uint256 len = nftInfo.size();
            if(len == 0) lastAutoProcessTimestamp = block.timestamp;

            for (uint8 i = 0; i < 100; i++) {
                uint256 key = nftInfo.getKeyAtIndex(counter - 1);
                address user = nftInfo.get(key);

                claimAll(user);
                counter++;

                if (counter > len) {
                    counter = 0;
                    lastAutoProcessTimestamp = block.timestamp;
                    break;
                }
            }
        }
    }

    function stake(uint8 _pid, uint16 _tokenId)
        external
        returns (bool)
    {
        require(nft.ownerOf(_tokenId) == msg.sender, "You don't own this NFT");

        nft.transferFrom(msg.sender, address(this), _tokenId);

        _claim(_pid, msg.sender);

        _stake(_pid, msg.sender);

        nftInfo.set(_tokenId, msg.sender);

        emit Stake(msg.sender, _tokenId);

        return true;
    }

    function _stake(uint8 _pid, address _sender) internal {
        User storage user = users[_pid][_sender];
        Pool storage pool = poolInfo[_pid];

        uint256 stopDepo = pool.endDate.sub(pool.lockPeriodInDays.mul(1 days));

        require(
            block.timestamp <= stopDepo,
            "Staking is disabled for this pool"
        );

        user.totalNFTDeposited++;
        pool.totalDeposit++;
        user.lastDepositTime = block.timestamp;
    }

    function claimAll(address _addr) public returns (bool) {
        uint256 len = poolInfo.length;
        
        for (uint8 i = 0; i < len; i++) {
            _claim(i, _addr);
        }

        return true;
    }

    function claim(uint8 _pid) public returns (bool) {
        _claim(_pid, msg.sender);

        return true;
    }

    function canClaim(uint8 _pid, address _addr) public view returns (bool) {
        User storage user = users[_pid][_addr];
        Pool storage pool = poolInfo[_pid];

        return (block.timestamp >=
            user.lastClaimTime.add(pool.lockPeriodInDays.mul(1 days)));
    }

    function unStake(uint8 _pid, uint16 _tokenId) external returns (bool) {
        User storage user = users[_pid][msg.sender];
        Pool storage pool = poolInfo[_pid];

        require(
            nftInfo.get(_tokenId) == msg.sender,
            "You didin't staked this NFT"
        );

        require(
            block.timestamp >=
                user.lastDepositTime.add(pool.lockPeriodInDays.mul(1 days)),
            "Stake still in locked state"
        );

        _claim(_pid, msg.sender);

        pool.totalDeposit--;
        user.totalNFTDeposited--;

        nft.transferFrom(address(this), msg.sender, _tokenId);
        nftInfo.remove(_tokenId);

        return true;
    }

    function _claim(uint8 _pid, address _addr) internal {
        User storage user = users[_pid][_addr];

        uint256 amount = payout(_pid, _addr);

        if (amount > 0) {
            safeTransfer(_addr, amount);

            user.lastClaimTime = block.timestamp;

            user.totalClaimed = user.totalClaimed.add(amount);
        }

        poolInfo[_pid].totalRewardDistributed += amount;

        emit Claim(_addr, amount);
    }

    function payout(uint8 _pid, address _addr)
        public
        view
        returns (uint256 value)
    {
        User storage user = users[_pid][_addr];
        Pool storage pool = poolInfo[_pid];

        uint256 from = user.lastClaimTime > user.lastDepositTime
            ? user.lastClaimTime
            : user.lastDepositTime;
        uint256 to = block.timestamp > pool.endDate
            ? pool.endDate
            : block.timestamp;

        if (from < to) {
            value = value.add(
                user
                    .totalNFTDeposited
                    .mul(to.sub(from))
                    .mul(pool.rewardPerNFT)
                    .div(pool.rewardInterval)
            );
        }

        return value;
    }

    function claimStuckTokens(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    /**
     *
     * @dev safe transfer function, require to have enough token to transfer
     *
     */
    function safeTransfer(address _to, uint256 _amount) internal {
        uint256 bal = token.balanceOf(address(this));
        if (_amount > bal) {
            token.transfer(_to, bal);
        } else {
            token.transfer(_to, _amount);
        }
    }
}
