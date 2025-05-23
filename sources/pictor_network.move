module pictor_network::pictor_network;

use sui::table::{Self, Table};

const EUserRegistered: u64 = 0;
const EUserNotRegistered: u64 = 1;
const EWorkerRegistered: u64 = 2;
const EWorkerNotRegistered: u64 = 3;
const EJobRegistered: u64 = 4;
const EJobNotRegistered: u64 = 5;

public struct AdminCap has key {
    id: UID,
}

public struct OperatorCap has key {
    id: UID,
}

public struct Config has key, store {
    id: UID,
    power_score_price: u64
}

public struct UserInfo has key, store {
    id: UID,
    balance: u64,
    credit: u64,
    locked: u64,
    pending: u64,
}

public struct Worker has store {
    owner: address,
    staked: u64,
    is_active: bool,
}

public struct Task has store {
    worker_id: vector<u8>,
    power_score: u64,
    duration: u64,
}

public struct Job has store {
    owner: address,
    tasks: Table<vector<u8>, Task>,
}

public struct GlobalData has key, store {
    id: UID,
    users: Table<address, UserInfo>,
    workers: Table<vector<u8>, Worker>,
    jobs: Table<vector<u8>, Job>,
}

fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap {
            id: object::new(ctx),
        },
        tx_context::sender(ctx),
    );
    let users = GlobalData {
        id: object::new(ctx),
        users: table::new<address, UserInfo>(ctx),
        workers: table::new<vector<u8>, Worker>(ctx),
        jobs: table::new<vector<u8>, Job>(ctx),
    };
    transfer::public_transfer(users, tx_context::sender(ctx));
}

public fun new_operator(_: &AdminCap, operator: address, ctx: &mut TxContext) {
    let operator_cap = OperatorCap {
        id: object::new(ctx),
    };
    transfer::transfer(operator_cap, operator);
}

public fun register_user(users: &mut GlobalData, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    assert!(!table::contains<address, UserInfo>(&users.users, sender), EUserRegistered);

    let balance = UserInfo {
        id: object::new(ctx),
        balance: 0,
        credit: 0,
        locked: 0,
        pending: 0,
    };

    table::add(&mut users.users, sender, balance);
}

public fun register_worker(_: &OperatorCap, global: &mut GlobalData, worker_owner: address, worker_id: vector<u8>, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    assert!(table::contains<address, UserInfo>(&global.users, sender), EUserNotRegistered);

    assert!(!table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerRegistered);

    let worker = Worker {
        owner: worker_owner,
        staked: 0,
        is_active: true,
    };

    table::add(&mut global.workers, worker_id, worker);
}

public fun add_job(_: &OperatorCap, global: &mut GlobalData, job_owner: address, job_id: vector<u8>, ctx: &mut TxContext) {

    assert!(table::contains<address, UserInfo>(&global.users, job_owner), EUserNotRegistered);

    assert!(!table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobRegistered);

    let job = Job {
        owner: job_owner,
        tasks: table::new<vector<u8>, Task>(ctx),
    };
    table::add(&mut global.jobs, job_id, job);
}

public fun add_task(_: &OperatorCap, global: &mut GlobalData, job_id: vector<u8>, task_id: vector<u8>, worker_id: vector<u8>, power_score: u64, duration: u64) {
    assert!(table::contains<vector<u8>, Job>(&global.jobs, job_id), EJobNotRegistered);
    assert!(table::contains<vector<u8>, Worker>(&global.workers, worker_id), EWorkerNotRegistered);

    let task = Task {
        worker_id: worker_id,
        power_score: power_score,
        duration: duration,
    };
    table::add(&mut global.jobs[job_id].tasks, task_id, task);
}
