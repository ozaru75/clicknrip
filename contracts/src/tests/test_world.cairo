// Dojo
use dojo::model::ModelStorage;
use dojo::utils::selector_from_namespace_and_name;
use dojo::world::world::{Event as WorldEvent, EventEmitted};

// OpenZeppelin
use openzeppelin_interfaces::erc20::IERC20DispatcherTrait;

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
use crate::tests::utils::helpers::{TOKEN_UNIT, cheat_erc20_balance};
use crate::tests::utils::setup::setup;

#[test]
fn test_new_game() {
    let (world, mut actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let amount: u256 = 100 * TOKEN_UNIT;

    cheat_erc20_balance(player, token.contract_address, amount);

    // Player approves the pool to pull the stake
    start_cheat_caller_address(token.contract_address, player);
    token.approve(pool.contract_address, amount);
    stop_cheat_caller_address(token.contract_address);

    let player_balance_before = token.balance_of(player);
    let pool_balance_before = token.balance_of(pool.contract_address);

    // Cheat caller as player and capture emitted events
    let mut spy = spy_events();
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(amount);
    stop_cheat_caller_address(actions.contract_address);

    // Verify GameCreated event was emitted
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GameCreated"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: [id.into(), amount.try_into().unwrap(), amount.high.try_into().unwrap()].span(),
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    // Verify game state was written to world
    let game: Game = world.read_model(id);
    assert!(game.player == player, "Game player mismatch");
    assert!(game.stake == amount, "Game stake mismatch");
    assert!(game.status == GameStatus::Active, "Game should be active");
    assert!(game.level == 1, "Game should start at level 1");

    // Verify stake was transferred from player to pool
    let player_balance_after = token.balance_of(player);
    assert!(
        player_balance_after == player_balance_before - amount,
        "Player balance should decrease by stake: expected {}, got {}",
        player_balance_before - amount,
        player_balance_after,
    );

    let pool_balance_after = token.balance_of(pool.contract_address);
    assert!(
        pool_balance_after == pool_balance_before + amount,
        "Pool balance should increase by stake: expected {}, got {}",
        pool_balance_before + amount,
        pool_balance_after,
    );
}
