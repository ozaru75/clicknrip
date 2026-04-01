#[starknet::interface]
pub trait IActions<T> {
    fn new_game(ref self: T, stake: u256) -> u32;
    fn new_guess(ref self: T, guess: u8) -> bool;
    fn cashout(ref self: T);
    fn update_config(ref self: T, min_stake: u256, team_fee_bps: u16, max_stake_bps: u16);
    fn pause(ref self: T);
    fn unpause(ref self: T);
    fn admin_force_resolve(ref self: T, game_id: u32);
    fn get_payout(self: @T, stake: u256, level: u8) -> u256;
    fn get_row_size(self: @T, level: u8) -> u8;
}

#[dojo::contract]
pub mod actions {
    // Core
    use core::num::traits::Zero;

    // Dojo
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use dojo::world::{IWorldDispatcherTrait, WorldStorage};

    // OpenZeppelin
    use openzeppelin_access::accesscontrol::AccessControlComponent;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_security::{PausableComponent, ReentrancyGuardComponent};

    // Starknet
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    // Project
    use crate::models::config::{CONFIG_ID, Config};
    use crate::models::game::{Game, GameStatus, GameTrait};
    use crate::models::player::PlayerStats;
    use crate::pool::{IPoolDispatcher, IPoolDispatcherTrait};
    use crate::roles::{ADMIN_ROLE, OPERATOR_ROLE};
    use crate::vrf::{IVrfProviderDispatcher, IVrfProviderDispatcherTrait, Source};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    pub const LEVEL_MAX: u8 = 25;

    // 7 days in seconds; admin can only force-resolve games stuck longer than this
    pub const FORCE_RESOLVE_DELAY: u64 = 7 * 24 * 60 * 60;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameCreated {
        #[key]
        pub player: ContractAddress,
        pub id: u32,
        pub stake: u256,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GuessResolved {
        #[key]
        pub player: ContractAddress,
        pub id: u32,
        pub level: u8,
        pub guess: u8,
        pub death_tile: u8,
        pub survived: bool,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct GameEnded {
        #[key]
        pub player: ContractAddress,
        pub id: u32,
        pub status: GameStatus,
        pub payout: u256,
    }

    fn dojo_init(ref self: ContractState, admin: ContractAddress, operator: ContractAddress) {
        assert(admin.is_non_zero(), 'admin address is zero');
        assert(operator.is_non_zero(), 'operator address is zero');

        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(ADMIN_ROLE, admin);
        self.accesscontrol._grant_role(OPERATOR_ROLE, operator);
    }

    #[abi(embed_v0)]
    impl ActionsImpl of super::IActions<ContractState> {
        fn new_game(ref self: ContractState, stake: u256) -> u32 {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();

            let (mut world, config, last_game, mut stats, player) = self.get_context();

            // Reject if player already has an active game
            last_game.assert_not_active();

            let pool = IPoolDispatcher { contract_address: config.pool };

            // Reject stakes outside the allowed range
            assert(stake >= config.min_stake, 'stake below minimum');
            let max_stake = pool.get_liquidity() * config.max_stake_bps.into() / 10000;
            assert(stake <= max_stake, 'stake above maximum');

            // Pool must lock extra liquidity to cover level 1 payout
            let first_level_payout = self.get_payout(stake, 1);
            let extra_to_lock = first_level_payout - stake;
            pool.lock_reserve(extra_to_lock);

            // Pull stake from player into the pool
            pool.deposit(player, stake);

            // Generate unique game ID
            let id = world.dispatcher.uuid();

            // Write game state
            world
                .write_model(
                    @Game {
                        id,
                        player,
                        status: GameStatus::Active,
                        level: 1,
                        stake,
                        payout: 0,
                        started_at: get_block_timestamp(),
                    },
                );

            // Update player stats
            stats.last_game_id = id;
            stats.games_played += 1;
            stats.total_staked += stake;
            world.write_model(@stats);

            world.emit_event(@GameCreated { player, id, stake });

            self.reentrancy_guard.end();

            id
        }

        fn new_guess(ref self: ContractState, guess: u8) -> bool {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();

            let (mut world, config, mut game, mut stats, player) = self.get_context();

            game.assert_active();

            // Reject guess outside the valid range for this level
            let row_size = self.get_row_size(game.level);
            assert(guess >= 1 && guess <= row_size, 'guess out of range');

            let pool = IPoolDispatcher { contract_address: config.pool };
            let current_payout = self.get_payout(game.stake, game.level);

            // If not at max level ensure the pool can cover the reserve delta
            let next_payout = if game.level < LEVEL_MAX {
                let np = self.get_payout(game.stake, game.level + 1);
                assert(pool.get_liquidity() >= np - current_payout, 'insufficient liquidity');
                np
            } else {
                0
            };

            // Consume randomness and derive the death tile
            let vrf = IVrfProviderDispatcher { contract_address: config.vrf_provider };
            let random: u256 = vrf.consume_random(Source::Nonce(player)).into();

            let death_tile: u8 = ((random.low % row_size.into()) + 1).try_into().unwrap();

            let survived = guess != death_tile;

            world
                .emit_event(
                    @GuessResolved {
                        player, id: game.id, level: game.level, guess, death_tile, survived,
                    },
                );

            if !survived {
                // Stake stays in pool as revenue; release the reserved extra liquidity
                pool.unlock_reserve(current_payout - game.stake);

                if config.team_fee_bps > 0 {
                    let fee = game.stake * config.team_fee_bps.into() / 10000;
                    pool.accrue_fee(fee);
                }

                game.status = GameStatus::Lost;
                world.write_model(@game);

                world
                    .emit_event(
                        @GameEnded { player, id: game.id, status: GameStatus::Lost, payout: 0 },
                    );
            } else if game.level == LEVEL_MAX {
                // Max level reached: cashout at current payout
                self.finalize_cashout(ref world, pool, ref game, ref stats, player, current_payout);
            } else {
                // Survive: lock the extra reserve for the next level
                pool.lock_reserve(next_payout - current_payout);
                game.level += 1;
                world.write_model(@game);
            }

            self.reentrancy_guard.end();

            survived
        }

        fn cashout(ref self: ContractState) {
            self.pausable.assert_not_paused();
            self.reentrancy_guard.start();

            let (mut world, config, mut game, mut stats, player) = self.get_context();

            game.assert_active();

            // Player must have survived at least one guess before cashing out
            assert(game.level > 1, 'must guess before cashout');

            // Compute payout at the current level
            let payout = self.get_payout(game.stake, game.level);

            let pool = IPoolDispatcher { contract_address: config.pool };
            self.finalize_cashout(ref world, pool, ref game, ref stats, player, payout);

            self.reentrancy_guard.end();
        }

        fn update_config(
            ref self: ContractState, min_stake: u256, team_fee_bps: u16, max_stake_bps: u16,
        ) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);

            assert(max_stake_bps > 0, 'max stake bps is zero');

            // Read existing config to preserve pool and vrf_provider addresses
            let mut world: WorldStorage = self.world(@"clicknrip");
            let mut config: Config = world.read_model(CONFIG_ID);
            config.min_stake = min_stake;
            config.team_fee_bps = team_fee_bps;
            config.max_stake_bps = max_stake_bps;
            world.write_model(@config);
        }

        fn pause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.pausable.unpause();
        }

        fn admin_force_resolve(ref self: ContractState, game_id: u32) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.reentrancy_guard.start();

            let mut world: WorldStorage = self.world(@"clicknrip");
            let config: Config = world.read_model(CONFIG_ID);
            let mut game: Game = world.read_model(game_id);

            game.assert_active();

            let elapsed = get_block_timestamp() - game.started_at;
            assert(elapsed >= FORCE_RESOLVE_DELAY, 'too early to force resolve');

            // Release the locked reserve; stake stays in pool as revenue
            let locked_reserve = self.get_payout(game.stake, game.level) - game.stake;
            let pool = IPoolDispatcher { contract_address: config.pool };
            pool.unlock_reserve(locked_reserve);

            game.status = GameStatus::Lost;
            world.write_model(@game);

            world
                .emit_event(
                    @GameEnded {
                        player: game.player, id: game.id, status: GameStatus::Lost, payout: 0,
                    },
                );

            self.reentrancy_guard.end();
        }

        fn get_payout(self: @ContractState, stake: u256, level: u8) -> u256 {
            let multiplier: u256 = get_level_multiplier(level).into();
            stake * multiplier / 100
        }

        fn get_row_size(self: @ContractState, level: u8) -> u8 {
            assert(level >= 1 && level <= LEVEL_MAX, 'level out of range');
            *ROW_SIZES.span()[((level - 1) & 7).into()]
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_context(
            self: @ContractState,
        ) -> (WorldStorage, Config, Game, PlayerStats, ContractAddress) {
            let world: WorldStorage = self.world(@"clicknrip");
            let config: Config = world.read_model(CONFIG_ID);
            let player: ContractAddress = get_caller_address();
            let stats: PlayerStats = world.read_model(player);
            let game: Game = world.read_model(stats.last_game_id);

            (world, config, game, stats, player)
        }

        fn finalize_cashout(
            self: @ContractState,
            ref world: WorldStorage,
            pool: IPoolDispatcher,
            ref game: Game,
            ref stats: PlayerStats,
            player: ContractAddress,
            payout: u256,
        ) {
            pool.unlock_reserve(payout - game.stake);
            pool.payout(player, payout);

            game.status = GameStatus::CashedOut;
            game.payout = payout;
            world.write_model(@game);

            stats.games_won += 1;
            stats.total_won += payout;
            world.write_model(@stats);

            world
                .emit_event(
                    @GameEnded { player, id: game.id, status: GameStatus::CashedOut, payout },
                );
        }
    }

    const ROW_SIZES: [u8; 8] = [7, 6, 5, 4, 3, 4, 5, 6];

    // Precalculated multipliers for each level (1-25) at 95% RTP (5% house edge)
    // Values represent percentage multipliers (e.g., 110 = 1.10x)
    const LEVEL_MULTIPLIERS: [u32; 25] = [
        110, // Level 1:  1.10x
        133, // Level 2:  1.33x
        166, // Level 3:  1.66x
        221, // Level 4:  2.21x
        332, // Level 5:  3.32x
        443, // Level 6:  4.43x
        554, // Level 7:  5.54x
        665, // Level 8:  6.65x
        775, // Level 9:  7.75x
        931, // Level 10: 9.31x
        1163, // Level 11: 11.63x
        1551, // Level 12: 15.51x
        2327, // Level 13: 23.27x
        3103, // Level 14: 31.03x
        3879, // Level 15: 38.79x
        4655, // Level 16: 46.55x
        5430, // Level 17: 54.30x
        6517, // Level 18: 65.17x
        8146, // Level 19: 81.46x
        10861, // Level 20: 108.61x
        16292, // Level 21: 162.92x
        21723, // Level 22: 217.23x
        27154, // Level 23: 271.54x
        32585, // Level 24: 325.85x
        38015 // Level 25: 380.15x
    ];

    pub fn get_level_multiplier(level: u8) -> u32 {
        assert(level >= 1 && level <= LEVEL_MAX, 'level out of range');
        let multipliers_span = LEVEL_MULTIPLIERS.span();
        *multipliers_span[level.into() - 1]
    }
}
