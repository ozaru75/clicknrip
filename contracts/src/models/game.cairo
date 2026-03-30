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
    pub payout: u128,
}

#[generate_trait]
pub impl GameImpl of GameTrait {
    fn assert_active(self: @Game) {
        assert(*self.status == GameStatus::Active, 'game not active');
    }

    fn assert_not_active(self: @Game) {
        assert(*self.status != GameStatus::Active, 'game is active');
    }

    fn assert_owned_by(self: @Game, caller: ContractAddress) {
        assert(*self.player == caller, 'not your game');
    }
}
