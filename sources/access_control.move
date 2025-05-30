module pictor_network::access_control;

use sui::bag::{Self, Bag};

const ERecordExists: u64 = 0x1;
const ENoAuthRecord: u64 = 0x2;
const EUnAuthorized: u64 = 0x3;

public struct Auth has key {
    id: UID,
    is_paused: bool,
    roles: Bag, // Dynamic storage for role assignments.
}

// Admin capability to create the vault
public struct AdminCap has drop, store {}

public struct OperatorCap has drop, store {}

/// Allows global pause and unpause of coin transactions.
public struct PauserCap has drop, store {}

/// Namespace for dynamic fields: one for each of the capabilities.
public struct RoleKey<phantom C> has copy, drop, store { owner: address }

fun init(ctx: &mut TxContext) {
    let mut auth = Auth {
        id: object::new(ctx),
        is_paused: false,
        roles: bag::new(ctx),
    };

    let owner = tx_context::sender(ctx);

    auth
        .roles
        .add(
            RoleKey<AdminCap> { owner },
            AdminCap {},
        );
    auth
        .roles
        .add(
            RoleKey<OperatorCap> { owner },
            OperatorCap {},
        );
    transfer::share_object(auth);
}

public fun add_capability<C: store + drop>(auth: &mut Auth, owner: address, cap: C) {
    assert!(auth.has_cap<AdminCap>(owner), EUnAuthorized);
    assert!(!auth.has_cap<C>(owner), ERecordExists);
    auth.add_cap(owner, cap);
}

public fun remove_capability<C: store + drop>(auth: &mut Auth, owner: address) {
    assert!(auth.has_cap<AdminCap>(owner), EUnAuthorized);
    assert!(auth.has_cap<C>(owner), ENoAuthRecord);
    let _: C = auth.remove_cap(owner);
}

/// Check if a capability `Cap` is assigned to the `owner`.
public fun has_cap<Cap: store>(auth: &Auth, owner: address): bool {
    auth.roles.contains(RoleKey<Cap> { owner })
}

public fun add_operator(auth: &mut Auth, owner: address) {
    add_capability<OperatorCap>(
        auth,
        owner,
        OperatorCap {},
    );
}

public fun remove_operator(auth: &mut Auth, operator: address) {
    remove_capability<OperatorCap>(auth, operator);
}

public fun is_admin(auth: &Auth, owner: address): bool {
    has_cap<AdminCap>(auth, owner)
}

public fun is_operator(auth: &Auth, owner: address): bool {
    has_cap<OperatorCap>(auth, owner)
}

// === Private functions ===

/// Adds a capability `cap` for `owner`.
fun add_cap<Cap: store + drop>(auth: &mut Auth, owner: address, cap: Cap) {
    auth.roles.add(RoleKey<Cap> { owner }, cap)
}

/// Remove a `Cap` from the `owner`.
fun remove_cap<Cap: store + drop>(auth: &mut Auth, owner: address): Cap {
    auth.roles.remove(RoleKey<Cap> { owner })
}
