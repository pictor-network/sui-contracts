#[test_only]
#[allow(unused_use)]
module pictor_network::pictor_network_tests;

use pictor_network::pictor_manage::{Self, Auth, is_operator};
use pictor_network::pictor_coin::{Self, PICTOR_COIN};
use pictor_network::pictor_network::{Self, GlobalData};
use std::debug;
use std::unit_test::assert_eq;
use sui::address::{Self, to_string};
use sui::balance;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::test_scenario::{Self, ctx, Scenario};
use sui::test_utils;

const USER_CREDIT: u64 = 10000000;
const USER_MINT_AMOUNT: u64 = 1_000_000_000;
const WORKER_POWER: u64 = 100;
const WORKER_DURATION: u64 = 1000;

#[test]
fun test_pictor_network() {
    let admin = @0xAD;
    let user = @0xC0FFEE;
    let operator = @0xBEEF;
    let worker_owner = @0xDEADBEEF;
    let mut ts = test_scenario::begin(admin);

    test_init(&mut ts, admin);
    mint_coin(&mut ts, admin, user, USER_MINT_AMOUNT);
    add_operator(&mut ts, admin, operator);
    deposit_pictor_coin(&mut ts, user);
    credit_user(&mut ts, operator, user, USER_CREDIT);

    // Register worker owner
    register_user(&mut ts, worker_owner);

    // Register worker
    register_worker(&mut ts, operator, worker_owner, b"worker1");

    // operator should create job
    create_job(&mut ts, operator, user, b"job1");

    // operator should add task
    add_task(&mut ts, operator, b"job1", 1, b"worker1");

    complete_job(&mut ts, operator, b"job1");

    ts.next_tx(admin);
    let global = test_scenario::take_shared<GlobalData>(&ts);
    let power_score_price = pictor_network::get_power_score_price(&global);
    let (_, user_credit) = pictor_network::get_user_info(
        &global,
        user,
    );

    let payment = WORKER_POWER * WORKER_DURATION * power_score_price;

    assert!(user_credit == USER_CREDIT - payment);

    let (worker_balance, _) = pictor_network::get_user_info(
        &global,
        worker_owner,
    );

    assert!(worker_balance == pictor_network::calculate_payment_for_worker(payment));

    test_scenario::return_shared<GlobalData>(global);

    withdraw_pictor_coin(&mut ts, worker_owner, worker_balance);

    ts.end();
}

fun test_init(ts: &mut Scenario, admin: address) {
    test_utils::print(b"init");
    pictor_manage::test_init(ts.ctx());
    pictor_network::test_init(ts.ctx());
    pictor_coin::test_init(ts.ctx());
    ts.next_tx(admin);
    assert!(test_scenario::has_most_recent_shared<GlobalData>());
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
    let coin = test_scenario::take_from_sender<Coin<PICTOR_COIN>>(ts);

    pictor_network::deposit_pictor_coin(&mut global, coin, ts.ctx());
    test_scenario::return_shared<GlobalData>(global);
}

fun withdraw_pictor_coin(ts: &mut Scenario, user: address, amount: u64) {
    test_utils::print(concat(b"withdraw coin from: ", user));
    ts.next_tx(user);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    pictor_network::withdraw_pictor_coin(&mut global, amount, ts.ctx());
    test_scenario::return_shared<GlobalData>(global);
}

fun add_operator(ts: &mut Scenario, admin: address, operator: address) {
    test_utils::print(concat(b"add operator: ", operator));
    ts.next_tx(admin);
    let mut auth = test_scenario::take_shared<Auth>(ts);
    pictor_manage::add_operator(&mut auth, operator, ts.ctx());
    test_scenario::return_shared<Auth>(auth);
}

fun register_user(ts: &mut Scenario, user: address) {
    test_utils::print(concat(b"register user: ", user));
    ts.next_tx(user);
    let mut global = test_scenario::take_shared<GlobalData>(ts);
    pictor_network::register_user(&mut global, ts.ctx());
    let (balance, credit) = pictor_network::get_user_info(&global, user);
    assert!(balance == 0 && credit == 0);
    test_scenario::return_shared<GlobalData>(global);
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

fun register_worker(
    ts: &mut Scenario,
    operator: address,
    worker_owner: address,
    worker_id: vector<u8>,
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

fun create_job(ts: &mut Scenario, operator: address, user: address, job_id: vector<u8>) {
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
    job_id: vector<u8>,
    task_id: u64,
    worker_id: vector<u8>,
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
        WORKER_POWER,
        WORKER_DURATION,
        ts.ctx(),
    );
    test_scenario::return_shared<GlobalData>(global);
    test_scenario::return_shared<Auth>(auth);
}

fun complete_job(ts: &mut Scenario, operator: address, job_id: vector<u8>) {
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

fun concat(str: vector<u8>, user: address): vector<u8> {
    let mut result = vector::empty<u8>();
    vector::append(&mut result, str);
    vector::append(&mut result, *address::to_string(user).as_bytes());
    result
}
