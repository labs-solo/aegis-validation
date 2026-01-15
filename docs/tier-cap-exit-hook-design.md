# Tier-Cap Accounting With Refund/Elimination Awareness (CCA + Hook)

## Goals

- Enforce per-tier max “in-auction exposure” for whitelisted bidders.
- When a bid is outbid/eliminated, the *eliminated remainder* must stop counting toward the user’s tier cap.
- Keep this efficient: O(1) per bid submit/exit; avoid iterating over historical bids.

## Key Observation (CCA behavior)

- CCA does **not** update per-bid/per-owner state when a bid becomes outbid; it only **computes the eliminated remainder (“refund”) at exit time** inside
  `ContinuousClearingAuction._processExit`:
  - `refundWei = (bid.amountQ96 - currencySpentQ96) >> 96`.
- Therefore, the clean on-chain point to “stop counting eliminated amounts” is **when CCA computes `refundWei`**.

## Accounting Model (math)

Definitions:

- `amountWei`: bid amount in wei (what the bidder deposited for that bid).
- `currencySpentWei`: amount of currency actually spent to buy tokens (possibly 0 for fully eliminated).
- `refundWei`: `amountWei - currencySpentWei` (the eliminated/unspent remainder returned to bidder on exit).

We enforce tier cap against:

```
committedWei[owner] := Σ amountWei(submitted) - Σ refundWei(exited)
```

This equals `Σ currencySpentWei` across exited bids + `Σ amountWei` for not-yet-exited bids, which matches:

- Eliminated/unspent amounts stop counting once the user exits (and receives the refund).
- Actually-spent currency continues to count.

This satisfies: “eliminated amounts don’t count, so they can bid higher”.

## Required Contract Changes

### 1) Add an optional exit callback interface

Add a new interface in the CCA repo (or this project), e.g.:

```solidity
interface IBidExitHook {
    function onBidExit(uint256 bidId, address owner, uint256 refundWei) external;
}
```

Notes:

- Include `bidId` to support future extensions and safer bookkeeping (even if the current hook only needs `owner` + `refundWei`).
- `refundWei` (in wei) is the only value required to “release” tier capacity correctly.

### 2) Call the exit callback from CCA `_processExit`

In `ContinuousClearingAuction._processExit`, after `exitedBlock` is set and `refundWei` is computed, invoke the hook via a best-effort try/catch so that
misbehaving hooks cannot brick user exits:

Suggested ordering:

1. Write bid exit state (`tokensFilled`, `exitedBlock`).
2. `try IBidExitHook(address(VALIDATION_HOOK)).onBidExit(bidId, owner, refundWei) { } catch { }`
3. Transfer `refundWei` (if any).
4. Emit `BidExited`.

Rationale:

- If refund transfer triggers reentrancy (native currency), the bid is already marked as exited (prevents double-exit).
- Tier capacity is freed before the receiver’s fallback runs, enabling “exit then bid again” patterns.

### 3) Failure visibility (optional but recommended)

Because try/catch is best-effort, failures should be observable to avoid silent “over-counting” states:

- Add an event like:
  - `event BidExitHookCallFailed(uint256 bidId, address hook, bytes reason);`
- Emit it in the `catch (bytes memory reason)` path.

## Required Hook Changes (Aegis hook)

### Storage stays simple

Keep existing storage:

- `committed[owner]` (wei)
- `assignedTier[owner]`
- tier roots/caps/manual whitelist

### On bid validation (unchanged accounting)

In `validate(...)`:

- check whitelist/tier
- enforce cap using `nextCommitted = committed[owner] + amountWei`
- set `committed[owner] = nextCommitted`

### On bid exit callback (new)

Implement `onBidExit(bidId, owner, refundWei)`:

- Restrict caller:
  - `require(msg.sender == AUCTION_ADDRESS)` where `AUCTION_ADDRESS` is stored in the hook (immutable or configured once).
- Decrement:
  - `committed[owner] -= min(committed[owner], refundWei)`
- Do not modify `assignedTier` (tier remains stable for the auction).

Clamping instead of reverting avoids causing unexpected failures if the hook is ever desynchronized; it’s compatible with CCA’s best-effort calling pattern.

## Important Behavioral Clarification (aligned with CCA mechanics)

This design frees tier capacity when the bidder **exits** the eliminated/outbid bid, not automatically at the exact checkpoint where it becomes outbid.

If capacity must free immediately upon outbid *without requiring exit*, this requires a more invasive design (e.g., per-owner indexing plus an outbid-time hook, or a
user-supplied “release” mechanism with proofs/hints and robust double-count prevention).

## Testing Plan

- Hook unit test: `onBidExit` decrements `committed` correctly (including clamping behavior).
- Integration test: user bids up to cap, becomes outbid, exits, then can bid again up to cap because refunded amount no longer counts.
  - Likely uses `exitPartiallyFilledBid` with a valid `outbidBlock` hint to exit during an active auction.

## Follow-ups (not the focus of this doc)

- Manual whitelist should work without a root (move “zero root” check behind the manual whitelist bypass).
- Decide whether to enforce `owner == sender` (or validate `sender`) based on your definition of “participation”.

