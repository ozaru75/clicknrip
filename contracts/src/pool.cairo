use starknet::ContractAddress;

#[starknet::interface]
pub trait IPool<T> {
    fn get_liquidity(self: @T) -> u256;
    fn deposit(ref self: T, from: ContractAddress, amount: u256);
    fn payout(ref self: T, to: ContractAddress, amount: u256);
    fn lock_reserve(ref self: T, amount: u256);
    fn unlock_reserve(ref self: T, amount: u256);
}

#[starknet::contract]
pub mod pool {
    // Core
    use core::num::traits::Zero;

    // OpenZeppelin
    use openzeppelin_access::accesscontrol::{AccessControlComponent};
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;

    // Starknet
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use crate::roles::{ADMIN_ROLE, OPERATOR_ROLE};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        token: ContractAddress,
        locked_funds: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token: ContractAddress) {
        assert(owner.is_non_zero(), 'owner address is zero');
        assert(token.is_non_zero(), 'token address is zero');

        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(ADMIN_ROLE, owner);
        self.token.write(token);
    }

    #[abi(embed_v0)]
    impl PoolImpl of super::IPool<ContractState> {
        fn get_liquidity(self: @ContractState) -> u256 {
            let token = IERC20Dispatcher { contract_address: self.token.read() };
            token.balance_of(get_contract_address()) - self.locked_funds.read()
        }

        fn deposit(ref self: ContractState, from: ContractAddress, amount: u256) {
            self.accesscontrol.assert_only_role(OPERATOR_ROLE);
            let token = IERC20Dispatcher { contract_address: self.token.read() };
            token.transfer_from(from, get_contract_address(), amount);
        }

        fn payout(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.accesscontrol.assert_only_role(OPERATOR_ROLE);
            let token = IERC20Dispatcher { contract_address: self.token.read() };
            token.transfer(to, amount);
        }

        fn lock_reserve(ref self: ContractState, amount: u256) {
            self.accesscontrol.assert_only_role(OPERATOR_ROLE);
            self.adjust_locked_funds(amount, true);
        }

        fn unlock_reserve(ref self: ContractState, amount: u256) {
            self.accesscontrol.assert_only_role(OPERATOR_ROLE);
            self.adjust_locked_funds(amount, false);
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn adjust_locked_funds(ref self: ContractState, amount: u256, lock: bool) {
            let current = self.locked_funds.read();
            if lock {
                assert(self.get_liquidity() >= amount, 'insufficient liquidity');
                self.locked_funds.write(current + amount);
            } else {
                assert(current >= amount, 'unlock exceeds locked funds');
                self.locked_funds.write(current - amount);
            }
        }
    }
}
