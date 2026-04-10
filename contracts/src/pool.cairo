use starknet::ContractAddress;

#[starknet::interface]
pub trait IPool<T> {
    fn get_liquidity(self: @T) -> u256;
    fn get_team_unclaimed(self: @T) -> u256;
    fn deposit(ref self: T, from: ContractAddress, amount: u256);
    fn payout(ref self: T, to: ContractAddress, amount: u256);
    fn lock_reserve(ref self: T, amount: u256);
    fn unlock_reserve(ref self: T, amount: u256);
    fn accrue_fee(ref self: T, amount: u256);
    fn claim_fees(ref self: T, to: ContractAddress);
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

    // Project
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
        team_unclaimed: u256,
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
    fn constructor(ref self: ContractState, admin: ContractAddress, token: ContractAddress) {
        assert(admin.is_non_zero(), 'admin address is zero');
        assert(token.is_non_zero(), 'token address is zero');

        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(ADMIN_ROLE, admin);
        self.token.write(token);
    }

    #[abi(embed_v0)]
    impl PoolImpl of super::IPool<ContractState> {
        fn get_liquidity(self: @ContractState) -> u256 {
            let token = IERC20Dispatcher { contract_address: self.token.read() };
            token.balance_of(get_contract_address())
                - (self.locked_funds.read() + self.team_unclaimed.read())
        }

        fn get_team_unclaimed(self: @ContractState) -> u256 {
            self.team_unclaimed.read()
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

        fn accrue_fee(ref self: ContractState, amount: u256) {
            self.accesscontrol.assert_only_role(OPERATOR_ROLE);
            let current = self.team_unclaimed.read();
            self.team_unclaimed.write(current + amount);
        }

        fn claim_fees(ref self: ContractState, to: ContractAddress) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            assert(to.is_non_zero(), 'recipient is zero');
            let amount = self.team_unclaimed.read();
            if amount == 0 {
                return;
            }
            self.team_unclaimed.write(0);
            let token = IERC20Dispatcher { contract_address: self.token.read() };
            token.transfer(to, amount);
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
