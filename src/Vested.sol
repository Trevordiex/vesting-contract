// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Vested {

    struct Transfer {
        uint256 id;
        address sender;
        address recipient;
        uint256 amount;
        address token;
        uint256 startTime;
        uint256 duration;
        uint256 dailyReward;
        uint256 lastWithdrawTime;
        TransferStatus status;
    }

    enum TransferStatus {
        PENDING,
        ONGOING,
        ENDED
    }

    event Withdrawal(address indexed recipient, uint256 amount);

    error Vested__UnAuthorized();
    error Vested__InvalidAmount(uint256);
    error Vested__RecipientRequired();
    error Vested__ZeroAddress();
    error Vested__WithdrawalFailed();
    error Vested__TransferPending();
    error Vested__TransferOngoing();
    error Vested__TransferNotFound();
    error Vested__TransferEnded();

    uint256 constant MININUM_DEPOSIT = 2 ether;
    uint256 constant PERIOD = 1 days;

    uint256 globalTransferId;

    mapping (uint256 transferId => Transfer) transfers;
    mapping (address recipient => uint256[] trasferIds) recieved;

    constructor() {}

    modifier isRecipient(uint256 transferId) {
        if (msg.sender != transfers[transferId].recipient) {
            revert Vested__UnAuthorized();
        }
        _;
    }

    /**
    * @param amount: The amount to transfer to recipients
    * @param token: The address of the ERC20 token
    * @param recipient: The authorized address for withdrawal
    * @param waitTime: the delay time befor the vesting starts
    * @param duration: the duration of the vesting
    */
    function depositLocked(
        uint256 amount,
        address token,
        address recipient,
        uint256 waitTime,
        uint256 duration
    ) external returns (uint256) {

        if (amount < MININUM_DEPOSIT) revert Vested__InvalidAmount(amount);

        if (token == address(0) || recipient == address(0)) revert Vested__ZeroAddress();

        Transfer memory transfer = Transfer({
            id: ++globalTransferId,
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            token: token,
            startTime: block.timestamp + waitTime,
            duration: duration,
            dailyReward: _rewardPerDay(amount, duration),
            lastWithdrawTime: block.timestamp,
            status: TransferStatus.PENDING
        });

        transfers[globalTransferId] = transfer;
        recieved[recipient].push(globalTransferId);

        bool sent = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!sent) revert();

        return transfer.id;
    }


    function withdraw(uint256 transferId) external isRecipient(transferId) returns (bool) {
        Transfer memory transfer = getTransfer(transferId);
        uint256 amount = _accrued(transfer);

        if (amount <= 0) {
            revert Vested__WithdrawalFailed();
        }

        transfers[transfer.id].lastWithdrawTime = block.timestamp;
        if (transfer.status == TransferStatus.PENDING && transfer.startTime < block.timestamp) {
            transfers[transfer.id].status = TransferStatus.ONGOING;
        }
        if (block.timestamp >= transfer.startTime + transfer.duration) {
            completeTransfer(transfer);
        }

        bool sent = IERC20(transfer.token).transfer(msg.sender, amount);
        if (!sent) revert();

        return true;
    }



    function accrued(uint256 transferId) public view isRecipient(transferId) returns (uint256 amount) {
        Transfer memory transfer = getTransfer(transferId);
        return _accrued(transfer);
        
    }

    

    function completeTransfer(Transfer memory transfer) internal isRecipient(transfer.id) returns (bool completed) {
        uint256[] storage ids = recieved[msg.sender];

        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == transfer.id) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                completed = true;
                break;
            }
        }

        transfers[transfer.id].status = TransferStatus.ENDED;
    }

    function getReceivedTransferIds() external view returns (uint256[] memory) {
        return recieved[msg.sender];
    }

    function getTransfer(uint256 transferId) public view returns (Transfer memory) {
        if (transferId > globalTransferId) {
            revert Vested__TransferNotFound();
        }
        return transfers[transferId];
    }

    function getStatus(uint256 transferId) external view returns (TransferStatus) {
        return getTransfer(transferId).status;
    }

    // Internal & Private functions

    function _accrued(Transfer memory transfer) internal view returns (uint256) {
        if (transfer.status == TransferStatus.ENDED) {
            revert Vested__TransferEnded();
        }
        if (block.timestamp <= transfer.startTime) {
            return 0;
        }

        uint256 start = _max(transfer.startTime, transfer.lastWithdrawTime);
        uint256 end = _min(block.timestamp, transfer.startTime + transfer.duration);
        uint256 daysElapsed = (end - start) / PERIOD;

        if (daysElapsed >= 1) {
            return daysElapsed * transfer.dailyReward;
        }

        return 0;
    }

    function _rewardPerDay(uint256 amount, uint256 duration) internal pure returns (uint256 reward) {
        uint256 totalDays = duration / PERIOD;
        reward = amount / totalDays;
    }

    function _max(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > y) {
            return x;
        }
        return y;
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x < y) {
            return x;
        }
        return y;
    }
}