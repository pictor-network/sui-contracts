#[allow(unused_use)]
module pictor_network::pictor_network;

use pictor_network::pictor_coin::{Self, PICTOR_COIN};
use pictor_network::pictor_manage::{Self, Auth, is_operator};
use std::debug;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::pay;
use sui::table::{Self, Table};

const DENOMINATOR: u64 = 10000;
const WORKER_EARNING_PERCENTAGE: u64 = 80;

const ESystemPaused: u64 = 0;
const EUserNotRegistered: u64 = 1;
const EWorkerRegistered: u64 = 2;
const EWorkerNotRegistered: u64 = 3;
const EJobRegistered: u64 = 4;
const EJobNotRegistered: u64 = 5;
const EJobCompleted: u64 = 6;
const EInsufficentBalance: u64 = 7;

public struct UserInfo has store {
    balance: u64,
    credit: u64,
}

public struct Worker has store {
    owner: address,
    staked: u64,
    is_active: bool,
}

public struct Task has store {
    task_id: u64,
    worker_id: vector<u8>,
    cost: u64,
    duration: u64,
}

public struct Job has store {
    owner: address,
    tasks: vector<Task>,
    payment: u64,
    is_completed: bool,
}

public struct GlobalData has key, store {
    id: UID,
    users: Table<address, UserInfo>,
    workers: Table<vector<u8>, Worker>,
    jobs: Table<vector<u8>, Job>,
    vault: Balance<PICTOR_COIN>,
    is_paused: bool,
}

fun init(ctx: &mut TxContext) {
    let global = GlobalData {
        id: object::new(ctx),
        users: table::new<address, UserInfo>(ctx),
        workers: table::new<vector<u8>, Worker>(ctx),
        jobs: table::new<vector<u8>, Job>(ctx),
        vault: balance::zero<PICTOR_COIN>(),
        is_paused: false,
    };
    transfer::share_object(global);
}

public entry fun deposit_pictor_coin(
    global: &mut GlobalData,
    coin: Coin<PICTOR_COIN>,
    ctx: &mut TxContext,
) {
    check_not_paused(global);
    let sender = tx_context::sender(ctx);
    register_user_internal(global, sender);
    let amount = coin::value<PICTOR_COIN>(&coin);
    assert!(amount > 0, EInsufficentBalance);
    let deposited_balance = coin::into_balance(coin);
    balance::join(&mut global.vault, deposited_balance);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, sender);
    user_info.balance = user_info.balance + amount;
}

#[lint_allow(self_transfer)]
public entry fun withdraw_pictor_coin(global: &mut GlobalData, amount: u64, ctx: &mut TxContext) {
    check_not_paused(global);
    let sender = tx_context::sender(ctx);
    assert!(table::contains<address, UserInfo>(&global.users, sender), EUserNotRegistered);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, sender);
    assert!(user_info.balance >= amount, EInsufficentBalance);

    user_info.balance = user_info.balance - amount;
    let withdrawn_balance = balance::split(&mut global.vault, amount);
    let coin = coin::from_balance<PICTOR_COIN>(withdrawn_balance, ctx);
    transfer::public_transfer(coin, sender);
}

public entry fun register_user(global: &mut GlobalData, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    register_user_internal(global, sender);
}

public entry fun op_register_user(
    auth: &Auth,
    global: &mut GlobalData,
    user: address,
    ctx: &mut TxContext,
) {
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    register_user_internal(global, user);
}

public entry fun op_register_worker(
    auth: &Auth,
    global: &mut GlobalData,
    worker_owner: address,
    worker_id: vector<u8>,
    ctx: &mut TxContext,
) {
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    register_user_internal(global, worker_owner);

    assert!(!table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerRegistered);

    let worker = Worker {
        owner: worker_owner,
        staked: 0,
        is_active: true,
    };

    table::add(&mut global.workers, worker_id, worker);
}

public entry fun op_create_job(
    auth: &Auth,
    global: &mut GlobalData,
    job_owner: address,
    job_id: vector<u8>,
    ctx: &mut TxContext,
) {
    check_not_paused(global);
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    register_user_internal(global, job_owner);

    assert!(!table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobRegistered);

    let job = Job {
        owner: job_owner,
        tasks: vector::empty<Task>(),
        payment: 0,
        is_completed: false,
    };
    table::add(&mut global.jobs, job_id, job);
}

public entry fun op_add_task(
    auth: &Auth,
    global: &mut GlobalData,
    job_id: vector<u8>,
    task_id: u64,
    worker_id: vector<u8>,
    cost: u64,
    duration: u64,
    ctx: &mut TxContext,
) {
    check_not_paused(global);
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    assert!(table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobNotRegistered);
    assert!(table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerNotRegistered);

    let task = Task {
        task_id,
        worker_id,
        cost,
        duration,
    };
    vector::push_back(
        &mut table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id).tasks,
        task,
    );

    //need to calculate balance of user & worker
    let user_info = table::borrow_mut<address, UserInfo>(
        &mut global.users,
        global.jobs[job_id].owner,
    );
    assert!(user_info.credit + user_info.balance >= cost, EInsufficentBalance);

    // Deduct payment from user, credit first, then balance
    if (user_info.credit >= cost) {
        user_info.credit = user_info.credit - cost;
    } else {
        let remaining_payment = cost - user_info.credit;
        user_info.credit = 0;
        user_info.balance = user_info.balance - remaining_payment;
    };

    let job = table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id);
    job.payment = job.payment + cost;
}

public entry fun op_complete_job(
    auth: &Auth,
    global: &mut GlobalData,
    job_id: vector<u8>,
    ctx: &mut TxContext,
) {
    check_not_paused(global);
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    let job = table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id);
    assert!(job.is_completed == false, EJobCompleted);
    job.is_completed = true;

    // loop through tasks and calculate worker payments for each worker's owner
    let mut i = vector::length(&global.jobs[job_id].tasks);
    while (i > 0) {
        i = i - 1;
        let task = &global.jobs[job_id].tasks[i];
        let worker = table::borrow_mut<vector<u8>, Worker>(&mut global.workers, task.worker_id);

        // Add payment to worker's owner
        let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, worker.owner);
        user_info.balance = user_info.balance + calculate_worker_payment(task.cost );
    };
}

public entry fun op_credit_user(
    auth: &Auth,
    global: &mut GlobalData,
    user: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    check_not_paused(global);
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    register_user_internal(global, user);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, user);
    user_info.credit = user_info.credit + amount;
}

public entry fun admin_set_pause_status(
    auth: &Auth,
    global: &mut GlobalData,
    is_paused: bool,
    ctx: &mut TxContext,
) {
    pictor_manage::is_admin(auth, tx_context::sender(ctx));
    global.is_paused = is_paused;
}

public fun get_user_info(global: &GlobalData, user: address): (u64, u64) {
    if (table::contains<address, UserInfo>(&global.users, user)) {
        let user_info = table::borrow<address, UserInfo>(&global.users, user);
        (user_info.balance, user_info.credit)
    } else {
        (0, 0)
    }
}

public fun get_job_info(global: &GlobalData, job_id: vector<u8>): (address, u64, u64, bool) {
    assert!(table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobNotRegistered);
    let job = table::borrow<vector<u8>, Job>(&global.jobs, job_id);
    (job.owner, vector::length<Task>(&job.tasks), job.payment, job.is_completed)
}

public fun calculate_worker_payment(payment: u64): u64 {
    payment * WORKER_EARNING_PERCENTAGE / DENOMINATOR
}

fun check_not_paused(global: &GlobalData) {
    assert!(!global.is_paused, ESystemPaused);
}

fun register_user_internal(global: &mut GlobalData, user: address) {
    if (!table::contains<address, UserInfo>(&global.users, user)) {
        let user_info = UserInfo {
            balance: 0,
            credit: 0,
        };
        table::add(&mut global.users, user, user_info);
    }
}

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}
