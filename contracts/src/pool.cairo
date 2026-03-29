#[starknet::interface]
pub trait IPool<T> {}

#[starknet::contract]
pub mod pool {
    // Starknet
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token: ContractAddress) {}

    #[abi(embed_v0)]
    impl PoolImpl of super::IPool<ContractState> {}
}
