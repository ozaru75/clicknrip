// Starknet
use starknet::ContractAddress;

// Standard ERC20 decimals unit (10^18)
pub const TOKEN_UNIT: u256 = 1_000_000_000_000_000_000;

pub const MIN_STAKE: u256 = TOKEN_UNIT * 2;

pub const ADMIN: ContractAddress = 'ADMIN'.try_into().unwrap();

// Initial token supply for tests
pub const TOKEN_SUPPLY: u256 = 100 * TOKEN_UNIT;
