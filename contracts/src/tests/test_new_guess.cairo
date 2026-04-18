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
use crate::pool::IPoolDispatcherTrait;
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::{ADMIN, MIN_STAKE, TEAM_FEE_BPS, VRNG_PROVIDER, fund_and_approve};
use crate::tests::utils::setup::setup;

#[test]
fn test_new_guess_survive() {
    let (world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    let liquidity_before = pool.get_liquidity();

    // Mock VRNG: death_tile = 1, player guesses = 2 (survives)
    mock_call(VRNG_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    let mut spy = spy_events();
    start_cheat_caller_address(actions.contract_address, player);
    let survived = actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    assert!(survived, "player should survive");

    // Verify GuessResolved event
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GuessResolved"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: [id.into(), 1_felt252, 2_felt252, 1_felt252, 1_felt252].span(),
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    // Verify game advanced to level 2
    let game: Game = world.read_model(id);
    assert!(game.level == 2, "game should advance to level 2");
    assert!(game.status == GameStatus::Active, "game should still be active");

    // Verify reserve delta for level 2 was locked
    let level_1_payout = actions.get_payout(stake, 1);
    let level_2_payout = actions.get_payout(stake, 2);
    assert!(
        pool.get_liquidity() == liquidity_before - (level_2_payout - level_1_payout),
        "liquidity should decrease by the level 2 reserve delta",
    );
}

#[test]
fn test_new_guess_lose() {
    let (world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    let liquidity_before = pool.get_liquidity();

    // Mock VRNG: death_tile = 2, player guesses = 2 (loses)
    mock_call(VRNG_PROVIDER, selector!("consume_random"), 1_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    let survived = actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    assert!(!survived, "player should lose");

    // Verify game model
    let game: Game = world.read_model(id);
    assert!(game.status == GameStatus::Lost, "game should be lost");
    assert!(game.payout == 0, "payout should be zero on loss");

    // Verify reserve released and team fee accrued
    let level_1_reserve = actions.get_payout(stake, 1) - stake;
    let expected_fee = stake * TEAM_FEE_BPS.into() / 10000;
    assert!(
        pool.get_liquidity() == liquidity_before + level_1_reserve - expected_fee,
        "liquidity should reflect released reserve minus team fee",
    );
    assert!(pool.get_team_unclaimed() == expected_fee, "team fee should accrue on loss");

    // Verify player stats unchanged on loss
    let stats: PlayerStats = world.read_model(player);
    assert!(stats.games_won == 0, "games_won should remain 0");
    assert!(stats.total_won == 0, "total_won should remain 0");
}

#[test]
fn test_new_guess_full_game() {
    let (world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    let expected_payout = actions.get_payout(stake, 25);
    let player_balance_before = token.balance_of(player);

    // Play through all 25 levels: death_tile = 1, player guesses 2 -> survives each level
    let mut level: u8 = 1;
    while level <= 25 {
        mock_call(VRNG_PROVIDER, selector!("consume_random"), 0_felt252, 1);
        start_cheat_caller_address(actions.contract_address, player);
        actions.new_guess(2);
        stop_cheat_caller_address(actions.contract_address);
        level += 1;
    }

    // Verify auto-cashout at level 25
    let game: Game = world.read_model(id);
    assert!(game.status == GameStatus::CashedOut, "game should be cashed out at level 25");
    assert!(game.payout == expected_payout, "payout should match level 25 multiplier");

    // Verify player received the payout
    assert!(
        token.balance_of(player) == player_balance_before + expected_payout,
        "player should receive level 25 payout",
    );

    // Verify pool liquidity is fully restored (all reserves released, no team fee on win)
    assert!(pool.get_team_unclaimed() == 0, "no team fee on win");

    // Verify player stats
    let stats: PlayerStats = world.read_model(player);
    assert!(stats.games_won == 1, "games_won should be 1");
    assert!(stats.total_won == expected_payout, "total_won should match payout");
}

#[test]
#[should_panic(expected: ('game not active',))]
fn test_new_guess_no_active_game() {
    let (_world, actions, _pool, _token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(1);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('game not active',))]
fn test_new_guess_after_loss() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    // Lose the game
    mock_call(VRNG_PROVIDER, selector!("consume_random"), 1_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    // Second guess after loss must revert
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(1);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('guess out of range',))]
fn test_new_guess_below_range() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    actions.new_guess(0);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('guess out of range',))]
fn test_new_guess_above_range() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    actions.new_guess(8); // level 1 row size is 7
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('insufficient liquidity',))]
fn test_new_guess_insufficient_liquidity() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    // Drain all free liquidity so pool cannot cover the level 2 reserve delta
    let remaining = pool.get_liquidity();
    start_cheat_caller_address(pool.contract_address, actions.contract_address);
    pool.lock_reserve(remaining);
    stop_cheat_caller_address(pool.contract_address);

    mock_call(VRNG_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_update_config_unauthorized() {
    let (_world, actions, _pool, _token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    start_cheat_caller_address(actions.contract_address, player);
    actions.update_config(MIN_STAKE, 100, 500, ADMIN, VRNG_PROVIDER);
    stop_cheat_caller_address(actions.contract_address);
}
