use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};
use stakcast::admin_interface::{IAdditionalAdminDispatcher, IAdditionalAdminDispatcherTrait};
use stakcast::interface::{IPredictionHubDispatcher, IPredictionHubDispatcherTrait};
use stakcast::types::{Outcome, UserStake};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use crate::test_utils::{
    ADMIN_ADDR, FEE_RECIPIENT_ADDR, HALF_PRECISION, MODERATOR_ADDR, USER1_ADDR, USER2_ADDR,
    USER3_ADDR, create_test_market, default_create_crypto_prediction, default_create_predictions,
    setup_test_environment, turn_number_to_precision_point,
};

// ================ General Prediction Market Tests ================
// ================ Buy share ========================
#[test]
fn test_admin_functions() {
    let (contract, _admin_interface, _token) = setup_test_environment();

    // asset that adin addres is the expected address
    assert!(contract.get_admin() == ADMIN_ADDR(), "addres not admin");
    assert!(contract.get_fee_recipient() == FEE_RECIPIENT_ADDR(), "address not recipient address");

    // change fee recipient
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    contract.set_fee_recipient(USER3_ADDR());
    stop_cheat_caller_address(contract.contract_address);
    assert!(contract.get_fee_recipient() == USER3_ADDR(), "address not recipient address");

    // add moderator
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    contract.add_moderator(USER1_ADDR());
    contract.set_fee_recipient(MODERATOR_ADDR());
    stop_cheat_caller_address(contract.contract_address);

    // add prediction
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    default_create_predictions(contract);
    stop_cheat_caller_address(contract.contract_address);
    let count = contract.get_prediction_count();
    assert(count == 1, 'Market count should be 1');

    // add moderator
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    contract.remove_all_predictions();
    stop_cheat_caller_address(contract.contract_address);
    let count = contract.get_prediction_count();
    assert(count == 0, 'Market count should be 0');
    assert!(contract.get_fee_recipient() == MODERATOR_ADDR(), "address not recipient address");
}

#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_function_should_panic() {
    let (contract, _admin_interface, _token) = setup_test_environment();
    // set fee recipent with non admin call should panic
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    contract.set_fee_recipient(MODERATOR_ADDR());
    stop_cheat_caller_address(contract.contract_address);
}


#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_remove_prediction_should_panic() {
    let (contract, _admin_interface, _token) = setup_test_environment();
    // set fee recipent with non admin call should panic
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    contract.remove_all_predictions();
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_add_moderator_should_panic() {
    let (contract, _admin_interface, _token) = setup_test_environment();
    // set fee recipent with non admin call should panic
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    contract.add_moderator(MODERATOR_ADDR());
    stop_cheat_caller_address(contract.contract_address);
}


#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_emergency_resolve_market_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    admin_interface.emergency_resolve_market(0, 0, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market does not exist')]
fn test_emergency_resolve_market_market_does_not_exist_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    admin_interface.emergency_resolve_market(999, 0, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market already resolved')]
fn test_emergency_resolve_market_market_already_resolved_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    // Fast forward time to after market end
    start_cheat_block_timestamp(
        contract.contract_address, get_block_timestamp() + 86400 + 3600,
    ); // 1 day + 1 hour
    
    contract.resolve_prediction(market_id, 0);
   
    admin_interface.emergency_resolve_market(market_id, 0, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Invalid choice selected')]
fn test_emergency_resolve_market_invalid_choice_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    admin_interface.emergency_resolve_market(market_id, 0, 3);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_emergency_resolve_market_success() {
    let (contract, admin_interface, _token) = setup_test_environment();

    let mut spy = spy_events();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    admin_interface.emergency_resolve_market(market_id, 0, 0);
    stop_cheat_caller_address(contract.contract_address);

    let (emitter, event) = spy.get_events().events.into_iter().last().unwrap();
    
    assert!(emitter == contract.contract_address, "emitter not contract");
    assert!((*event.data.at(0)).into() == market_id, "market not resolved");
    assert!(*event.data.at(1) == 0, "admin not resolver");
    assert!(*event.data.at(2) == ADMIN_ADDR().into(), "admin not resolver");
    assert!(*event.data.at(3) == 0, "winning choice not 0");

    stop_cheat_caller_address(contract.contract_address);
}

