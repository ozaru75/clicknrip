use starknet::ContractAddress;

#[derive(Drop, Copy, Clone, Serde)]
pub enum Source {
    Nonce: ContractAddress,
    Salt: felt252,
}

#[starknet::interface]
pub trait IVrfProvider<T> {
    fn request_random(self: @T, caller: ContractAddress, source: Source);
    fn consume_random(ref self: T, source: Source) -> felt252;
}
