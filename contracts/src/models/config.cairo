use starknet::ContractAddress;

pub const CONFIG_ID: felt252 = 'CONFIG';

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Config {
    #[key]
    pub id: felt252,
    pub min_stake: u256,
    pub team_fee_bps: u16,
    pub max_stake_bps: u16,
    pub pool: ContractAddress,
    pub vrf_provider: ContractAddress,
}
