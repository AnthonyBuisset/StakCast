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

// ================ Emergency Resolve Multiple Markets Tests ================

#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_emergency_resolve_multiple_markets_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    
    let market_ids = array![1, 2];
    let market_types = array![0, 0];
    let winning_choices = array![0, 1];
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Arrays length mismatch')]
fn test_emergency_resolve_multiple_markets_arrays_length_mismatch_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_ids = array![1, 2];
    let market_types = array![0]; // Different length
    let winning_choices = array![0, 1];
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Arrays length mismatch')]
fn test_emergency_resolve_multiple_markets_winning_choices_length_mismatch_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_ids = array![1, 2];
    let market_types = array![0, 0];
    let winning_choices = array![0]; // Different length
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market does not exist')]
fn test_emergency_resolve_multiple_markets_market_does_not_exist_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_ids = array![999, 1000]; // Non-existent markets
    let market_types = array![0, 0];
    let winning_choices = array![0, 1];
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market already resolved')]
fn test_emergency_resolve_multiple_markets_market_already_resolved_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_id1 = default_create_predictions(contract);
    let market_id2 = default_create_predictions(contract);
    
    // Resolve the first market first
    start_cheat_block_timestamp(
        contract.contract_address, get_block_timestamp() + 86400 + 3600,
    ); // 1 day + 1 hour
    contract.resolve_prediction(market_id1, 0);
    
    let market_ids = array![market_id1, market_id2]; // First market already resolved
    let market_types = array![0, 0];
    let winning_choices = array![0, 1];
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Invalid choice selected')]
fn test_emergency_resolve_multiple_markets_invalid_choice_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_id1 = default_create_predictions(contract);
    let market_id2 = default_create_predictions(contract);
    
    let market_ids = array![market_id1, market_id2];
    let market_types = array![0, 0];
    let winning_choices = array![0, 3]; // Invalid choice (3)
    
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_emergency_resolve_multiple_markets_success() {
    let (contract, admin_interface, _token) = setup_test_environment();

    // Create multiple markets
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    start_cheat_block_timestamp(contract.contract_address, get_block_timestamp() + 1);
    let market_id1 = default_create_predictions(contract);
    start_cheat_block_timestamp(contract.contract_address, get_block_timestamp() + 2);
    let market_id2 = default_create_predictions(contract);
    start_cheat_block_timestamp(contract.contract_address, get_block_timestamp() + 3);
    let market_id3 = default_create_predictions(contract);
    
    let market_ids = array![market_id1, market_id2, market_id3];
    let market_types = array![0, 0, 0];
    let winning_choices = array![0, 1, 0];
    
    // Resolve all markets at once
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    stop_cheat_caller_address(contract.contract_address);
    
    // Verify all markets are resolved by checking their status
    let market1 = contract.get_prediction(market_id1);
    let market2 = contract.get_prediction(market_id2);
    let market3 = contract.get_prediction(market_id3);
    
    assert!(market1.is_resolved, "Market 1 should be resolved");
    assert!(market2.is_resolved, "Market 2 should be resolved");
    assert!(market3.is_resolved, "Market 3 should be resolved");
    
    assert!(!market1.is_open, "Market 1 should be closed");
    assert!(!market2.is_open, "Market 2 should be closed");
    assert!(!market3.is_open, "Market 3 should be closed");
    
    assert!(market1.winning_choice == Option::Some(0), "Market 1 winning choice should be 0");
    assert!(market2.winning_choice == Option::Some(1), "Market 2 winning choice should be 1");
    assert!(market3.winning_choice == Option::Some(0), "Market 3 winning choice should be 0");
}

#[test]
fn test_emergency_resolve_multiple_markets_empty_arrays_success() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    
    let market_ids = array![];
    let market_types = array![];
    let winning_choices = array![];
    
    // Should succeed with empty arrays
    admin_interface.emergency_resolve_multiple_markets(market_ids, market_types, winning_choices);
    
    stop_cheat_caller_address(contract.contract_address);
}

// ================ Emergency Close Market Tests ================

#[test]
#[should_panic(expected: 'Only admin allowed')]
fn test_non_admin_emergency_close_market_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    stop_cheat_caller_address(contract.contract_address);
    
    start_cheat_caller_address(contract.contract_address, USER1_ADDR());
    admin_interface.emergency_close_market(market_id, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market does not exist')]
fn test_emergency_close_market_market_does_not_exist_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    admin_interface.emergency_close_market(999, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: 'Market already closed')]
fn test_emergency_close_market_already_closed_should_panic() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    
    // Close the market first
    admin_interface.emergency_close_market(market_id, 0);
    
    // Try to close it again - should panic
    admin_interface.emergency_close_market(market_id, 0);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_emergency_close_market_success() {
    let (contract, admin_interface, _token) = setup_test_environment();

    let mut spy = spy_events();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    
    // Close the market
    admin_interface.emergency_close_market(market_id, 0);
    stop_cheat_caller_address(contract.contract_address);
    
    // Verify market is now closed
    let market_after = contract.get_prediction(market_id);
    assert!(!market_after.is_open, "Market should be closed after emergency close");
    
    // Verify event was emitted
    let (emitter, event) = spy.get_events().events.into_iter().last().unwrap();
    assert!(emitter == contract.contract_address, "emitter not contract");
    assert!((*event.data.at(0)).into() == market_id, "market id not correct");
    assert!(*event.data.at(1) == 0, "admin not closer");
    assert!(*event.data.at(2) == ADMIN_ADDR().into(), "admin not closer");
}

#[test]
fn test_emergency_close_market_preserves_other_properties() {
    let (contract, admin_interface, _token) = setup_test_environment();
    start_cheat_caller_address(contract.contract_address, ADMIN_ADDR());
    let market_id = default_create_predictions(contract);
    
    // Get market properties before closing
    let market_before = contract.get_prediction(market_id);
    let title_before = market_before.title.clone();
    let description_before = market_before.description.clone();
    let end_time_before = market_before.end_time;
    let is_resolved_before = market_before.is_resolved;
    
    // Close the market
    admin_interface.emergency_close_market(market_id, 0);
    
    // Verify other properties remain unchanged
    let market_after = contract.get_prediction(market_id);
    assert!(market_after.title == title_before, "Title should not change");
    assert!(market_after.description == description_before, "Description should not change");
    assert!(market_after.end_time == end_time_before, "End time should not change");
    assert!(market_after.is_resolved == is_resolved_before, "Resolved status should not change");
    assert!(!market_after.is_open, "Market should be closed");
    
    stop_cheat_caller_address(contract.contract_address);
}
