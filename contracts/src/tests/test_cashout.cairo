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
use crate::tests::utils::helpers::{MIN_STAKE, VRF_PROVIDER, fund_and_approve};
use crate::tests::utils::setup::setup;

// Death tile formula: (vrf_value % row_size) + 1
// VRF = 0 -> death_tile = 1 for any row_size, guessing 2 survives

#[test]
fn test_cashout() {
    let (world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(stake);
    stop_cheat_caller_address(actions.contract_address);

    let player_balance_before = token.balance_of(player);

    // Survive level 1: death_tile = 1, player guesses 2
    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    // Survive level 2: death_tile = 1, player guesses 2
    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    let expected_payout = actions.get_payout(stake, 3);
    let liquidity_before_cashout = pool.get_liquidity();

    // Cashout at level 3
    let mut spy = spy_events();
    start_cheat_caller_address(actions.contract_address, player);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);

    // Verify GameEnded event
    let mut event_fields: Array<felt252> = array![];
    Serde::serialize(
        @crate::systems::actions::actions::GameEnded {
            player, id, status: GameStatus::CashedOut, payout: expected_payout,
        },
        ref event_fields,
    );
    let event_values = event_fields.span().slice(1, event_fields.len() - 1);
    let expected = WorldEvent::EventEmitted(
        EventEmitted {
            selector: selector_from_namespace_and_name(world.namespace_hash, @"GameEnded"),
            system_address: actions.contract_address,
            keys: [player.into()].span(),
            values: event_values,
        },
    );
    spy.assert_emitted(@array![(world.dispatcher.contract_address, expected)]);

    // Verify game model
    let game: Game = world.read_model(id);
    assert!(game.status == GameStatus::CashedOut, "game should be cashed out");
    assert!(game.payout == expected_payout, "payout should match level 3 multiplier");

    // Verify player received the payout
    assert!(
        token.balance_of(player) == player_balance_before + expected_payout,
        "player should receive level 3 payout",
    );

    // Verify reserve was released and payout transferred out of the pool
    let level_3_reserve = expected_payout - stake;
    assert!(
        pool.get_liquidity() == liquidity_before_cashout + level_3_reserve - expected_payout,
        "liquidity should reflect released reserve minus payout transferred to player",
    );
    assert!(pool.get_team_unclaimed() == 0, "no team fee on cashout");

    // Verify player stats updated
    let stats: PlayerStats = world.read_model(player);
    assert!(stats.games_won == 1, "games_won should be 1");
    assert!(stats.total_won == expected_payout, "total_won should match payout");
}

#[test]
#[should_panic(expected: ('must guess before cashout',))]
fn test_cashout_without_guess() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let stake = MIN_STAKE;

    fund_and_approve(player, token, pool.contract_address, stake);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(stake);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('game not active',))]
fn test_cashout_no_active_game() {
    let (_world, actions, _pool, _token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    start_cheat_caller_address(actions.contract_address, player);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);
}
