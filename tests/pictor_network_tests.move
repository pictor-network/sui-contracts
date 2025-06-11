#[test_only]
#[allow(unused_use)]
module pictor_network::pictor_network_tests;

use pictor_network::pictor_coin::{Self, PICTOR_COIN};
use pictor_network::pictor_manage::{Self, Auth, is_operator};
use pictor_network::pictor_network::{Self, GlobalData, ESystemPaused};
use std::ascii::{Self, String};
use std::debug;
use std::unit_test::assert_eq;
use sui::address::{Self, to_string};
use sui::balance;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::table;
use sui::test_scenario::{Self, ctx, Scenario};
use sui::test_utils;

const USER_CREDIT: u64 = 10000000;
const USER_MINT_AMOUNT: u64 = 1_000_000_000;
const WORKER_COST: u64 = 100;
const WORKER_DURATION: u64 = 1000;

#[test]
fun test_pictor_network() {
    let admin = @0xAD;
    let operator = @0xBEEF;
    let user = @0xC0FFEE;
    let worker_owner = @0xDEADBEEF;
    let mut ts = test_scenario::begin(admin);
    let worker1 = b"worker1".to_ascii_string();
    let job1 = b"job1".to_ascii_string();
    let percentage = 7000; // 70% of earnings
    let deminonator = 10000; // 100% in basis points

    test_init(&mut ts, admin);
    mint_coin(&mut ts, admin, user, USER_MINT_AMOUNT);
    add_operator(&mut ts, admin, operator);
    set_worker_earning_percentage(&mut ts, admin, percentage);
    deposit_pictor_coin(&mut ts, user);
    credit_user(&mut ts, operator, user, USER_CREDIT);

    // Register worker
    register_worker(&mut ts, operator, worker_owner, worker1);

    // operator should create job
    create_job(&mut ts, operator, user, job1);

    // operator should add task
    add_task(&mut ts, operator, job1, 1, worker1);

    let (task_count, payment, is_completed) = get_job_info_by_worker(
        &mut ts,
        operator,
        job1,
        worker1,
    );
    assert!(task_count == 1 && payment == WORKER_COST*percentage/deminonator && !is_completed);

    complete_job(&mut ts, operator, job1);

    let (_, user_credit) = get_user_info(
        &mut ts,
        user,
    );

    let user_remaining_credit = USER_CREDIT - WORKER_COST;

    assert!(user_credit == user_remaining_credit);

    let (worker_balance, _) = get_user_info(
        &mut ts,
        worker_owner,
    );

    assert!(worker_balance == WORKER_COST * percentage / deminonator);

    debit_user(&mut ts, operator, user, 1_000_000);
    let (_, user_credit) = get_user_info(&mut ts, user);
    assert!(user_credit == user_remaining_credit - 1_000_000);

    withdraw_pictor_coin(&mut ts, worker_owner, worker_balance);

    ts.next_tx(admin);
    let treasury_value = get_treasury_value(&ts);
    assert!(treasury_value == USER_MINT_AMOUNT - worker_balance);

    admin_withdraw_treasury(&mut ts, admin, treasury_value);
    ts.next_tx(admin);
    let treasury_value = get_treasury_value(&ts);
    assert!(treasury_value == 0);

    ts.end();
}

#[test]
#[expected_failure(abort_code = pictor_network::ESystemPaused)]
fun test_paused() {
    let admin = @0xAD;
    let operator = @0xBEEF;
    let user = @0xC0FFEE;
    let mut ts = test_scenario::begin(admin);

    test_init(&mut ts, admin);
    pause_system(&mut ts, admin);
    add_operator(&mut ts, admin, operator);
    credit_user(&mut ts, operator, user, USER_CREDIT);

    ts.end();
}

fun test_init(ts: &mut Scenario, admin: address) {
    test_utils::print(b"init");
    pictor_manage::test_init(ts.ctx());
    pictor_network::test_init(ts.ctx());
    pictor_coin::test_init(ts.ctx());
    ts.next_tx(admin);

    assert!(test_scenario::has_most_recent_shared<GlobalData>());

    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::set_coin_type<PICTOR_COIN>(&auth, &mut global, ts.ctx());
    test_scenario::return_shared<Auth>(auth);
    test_scenario::return_shared<GlobalData>(global);
}

fun pause_system(ts: &mut Scenario, admin: address) {
    ts.next_tx(admin);
    let mut auth = test_scenario::take_shared<Auth>(ts);
    pictor_manage::set_pause_status(&mut auth, true, ts.ctx());
    test_scenario::return_shared<Auth>(auth);
}

fun set_worker_earning_percentage(ts: &mut Scenario, admin: address, percentage: u64) {
    test_utils::print(b"set worker earning percentage: ");
    ts.next_tx(admin);
    let mut auth = test_scenario::take_shared<Auth>(ts);
    pictor_manage::set_worker_earning_percentage(&mut auth, percentage, ts.ctx());
    test_scenario::return_shared<Auth>(auth);
}

fun mint_coin(ts: &mut Scenario, admin: address, recipient: address, amount: u64) {
    test_utils::print(concat(b"mint coin to: ", recipient));
    ts.next_tx(admin);
    let mut treasury_cap = test_scenario::take_from_sender<TreasuryCap<PICTOR_COIN>>(ts);
    pictor_coin::mint(&mut treasury_cap, amount, recipient, ts.ctx());
    test_scenario::return_to_sender<TreasuryCap<PICTOR_COIN>>(ts, treasury_cap);
}

fun deposit_pictor_coin(ts: &mut Scenario, user: address) {
    test_utils::print(concat(b"deposit coin from: ", user));
    ts.next_tx(user);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    let coin = test_scenario::take_from_sender<Coin<PICTOR_COIN>>(ts);

    pictor_network::deposit_coin<PICTOR_COIN>(&auth, &mut global, coin, ts.ctx());
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun withdraw_pictor_coin(ts: &mut Scenario, user: address, amount: u64) {
    test_utils::print(concat(b"withdraw coin from: ", user));
    ts.next_tx(user);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::withdraw_coin<PICTOR_COIN>(&auth, &mut global, amount, ts.ctx());
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun add_operator(ts: &mut Scenario, admin: address, operator: address) {
    test_utils::print(concat(b"add operator: ", operator));
    ts.next_tx(admin);
    let mut auth = test_scenario::take_shared<Auth>(ts);
    pictor_manage::add_operator(&mut auth, operator, ts.ctx());
    test_scenario::return_shared<Auth>(auth);
}

fun credit_user(ts: &mut Scenario, operator: address, user: address, amount: u64) {
    test_utils::print(b"operator should credit user");
    ts.next_tx(operator);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::op_credit_user(
        &auth,
        &mut global,
        user,
        amount,
        ts.ctx(),
    );
    let (balance, credit) = pictor_network::get_user_info(&global, user);
    assert!(balance == USER_MINT_AMOUNT && credit == amount);
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun debit_user(ts: &mut Scenario, operator: address, user: address, amount: u64): (u64, u64) {
    test_utils::print(b"operator should debit user");
    ts.next_tx(operator);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::op_debit_user(
        &auth,
        &mut global,
        user,
        amount,
        ts.ctx(),
    );
    let (balance, credit) = pictor_network::get_user_info(&global, user);
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
    (balance, credit)
}

fun register_worker(
    ts: &mut Scenario,
    operator: address,
    worker_owner: address,
    worker_id: String,
) {
    test_utils::print(b"register worker");
    ts.next_tx(operator);
    let auth = test_scenario::take_shared<Auth>(ts);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    pictor_network::op_register_worker(
        &auth,
        &mut global,
        worker_owner,
        worker_id,
        ts.ctx(),
    );

    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun create_job(ts: &mut Scenario, operator: address, user: address, job_id: String) {
    test_utils::print(b"operator should create job");
    ts.next_tx(operator);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::op_create_job(
        &auth,
        &mut global,
        user,
        job_id,
        ts.ctx(),
    );

    let (owner, task_count, payment, is_completed) = pictor_network::get_job_info(&global, job_id);
    assert!(owner == user && task_count == 0 && payment == 0 && !is_completed);
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun add_task(
    ts: &mut Scenario,
    operator: address,
    job_id: String,
    task_id: u64,
    worker_id: String,
) {
    test_utils::print(b"operator should add task");
    ts.next_tx(operator);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::op_add_task(
        &auth,
        &mut global,
        job_id,
        task_id,
        worker_id,
        WORKER_COST,
        WORKER_DURATION,
        ts.ctx(),
    );
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun complete_job(ts: &mut Scenario, operator: address, job_id: String) {
    test_utils::print(b"operator should complete job");
    ts.next_tx(operator);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::op_complete_job(&auth, &mut global, job_id, ts.ctx());
    let (_, _, _, is_completed) = pictor_network::get_job_info(&global, job_id);
    assert!(is_completed);
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun get_job_info_by_worker(
    ts: &mut Scenario,
    operator: address,
    job_id: String,
    worker_id: String,
): (u64, u64, bool) {
    ts.next_tx(operator);
    let global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    let (task_count, payment, is_completed) = pictor_network::get_job_info_by_worker(
        &auth,
        &global,
        job_id,
        worker_id,
    );
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
    (task_count, payment, is_completed)
}

fun get_user_info(ts: &mut Scenario, user: address): (u64, u64) {
    ts.next_tx(user);
    let global = test_scenario::take_shared<GlobalData>(ts);
    let (balance, credit) = pictor_network::get_user_info(&global, user);
    test_scenario::return_shared<GlobalData>(global);
    (balance, credit)
}

fun admin_withdraw_treasury(ts: &mut Scenario, admin: address, amount: u64) {
    test_utils::print(b"admin withdraw treasury");
    ts.next_tx(admin);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    let auth = test_scenario::take_shared<Auth>(ts);
    pictor_network::admin_withdraw_treasury<PICTOR_COIN>(&auth, &mut global, amount, ts.ctx());
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun get_treasury_value(ts: &Scenario): u64 {
    let global = test_scenario::take_shared<GlobalData>(ts);
    let treasury_value = pictor_network::get_treasury_value<PICTOR_COIN>(&global);
    test_scenario::return_shared<GlobalData>(global);
    treasury_value
}

fun concat(str: vector<u8>, user: address): vector<u8> {
    let mut result = vector::empty<u8>();
    vector::append(&mut result, str);
    vector::append(&mut result, *address::to_string(user).as_bytes());
    result
}
