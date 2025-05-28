#[allow(unused_use)]
module pictor_network::pictor_network;

use std::debug;
use sui::table::{Self, Table};

const EUserRegistered: u64 = 0;
const EUserNotRegistered: u64 = 1;
const EWorkerRegistered: u64 = 2;
const EWorkerNotRegistered: u64 = 3;
const EJobRegistered: u64 = 4;
const EJobNotRegistered: u64 = 5;
const EJobCompleted: u64 = 6;
const EInsufficentBalance: u64 = 7;

public struct AdminCap has key {
    id: UID,
}

public struct OperatorCap has key {
    id: UID,
}

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
    power_score: u64,
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
    power_score_price: u64,
}

fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap {
            id: object::new(ctx),
        },
        tx_context::sender(ctx),
    );
    let global = GlobalData {
        id: object::new(ctx),
        users: table::new<address, UserInfo>(ctx),
        workers: table::new<vector<u8>, Worker>(ctx),
        jobs: table::new<vector<u8>, Job>(ctx),
        power_score_price: 1,
    };
    transfer::share_object(global);
}

public fun new_operator(_: &AdminCap, operator: address, ctx: &mut TxContext) {
    let operator_cap = OperatorCap {
        id: object::new(ctx),
    };
    transfer::transfer(operator_cap, operator);
}

public fun register_user(global: &mut GlobalData, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    register_user_internal(global, sender);
}

public fun op_register_user(_: &OperatorCap, global: &mut GlobalData, user: address) {
    assert!(!table::contains<address, UserInfo>(&global.users, user), EUserRegistered);

    register_user_internal(global, user);
}

public fun op_register_worker(
    _: &OperatorCap,
    global: &mut GlobalData,
    worker_owner: address,
    worker_id: vector<u8>,
    _ctx: &mut TxContext,
) {
    assert!(table::contains<address, UserInfo>(&global.users, worker_owner), EUserNotRegistered);

    assert!(!table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerRegistered);

    let worker = Worker {
        owner: worker_owner,
        staked: 0,
        is_active: true,
    };

    table::add(&mut global.workers, worker_id, worker);
}

public fun op_create_job(
    _: &OperatorCap,
    global: &mut GlobalData,
    job_owner: address,
    job_id: vector<u8>,
    _ctx: &mut TxContext,
) {
    assert!(table::contains<address, UserInfo>(&global.users, job_owner), EUserNotRegistered);

    assert!(!table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobRegistered);

    let job = Job {
        owner: job_owner,
        tasks: vector::empty<Task>(),
        payment: 0,
        is_completed: false,
    };
    table::add(&mut global.jobs, job_id, job);
}

public fun op_add_task(
    _: &OperatorCap,
    global: &mut GlobalData,
    job_id: vector<u8>,
    task_id: u64,
    worker_id: vector<u8>,
    power_score: u64,
    duration: u64,
    _ctx: &mut TxContext,
) {
    assert!(table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobNotRegistered);
    assert!(table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerNotRegistered);

    let task = Task {
        task_id: task_id,
        worker_id: worker_id,
        power_score: power_score,
        duration: duration,
    };
    vector::push_back(
        &mut table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id).tasks,
        task,
    );

    //need to calculate balance of user & worker
    let payment = power_score * global.power_score_price * duration;
    let user_info = table::borrow_mut<address, UserInfo>(
        &mut global.users,
        global.jobs[job_id].owner,
    );
    assert!(user_info.credit + user_info.balance >= payment, EInsufficentBalance);

    // Deduct payment from user, credit first, then balance
    if (user_info.credit >= payment) {
        user_info.credit = user_info.credit - payment;
    } else {
        let remaining_payment = payment - user_info.credit;
        user_info.credit = 0;
        user_info.balance = user_info.balance - remaining_payment;
    };

    let job = table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id);
    job.payment = job.payment + payment;
}

public fun op_complete_job(_: &OperatorCap, global: &mut GlobalData, job_id: vector<u8>) {
    let job = table::borrow_mut<vector<u8>, Job>(&mut global.jobs, job_id);
    assert!(job.is_completed == false, EJobCompleted);
    job.is_completed = true;

    // loop through tasks and calculate worker payments for each worker's owner
    let mut i = vector::length(&global.jobs[job_id].tasks);
    while (i > 0) {
        i = i - 1;
        let task = &global.jobs[job_id].tasks[i];
        let worker = table::borrow_mut<vector<u8>, Worker>(&mut global.workers, task.worker_id);
        let payment = task.power_score * global.power_score_price * task.duration;

        // Add payment to worker's owner
        let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, worker.owner);
        user_info.balance = user_info.balance + payment;
    };
}

public fun op_credit_user(
    _: &OperatorCap,
    global: &mut GlobalData,
    user: address,
    amount: u64,
    _ctx: &mut TxContext,
) {
    assert!(table::contains<address, UserInfo>(&global.users, user), EUserNotRegistered);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, user);
    user_info.credit = user_info.credit + amount;
}

public fun get_user_info(global: &GlobalData, user: address): (u64, u64) {
    assert!(table::contains<address, UserInfo>(&global.users, user), EUserNotRegistered);
    let user_info = table::borrow<address, UserInfo>(&global.users, user);
    (user_info.balance, user_info.credit)
}

public fun get_job_info(global: &GlobalData, job_id: vector<u8>): (address, u64, u64, bool) {
    assert!(table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobNotRegistered);
    let job = table::borrow<vector<u8>, Job>(&global.jobs, job_id);
    (job.owner, vector::length<Task>(&job.tasks), job.payment, job.is_completed)
}

fun register_user_internal(global: &mut GlobalData, user: address) {
    assert!(!table::contains<address, UserInfo>(&global.users, user), EUserRegistered);

    let user_info = UserInfo {
        balance: 0,
        credit: 0,
    };

    table::add(&mut global.users, user, user_info);
}

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}
