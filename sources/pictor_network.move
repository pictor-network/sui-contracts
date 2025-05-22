module pictor_network::pictor_network;

use std::string;
use std::u64;
use sui::object::{Self, UID};
use sui::table::{Self, Table};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

const EUserRegistered: u64 = 0;

public struct UsdBalance has key, store {
    id: UID,
    balance: u64,
    credit: u64,
    locked: u64,
    pending: u64,
}

public struct Worker has key, store {
    id: UID,
    staked: u64,
    is_active: bool,
}

public struct Users has key, store {
    id: UID,
    users_balance: Table<address, UsdBalance>,
    
}

fun init(ctx: &mut TxContext) {
    let users = Users {
        id: object::new(ctx),
        users_balance: table::new<address, UsdBalance>(ctx),
    };
    transfer::public_transfer(users, tx_context::sender(ctx));
}

public fun register_user(users: &mut Users, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    assert!(!table::contains<address, UsdBalance>(&users.users_balance, sender), EUserRegistered);

    let balance = UsdBalance {
        id: object::new(ctx),
        balance: 0,
        credit: 0,
        locked: 0,
        pending: 0,
    };

    table::add(&mut users.users_balance, sender, balance);
}
