# Architecture: How 7 EAs Coordinate Through GlobalVariables

## The core fact to understand first

**These 7 MT5 programs never call each other's functions.** MT5 doesn't support that between
separate EAs. They coordinate ONLY through **GlobalVariables** -- a simple terminal-wide
key-value store (string key -> double value) that any EA on the same terminal can read and
write. All the gate logic described below is built on top of this single primitive:
`GlobalVariableSet(name, value)` / `GlobalVariableGet(name)`.

`BossafxGuardGate.mqh` is the shared header both the Guard EA and all 5 trading EAs `#include`.
It defines the GlobalVariable name constants and wraps the read/write logic into named functions
so every EA calls the same functions and agrees on the same contract -- but there is NO
compile-time enforcement that every EA actually calls them correctly. Trust the GlobalVariable
names and the actual call sites in each `.mq5`, not just the header's doc comments.

## The 7 programs

| Program | File | Role | Magic(s) |
|---|---|---|---|
| Guard | `EA_G_PortfolioGuard_MultiEA.mq5` | Watches the fleet, publishes gate state, can flatten | 61998 |
| bot1 v2.0 | `bot1_regime2.0.mq5` | Trading EA | 54321-54327 |
| bot1 v2.1 | `bot1_regime2.1.mq5` | Trading EA | 54510, 54511 |
| bot1 v2.2 | `bot1_regime2.2.mq5` | Trading EA | 220001, 220201, 220202 |
| bot4 v1.49 | `bot4_TREND_FX_v1_49.mq5` | Trading EA | 40001 |
| test4 v52 | `test4_clean_HYBRID_v52.mq5` | Trading EA | 54340 |

Each trading EA runs as a separate chart/instance per magic-config it manages (e.g. bot1 v2.0 has
up to 6 separate chart instances, one per magic, each with its own `.set` file -- see
`VALIDATED_LIVE_CONFIGS/`). All of them trade GOLD on the same account.

## The gates, in the order they run

Every trading EA calls these checks, in roughly this order, right before it would otherwise send
an order. All of them **fail OPEN** (i.e. allow the trade) if Guard isn't running or the
GlobalVariable hasn't been set yet -- this is a deliberate safety choice documented in the header
(a trading EA should never get permanently stuck because Guard crashed), but it also means a
silent Guard failure is invisible unless you check Guard's own logs.

### 1. `GGate_ShouldOpen()` -- 1-per-bar PF-priority entry gate
Guard ranks every protected magic once per bar by priority and publishes an ordered list via
`BOSSAFX_GuardPriority_0..N` GlobalVariables (count in `BOSSAFX_GuardPriority_Count`). A trading
EA calls `GGate_ShouldOpen(magic)` before opening; it looks itself up in that list and only the
HIGHEST-ranked magic that actually has a signal this bar is allowed through. Purpose: stop every
magic piling into the same bar's signal redundantly. **Known live bug (fixed 2026-10-15):** the
published-list size cap was smaller than the actual magic pool for a period, silently excluding
some magics from ever being found in the list (which fails OPEN, i.e. made the gate permanently
inert for them) -- see `GUARD_FEATURES.md` for the fix and which magics were affected.

### 2. `GGate_PriceDistanceOk()` -- re-entry price-distance gate
Guard publishes the fleet's last entry price every tick; a trading EA checks its candidate entry
is at least `MinReentryDistancePoints` away before opening. Meant to stop pile-ups at nearly the
same price level.

### 3. `GGate_LossCooldownOk()` -- per-direction loss cooldown
After ANY protected magic closes a losing trade, Guard starts a cooldown; trading EAs check this
before opening a NEW position in the SAME direction. Meant to stop "revenge trading" right after
a loss in that direction.

### 4. `GGate_FleetOpenCooldownOk()` / `GGate_StampFleetOpen()` -- same-instant pile-on gate
The newest gate (2026-10-14). Problem it solves: gates 1-3 above all read a snapshot Guard
refreshes once per TICK -- if 2+ EAs evaluate the same price bar within the same second (normal,
since every EA ticks independently off the same feed), they can all read "all clear" before
Guard's next tick updates anything, and all open together. Fix: the trading EA that actually
opens a position stamps a shared "an open just happened" timestamp DIRECTLY (not routed through
Guard's tick), and every EA (including itself) checks this stamp before its next attempt. This is
a short shared cooldown window (currently 10 seconds, fleet-wide -- not just within correlated
pairs), not a queue: whoever gets there first still opens immediately, everyone else waits out
the window.

## The flattens (Guard-initiated, not gates)

Unlike the gates above (which only block NEW entries), these can actively CLOSE existing
positions. All controlled by their own `Use...` boolean input on the Guard's `.set` file:

- **Hard-floor flatten** -- equity below an absolute $ floor -> flatten everything.
- **Daily-floor flatten** -- today's losses exceed a daily $ limit -> flatten everything.
- **Profit-target flatten** (`UseProfitTargetFlatten` / `ProfitTargetUsd`) -- fleet floating
  profit crosses a target -> lock it in by flattening. Currently OFF (logging-only) in production.
- **Basket-SL flatten** (`UseBasketSLGuard` / `BasketSLMaxLossUsd`) -- one direction's combined
  floating loss across ALL protected magics crosses a threshold -> flatten just that direction's
  basket.
- **Friday backstop** -- de-risk ahead of the weekend close.

See `GUARD_FEATURES.md` for the full feature-by-feature state and known issues.

## Where to look for bugs

1. **GlobalVariable name/contract mismatches** between `BossafxGuardGate.mqh`'s definitions and
   each `.mq5`'s actual call sites -- a gate is only as good as every EA correctly reading the
   SAME variable the Guard writes.
2. **Fail-open paths** -- anywhere a gate's "I don't know, so allow it" default could mask a real
   failure. Search for `fail-open` / `fail open` in comments for ones already flagged.
3. **Array/constant size mismatches** -- `GGATE_MAX_PRIORITY_SLOTS` vs. the actual number of
   magics in `g_gateMagics[]` is a confirmed real bug class (see 2026-10-15 fix comment in
   `BossafxGuardGate.mqh`); check for similar off-by-constant issues elsewhere.
3. **Closure-reason tagging gap** -- `GGate_BuildCloseComment()` tags opens correctly but closes
   never carry the tag in live deal history (confirmed via direct Deals-sheet inspection). Trace
   every close-side `OrderSend`/`trade.PositionClose()` call in all 6 trading EAs + the Guard's
   flatten code to find where the tag is being dropped.
4. **Magic-range discipline** -- the project maintains per-EA magic-number ranges in source
   comments (see each `.mq5`'s `input` block). Production magics should only come from the
   documented range for that EA; a magic outside its EA's declared range is a red flag.
