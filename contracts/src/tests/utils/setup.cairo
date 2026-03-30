// Dojo
use dojo::model::ModelStorageTest;
use dojo::world::{WorldStorage, WorldStorageTrait};
use dojo_snf_test::world::WorldStorageTestTrait;
use dojo_snf_test::{ContractDef, ContractDefTrait, NamespaceDef, TestResource, spawn_test_world};

// OpenZeppelin
use openzeppelin_interfaces::accesscontrol::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin_interfaces::erc20::IERC20Dispatcher;

// Snforge
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Project
use crate::models::config::{CONFIG_ID, Config};
use crate::pool::IPoolDispatcher;
use crate::roles::OPERATOR_ROLE;
use crate::systems::actions::IActionsDispatcher;

// Tests
use crate::tests::utils::helpers::{
    ADMIN, MIN_STAKE, POOL_LIQUIDITY, TOKEN_SUPPLY, cheat_erc20_balance,
};

pub fn setup() -> (WorldStorage, IActionsDispatcher, IPoolDispatcher, IERC20Dispatcher) {
    // Deploy collateral token (ERC20)
    let token_class = declare("ERC20Upgradeable").unwrap().contract_class();
    let name: ByteArray = "Token";
    let symbol: ByteArray = "TKN";
    let mut calldata = array![];
    Serde::serialize(@name, ref calldata);
    Serde::serialize(@symbol, ref calldata);
    Serde::serialize(@TOKEN_SUPPLY, ref calldata);
    Serde::serialize(@ADMIN, ref calldata);
    Serde::serialize(@ADMIN, ref calldata);
    let (contract_address, _) = token_class.deploy(@calldata).unwrap();
    let token = IERC20Dispatcher { contract_address };

    // Deploy pool contract
    let pool_class = declare("pool").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    ADMIN.serialize(ref calldata);
    token.contract_address.serialize(ref calldata);
    let (contract_address, _) = pool_class.deploy(@calldata).unwrap();
    let pool = IPoolDispatcher { contract_address };

    // Spawn Dojo world with all resources
    let ndef = namespace_def();
    let mut world = spawn_test_world([ndef].span());
    world.sync_perms_and_inits(contract_defs());

    // Resolve actions contract address
    let (contract_address, _) = world.dns(@"actions").unwrap();
    let actions = IActionsDispatcher { contract_address };

    // Write protocol config into the world
    let config = Config {
        id: CONFIG_ID, min_stake: MIN_STAKE, team_fee_bps: 0, pool_address: pool.contract_address,
    };
    world.write_model_test(@config);

    // Seed pool with initial liquidity
    cheat_erc20_balance(pool.contract_address, token.contract_address, POOL_LIQUIDITY);

    // Grant the actions contract the operator role on the pool
    start_cheat_caller_address(pool.contract_address, ADMIN);
    IAccessControlDispatcher { contract_address: pool.contract_address }
        .grant_role(OPERATOR_ROLE, actions.contract_address);
    stop_cheat_caller_address(pool.contract_address);

    (world, actions, pool, token)
}

fn namespace_def() -> NamespaceDef {
    NamespaceDef {
        namespace: "clicknrip",
        resources: [
            TestResource::Model("Game"), TestResource::Model("PlayerStats"),
            TestResource::Model("Config"), TestResource::Event("GameCreated"),
            TestResource::Event("GameEnded"), TestResource::Contract("actions"),
        ]
            .span(),
    }
}

fn contract_defs() -> Span<ContractDef> {
    [
        ContractDefTrait::new(@"clicknrip", @"actions")
            .with_writer_of([dojo::utils::bytearray_hash(@"clicknrip")].span())
            .with_init_calldata([ADMIN.into(), ADMIN.into()].span()),
    ]
        .span()
}
