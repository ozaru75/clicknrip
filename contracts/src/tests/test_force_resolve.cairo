// Snforge
use snforge_std::{
    mock_call, start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};

// Starknet
use starknet::ContractAddress;

// Project
use crate::systems::actions::IActionsDispatcherTrait;
use crate::systems::actions::actions::FORCE_RESOLVE_DELAY;

// Tests
use crate::tests::utils::helpers::{ADMIN, MIN_STAKE, VRNG_PROVIDER, fund_and_approve};
use crate::tests::utils::setup::setup;

fn start_game(
    actions: crate::systems::actions::IActionsDispatcher,
    pool: crate::pool::IPoolDispatcher,
    token: openzeppelin_interfaces::erc20::IERC20Dispatcher,
    player: ContractAddress,
) -> u32 {
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);
    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);
    id
}

#[test]
fn test_force_resolve_after_delay() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let id = start_game(actions, pool, token, player);

    // Advance time past the delay
    start_cheat_block_timestamp(actions.contract_address, FORCE_RESOLVE_DELAY + 1);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.admin_force_resolve(id);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('too early to force resolve',))]
fn test_force_resolve_too_early() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let id = start_game(actions, pool, token, player);

    // Just one second short of the delay
    start_cheat_block_timestamp(actions.contract_address, FORCE_RESOLVE_DELAY - 1);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.admin_force_resolve(id);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('game not active',))]
fn test_force_resolve_non_active_game() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let id = start_game(actions, pool, token, player);

    // Player cashes out normally first
    mock_call(VRNG_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, player);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);

    // Attempt to force-resolve an already-finished game
    start_cheat_block_timestamp(actions.contract_address, FORCE_RESOLVE_DELAY + 1);
    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.admin_force_resolve(id);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_force_resolve_unauthorized() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    let id = start_game(actions, pool, token, player);

    start_cheat_block_timestamp(actions.contract_address, FORCE_RESOLVE_DELAY + 1);

    // Player tries to force-resolve their own stuck game
    start_cheat_caller_address(actions.contract_address, player);
    actions.admin_force_resolve(id);
    stop_cheat_caller_address(actions.contract_address);
}
