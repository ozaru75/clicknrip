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
use crate::models::player::PlayerStats;
use crate::pool::IPoolDispatcherTrait;
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::{MIN_STAKE, TOKEN_UNIT, cheat_erc20_balance, fund_and_approve};
use crate::tests::utils::setup::setup;

#[test]
fn test_new_game() {
    let (world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);

    let player_balance_before = token.balance_of(player);
    let pool_balance_before = token.balance_of(pool.contract_address);
    let liquidity_before = pool.get_liquidity();

    let mut spy = spy_events();
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    // Verify GameCreated event
    let mut event_fields: Array<felt252> = array![];
    Serde::serialize(
        @crate::systems::actions::actions::GameCreated { player, id, stake }, ref event_fields,
    );
    let event_values = event_fields.span().slice(1, event_fields.len() - 1);
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GameCreated"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: event_values,
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    // Verify game model
    let game: Game = world.read_model(id);
    assert!(game.player == player, "player mismatch");
    assert!(game.stake == stake, "stake mismatch");
    assert!(game.status == GameStatus::Active, "game should be active");
    assert!(game.level == 1, "level should start at 1");
    assert!(game.payout == 0, "payout should be zero at start");

    // Verify stake transferred from player to pool
    assert!(
        token.balance_of(player) == player_balance_before - stake,
        "player balance should decrease by stake",
    );
    assert!(
        token.balance_of(pool.contract_address) == pool_balance_before + stake,
        "pool balance should increase by stake",
    );

    // Verify level 1 reserve was locked
    let level_1_reserve = actions.get_payout(stake, 1) - stake;
    assert!(
        pool.get_liquidity() == liquidity_before + stake - level_1_reserve,
        "liquidity should reflect deposited stake minus level 1 reserve",
    );

    // Verify player stats
    let stats: PlayerStats = world.read_model(player);
    assert!(stats.games_played == 1, "games_played should be 1");
    assert!(stats.total_staked == stake, "total_staked should equal stake");
    assert!(stats.last_game_id == id, "last_game_id should match");
}

#[test]
#[should_panic(expected: ('game is active',))]
fn test_new_game_while_active() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    // Fund enough for one game only; the second call reverts before transfer
    fund_and_approve(player, token, pool.contract_address, stake);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('stake below minimum',))]
fn test_new_game_stake_below_minimum() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE - 1;

    fund_and_approve(player, token, pool.contract_address, stake);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('stake above maximum',))]
fn test_new_game_stake_above_maximum() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = 1001 * TOKEN_UNIT;

    fund_and_approve(player, token, pool.contract_address, stake);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('stake above maximum',))]
fn test_new_game_empty_pool() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    cheat_erc20_balance(pool.contract_address, token.contract_address, 0);
    fund_and_approve(player, token, pool.contract_address, stake);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('stake above maximum',))]
fn test_new_game_insufficient_liquidity() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    cheat_erc20_balance(pool.contract_address, token.contract_address, 19 * TOKEN_UNIT);
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);
}
