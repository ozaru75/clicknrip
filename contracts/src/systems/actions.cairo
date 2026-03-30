#[starknet::interface]
pub trait IActions<T> {
    fn new_game(ref self: T, stake: u256) -> u32;
    fn new_guess(ref self: T, guess: u8) -> bool;
    fn get_round_payout(self: @T, stake: u256, round: u8) -> u256;
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
    use openzeppelin_security::ReentrancyGuardComponent;

    // Starknet
    use starknet::{ContractAddress, get_caller_address};

    // Project
    use crate::models::config::{CONFIG_ID, Config};
    use crate::models::game::{Game, GameStatus, GameTrait};
    use crate::models::player::PlayerStats;
    use crate::pool::{IPoolDispatcher, IPoolDispatcherTrait};
    use crate::roles::{ADMIN_ROLE, OPERATOR_ROLE};
    use super::get_round_multiplier;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    pub const MAX_ROUNDS: u8 = 25;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
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
    pub struct GameEnded {
        #[key]
        pub player: ContractAddress,
        pub id: u32,
        pub status: GameStatus,
        pub payout: u128,
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
            self.reentrancy_guard.start();

            let (mut world, config, last_game, mut stats, player) = self.get_context();

            // Reject if player already has an active game
            last_game.assert_not_active();

            // Reject stakes below the protocol minimum
            assert(stake >= config.min_stake, 'stake below minimum');

            // Compute extra liquidity the pool must lock to guarantee the round 1 payout
            let first_round_payout = self.get_round_payout(stake, 1);
            let extra_to_lock = first_round_payout - stake;

            // Reserve extra liquidity in the pool to cover the round 1 payout
            let pool = IPoolDispatcher { contract_address: config.pool_address };
            pool.lock_reserve(extra_to_lock);

            // TODO: pool deposit

            // Generate unique game ID
            let id = world.dispatcher.uuid();

            // Write game state
            world
                .write_model(
                    @Game { id, player, status: GameStatus::Active, level: 1, stake, payout: 0 },
                );

            // Update player stats
            stats.last_game_id = id;
            stats.games_played += 1;
            stats.total_wagered += stake;
            world.write_model(@stats);

            world.emit_event(@GameCreated { player, id, stake });

            self.reentrancy_guard.end();

            id
        }

        fn new_guess(ref self: ContractState, guess: u8) -> bool {
            true
        }

        fn get_round_payout(self: @ContractState, stake: u256, round: u8) -> u256 {
            assert(round >= 1 && round <= MAX_ROUNDS, 'round out of range');
            let multiplier = get_round_multiplier(round);
            (stake * multiplier.into()) / 100
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
    }
}

// Precalculated multiplier values for each round (1-25)
// Values represent percentage multipliers (e.g., 110 = 1.10x)
const ROUND_MULTIPLIERS: [u32; 25] = [
    110, // Round 1:  1.10x
    133, // Round 2:  1.33x
    166, // Round 3:  1.66x
    221, // Round 4:  2.21x
    332, // Round 5:  3.32x
    443, // Round 6:  4.43x
    554, // Round 7:  5.54x
    665, // Round 8:  6.65x
    775, // Round 9:  7.75x
    931, // Round 10: 9.31x
    1163, // Round 11: 11.63x
    1551, // Round 12: 15.51x
    2327, // Round 13: 23.27x
    3103, // Round 14: 31.03x
    3879, // Round 15: 38.79x
    4655, // Round 16: 46.55x
    5430, // Round 17: 54.30x
    6517, // Round 18: 65.17x
    8146, // Round 19: 81.46x
    10861, // Round 20: 108.61x
    16292, // Round 21: 162.92x
    21723, // Round 22: 217.23x
    27154, // Round 23: 271.54x
    32585, // Round 24: 325.85x
    38015 // Round 25: 380.15x
];

pub fn get_round_multiplier(round: u8) -> u32 {
    let multipliers_span = ROUND_MULTIPLIERS.span();
    *multipliers_span[round.into() - 1]
}
