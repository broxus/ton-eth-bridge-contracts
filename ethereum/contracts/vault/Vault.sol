// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/Math.sol";

import "../interfaces/vault/IVault.sol";
import "../interfaces/IBridge.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IERC20Metadata.sol";

import "./VaultHelpers.sol";


string constant API_VERSION = '0.1.5';


contract Vault is IVault, VaultHelpers {
    using SafeERC20 for IERC20;

    function initialize(
        address _bridge,
        address _governance,
        address _token,
        uint _targetDecimals
    ) external override initializer {
        bridge = _bridge;
        emit UpdateBridge(bridge);

        governance = _governance;
        emit UpdateGovernance(governance);

        performanceFee = 0;
        emit UpdatePerformanceFee(0);

        managementFee = 0;
        emit UpdateManagementFee(0);

        token = _token;
        tokenDecimals = IERC20Metadata(token).decimals();
        targetDecimals = _targetDecimals;
    }

    /**
        @notice Vault API version. Used to track the deployed version of this contract.
        @return api_version Current API version
    */
    function apiVersion()
        external
        override
        pure
    returns (
        string memory api_version
    ) {
        return API_VERSION;
    }

    /**
        @notice Set deposit fee. Must be less than `MAX_BPS`.
        This may be called only by `governance` or `management`.
        @param _depositFee Deposit fee, must be less than `MAX_BPS / 2`.
    */
    function setDepositFee(
        uint _depositFee
    ) external override onlyGovernanceOrManagement {
        require(_depositFee <= MAX_BPS / 2);

        depositFee = _depositFee;

        emit UpdateDepositFee(depositFee);
    }

    /**
        @notice Set withdraw fee. Must be less than `MAX_BPS`.
        This may be called only by `governance` or `management`
        @param _withdrawFee Withdraw fee, must be less than `MAX_BPS / 2`.
    */
    function setWithdrawFee(
        uint _withdrawFee
    ) external override onlyGovernanceOrManagement {
        require(_withdrawFee <= MAX_BPS / 2);

        withdrawFee = _withdrawFee;

        emit UpdateWithdrawFee(withdrawFee);
    }

    /// @notice Set configuration address.
    /// @param _configuration The address to use for configuration.
    function setConfiguration(
        EverscaleAddress memory _configuration
    ) external override onlyGovernance {
        configuration = _configuration;

        emit UpdateConfiguration(configuration.wid, configuration.addr);
    }

    /// @notice Nominate new address to use as a governance.
    /// The change does not go into effect immediately. This function sets a
    /// pending change, and the governance address is not updated until
    /// the proposed governance address has accepted the responsibility.
    /// This may only be called by the `governance`.
    /// @param _governance The address requested to take over Vault governance.
    function setGovernance(
        address _governance
    ) external override onlyGovernance {
        pendingGovernance = _governance;

        emit NewPendingGovernance(pendingGovernance);
    }

    /// @notice Once a new governance address has been proposed using `setGovernance`,
    /// this function may be called by the proposed address to accept the
    /// responsibility of taking over governance for this contract.
    /// This may only be called by the `pendingGovernance`.
    function acceptGovernance()
        external
        override
        onlyPendingGovernance
    {
        governance = pendingGovernance;

        emit UpdateGovernance(governance);
    }

    /// @notice Changes the management address.
    /// This may only be called by `governance`
    /// @param _management The address to use for management.
    function setManagement(
        address _management
    )
        external
        override
        onlyGovernance
    {
        management = _management;

        emit UpdateManagement(management);
    }

    /// @notice Changes the address of `guardian`.
    /// This may only be called by `governance` or `guardian`.
    /// @param _guardian The new guardian address to use.
    function setGuardian(
        address _guardian
    ) external override onlyGovernanceOrGuardian {
        guardian = _guardian;

        emit UpdateGuardian(guardian);
    }

    /// @notice Changes the address of `withdrawGuardian`.
    /// This may only be called by `governance` or `withdrawGuardian`.
    /// @param _withdrawGuardian The new withdraw guardian address to use.
    function setWithdrawGuardian(
        address _withdrawGuardian
    ) external override onlyGovernanceOrWithdrawGuardian {
        withdrawGuardian = _withdrawGuardian;

        emit UpdateWithdrawGuardian(withdrawGuardian);
    }

    /// @notice Set strategy rewards recipient address.
    /// This may only be called by the `governance` or strategy rewards manager.
    /// @param strategyId Strategy address.
    /// @param _rewards Rewards recipient.
    function setStrategyRewards(
        address strategyId,
        EverscaleAddress memory _rewards
    )
        external
        override
        onlyGovernanceOrStrategyRewardsManager(strategyId)
        strategyExists(strategyId)
    {
        _strategyRewardsUpdate(strategyId, _rewards);

        emit StrategyUpdateRewards(strategyId, _rewards.wid, _rewards.addr);
    }

    /// @notice Set address to receive rewards (fees, gains, etc)
    /// This may be called only by `governance`
    /// @param _rewards Rewards receiver in Everscale network
    function setRewards(
        EverscaleAddress memory _rewards
    ) external override onlyGovernance {
        rewards = _rewards;

        emit UpdateRewards(rewards.wid, rewards.addr);
    }

    /// @notice Changes the locked profit degradation
    /// @param degradation The rate of degradation in percent per second scaled to 1e18
    function setLockedProfitDegradation(
        uint256 degradation
    ) external override onlyGovernance {
        require(degradation <= DEGRADATION_COEFFICIENT);

        lockedProfitDegradation = degradation;
    }

    /// @notice Changes the maximum amount of `token` that can be deposited in this Vault
    /// Note, this is not how much may be deposited by a single depositor,
    /// but the maximum amount that may be deposited across all depositors.
    /// This may be called only by `governance`
    /// @param limit The new deposit limit to use.
    function setDepositLimit(
        uint256 limit
    ) external override onlyGovernance {
        depositLimit = limit;

        emit UpdateDepositLimit(depositLimit);
    }

    /// @notice Changes the value of `performanceFee`.
    /// Should set this value below the maximum strategist performance fee.
    /// This may only be called by `governance`.
    /// @param fee The new performance fee to use.
    function setPerformanceFee(
        uint256 fee
    ) external override onlyGovernance {
        require(fee <= MAX_BPS / 2);

        performanceFee = fee;

        emit UpdatePerformanceFee(performanceFee);
    }

    /// @notice Changes the value of `managementFee`.
    /// This may only be called by `governance`.
    /// @param fee The new management fee to use.
    function setManagementFee(
        uint256 fee
    ) external override onlyGovernance {
        require(fee <= MAX_BPS);

        managementFee = fee;

        emit UpdateManagementFee(managementFee);
    }

    /// @notice Changes the value of `withdrawLimitPerPeriod`
    /// This may only be called by `governance`
    /// @param _withdrawLimitPerPeriod The new withdraw limit per period to use.
    function setWithdrawLimitPerPeriod(
        uint256 _withdrawLimitPerPeriod
    ) external override onlyGovernance {
        withdrawLimitPerPeriod = _withdrawLimitPerPeriod;

        emit UpdateWithdrawLimitPerPeriod(withdrawLimitPerPeriod);
    }

    /// @notice Changes the value of `undeclaredWithdrawLimit`
    /// This may only be called by `governance`
    /// @param _undeclaredWithdrawLimit The new undeclared withdraw limit to use.
    function setUndeclaredWithdrawLimit(
        uint256 _undeclaredWithdrawLimit
    ) external override onlyGovernance {
        undeclaredWithdrawLimit = _undeclaredWithdrawLimit;

        emit UpdateUndeclaredWithdrawLimit(undeclaredWithdrawLimit);
    }

    /// @notice Activates or deactivates Vault emergency mode, where all Strategies go into full withdrawal.
    ///     During emergency shutdown:
    ///     - Deposits are disabled
    ///     - Withdrawals are disabled (all types of withdrawals)
    ///     - Each Strategy must pay back their debt as quickly as reasonable to minimally affect their position
    ///     - Only `governance` may undo Emergency Shutdown
    /// This may only be called by `governance` or `guardian`.
    /// @param active If `true`, the Vault goes into Emergency Shutdown. If `false`, the Vault goes back into
    ///     Normal Operation.
    function setEmergencyShutdown(
        bool active
    ) external override {
        if (active) {
            require(msg.sender == guardian || msg.sender == governance);
        } else {
            require(msg.sender == governance);
        }

        emergencyShutdown = active;

        emit EmergencyShutdown(active);
    }

    /// @notice Changes `withdrawalQueue`
    /// This may only be called by `governance`
    function setWithdrawalQueue(
        address[20] memory queue
    ) external override onlyGovernanceOrManagement {
        withdrawalQueue = queue;

        emit UpdateWithdrawalQueue(withdrawalQueue);
    }

    /// @notice Changes pending withdrawal bounty for specific pending withdrawal
    /// @param id Pending withdrawal ID
    /// @param bounty The new bounty for pending withdrawal.
    function setPendingWithdrawalBounty(
        uint256 id,
        uint256 bounty
    )
        external
        override
        pendingWithdrawalOpened(PendingWithdrawalId(msg.sender, id))
    {
        _pendingWithdrawalBountyUpdate(PendingWithdrawalId(msg.sender, id), bounty);

        emit PendingWithdrawalUpdateBounty(msg.sender, id, bounty);
    }

    /// @notice Returns the total quantity of all assets under control of this
    /// Vault, whether they're loaned out to a Strategy, or currently held in
    /// the Vault.
    /// @return The total assets under control of this Vault.
    function totalAssets() external view override returns (uint256) {
        return _totalAssets();
    }

    /// @notice Deposits `token` into the Vault, leads to producing corresponding token
    /// on the Everscale side.
    /// @param recipient Recipient in the Everscale network
    /// @param amount Amount of `token` to deposit
    function deposit(
        EverscaleAddress memory recipient,
        uint256 amount
    )
        public
        override
        onlyEmergencyDisabled
        respectDepositLimit(amount)
        nonReentrant
    {
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        uint256 fee = _calculateMovementFee(amount, depositFee);

        _transferToEverscale(recipient, amount - fee);

        if (fee > 0) _transferToEverscale(rewards, fee);
    }

    /// @notice Same as regular `deposit`, but fills pending withdrawal.
    /// Pending withdrawal recipient receives `pendingWithdrawal.amount - pendingWithdrawal.bounty`.
    /// Deposit author receives `amount + pendingWithdrawal.bounty`.
    /// @param recipient Deposit recipient in the Everscale network.
    /// @param amount Amount of tokens to deposit.
    /// @param pendingWithdrawalId Pending withdrawal ID to fill.
    function deposit(
        EverscaleAddress memory recipient,
        uint256 amount,
        PendingWithdrawalId memory pendingWithdrawalId
    )
        public
        override
        onlyEmergencyDisabled
        pendingWithdrawalApproved(pendingWithdrawalId)
        pendingWithdrawalOpened(pendingWithdrawalId)
        nonReentrant
    {
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

        require(amount >= pendingWithdrawal.amount, "Vault: too low deposit");

        deposit(
            recipient,
            amount + pendingWithdrawal.bounty
        );

        IERC20(token).safeTransfer(
            pendingWithdrawalId.recipient,
            pendingWithdrawal.amount - pendingWithdrawal.bounty
        );
    }

    /**
        @notice Multicall for `deposit`. Fills multiple pending withdrawals at once.
        @param recipient Deposit recipient in the Everscale network.
        @param amount List of amount
    */
    function deposit(
        EverscaleAddress memory recipient,
        uint256[] memory amount,
        PendingWithdrawalId[] memory pendingWithdrawalId
    ) external override {
        require(amount.length == pendingWithdrawalId.length);

        for (uint i = 0; i < amount.length; i++) {
            deposit(recipient, amount[i], pendingWithdrawalId[i]);
        }
    }

    /**
        @notice Save withdrawal receipt. If Vault has enough tokens and withdrawal passes the
            limits, then it's executed immediately. Otherwise it's saved as a pending withdrawal.
        @param payload Withdrawal receipt. Bytes encoded `struct EverscaleEvent`.
        @param signatures List of relay's signatures. See not on `Bridge.verifySignedEverscaleEvent`.
        @param bounty Bounty for filling pending withdrawal. Ignores is `msg.sender` is different from
            withdrawal recipient.
    */
    function saveWithdrawal(
        bytes memory payload,
        bytes[] memory signatures,
        uint256 bounty
    )
        external
        override
        onlyEmergencyDisabled
        withdrawalNotSeenBefore(payload)
        nonReentrant
    {
        require(
            IBridge(bridge).verifySignedEverscaleEvent(payload, signatures) == 0,
            "Vault: signatures verification failed"
        );

        // Decode Everscale event
        (EverscaleEvent memory _event) = abi.decode(payload, (EverscaleEvent));

        require(
            _event.configurationWid == configuration.wid &&
            _event.configurationAddress == configuration.addr,
            "Vault: wrong event configuration"
        );

        // Decode event data
        (
            int8 sender_wid,
            uint256 sender_addr,
            uint128 _amount,
            uint160 _recipient,
            uint32 chainId
        ) = abi.decode(
            _event.eventData,
            (int8, uint256, uint128, uint160, uint32)
        );

        require(chainId == _getChainID());

        address recipient = address(_recipient);
        uint amount = _convertFromTargetDecimals(_amount);
        bytes32 payloadId = keccak256(payload);

        uint256 fee = _calculateMovementFee(amount, withdrawFee);

        if (fee > 0) _transferToEverscale(rewards, fee);

        // Consider withdrawal period limit
        WithdrawalPeriodParams memory withdrawalPeriod = _withdrawalPeriod(_event.eventTimestamp);

        // Withdrawal is less than limits and Vault's token balance is enough for instant withdrawal
        if (
            amount <= _vaultTokenBalance() &&
            amount < undeclaredWithdrawLimit &&
            amount + (withdrawalPeriod.total - withdrawalPeriod.considered) < withdrawLimitPerPeriod
        ) {
            IERC20(token).safeTransfer(recipient, amount - fee);

            emit InstantWithdrawal(payloadId, recipient, amount - fee);
        } else {
            uint256 id = _pendingWithdrawalCreate(
                recipient,
                amount - fee,
                _event.eventTimestamp
            );

            emit PendingWithdrawalCreated(recipient, id, amount - fee, payloadId);

            PendingWithdrawalId memory pendingWithdrawalId = PendingWithdrawalId(recipient, id);

//            {
//                if (msg.sender == recipient && bounty != 0) {
//                    _pendingWithdrawalBountyUpdate(pendingWithdrawalId, bounty);
//
//                    emit PendingWithdrawalUpdateBounty(recipient, id, bounty);
//                }
//            }

            {
                if (amount >= undeclaredWithdrawLimit ||
                    amount + withdrawalPeriod.total - withdrawalPeriod.considered >= withdrawLimitPerPeriod
                ) {
                    _pendingWithdrawalApproveStatusUpdate(pendingWithdrawalId, ApproveStatus.Required);

                    emit PendingWithdrawalUpdateApproveStatus(recipient, id, ApproveStatus.Required);
                }
            }
        }

        _withdrawalPeriodIncreaseTotalByTimestamp(_event.eventTimestamp, amount);
    }

    /// @notice Cancel pending withdrawal partially or completely.
    /// This may only be called by pending withdrawal recipient.
    /// @param id Pending withdrawal ID
    /// @param amount Amount to cancel, should be less or equal than pending withdrawal amount
    /// @param recipient Tokens recipient, in Everscale network
    function cancelPendingWithdrawal(
        uint256 id,
        uint256 amount,
        EverscaleAddress memory recipient
    )
        external
        override
        onlyEmergencyDisabled
        pendingWithdrawalApproved(PendingWithdrawalId(msg.sender, id))
        pendingWithdrawalOpened(PendingWithdrawalId(msg.sender, id))
    {
        PendingWithdrawalId memory pendingWithdrawalId = PendingWithdrawalId(msg.sender, id);
        PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

        require(
            amount > 0 && amount <= pendingWithdrawal.amount,
            "Vault: amount is wrong"
        );

        _transferToEverscale(recipient, amount);

        _pendingWithdrawalAmountReduce(pendingWithdrawalId, amount);

        emit PendingWithdrawalCancel(msg.sender, id, amount);
    }

    /**
        @notice Withdraws the calling account's pending withdrawal from this Vault.
        @param id Pending withdrawal ID.
        @param amountRequested Amount of tokens to be withdrawn.
        @param recipient The address to send the redeemed tokens.
        @param maxLoss The maximum acceptable loss to sustain on withdrawal.
            If a loss is specified, up to that amount of tokens may be burnt to cover losses on withdrawal.
        @return amountAdjusted The quantity of tokens redeemed.
    */
    function withdraw(
        uint256 id,
        uint256 amountRequested,
        address recipient,
        uint256 maxLoss
    )
        external
        override
        onlyEmergencyDisabled
        pendingWithdrawalOpened(PendingWithdrawalId(msg.sender, id))
        pendingWithdrawalApproved(PendingWithdrawalId(msg.sender, id))
        returns(uint256 amountAdjusted)
    {
        PendingWithdrawalId memory pendingWithdrawalId = PendingWithdrawalId(msg.sender, id);
        PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

        require(
            amountRequested > 0 && amountRequested <= pendingWithdrawal.amount,
            "Vault: requested amount is wrong"
        );

        amountAdjusted = amountRequested;

        if (amountAdjusted > _vaultTokenBalance()) {
            uint256 totalLoss = 0;

            for (uint i = 0; i < withdrawalQueue.length; i++) {
                address strategyId = withdrawalQueue[i];

                // We're done withdrawing
                if (strategyId == address(0)) break;

                uint256 vaultBalance = _vaultTokenBalance();
                uint256 amountNeeded = amountAdjusted - vaultBalance;

                // Don't withdraw more than the debt so that Strategy can still
                // continue to work based on the profits it has
                // This means that user will lose out on any profits that each
                // Strategy in the queue would return on next harvest, benefiting others
                amountNeeded = Math.min(
                    amountNeeded,
                    _strategy(strategyId).totalDebt
                );

                // Nothing to withdraw from this Strategy, try the next one
                if (amountNeeded == 0) continue;

                // Force withdraw value from each Strategy in the order set by governance
                uint256 loss = IStrategy(strategyId).withdraw(amountNeeded);
                uint256 withdrawn = _vaultTokenBalance() - vaultBalance;

                // Withdrawer incurs any losses from liquidation
                if (loss > 0) {
                    amountAdjusted -= loss;
                    totalLoss += loss;
                    _strategyReportLoss(strategyId, loss);
                }

                // Reduce the Strategy's debt by the value withdrawn ("realized returns")
                // This doesn't add to returns as it's not earned by "normal means"
                _strategyTotalDebtReduce(strategyId, withdrawn);
            }

            require(_vaultTokenBalance() >= amountAdjusted, "Vault: can't close pending withdrawal");

            // This loss protection is put in place to revert if losses from
            // withdrawing are more than what is considered acceptable.
            require(totalLoss <= maxLoss * (amountAdjusted + totalLoss) / MAX_BPS, "Vault: loss too high");
        }

        IERC20(token).safeTransfer(recipient, amountAdjusted);

        _pendingWithdrawalAmountReduce(pendingWithdrawalId, amountRequested);

        emit PendingWithdrawalWithdraw(msg.sender, id, amountRequested, amountAdjusted);

        return amountAdjusted;
    }

    /// @notice Add a Strategy to the Vault
    /// This may only be called by `governance`
    /// @param strategyId The address of the Strategy to add.
    /// @param _debtRatio The share of the total assets in the `vault that the `strategy` has access to.
    /// @param minDebtPerHarvest Lower limit on the increase of debt since last harvest.
    /// @param maxDebtPerHarvest Upper limit on the increase of debt since last harvest.
    /// @param _performanceFee The fee the strategist will receive based on this Vault's performance.
    function addStrategy(
        address strategyId,
        uint256 _debtRatio,
        uint256 minDebtPerHarvest,
        uint256 maxDebtPerHarvest,
        uint256 _performanceFee
    )
        external
        override
        onlyGovernance
        onlyEmergencyDisabled
        strategyNotExists(strategyId)
    {
        require(strategyId != address(0));

        require(IStrategy(strategyId).vault() == address(this));
        require(IStrategy(strategyId).want() == token);

        require(debtRatio + _debtRatio <= MAX_BPS);
        require(minDebtPerHarvest <= maxDebtPerHarvest);
        require(_performanceFee <= MAX_BPS / 2);

        _strategyCreate(strategyId, StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            debtRatio: _debtRatio,
            minDebtPerHarvest: minDebtPerHarvest,
            maxDebtPerHarvest: maxDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalSkim: 0,
            totalLoss: 0,
            rewardsManager: address(0),
            rewards: rewards
        }));

        emit StrategyAdded(strategyId, _debtRatio, minDebtPerHarvest, maxDebtPerHarvest, _performanceFee);

        _debtRatioIncrease(_debtRatio);
    }

    /**
        @notice Change the quantity of assets `strategy` may manage.
        This may be called by `governance` or `management`.
        @param strategyId The Strategy to update.
        @param _debtRatio The quantity of assets `strategy` may now manage.
    */
    function updateStrategyDebtRatio(
        address strategyId,
        uint256 _debtRatio
    )
        external
        override
        onlyGovernanceOrManagement
        strategyExists(strategyId)
    {
        StrategyParams memory strategy = _strategy(strategyId);

        _debtRatioReduce(strategy.debtRatio);
        _strategyDebtRatioUpdate(strategyId, _debtRatio);
        _debtRatioIncrease(debtRatio);

        require(debtRatio <= MAX_BPS);

        emit StrategyUpdateDebtRatio(strategyId, _debtRatio);
    }

    function updateStrategyMinDebtPerHarvest(
        address strategyId,
        uint256 minDebtPerHarvest
    )
        external
        override
        onlyGovernanceOrManagement
        strategyExists(strategyId)
    {
        StrategyParams memory strategy = _strategy(strategyId);

        require(strategy.maxDebtPerHarvest >= minDebtPerHarvest);

        _strategyMinDebtPerHarvestUpdate(strategyId, minDebtPerHarvest);

        emit StrategyUpdateMinDebtPerHarvest(strategyId, minDebtPerHarvest);
    }

    function updateStrategyMaxDebtPerHarvest(
        address strategyId,
        uint256 maxDebtPerHarvest
    )
        external
        override
        onlyGovernanceOrManagement
        strategyExists(strategyId)
    {
        StrategyParams memory strategy = _strategy(strategyId);

        require(strategy.minDebtPerHarvest <= maxDebtPerHarvest);

        _strategyMaxDebtPerHarvestUpdate(strategyId, maxDebtPerHarvest);

        emit StrategyUpdateMaxDebtPerHarvest(strategyId, maxDebtPerHarvest);
    }

    function updateStrategyPerformanceFee(
        address strategyId,
        uint256 _performanceFee
    )
        external
        override
        onlyGovernance
        strategyExists(strategyId)
    {
        require(_performanceFee <= MAX_BPS / 2);

        performanceFee = _performanceFee;

        emit StrategyUpdatePerformanceFee(strategyId, _performanceFee);
    }

    function migrateStrategy(
        address oldVersion,
        address newVersion
    )
        external
        override
        onlyGovernance
        strategyExists(oldVersion)
        strategyNotExists(newVersion)
    {

    }

    function revokeStrategy(
        address strategyId
    )
        external
        override
        onlyStrategyOrGovernanceOrGuardian(strategyId)
    {
        _strategyRevoke(strategyId);

        emit StrategyRevoked(strategyId);
    }

    function revokeStrategy()
        external
        override
        onlyStrategyOrGovernanceOrGuardian(msg.sender)
    {
        _strategyRevoke(msg.sender);

        emit StrategyRevoked(msg.sender);
    }

    function debtOutstanding(
        address strategyId
    )
        external
        view
        override
        returns (uint256)
    {
        return _strategyDebtOutstanding(strategyId);
    }

    function debtOutstanding()
        external
        view
        override
        returns (uint256)
    {
        return _strategyDebtOutstanding(msg.sender);
    }

    function creditAvailable(
        address strategyId
    )
        external
        view
        override
        returns (uint256)
    {
        return _strategyCreditAvailable(strategyId);
    }

    function creditAvailable()
        external
        view
        override
        returns (uint256)
    {
        return _strategyCreditAvailable(msg.sender);
    }


    function availableDepositLimit()
        external
        view
        override
        returns (uint256)
    {
        if (depositLimit > _totalAssets()) {
            return depositLimit - _totalAssets();
        }

        return 0;
    }

    function expectedReturn(
        address strategyId
    )
        external
        override
        view
        returns (uint256)
    {
        return _strategyExpectedReturn(strategyId);
    }

    function _assessFees(
        address strategyId,
        uint256 gain
    ) internal returns (uint256) {
        StrategyParams memory strategy = _strategy(strategyId);

        // Just added, no fees to assess
        if (strategy.activation == block.timestamp) return 0;

        uint256 duration = block.timestamp - strategy.lastReport;
        require(duration > 0); // Can't call twice within the same block

        if (gain == 0) return 0; // The fees are not charged if there hasn't been any gains reported

        uint256 management_fee = (
            strategy.totalDebt - IStrategy(strategyId).delegatedAssets()
        ) * duration * managementFee / MAX_BPS / SECS_PER_YEAR;

        uint256 strategist_fee = (gain * strategy.performanceFee) / MAX_BPS;

        uint256 performance_fee = (gain * performanceFee) / MAX_BPS;

        uint256 total_fee = management_fee + strategist_fee + performance_fee;

        // Fee
        if (total_fee > gain) {
            strategist_fee = strategist_fee * gain / total_fee;
            performance_fee = performance_fee * gain / total_fee;
            management_fee = management_fee * gain / total_fee;

            total_fee = gain;
        }

        if (strategist_fee > 0) {
            _transferToEverscale(strategy.rewards, strategist_fee);
        }

        if (performance_fee + management_fee > 0) {
            _transferToEverscale(rewards, performance_fee + management_fee);
        }

        return total_fee;
    }

    /**
        @notice Reports the amount of assets the calling Strategy has free (usually in
            terms of ROI).

            The performance fee is determined here, off of the strategy's profits
            (if any), and sent to governance.

            The strategist's fee is also determined here (off of profits), to be
            handled according to the strategist on the next harvest.

            This may only be called by a Strategy managed by this Vault.
        @dev For approved strategies, this is the most efficient behavior.
            The Strategy reports back what it has free, then Vault "decides"
            whether to take some back or give it more. Note that the most it can
            take is `gain + _debtPayment`, and the most it can give is all of the
            remaining reserves. Anything outside of those bounds is abnormal behavior.

            All approved strategies must have increased diligence around
            calling this function, as abnormal behavior could become catastrophic.
        @param gain Amount Strategy has realized as a gain on it's investment since its
            last report, and is free to be given back to Vault as earnings
        @param loss Amount Strategy has realized as a loss on it's investment since its
            last report, and should be accounted for on the Vault's balance sheet.
            The loss will reduce the debtRatio. The next time the strategy will harvest,
            it will pay back the debt in an attempt to adjust to the new debt limit.
        @param _debtPayment Amount Strategy has made available to cover outstanding debt
        @return Amount of debt outstanding (if totalDebt > debtLimit or emergency shutdown).
    */
    function report(
        uint256 gain,
        uint256 loss,
        uint256 _debtPayment
    )
        external
        override
        strategyExists(msg.sender)
        returns (uint256)
    {
        if (loss > 0) _strategyReportLoss(msg.sender, loss);

        uint256 totalFees = _assessFees(msg.sender, gain);

        _strategyTotalGainIncrease(msg.sender, gain);

        // Compute the line of credit the Vault is able to offer the Strategy (if any)
        uint256 credit = _strategyCreditAvailable(msg.sender);

        // Outstanding debt the Strategy wants to take back from the Vault (if any)
        // debtOutstanding <= strategy.totalDebt
        uint256 debt = _strategyDebtOutstanding(msg.sender);
        uint256 debtPayment = Math.min(_debtPayment, debt);

        if (debtPayment > 0) {
            _strategyTotalDebtReduce(msg.sender, debtPayment);

            debt -= debtPayment;
        }

        // Update the actual debt based on the full credit we are extending to the Strategy
        // or the returns if we are taking funds back
        // NOTE: credit + self.strategies_[msg.sender].totalDebt is always < self.debtLimit
        // NOTE: At least one of `credit` or `debt` is always 0 (both can be 0)
        if (credit > 0) {
            _strategyTotalDebtIncrease(msg.sender, credit);
        }

        // Give/take balance to Strategy, based on the difference between the reported gains
        // (if any), the debt payment (if any), the credit increase we are offering (if any),
        // and the debt needed to be paid off (if any)
        // NOTE: This is just used to adjust the balance of tokens between the Strategy and
        //       the Vault based on the Strategy's debt limit (as well as the Vault's).
        uint256 totalAvailable = gain + debtPayment;

        if (totalAvailable < credit) { // credit surplus, give to Strategy
            IERC20(token).safeTransfer(msg.sender, credit - totalAvailable);
        } else if (totalAvailable > credit) { // credit deficit, take from Strategy
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalAvailable - credit);
        } else {
            // don't do anything because it is balanced
        }

        // Profit is locked and gradually released per block
        // NOTE: compute current locked profit and replace with sum of current and new
        uint256 lockedProfitBeforeLoss = _calculateLockedProfit() + gain - totalFees;

        if (lockedProfitBeforeLoss > loss) {
            lockedProfit = lockedProfitBeforeLoss - loss;
        } else {
            lockedProfit = 0;
        }

        _strategyLastReportUpdate(msg.sender);

        StrategyParams memory strategy = _strategy(msg.sender);

        emit StrategyReported(
            msg.sender,
            gain,
            loss,
            debtPayment,
            strategy.totalGain,
            strategy.totalSkim,
            strategy.totalLoss,
            strategy.totalDebt,
            credit,
            strategy.debtRatio
        );

        if (strategy.debtRatio == 0 || emergencyShutdown) {
            // Take every last penny the Strategy has (Emergency Exit/revokeStrategy)
            // NOTE: This is different than `debt` in order to extract *all* of the returns
            return IStrategy(msg.sender).estimatedTotalAssets();
        } else {
            return debt;
        }
    }

    /// @notice Skim strategy gain to the `rewards` address.
    /// This may only be called by `governance` or `management`
    /// @param strategyId Strategy address to skim.
    function skim(
        address strategyId
    )
        external
        override
        onlyGovernanceOrManagement
        strategyExists(strategyId)
    {
        uint amount = strategies_[strategyId].totalGain - strategies_[strategyId].totalSkim;

        require(amount > 0);

        strategies_[strategyId].totalSkim += amount;

        _transferToEverscale(rewards, amount);
    }

    /**
        @notice Removes tokens from this Vault that are not the type of token managed
            by this Vault. This may be used in case of accidentally sending the
            wrong kind of token to this Vault.

            Tokens will be sent to `governance`.

            This will fail if an attempt is made to sweep the tokens that this
            Vault manages.

            This may only be called by `governance`.
        @param _token The token to transfer out of this vault.
    */
    function sweep(
        address _token
    ) external override onlyGovernance {
        require(token != _token);

        uint256 amount = IERC20(_token).balanceOf(address(this));

        IERC20(_token).safeTransfer(governance, amount);
    }

    /**
        @notice Force user's pending withdraw. Works only if Vault has enough
            tokens on its balance.

            This may only be called by wrapper.
        @param pendingWithdrawalId Pending withdrawal ID
    */
    function forceWithdraw(
        PendingWithdrawalId memory pendingWithdrawalId
    )
        public
        override
        onlyEmergencyDisabled
        pendingWithdrawalOpened(pendingWithdrawalId)
        pendingWithdrawalApproved(pendingWithdrawalId)
    {
        PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

        IERC20(token).safeTransfer(pendingWithdrawalId.recipient, pendingWithdrawal.amount);

        _pendingWithdrawalAmountReduce(pendingWithdrawalId, pendingWithdrawal.amount);
    }

    /**
        @notice Multicall for `forceWithdraw`
        @param pendingWithdrawalId List of pending withdrawal IDs
    */
    function forceWithdraw(
        PendingWithdrawalId[] memory pendingWithdrawalId
    ) external override {
        for (uint i = 0; i < pendingWithdrawalId.length; i++) {
            forceWithdraw(pendingWithdrawalId[i]);
        }
    }

    /**
        @notice Set approve status for pending withdrawal.
            Pending withdrawal must be in `Required` (1) approve status, so approve status can be set only once.
            If Vault has enough tokens on its balance - withdrawal will be filled immediately.
            This may only be called by `governance` or `withdrawGuardian`.
        @param pendingWithdrawalId Pending withdrawal ID.
        @param approveStatus Approve status. Must be `Approved` (2) or `Rejected` (3).
    */
    function setPendingWithdrawalApprove(
        PendingWithdrawalId memory pendingWithdrawalId,
        ApproveStatus approveStatus
    )
        public
        override
        onlyGovernanceOrWithdrawGuardian
        pendingWithdrawalOpened(pendingWithdrawalId)
    {
        PendingWithdrawalParams memory pendingWithdrawal = _pendingWithdrawal(pendingWithdrawalId);

        require(
            pendingWithdrawal.approveStatus == ApproveStatus.Required,
            "Vault: pending withdrawal should require confirmation"
        );

        require(
            approveStatus == ApproveStatus.Approved || approveStatus == ApproveStatus.Rejected,
            "Vault: current approve status is wrong"
        );

        _pendingWithdrawalApproveStatusUpdate(pendingWithdrawalId, approveStatus);

        emit PendingWithdrawalUpdateApproveStatus(
            pendingWithdrawalId.recipient,
            pendingWithdrawalId.id,
            approveStatus
        );

        // Fill approved withdrawal
        if (approveStatus == ApproveStatus.Approved && pendingWithdrawal.amount <= _vaultTokenBalance()) {
            _pendingWithdrawalAmountReduce(pendingWithdrawalId, pendingWithdrawal.amount);

            IERC20(token).safeTransfer(
                pendingWithdrawalId.recipient,
                pendingWithdrawal.amount
            );

            emit PendingWithdrawalWithdraw(
                pendingWithdrawalId.recipient,
                pendingWithdrawalId.id,
                pendingWithdrawal.amount,
                pendingWithdrawal.amount
            );
        }

        // Update withdrawal period considered amount
        _withdrawalPeriodIncreaseConsideredByTimestamp(
            pendingWithdrawal.timestamp,
            pendingWithdrawal.amount
        );
    }

    /**
        @notice Multicall for `setPendingWithdrawalApprove`.
        @param pendingWithdrawalId List of pending withdrawals IDs.
        @param approveStatus List of approve statuses.
    */
    function setPendingWithdrawalApprove(
        PendingWithdrawalId[] memory pendingWithdrawalId,
        ApproveStatus[] memory approveStatus
    ) external override {
        require(pendingWithdrawalId.length == approveStatus.length);

        for (uint i = 0; i < pendingWithdrawalId.length; i++) {
            setPendingWithdrawalApprove(pendingWithdrawalId[i], approveStatus[i]);
        }
    }

    function _transferToEverscale(
        EverscaleAddress memory recipient,
        uint256 _amount
    ) internal {
        uint256 amount = _convertToTargetDecimals(_amount);

        emit Deposit(amount, recipient.wid, recipient.addr);
    }
}