module pictor_network::pictor_manage;

use sui::bag::{Self, Bag};

const EUnAuthorized: u64 = 0;
const ERecordExists: u64 = 1;
const ENoAuthRecord: u64 = 2;

public struct Auth has key {
    id: UID,
    roles: Bag, // Dynamic storage for role assignments.
    treasury_addr: address, // Address of the treasury cap for minting coins.
    is_paused: bool, // Global pause state for the network.
}

// Admin capability to create the vault
public struct AdminCap has drop, store {}

public struct OperatorCap has drop, store {}

/// Allows global pause and unpause of coin transactions.
public struct PauserCap has drop, store {}

/// Namespace for dynamic fields: one for each of the capabilities.
public struct RoleKey<phantom C> has copy, drop, store { owner: address }

fun init(ctx: &mut TxContext) {
    let owner = tx_context::sender(ctx);
    let mut auth = Auth {
        id: object::new(ctx),
        roles: bag::new(ctx),
        treasury_addr: owner,
        is_paused: false,
    };

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

public fun add_capability<C: store + drop>(
    auth: &mut Auth,
    owner: address,
    cap: C,
    ctx: &mut TxContext,
) {
    assert!(auth.has_cap<AdminCap>(tx_context::sender(ctx)), EUnAuthorized);
    assert!(!auth.has_cap<C>(owner), ERecordExists);
    auth.add_cap(owner, cap);
}

public fun remove_capability<C: store + drop>(
    auth: &mut Auth,
    owner: address,
    ctx: &mut TxContext,
) {
    assert!(auth.has_cap<AdminCap>(tx_context::sender(ctx)), EUnAuthorized);
    assert!(auth.has_cap<C>(owner), ENoAuthRecord);
    let _: C = auth.remove_cap(owner);
}

/// Check if a capability `Cap` is assigned to the `owner`.
public fun has_cap<Cap: store>(auth: &Auth, owner: address): bool {
    auth.roles.contains(RoleKey<Cap> { owner })
}

public fun add_operator(auth: &mut Auth, owner: address, ctx: &mut TxContext) {
    add_capability<OperatorCap>(
        auth,
        owner,
        OperatorCap {},
        ctx,
    );
}

public fun remove_operator(auth: &mut Auth, operator: address, ctx: &mut TxContext) {
    remove_capability<OperatorCap>(auth, operator, ctx);
}

public fun is_admin(auth: &Auth, owner: address): bool {
    has_cap<AdminCap>(auth, owner)
}

public fun is_operator(auth: &Auth, owner: address): bool {
    has_cap<OperatorCap>(auth, owner)
}

public fun get_treasury_address(auth: &Auth): address {
    auth.treasury_addr
}

public fun set_treasury_address(auth: &mut Auth, new_addr: address, ctx: &mut TxContext) {
    assert!(auth.has_cap<AdminCap>(tx_context::sender(ctx)), EUnAuthorized);
    auth.treasury_addr = new_addr;
}

public fun get_paused_status(auth: &Auth): bool {
    auth.is_paused
}

public entry fun set_pause_status(auth: &mut Auth, is_paused: bool, ctx: &mut TxContext) {
    assert!(is_admin(auth, tx_context::sender(ctx)), EUnAuthorized);
    auth.is_paused = is_paused;
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

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}
