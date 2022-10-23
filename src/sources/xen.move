/// # Module-level documentation sections
///
/// * [Background](#Background)
/// * [Implementation](#Implementation)
/// * [Basic public functions](#Basic-public-functions)
/// * [Traversal](#Traversal)
///
/// # Background
///
/// XEN crypto
/// 
module xen::xen {
    use std::string;
    use std::option;
    use std::signer::address_of;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    // use aptos_framework::account;
    use aptos_std::table::{Self, Table};
    // use aptos_std::event::{Self, EventHandle};

    // Events ====================================================
    // struct RedeemEvent has drop, store {
    //     user: address,
    //     xen_amount: u64,
    //     token_amount: u64,
    // }
    /*
    struct RankClaimEvent has drop, store {
        user: address,
        term: u64,
        rank: u64,
    }
    
    struct MintClaimEvent has drop, store {
        user: address,
        reward_amount: u64,
    }

    struct StakeEvent has drop, store {
        user: address,
        amount: u64,
        term: u64,
    }

    struct WithdrawEvent has drop, store {
        user: address,
        amount: u64,
        reward: u64,
    }
    */

    // Structs ====================================================

    // INTERNAL TYPE TO DESCRIBE A XEN MINT INFO
    struct MintInfo has key {
        user: address,
        term: u64,
        maturity_ts: u64,
        rank: u64,
        amplifier: u64,
        eaa_rate: u64,
        // post_1b: bool,
    }

    // INTERNAL TYPE TO DESCRIBE A XEN STAKE
    struct StakeInfo has key {
        apy: u64,
        term: u64,
        maturity_ts: u64,
        amount: u64,
    }

    struct XEN {}

    struct Dashboard has key {
        genesis_ts: u64,
        global_rank: u64,
        active_minters: u64,
        active_stakes: u64,
        total_xen_staked: u64,
        // user address => XEN burn amount
        user_burns: Table<address, u64>,
        total_supply: u64,
        // redeem_events: EventHandle<RedeemEvent>,
        // rank_claim_events: EventHandle<RankClaimEvent>,
        // mint_claim_events: EventHandle<MintClaimEvent>,
        // stake_events: EventHandle<StakeEvent>,
        // withdraw_events: EventHandle<WithdrawEvent>,
    }

    struct XENCapbility<phantom CoinType> has key {
        burn_cap: coin::BurnCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
    }

    // Constants ====================================================
    const TIME_RATIO:     u64 = 1;          // for test: 60*24=1 minute; 6*24=10 min; 24=1 hour
    const SECONDS_IN_DAY: u64 = 3600 * 24;
    const DAYS_IN_YEAR:   u64 = 365;
    const GENESIS_RANK:   u64 = 1;
    const MIN_TERM:       u64 = 1 * 3600 * 24 - 1;
    const MAX_TERM_START: u64 = 100 * 3600 * 24;
    const MAX_TERM_END:   u64 = 1000 * 3600 * 24;
    const TERM_AMPLIFIER: u64 = 15;
    const EAA_PM_START:   u64 = 100;
    const EAA_PM_STEP:    u64 = 1;
    const EAA_RANK_STEP:  u64 = 100000;
    const XEN_MIN_STAKE:  u64 = 0;
    const XEN_MIN_BURN:   u64 = 0;
    const XEN_APY_START:  u64 = 200;   // denominator 1000
    const XEN_APY_END:    u64 = 2;
    const XEN_APY_DENOM:  u64 = 1000;
    const XEN_SCALE:      u64 = 10000;

    const XEN_APY_DAYS_STEP:        u64 = 9;
    const MAX_PENALTY_PCT:          u64 = 99;
    const WITHDRAWAL_WINDOW_DAYS:   u64 = 7;
    const TERM_AMPLIFIER_THRESHOLD: u64 = 5000;
    const REWARD_AMPLIFIER_START:   u64 = 2000; // 3000;
    const REWARD_AMPLIFIER_END:     u64 = 100;  // 1
    const MAX_REWARD_CLAIM:         u64 = 220*1000*40; // 

    const ONE_BILLION: u64 = 1000000000;
    const TWO_BILLION: u64 = 2000000000;
    const MAX_MINT_SUPPLY: u64 = 2100000000;
    const MILLION: u64 = 1000000;

    // Errors ====================================================
    const E_MIN_TERM:    u64 = 100;
    const E_MAX_TERM:    u64 = 101;
    const E_MINT_INFO_EXIST: u64 = 102;
    const E_ALREADY_MINTED:      u64 = 103;
    const E_MIN_STAKE: u64 = 104;
    const E_ALREADY_STAKE: u64 = 105;
    const E_NOT_ENOUGH_BALANCE: u64 = 106;
    const E_NOT_MATURITY: u64 = 107;
    const E_PERCENT_TOO_LARGE: u64 = 108;
    const E_NOT_MINTED: u64 = 109;
    const E_NOT_IMPLEMENT: u64 = 110;
    const E_NO_STAKE: u64 = 111;
    const E_MIN_BURN: u64 = 112;
    const E_ALREADY_CLAIMED: u64 = 113;
    const E_MAX_SUPPLY: u64 = 114;
    const E_IN_STAKE:   u64 = 115;
    const E_NOT_STAKE:  u64 = 116;

    // const AUTHORS: string = utf"XEN@seaprotocol";

    fun init_module(sender: &signer) {
        assert!(address_of(sender) == @xen, 1);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<XEN>(
            sender,
            string::utf8(b"XEN"),
            string::utf8(b"XEN"),
            4,
            false,
        );
        coin::destroy_freeze_cap<XEN>(freeze_cap);
        move_to(sender, XENCapbility<XEN> {
            burn_cap: burn_cap,
            mint_cap: mint_cap,
            // freeze_cap: freeze_cap,
        });
        move_to(sender, Dashboard {
            genesis_ts: get_timestamp(),
            global_rank: 0,
            active_minters: 0,
            active_stakes: 0,
            total_xen_staked: 0,
            user_burns: table::new<address, u64>(),
            total_supply: 0,
            // redeem_events: account::new_event_handle<RedeemEvent>(sender),
            // rank_claim_events: account::new_event_handle<RankClaimEvent>(sender),
            // mint_claim_events: account::new_event_handle<MintClaimEvent>(sender),
            // stake_events: account::new_event_handle<StakeEvent>(sender),
            // withdraw_events: account::new_event_handle<WithdrawEvent>(sender),
        });
        coin::register<XEN>(sender);
    }
    
    // Public functions ====================================================
    /**
     * @dev accepts User cRank claim provided all checks pass (incl. no current claim exists)
     */
    public entry fun claim_rank(
        account: &signer,
        term: u64,
    ) acquires Dashboard {
        let account_addr = address_of(account);
        assert!(!exists<MintInfo>(account_addr), E_MINT_INFO_EXIST);
        let term_sec = term * SECONDS_IN_DAY / TIME_RATIO;
        assert!(term_sec > MIN_TERM / TIME_RATIO, E_MIN_TERM);
        assert!(term_sec < calc_max_term() + 1, E_MAX_TERM);
        let supply = xen_supply();
        assert!(supply < MAX_MINT_SUPPLY * XEN_SCALE, E_MAX_SUPPLY);
        // let post_1b = supply >= ONE_BILLION * XEN_SCALE;

        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_minters = dash.active_minters + 1;
        dash.global_rank  = dash.global_rank + 1;
        let delta_ts = get_timestamp() - dash.genesis_ts;
        // event
        // event::emit_event<RankClaimEvent>(
        //     &mut dash.rank_claim_events,
        //     RankClaimEvent { user: account_addr, term: term, rank: dash.global_rank },
        // );
        move_to(account, MintInfo{
            user: account_addr,
            term: term,
            maturity_ts: get_timestamp() + term_sec,
            rank: dash.global_rank,
            amplifier: calculate_reward_amplifier(delta_ts, supply),
            eaa_rate: calculate_eaa_rate(),
            // post_1b: post_1b,
        });
    }

    /**
     * @dev ends minting upon maturity (and within permitted Withdrawal Time Window), gets minted XEN
     */
    public entry fun claim_mint_reward(
        account: &signer,
    ) acquires MintInfo, Dashboard, XENCapbility {
        let account_addr = address_of(account);
        let mi = borrow_global_mut<MintInfo>(account_addr);
        assert!(mi.term > 0, E_ALREADY_CLAIMED);

        assert!(get_timestamp() >= mi.maturity_ts, E_NOT_MATURITY);
        let reward_amount = calculate_mint_reward(
            mi.rank,
            mi.term,
            mi.maturity_ts,
            mi.amplifier,
            mi.eaa_rate,
            // mi.post_1b,
        ) * XEN_SCALE;

        cleanup_user_mint(mi);
        // mint to user
        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.total_supply = dash.total_supply + reward_amount/100 + reward_amount;
        mint_internal(account, account_addr, reward_amount);
        mint_addition(reward_amount/100)
        // event::emit_event<MintClaimEvent>(
        //     &mut dash.mint_claim_events,
        //     MintClaimEvent { user: account_addr, reward_amount: reward_amount },
        // );
    }

    /**
     * @dev  ends minting upon maturity (and within permitted Withdrawal time Window)
     *       mints XEN coins and stakes 'pct' of it for 'term'
     */
    public entry fun claim_mint_reward_stake(
        account: &signer,
        pct: u64,
        term: u64,
    ) acquires MintInfo, Dashboard, XENCapbility, StakeInfo {
        let account_addr = address_of(account);
        let mi = borrow_global_mut<MintInfo>(account_addr);
        assert!(mi.term > 0, E_ALREADY_CLAIMED);
        assert!(pct < 101, E_PERCENT_TOO_LARGE);
        assert!(get_timestamp() > mi.maturity_ts, E_NOT_MATURITY);

        let reward_amount = calculate_mint_reward(
            mi.rank,
            mi.term,
            mi.maturity_ts,
            mi.amplifier,
            mi.eaa_rate,
            // mi.post_1b,
        ) * XEN_SCALE;
        let staked_reward = (reward_amount * pct) / 100;
        let own_reward = reward_amount - staked_reward;
        //
        // mint reward tokens part
        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.total_supply = dash.total_supply + reward_amount/100 + own_reward;
        mint_internal(account, account_addr, own_reward);
        mint_addition(reward_amount/100);
        cleanup_user_mint(mi);

        // nothing to burn since we haven't minted this part yet
        // stake extra tokens part
        assert!(staked_reward > XEN_MIN_STAKE, E_MIN_STAKE);
        assert!(term * SECONDS_IN_DAY > MIN_TERM, E_MIN_TERM);
        assert!(term * SECONDS_IN_DAY < MAX_TERM_END + 1, E_MAX_TERM);

        create_stake(account, staked_reward, term);

        // event
        // let dash = borrow_global_mut<Dashboard>(@xen);
        // event::emit_event<MintClaimEvent>(
        //     &mut dash.mint_claim_events,
        //     MintClaimEvent { user: account_addr, reward_amount: reward_amount },
        // );
        // event::emit_event<StakeEvent>(
        //     &mut dash.stake_events,
        //     StakeEvent { user: account_addr, amount: staked_reward, term: mi.term },
        // );
    }

    /**
     * @dev initiates XEN Stake in amount for a term (days)
     */
    public entry fun stake(
        account: &signer,
        amount: u64,
        term: u64,
    ) acquires Dashboard, XENCapbility, StakeInfo {
        let account_addr = address_of(account);
        assert!(coin::balance<XEN>(account_addr) >= amount, E_NOT_ENOUGH_BALANCE);
        assert!(amount > XEN_MIN_STAKE, E_MIN_STAKE);
        assert!(term * SECONDS_IN_DAY > MIN_TERM, E_MIN_TERM);
        assert!(term * SECONDS_IN_DAY < MAX_TERM_END + 1, E_MAX_TERM);

        // burn staked XEN
        burn_internal(account, amount);
        // create XEN Stake
        create_stake(account, amount, term);
        // event
        // emit Staked(_msgSender(), amount, term);
        let dash = borrow_global_mut<Dashboard>(@xen);
        if (dash.total_supply > amount) {
            dash.total_supply = dash.total_supply - amount;
        }
        // event::emit_event<StakeEvent>(
        //     &mut dash.stake_events,
        //     StakeEvent { user: account_addr, amount: amount, term: term },
        // );
    }

    /**
     * @dev ends XEN Stake and gets reward if the Stake is mature
     */
    public entry fun withdraw(
        account: &signer,
    ) acquires StakeInfo, Dashboard, XENCapbility {
        let account_addr = address_of(account);
        assert!(exists<StakeInfo>(account_addr), E_NOT_STAKE);
        let si = borrow_global_mut<StakeInfo>(account_addr);
        assert!(si.amount > 0, E_NO_STAKE);
        let xen_reward = calculate_stake_reward(
            si.amount,
            si.term,
            get_timestamp(),
            si.maturity_ts,
            si.apy,
        );

        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_stakes = dash.active_stakes - 1;
        dash.total_xen_staked = dash.total_xen_staked - si.amount;
        dash.total_supply = dash.total_supply + xen_reward;
        si.amount = 0;

        mint_internal(account, account_addr, xen_reward);
        // emit
        // let dash = borrow_global_mut<Dashboard>(@xen);
        // event::emit_event<WithdrawEvent>(
        //     &mut dash.withdraw_events,
        //     WithdrawEvent { user: account_addr, amount: si.amount, reward: xen_reward },
        // );
    }

    /**
     * @dev burns XEN tokens and creates Proof-Of-Burn record to be used by connected DeFi services
     */
    public entry fun burn(
        account: &signer,
        amount: u64,
    ) acquires Dashboard, XENCapbility {
        let account_addr = address_of(account);
        assert!(amount > XEN_MIN_BURN, E_MIN_BURN);

        burn_internal(account, amount);
        let dash = borrow_global_mut<Dashboard>(@xen);
        if (table::contains(&dash.user_burns, account_addr)) {
            let burned = *table::borrow(&dash.user_burns, account_addr);
            table::upsert(&mut dash.user_burns, account_addr, burned + amount);
        } else {
            table::add(&mut dash.user_burns, account_addr, amount);
        }
    }

    // Public Getter functions ====================================================
    /**
     * @dev calculates gross Mint Reward
     */
    public entry fun get_gross_reward(
        rank_delta: u64,
        amplifier: u64,
        term: u64,
        eaa: u64,
        // post_1b: bool,
    ): u64 {
        let log128 = log2(rank_delta);
        // let reward128 = if (post_1b) {
        //     log128 * 100 * term * eaa
        // } else { log128 * amplifier * term * eaa };

        log128 * amplifier * term * eaa
    }

    // Private functions ====================================================
    fun min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    fun max(a: u64, b: u64): u64 {
        if (a < b) b else a
    }

    fun xen_supply(): u64 {
        let supply = coin::supply<XEN>();
        if (option::is_some(&supply)) {
            return ((*option::borrow(&supply) & 0xffffffffffffffff) as u64)
        };
        0
    }

    // mint XEN to account
    fun mint_internal(
        account: &signer,
        addr: address,
        amount: u64,
    ) acquires XENCapbility {
        let cap = borrow_global<XENCapbility<XEN>>(@xen);
        if (!coin::is_account_registered<XEN>(addr)) {
            coin::register<XEN>(account);
        };
        coin::deposit<XEN>(addr, coin::mint(amount, &cap.mint_cap));
    }

    fun mint_addition(
        amount: u64) acquires XENCapbility {
        let cap = borrow_global<XENCapbility<XEN>>(@xen);
        coin::deposit<XEN>(@xen, coin::mint(amount/100, &cap.mint_cap));
    }

    fun burn_internal(
        account: &signer,
        amount: u64
    ) acquires XENCapbility {
        let cap = borrow_global<XENCapbility<XEN>>(@xen);
        coin::burn_from<XEN>(address_of(account), amount, &cap.burn_cap);
    }

    fun log2(a: u64): u64 {
        if (a <= 2) {
            return 1
        };
        let l = 0;
        while (a > 0) {
            a = a>>1;
            l = l + 1;
        };
        l-1
    }

    // fun log10(a: u64): u64 {
    //     if (a < 100) {
    //         return 1
    //     };
    //     let l = 0;
    //     while (a > 0) {
    //         a = a/10;
    //         l = l + 1;
    //     };
    //     l-1
    // }

    fun get_timestamp(): u64 {
        timestamp::now_seconds()
    }

    /**
     * @dev calculates current MaxTerm based on Global Rank
     *      (if Global Rank crosses over TERM_AMPLIFIER_THRESHOLD)
     */
    fun calc_max_term(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);

        calc_max_term_pure(dash.global_rank)
    }

    fun calc_max_term_pure(global_rank: u64): u64 {
        if (global_rank > TERM_AMPLIFIER_THRESHOLD) {
            let delta = log2(global_rank) * TERM_AMPLIFIER;
            let new_max = delta * SECONDS_IN_DAY / TIME_RATIO;
            return min(new_max, MAX_TERM_END / TIME_RATIO)
        };

        MAX_TERM_START / TIME_RATIO
    }

    /**
     * @dev calculates Withdrawal Penalty depending on lateness
     */
    fun penalty(secs_late: u64): u64 {
        // =MIN(2^(daysLate+3)/window-1,99)
        let days_late = secs_late / (SECONDS_IN_DAY / TIME_RATIO);
        if (days_late > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        let penalty: u64 = (1 << ((days_late + 3) as u8)) / WITHDRAWAL_WINDOW_DAYS - 1;
        return min(penalty, MAX_PENALTY_PCT)
    }

    /**
     * @dev calculates net Mint Reward (adjusted for Penalty)
     */
    fun calculate_mint_reward(
        c_rank: u64,
        term: u64,
        maturity_ts: u64,
        amplifier: u64,
        eea_rate: u64,
        // post_1b: bool,
    ): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);
        let now_ts = get_timestamp();

        calc_mint_reward_pure(dash.global_rank,
            c_rank,
            term,
            now_ts,
            maturity_ts,
            amplifier,
            eea_rate,
            // post_1b
        )
    }

    fun calc_mint_reward_pure(
        global_rank: u64,
        c_rank: u64,
        term: u64,
        now_ts: u64,
        maturity_ts: u64,
        amplifier: u64,
        eea_rate: u64,
        // post_1b: bool,
        ): u64 {
        let secs_late = now_ts - maturity_ts;
        let penalty = penalty(secs_late);
        let rank_delta = max(global_rank - c_rank, 2);
        let eaa = (1000 + eea_rate);
        let reward = get_gross_reward(rank_delta, amplifier, term, eaa);
        if (reward > MAX_REWARD_CLAIM * XEN_SCALE) {
            reward = MAX_REWARD_CLAIM * XEN_SCALE;
        };
        // last 100 is decrease the ampl
        return (reward * (100 - penalty)) / 1000 / 100 / 100
    }

    /**
     * @dev cleans up User Mint storage (gets some Gas credit;))
     */
    fun cleanup_user_mint(mi: &mut MintInfo) acquires Dashboard {
        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_minters = dash.active_minters - 1;

        mi.term = 0;
    }

    /**
     * @dev calculates XEN Stake Reward
     */
    fun calculate_stake_reward(
        amount: u64,
        term: u64,
        now_ts: u64,
        maturity_ts: u64,
        apy: u64,
    ): u64 {
        if (now_ts >= maturity_ts) {
            // let rate = (apy * term * 1000_000) / DAYS_IN_YEAR;
            // return (amount * rate) / 100_000_000
            return amount + (apy * amount * term ) / (XEN_APY_DENOM * DAYS_IN_YEAR)
        };
        amount
    }

    /**
     * @dev calculates Reward Amplifier
     */
    fun calculate_reward_amplifier(
        delta_ts: u64,
        supply: u64
    ): u64 {
        let amplifier_decrease = (delta_ts) / (SECONDS_IN_DAY / TIME_RATIO);

        if (amplifier_decrease < REWARD_AMPLIFIER_START) {
            let term_ampl = max(REWARD_AMPLIFIER_START - amplifier_decrease, REWARD_AMPLIFIER_END);
            let supply_decrease = supply / MILLION;
            let supply_ampl = if (supply_decrease > REWARD_AMPLIFIER_START - REWARD_AMPLIFIER_END) {
                REWARD_AMPLIFIER_END
            } else {
                REWARD_AMPLIFIER_START - supply_decrease
            };
            return min(term_ampl, supply_ampl)
        } else {
            return REWARD_AMPLIFIER_END
        }
    }

    /**
     * @dev calculates Early Adopter Amplifier Rate (in 1/000ths)
     *      actual EAA is (1_000 + EAAR) / 1_000
     */
    fun calculate_eaa_rate(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);
        let decrease = (EAA_PM_STEP * dash.global_rank) / EAA_RANK_STEP;
        if (decrease > EAA_PM_START) {
            return 0
        };
        return EAA_PM_START - decrease
    }

    /**
     * @dev calculates APY (in n/1000)
     */
    fun calculate_apy(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);
        cacl_apy_pure(get_timestamp(), dash.genesis_ts)
    }

    fun cacl_apy_pure(
        now_ts: u64,
        genesis_ts: u64,
    ): u64 {
        let decrease = (now_ts - genesis_ts) * 2 / (SECONDS_IN_DAY / TIME_RATIO * XEN_APY_DAYS_STEP);
        if (XEN_APY_START - XEN_APY_END < decrease) XEN_APY_END else XEN_APY_START - decrease
    }

    /**
     * @dev creates User Stake
     */
    fun create_stake(
        account: &signer,
        amount: u64,
        term: u64) acquires Dashboard, StakeInfo {
        if (!exists<StakeInfo>(address_of(account))) {
            move_to(account, StakeInfo{
                term: term,
                maturity_ts: get_timestamp() + term * SECONDS_IN_DAY / TIME_RATIO,
                amount: amount,
                apy: calculate_apy()
            });
        } else {
            let si = borrow_global_mut<StakeInfo>(address_of(account));
            assert!(si.amount == 0, E_IN_STAKE);
            si.term = term;
            si.maturity_ts = get_timestamp() + term * SECONDS_IN_DAY / TIME_RATIO;
            si.amount = amount;
            si.apy = calculate_apy();
        };

        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_stakes = dash.active_stakes + 1;
        dash.total_xen_staked = dash.total_xen_staked + amount;
    }

    #[test_only]
    use std::debug;

    #[test]
    fun test_log2() {
        assert!(log2(2) == 1, 2);
        assert!(log2(3) == 1, 3);
        assert!(log2(4) == 2, 4);
        assert!(log2(5) == 2, 5);
        assert!(log2(6) == 2, 5);
        assert!(log2(7) == 2, 5);
        assert!(log2(8) == 3, 5);
    }

    // #[test]
    // fun test_log10() {
    //     assert!(log10(2) == 1, 2);
    //     assert!(log10(7) == 1, 3);
    //     assert!(log10(10) == 1, 3);
    //     assert!(log10(12) == 1, 3);
    //     assert!(log10(90) == 1, 3);
    //     assert!(log10(100) == 2, 3);
    //     assert!(log10(200) == 2, 3);
    //     assert!(log10(300) == 2, 3);
    //     assert!(log10(1000) == 3, 3);
    //     assert!(log10(3000) == 3, 3);
    //     assert!(log10(9000) == 3, 3);
    // }

    #[test]
    fun test_calc_max_term() {
        debug::print(&(calc_max_term_pure(1)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(10)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(5000)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(5005)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(500500)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(1500500)*TERM_AMPLIFIER/TIME_RATIO));
        debug::print(&(calc_max_term_pure(15005000)*TERM_AMPLIFIER/TIME_RATIO));
    }

    #[test_only]
    fun test_init_module(sender: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<XEN>(
            sender,
            string::utf8(b"XEN"),
            string::utf8(b"XEN"),
            4,
            false,
        );
        move_to(sender, XENCapbility<XEN> {
            burn_cap: burn_cap,
            mint_cap: mint_cap,
        });
        move_to(sender, Dashboard {
            genesis_ts: 0,
            global_rank: 0,
            active_minters: 0,
            active_stakes: 0,
            total_xen_staked: 0,
            user_burns: table::new<address, u64>(),
            total_supply: 0,
            // redeem_events: account::new_event_handle<RedeemEvent>(sender),
            // rank_claim_events: account::new_event_handle<RankClaimEvent>(sender),
            // mint_claim_events: account::new_event_handle<MintClaimEvent>(sender),
            // stake_events: account::new_event_handle<StakeEvent>(sender),
            // withdraw_events: account::new_event_handle<WithdrawEvent>(sender),
        });
        coin::register<XEN>(sender);
        coin::destroy_freeze_cap(freeze_cap);
    }

    #[test]
    fun test_calculate_mint_reward() {
        let reward: u64;
        let global_rank = 10001;
        let c_rank = 1;
        let now_ts = 10;
        let maturity_ts = 10;
        let terms = 1;
        let eaa_rate = 0;
        let amplifier = 2000;

        reward = calc_mint_reward_pure(
            global_rank,
            c_rank,
            terms,
            now_ts,
            maturity_ts,
            amplifier,
            eaa_rate,
            );
        debug::print(&reward);
    }

    #[test]
    fun test_cacl_apy_pure() {
        let now_ts = 102*60*9;
        let genesis_ts = 0;
        debug::print(&cacl_apy_pure(now_ts, genesis_ts));
        now_ts = 101*60*9;
        debug::print(&cacl_apy_pure(now_ts, genesis_ts));
        now_ts = 100*60*9;
        debug::print(&cacl_apy_pure(now_ts, genesis_ts));
        now_ts = 99*60*9;
        debug::print(&cacl_apy_pure(now_ts, genesis_ts));
        now_ts = 50*60*9;
        debug::print(&cacl_apy_pure(now_ts, genesis_ts));
    }

    #[test]
    fun test_calculate_reward_amplifier() {
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 1000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 1000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 200000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 1200000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2000000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2100000000-1));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2100000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2100000001));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 2200000000));
        debug::print(&calculate_reward_amplifier(1/TIME_RATIO, 3200000000));

        debug::print(&calculate_reward_amplifier(1*SECONDS_IN_DAY, 1000000));
        debug::print(&calculate_reward_amplifier(2*SECONDS_IN_DAY, 1000000));
        debug::print(&calculate_reward_amplifier(3*SECONDS_IN_DAY, 1000000));
        debug::print(&calculate_reward_amplifier(10*SECONDS_IN_DAY, 1000000));
        debug::print(&calculate_reward_amplifier(60*SECONDS_IN_DAY, 1000000));
        debug::print(&calculate_reward_amplifier(100*SECONDS_IN_DAY, 1000000));
    }

    #[test]
    fun test_calculate_stake_reward() {
        let amount: u64 = 100 * XEN_SCALE;
        let term: u64 = 10;
        let now_ts: u64 = 1;
        let maturity_ts: u64 = 0;
        let apy: u64 = 1010;
        debug::print(&calculate_stake_reward(amount, term, now_ts, maturity_ts, apy));
    }
}
