// Dojo
use dojo::model::ModelStorage;
use dojo::utils::selector_from_namespace_and_name;
use dojo::world::world::{Event as WorldEvent, EventEmitted};

// OpenZeppelin
use openzeppelin_interfaces::erc20::IERC20DispatcherTrait;

// Snforge
use snforge_std::{
    EventSpyAssertionsTrait, mock_call, spy_events, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Starknet
use starknet::ContractAddress;

// Project
use crate::models::game::{Game, GameStatus};
use crate::models::player::PlayerStats;
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::{TOKEN_UNIT, VRF_PROVIDER, cheat_erc20_balance};
use crate::tests::utils::setup::setup;

#[test]
fn test_game_cashout() {
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
    start_cheat_caller_address(actions.contract_address, player);
    let mut spy = spy_events();
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

    // Guess at level 1 (survive)
    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    let mut spy = spy_events();
    let survived = actions.new_guess(2); // guess 2, death_tile 1
    stop_cheat_caller_address(actions.contract_address);

    // Verify GuessResolved event: VRF=0 -> slot=0%7=0 -> death_tile=1, guess=2 -> survived=true
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GuessResolved"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: [id.into(), 1_felt252, 2_felt252, 1_felt252, true.into()].span(),
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    assert!(survived, "Player should survive level 1");

    let game: Game = world.read_model(id);
    assert!(game.level == 2, "Game should advance to level 2");
    assert!(game.status == GameStatus::Active, "Game should remain active after level 1");

    // Guess at level 2 (survive)
    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    let survived = actions.new_guess(2); // guess 2, death_tile 1
    stop_cheat_caller_address(actions.contract_address);

    assert!(survived, "Player should survive level 2");

    let game: Game = world.read_model(id);
    assert!(game.level == 3, "Game should advance to level 3");
    assert!(game.status == GameStatus::Active, "Game should remain active after level 2");

    // Cashout at level 3
    let player_balance_before = token.balance_of(player);
    let expected_payout = actions.get_payout(amount, 3);

    start_cheat_caller_address(actions.contract_address, player);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);

    let game: Game = world.read_model(id);
    assert!(game.status == GameStatus::CashedOut, "Game should be cashed out");
    assert!(game.payout == expected_payout, "Game payout should match level 3 payout");

    let player_balance_after = token.balance_of(player);
    assert!(
        player_balance_after == player_balance_before + expected_payout,
        "Player should receive the level 3 payout: expected {}, got {}",
        player_balance_before + expected_payout,
        player_balance_after,
    );

    let stats: PlayerStats = world.read_model(player);
    assert!(stats.games_won == 1, "Player should have 1 win");
    assert!(stats.total_won == expected_payout, "total_won should match payout");
}
