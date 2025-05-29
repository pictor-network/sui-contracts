module pictor_network::pictor_coin;

use sui::coin::{Self, Coin, TreasuryCap};

/// Name of the coin. By convention, this type has the same name as its parent module
/// and has no fields. The full type of the coin defined by this module will be `COIN<MANAGED>`.
public struct PICTOR_COIN has drop {}

/// Register the managed currency to acquire its `TreasuryCap`. Because
/// this is a module initializer, it ensures the currency only gets
/// registered once.
fun init(witness: PICTOR_COIN, ctx: &mut TxContext) {
    // Get a treasury cap for the coin and give it to the transaction sender
    let (treasury_cap, metadata) = coin::create_currency<PICTOR_COIN>(
        witness,
        9,
        b"PICTOR",
        b"PIC",
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury_cap, tx_context::sender(ctx))
}

/// Manager can mint new coins
public fun mint(
    treasury_cap: &mut TreasuryCap<PICTOR_COIN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    coin::mint_and_transfer(treasury_cap, amount, recipient, ctx)
}

/// Manager can burn coins
public fun burn(treasury_cap: &mut TreasuryCap<PICTOR_COIN>, coin: Coin<PICTOR_COIN>) {
    coin::burn(treasury_cap, coin);
}

#[test_only]
/// Wrapper of module initializer for testing
public fun test_init(ctx: &mut TxContext) {
    init(PICTOR_COIN {}, ctx)
}