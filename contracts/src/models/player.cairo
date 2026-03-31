use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct PlayerStats {
    #[key]
    pub player: ContractAddress,
    pub last_game_id: u32,
    pub games_played: u32,
    pub games_won: u32,
    pub total_staked: u256,
    pub total_won: u256,
    pub points: u64,
}
