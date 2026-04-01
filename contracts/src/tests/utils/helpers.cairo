// OpenZeppelin
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

// Snforge
use snforge_std::{
    CustomToken, Token, set_balance, start_cheat_caller_address, stop_cheat_caller_address,
};

// Starknet
use starknet::ContractAddress;

// Standard ERC20 unit (10^18)
pub const TOKEN_UNIT: u256 = 1_000_000_000_000_000_000;

pub const MIN_STAKE: u256 = TOKEN_UNIT * 2;

// Team fee: 1% (matches Config in setup)
pub const TEAM_FEE_BPS: u16 = 100;

pub const ADMIN: ContractAddress = 'ADMIN'.try_into().unwrap();

pub const VRF_PROVIDER: ContractAddress = 'VRF_PROVIDER'.try_into().unwrap();

// Initial token supply minted to ADMIN
pub const TOKEN_SUPPLY: u256 = 100 * TOKEN_UNIT;

// Initial pool liquidity seeded at setup
pub const POOL_LIQUIDITY: u256 = TOKEN_UNIT * 10_000;

pub fn cheat_erc20_balance(user: ContractAddress, token: ContractAddress, balance: u256) {
    let token = Token::Custom(
        CustomToken {
            contract_address: token, balances_variable_selector: selector!("ERC20_balances"),
        },
    );
    set_balance(user, balance, token);
}

pub fn fund_and_approve(
    player: ContractAddress, token: IERC20Dispatcher, spender: ContractAddress, amount: u256,
) {
    cheat_erc20_balance(player, token.contract_address, amount);
    start_cheat_caller_address(token.contract_address, player);
    token.approve(spender, amount);
    stop_cheat_caller_address(token.contract_address);
}
