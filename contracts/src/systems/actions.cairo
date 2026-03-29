#[starknet::interface]
pub trait IActions<T> {
    fn new_game(ref self: T, stake: u256) -> u32;
    fn new_guess(ref self: T, guess: u8) -> bool;
}

#[dojo::contract]
pub mod actions {
    // Dojo
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use dojo::world::{IWorldDispatcherTrait, WorldStorage};

    // OpenZeppelin
    use openzeppelin_access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_security::ReentrancyGuardComponent;

    // Starknet
    use starknet::{ContractAddress, get_caller_address};

    // Project
    use crate::models::config::{CONFIG_ID, Config};
    use crate::models::game::{Game, GameStatus, GameTrait};
    use crate::models::player::PlayerStats;
    // use crate::pool::IPoolDispatcher;

    pub const OPERATOR_ROLE: felt252 = selector!("OPERATOR_ROLE");

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
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
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

            // Generate unique game ID
            let id = world.dispatcher.uuid();

            // TODO: Verify pool has enough liquidity to cover first-round cashout
            // TODO: Pull stake from player into pool

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
