use snforge_std::{CustomToken, Token, set_balance};

// Starknet
use starknet::ContractAddress;

// Standard ERC20 decimals unit (10^18)
pub const TOKEN_UNIT: u256 = 1_000_000_000_000_000_000;

pub const MIN_STAKE: u256 = TOKEN_UNIT * 2;

pub const ADMIN: ContractAddress = 'ADMIN'.try_into().unwrap();

pub const VRF_PROVIDER: ContractAddress = 'VRF_PROVIDER'.try_into().unwrap();

// Initial token supply for tests
pub const TOKEN_SUPPLY: u256 = 100 * TOKEN_UNIT;

// Initial pool liquidity funded at setup
pub const POOL_LIQUIDITY: u256 = TOKEN_UNIT * 10_000;

pub fn cheat_erc20_balance(user: ContractAddress, token: ContractAddress, balance: u256) {
    let token = Token::Custom(
        CustomToken {
            contract_address: token, balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    set_balance(user, balance, token);
}

