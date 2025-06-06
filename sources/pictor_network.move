#[allow(unused_use)]
module pictor_network::pictor_network;

use pictor_network::pictor_manage::{Self, Auth, is_operator, add_cap};
use std::ascii::{Self, String};
use std::debug;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::pay;
use sui::table::{Self, Table};

const ESystemPaused: u64 = 0;
const EUnAuthorized: u64 = 1;
const EUserNotRegistered: u64 = 2;
const EWorkerRegistered: u64 = 3;
const EWorkerNotRegistered: u64 = 4;
const EJobRegistered: u64 = 5;
const EJobNotRegistered: u64 = 6;
const EJobCompleted: u64 = 7;
const EInsufficentBalance: u64 = 8;
const ERecordExists: u64 = 9;

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
    worker_id: String,
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
    workers: Table<String, Worker>,
    jobs: Table<String, Job>,
    vault: Bag,
}

public struct CoinKey<phantom C> has copy, drop, store {}

fun init(ctx: &mut TxContext) {
    let global = GlobalData {
        id: object::new(ctx),
        users: table::new<address, UserInfo>(ctx),
        workers: table::new<String, Worker>(ctx),
        jobs: table::new<String, Job>(ctx),
        vault: bag::new(ctx),
    };
    transfer::share_object(global);
}

public fun set_coin_type<CoinType>(auth: &Auth, global: &mut GlobalData, ctx: &mut TxContext) {
    assert!(pictor_manage::is_admin(auth, tx_context::sender(ctx)), EUnAuthorized);
    assert!(!global.vault.contains(CoinKey<CoinType> {}), ERecordExists);
    global.vault.add(CoinKey<CoinType> {}, balance::zero<CoinType>());
}

public entry fun deposit_coin<CoinType>(
    auth: &Auth,
    global: &mut GlobalData,
    coin: Coin<CoinType>,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    let sender = tx_context::sender(ctx);
    register_user_internal(global, sender);
    let amount = coin::value<CoinType>(&coin);
    assert!(amount > 0, EInsufficentBalance);
    let deposited_balance = coin::into_balance(coin);
    balance::join(global.vault.borrow_mut(CoinKey<CoinType> {}), deposited_balance);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, sender);
    user_info.balance = user_info.balance + amount;
}

#[lint_allow(self_transfer)]
public entry fun withdraw_coin<CoinType>(
    auth: &Auth,
    global: &mut GlobalData,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    let sender = tx_context::sender(ctx);
    assert!(table::contains<address, UserInfo>(&global.users, sender), EUserNotRegistered);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, sender);
    assert!(user_info.balance >= amount, EInsufficentBalance);

    user_info.balance = user_info.balance - amount;
    let withdrawn_balance = balance::split(global.vault.borrow_mut(CoinKey<CoinType> {}), amount);
    let coin = coin::from_balance<CoinType>(withdrawn_balance, ctx);
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
    worker_id: String,
    ctx: &mut TxContext,
) {
    pictor_manage::is_operator(auth, tx_context::sender(ctx));
    register_user_internal(global, worker_owner);

    assert!(!table::contains<String, Worker>(&global.workers, worker_id), EWorkerRegistered);

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
    job_id: String,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    assert!(pictor_manage::is_operator(auth, tx_context::sender(ctx)), EUnAuthorized);
    register_user_internal(global, job_owner);

    assert!(!table::contains<String, Job>(&global.jobs, job_id), EJobRegistered);

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
    job_id: String,
    task_id: u64,
    worker_id: String,
    cost: u64,
    duration: u64,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    assert!(pictor_manage::is_operator(auth, tx_context::sender(ctx)), EUnAuthorized);
    assert!(table::contains<String, Job>(&global.jobs, job_id), EJobNotRegistered);
    assert!(table::contains<String, Worker>(&global.workers, worker_id), EWorkerNotRegistered);

    let task = Task {
        task_id,
        worker_id,
        cost,
        duration,
    };
    vector::push_back(
        &mut table::borrow_mut<String, Job>(&mut global.jobs, job_id).tasks,
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

    let job = table::borrow_mut<String, Job>(&mut global.jobs, job_id);
    job.payment = job.payment + cost;
}

public entry fun op_complete_job(
    auth: &Auth,
    global: &mut GlobalData,
    job_id: String,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    assert!(pictor_manage::is_operator(auth, tx_context::sender(ctx)), EUnAuthorized);
    let job = table::borrow_mut<String, Job>(&mut global.jobs, job_id);
    assert!(job.is_completed == false, EJobCompleted);
    job.is_completed = true;

    // loop through tasks and calculate worker payments for each worker's owner
    let mut i = vector::length(&global.jobs[job_id].tasks);
    while (i > 0) {
        i = i - 1;
        let task = &global.jobs[job_id].tasks[i];
        let worker = table::borrow_mut<String, Worker>(&mut global.workers, task.worker_id);

        // Add payment to worker's owner
        let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, worker.owner);
        user_info.balance =
            user_info.balance + pictor_manage::calculate_worker_payment(auth, task.cost );
    };
}

public entry fun op_credit_user(
    auth: &Auth,
    global: &mut GlobalData,
    user: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(!pictor_manage::get_paused_status(auth), ESystemPaused);
    assert!(pictor_manage::is_operator(auth, tx_context::sender(ctx)), EUnAuthorized);
    register_user_internal(global, user);
    let user_info = table::borrow_mut<address, UserInfo>(&mut global.users, user);
    user_info.credit = user_info.credit + amount;
}

public entry fun admin_withdraw_treasury<CoinType>(
    auth: &Auth,
    global: &mut GlobalData,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(pictor_manage::is_admin(auth, tx_context::sender(ctx)), EUnAuthorized);
    let vault = bag::borrow_mut<CoinKey<CoinType>, Balance<CoinType>>(
        &mut global.vault,
        CoinKey<CoinType> {},
    );
    assert!(balance::value(vault) >= amount, EInsufficentBalance);

    let withdrawn_balance = balance::split(vault, amount);
    let coin = coin::from_balance<CoinType>(withdrawn_balance, ctx);
    transfer::public_transfer(coin, pictor_manage::get_treasury_address(auth));
}

public fun get_user_info(global: &GlobalData, user: address): (u64, u64) {
    if (table::contains<address, UserInfo>(&global.users, user)) {
        let user_info = table::borrow<address, UserInfo>(&global.users, user);
        (user_info.balance, user_info.credit)
    } else {
        (0, 0)
    }
}

public fun get_job_info(global: &GlobalData, job_id: String): (address, u64, u64, bool) {
    assert!(table::contains<String, Job>(&global.jobs, job_id), EJobNotRegistered);
    let job = table::borrow<String, Job>(&global.jobs, job_id);
    (job.owner, vector::length<Task>(&job.tasks), job.payment, job.is_completed)
}

public fun get_treasury_value<CoinType>(global: &GlobalData): u64 {
    let vault = bag::borrow<CoinKey<CoinType>, Balance<CoinType>>(
        &global.vault,
        CoinKey<CoinType> {},
    );
    balance::value(vault)
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
