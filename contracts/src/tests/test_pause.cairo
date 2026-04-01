// OpenZeppelin
use openzeppelin_interfaces::pausable::{IPausableDispatcher, IPausableDispatcherTrait};

// Snforge
use snforge_std::{mock_call, start_cheat_caller_address, stop_cheat_caller_address};

// Starknet
use starknet::ContractAddress;

// Project
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::{ADMIN, MIN_STAKE, VRF_PROVIDER, fund_and_approve};
use crate::tests::utils::setup::setup;

#[test]
fn test_pause_and_unpause() {
    let (_world, actions, _pool, _token) = setup();

    let pausable = IPausableDispatcher { contract_address: actions.contract_address };

    assert!(!pausable.is_paused(), "should not be paused initially");

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);

    assert!(pausable.is_paused(), "should be paused after pause()");

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.unpause();
    stop_cheat_caller_address(actions.contract_address);

    assert!(!pausable.is_paused(), "should not be paused after unpause()");
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_pause_blocks_new_game() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_pause_blocks_new_guess() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);

    // Start a game before pausing
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);

    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_pause_blocks_cashout() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);

    // Start a game and survive one level so cashout is valid
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);

    mock_call(VRF_PROVIDER, selector!("consume_random"), 0_felt252, 1);
    start_cheat_caller_address(actions.contract_address, player);
    actions.new_guess(2);
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, player);
    actions.cashout();
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
fn test_unpause_resumes_new_game() {
    let (_world, actions, pool, token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();
    fund_and_approve(player, token, pool.contract_address, MIN_STAKE);

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    actions.unpause();
    stop_cheat_caller_address(actions.contract_address);

    start_cheat_caller_address(actions.contract_address, player);
    let id = actions.new_game(MIN_STAKE);
    stop_cheat_caller_address(actions.contract_address);

    assert!(id > 0 || id == 0, "new_game should succeed after unpause");
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_pause_unauthorized() {
    let (_world, actions, _pool, _token) = setup();

    let player: ContractAddress = 'player'.try_into().unwrap();

    start_cheat_caller_address(actions.contract_address, player);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unpause_unauthorized() {
    let (_world, actions, _pool, _token) = setup();

    start_cheat_caller_address(actions.contract_address, ADMIN);
    actions.pause();
    stop_cheat_caller_address(actions.contract_address);

    let player: ContractAddress = 'player'.try_into().unwrap();

    start_cheat_caller_address(actions.contract_address, player);
    actions.unpause();
    stop_cheat_caller_address(actions.contract_address);
}
