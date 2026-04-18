// Mock vRNG for devnet testing only
// Returns block timestamp as the random value
// Do not deploy to sepolia or mainnet

use starknet::ContractAddress;
use crate::vrng::Source;

#[starknet::interface]
pub trait IMockVRNG<T> {
    fn request_random(self: @T, caller: ContractAddress, source: Source);
    fn consume_random(ref self: T, source: Source) -> felt252;
}

#[starknet::contract]
pub mod mock_vrng {
    // Starknet
    use starknet::ContractAddress;

    // Project
    use crate::vrng::Source;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MockVRNG of super::IMockVRNG<ContractState> {
        fn request_random(self: @ContractState, caller: ContractAddress, source: Source) {}

        fn consume_random(ref self: ContractState, source: Source) -> felt252 {
            starknet::get_block_timestamp().into()
        }
    }
}
