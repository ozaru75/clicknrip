use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, Introspect, PartialEq, Debug, DojoStore, Default)]
pub enum GameStatus {
    #[default]
    None,
    Active,
    CashedOut,
    Lost,
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Game {
    #[key]
    pub id: u32,
    pub player: ContractAddress,
    pub status: GameStatus,
    pub level: u8,
    pub stake: u256,
    pub payout: u256,
    pub started_at: u64,
}

#[generate_trait]
pub impl GameImpl of GameTrait {
    fn assert_active(self: @Game) {
        assert(*self.status == GameStatus::Active, 'game not active');
    }

    fn assert_not_active(self: @Game) {
        assert(*self.status != GameStatus::Active, 'game is active');
    }
}
