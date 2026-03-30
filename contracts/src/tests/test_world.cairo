// Dojo
use dojo::model::ModelStorage;
use dojo::utils::selector_from_namespace_and_name;
use dojo::world::world::{Event as WorldEvent, EventEmitted};

// Snforge
use snforge_std::{
    EventSpyAssertionsTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
};

// Starknet
use starknet::ContractAddress;

// Project
use crate::models::game::{Game, GameStatus};
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::{MIN_STAKE, cheat_erc20_balance};
use crate::tests::utils::setup::setup;

#[test]
fn test_new_game() {
    let (world, mut actions, _pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    cheat_erc20_balance(player, token.contract_address, MIN_STAKE);

    // let player_balance_before = token.balance_of(player);
    // let pool_balance_before = token.balance_of(pool.contract_address);

    // Cheat caller as player and capture emitted events
    let mut spy = spy_events();
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);

    // Verify GameCreated event was emitted
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GameCreated"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: [id.into(), MIN_STAKE.try_into().unwrap(), MIN_STAKE.high.try_into().unwrap()]
                .span(),
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    // Verify game state was written to world
    let game: Game = world.read_model(id);
    assert!(game.player == player, "Game player mismatch");
    assert!(game.stake == MIN_STAKE, "Game stake mismatch");
    assert!(game.status == GameStatus::Active, "Game should be active");
    assert!(game.level == 1, "Game should start at level 1");
}
