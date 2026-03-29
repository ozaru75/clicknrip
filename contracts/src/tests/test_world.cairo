// Project
use crate::systems::actions::IActionsDispatcherTrait;

// Tests
use crate::tests::utils::helpers::TOKEN_UNIT;
use crate::tests::utils::setup::setup;

#[test]
fn test_cashout() {
    let (_world, mut actions, _pool) = setup();

    let stake = TOKEN_UNIT * 100;

    actions.new_game(stake);
}
