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
    use std::signer::address_of;
    use aptos_framework::block;
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::table::{Self, Table};

    // Structs ====================================================

    // INTERNAL TYPE TO DESCRIBE A XEN MINT INFO
    struct MintInfo has key {
        user: address,
        term: u64,
        maturity_ts: u64,
        rank: u64,
        amplifier: u64,
        eaa_rate: u64,
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
        // user address => XEN mint info
        // user_mints: Table<address, MintInfo>,
        // user address => XEN stake info
        // user_stakes: Table<address, MintInfo>,
        // user address => XEN burn amount
        user_burns: Table<address, u64>,
    }

    struct XENCapbility<phantom CoinType> has key {
        burn_cap: coin::BurnCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
        freeze_cap: coin::FreezeCapability<CoinType>,
    }

    // Constants ====================================================

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
    const XEN_APY_START:  u64 = 20;
    const XEN_APY_END:    u64 = 2;

    const XEN_APY_DAYS_STEP:        u64 = 90;
    const MAX_PENALTY_PCT:          u64 = 99;
    const WITHDRAWAL_WINDOW_DAYS:   u64 = 7;
    const TERM_AMPLIFIER_THRESHOLD: u64 = 5000;
    const REWARD_AMPLIFIER_START:   u64 = 3000;
    const REWARD_AMPLIFIER_END:     u64 = 1;

    // const AUTHORS: string = utf"XEN@seaprotocol";

    fun init_module(sender: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<XEN>(
            sender,
            string::utf8(b"XEN"),
            string::utf8(b"XEN"),
            8,
            false,
        );
        move_to(sender, XENCapbility<XEN> {
            burn_cap: burn_cap,
            mint_cap: mint_cap,
            freeze_cap: freeze_cap,
        });
        move_to(sender, Dashboard {
            genesis_ts: block::get_epoch_interval_secs(),
            global_rank: 0,
            active_minters: 0,
            active_stakes: 0,
            total_xen_staked: 0,
            // user address => XEN mint info
            // user_mints: table::new<address, MintInfo>(),
            // user address => XEN stake info
            // user_stakes: table::new<address, MintInfo>(),
            // user address => XEN burn amount
            user_burns: table::new<address, u64>(),
        });
    }
    
    // Public functions ====================================================
    public entry fun claim_rank() {

    }

    public entry fun claim_mint_reward() {

    }

    public entry fun claim_mint_reward_share() {

    }

    public entry fun claim_mint_reward_stake() {

    }

    public entry fun mint() {

    }

    public entry fun stake() {

    }

    public entry fun withdraw() {

    }

    public entry fun burn() {

    }

    // Public Getter functions ====================================================
    /**
     * @dev calculates gross Mint Reward
     */
    public entry fun get_gross_reward(
        rank_delta: u64,
        amplifier: u64,
        term: u64,
        eaa: u64
    ): u64 {
        let log128 = log2(rank_delta);
        let reward128 = log128 * amplifier * term * eaa;
        reward128 / 1000
    }

    /**
     * @dev returns User Mint object associated with User account address
     */
    public entry fun get_user_mint(
        account: &signer,
    ): (u64, u64, u64, u64, u64) acquires MintInfo {
        let mi = borrow_global<MintInfo>(address_of(account));
        (mi.term, mi.maturity_ts, mi.rank, mi.amplifier, mi.eaa_rate)
    }

    /**
     * @dev returns XEN Stake object associated with User account address
     */
    public entry fun get_user_stake(
        account: &signer,
    ): (u64, u64, u64, u64) acquires StakeInfo {
        let si = borrow_global<StakeInfo>(address_of(account));
        (si.apy, si.term, si.maturity_ts, si.amount)
    }

    /**
     * @dev returns current AMP
     */
    public entry fun get_current_amp(): u64 acquires Dashboard {
        calculate_reward_amplifier()
    }

    /**
     * @dev returns current EAA Rate
     */
    public entry fun get_current_eaar(): u64 acquires Dashboard {
        calculate_eaa_rate()
    }

    /**
     * @dev returns current APY
     */
    public entry fun get_current_apy(): u64 acquires Dashboard {
        calculate_apy()
    }

    /**
     * @dev returns current MaxTerm
     */
    fun get_current_max_term(): u64 acquires Dashboard {
        calc_max_term()
    }

    // Private functions ====================================================
    fun min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    fun max(a: u64, b: u64): u64 {
        if (a < b) b else a
    }

    fun log2(a: u64): u64 {
        if (a == 0) {
            return 0
        };
        let l = 0;
        while (a > 0) {
            a = a>>1;
            l = l + 1;
        };
        l
    }

    /**
     * @dev calculates current MaxTerm based on Global Rank
     *      (if Global Rank crosses over TERM_AMPLIFIER_THRESHOLD)
     */
    fun calc_max_term(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);
        if (dash.global_rank > TERM_AMPLIFIER_THRESHOLD) {
            let delta = log2(dash.global_rank) * TERM_AMPLIFIER;
            let new_max = delta * SECONDS_IN_DAY + MAX_TERM_END;
            return min(new_max, MAX_TERM_END)
        };

        MAX_TERM_START
    }

    /**
     * @dev calculates Withdrawal Penalty depending on lateness
     */
    fun penalty(secs_late: u64): u64 {
        // =MIN(2^(daysLate+3)/window-1,99)
        let days_late = secs_late / SECONDS_IN_DAY;
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
        eea_rate: u64
    ): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);

        let secs_late = block::get_epoch_interval_secs() - maturity_ts;
        let penalty = penalty(secs_late);
        let rank_delta = max(dash.global_rank - c_rank, 2);
        let eaa = (1000 + eea_rate);
        let reward = get_gross_reward(rank_delta, amplifier, term, eaa);
        return (reward * (100 - penalty)) / 100
    }

    /**
     * @dev cleans up User Mint storage (gets some Gas credit;))
     */
    fun cleanup_user_mint() acquires Dashboard {
        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_minters = dash.active_minters - 1;
    }

    /**
     * @dev calculates XEN Stake Reward
     */
    fun calculate_stake_reward(
        amount: u64,
        term: u64,
        maturity_ts: u64,
        apy: u64,
    ): u64 {
        if (block::get_epoch_interval_secs() > maturity_ts) {
            let rate = (apy * term * 1000000) / DAYS_IN_YEAR;
            return (amount * rate) / 100000000
        };
        0
    }

    /**
     * @dev calculates Reward Amplifier
     */
    fun calculate_reward_amplifier(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);

        let amplifier_decrease = (block::get_epoch_interval_secs() - dash.genesis_ts) / SECONDS_IN_DAY;
        if (amplifier_decrease < REWARD_AMPLIFIER_START) {
            return max(REWARD_AMPLIFIER_START - amplifier_decrease, REWARD_AMPLIFIER_END)
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
     * @dev calculates APY (in %)
     */
    fun calculate_apy(): u64 acquires Dashboard {
        let dash = borrow_global<Dashboard>(@xen);
        let decrease = (block::get_epoch_interval_secs() - dash.genesis_ts) / (SECONDS_IN_DAY * XEN_APY_DAYS_STEP);
        if (XEN_APY_START - XEN_APY_END < decrease) return XEN_APY_END;
        return XEN_APY_START - decrease
    }

    /**
     * @dev creates User Stake
     */
    fun create_stake(
        account: &signer,
        amount: u64,
        term: u64) acquires Dashboard {
        move_to(account, StakeInfo{
            term: term,
            maturity_ts: block::get_epoch_interval_secs() + term * SECONDS_IN_DAY,
            amount: amount,
            apy: calculate_apy()
        });
        let dash = borrow_global_mut<Dashboard>(@xen);
        dash.active_stakes = dash.active_stakes + 1;
        dash.total_xen_staked = dash.total_xen_staked + amount;
    }

}
