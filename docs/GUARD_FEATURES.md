# Guard Features: What Each One Does, Current State, Known Issues

Source of truth for current ON/OFF state: `VALIDATED_LIVE_CONFIGS/EA_G_PortfolioGuard_MultiEA_PRODUCTION_20261013.set`.
Read that file directly for exact current values -- this doc explains WHAT each feature does and
WHY it's built that way; the `.set` file is the live truth of what's actually enabled right now.

## Protected magics vs. gate-priority-pool magics (important distinction)

Two separate lists exist in `EA_G_PortfolioGuard_MultiEA.mq5`:
- **`g_gateMagics[]`** -- every magic that participates in the 1-per-bar PF-priority entry gate.
- **`g_protectedMagics[]`** -- every magic covered by basket-SL / profit-target / hard/daily-floor
  FLATTEN protection.

These lists are NOT identical. As of the last review, `MagicSwingM15` (54322) and `MagicBot4_v49`
(40001) are in the gate pool but NOT in the protected-flatten list -- meaning they participate in
entry-gating but get no flatten protection. This might be intentional (a deliberate "let this one
run independently of the flatten safety net") or might be an oversight; flagged for review, not
resolved.

## Fleet-wide brakes (block ALL new entries fleet-wide while active)

### LOSS_COOLDOWN
`UseLossCooldown` / `LossCooldownMinutes` (currently 120). After ANY protected magic closes a
losing trade, blocks new entries fleet-wide for this many minutes. Published-only via
GlobalVariable (`GGate_LossCooldownOk()`) -- see `ARCHITECTURE.md` gate #3.
**Real observed cost** (from a multi-day log analysis): fired 47 times across a ~9-day window,
totaling ~1,639 minutes of fleet-wide no-new-trades time (avg 35 min/episode, longest single
episode ~218 min). This is the cost side to weigh against whatever losses it prevents --
not inherently good or bad, just the real number to reason about.

### DAILY_FLOOR
Daily soft-loss limit, tighter than the FTMO account's real daily limit by design (`DailySoftLossPct`,
currently 3.5%, vs. FTMO's real 5%). Blocks new entries once today's losses hit this %.
Observed: fired 34 times, but very briefly each time (avg 0.3 min/episode) -- consistent with a
threshold that's crossed and then the day resets quickly, or trades recovering fast.

### PROFIT_TARGET (see also the flatten below -- same underlying threshold, two different consumers)
Blocks new entries once fleet floating profit crosses `ProfitTargetUsd`. Observed: fired 13 times,
totaling ~929 min (avg 71.5 min/episode, longest ~307 min).

### FRIDAY backstop
`UseFridayBackstop`. De-risks ahead of the weekend close -- a portfolio-wide backstop in case any
single EA's own weekend-handling were ever misconfigured. Fired once in the observed window,
spanning the full weekend (~2621 min), as expected.

### Gap block
`UseGapBlock` / `GapDetectHours` / `GapBlockHours`. Treats a tick gap of >= `GapDetectHours` as a
weekend/feed-outage gap and blocks new entries for `GapBlockHours` after ticks resume --
incidentally also catches multi-hour feed outages, not just weekends (documented as "a reasonable
bonus, not a bug" in the source comment).

## Flattens (actively close positions, not just block new ones)

### Hard-floor flatten
Equity below an absolute $ floor (derived from `FtmoInitialBalance` / `FtmoMaxLossPct` /
`HardFloorBufferUsd`) -> flatten everything. The buffer exists specifically so slippage on the
CLOSING trade itself can't push equity through the real FTMO breach line.

### Profit-target flatten
`UseProfitTargetFlatten` / `ProfitTargetUsd` (currently $750 in the verify/analysis runs, check
the live `.set` for the actual production value). **Currently OFF in production** -- logging-only.
Real historical data shows 1 finished episode that crossed $750 and then gave back an average of
~$1,879 before the trades actually closed, since nothing was there to lock the profit in. Lowering
the target fires more often (14x at $250 vs 1x at $750 in the observed window) at the cost of
capping upside earlier.

### Basket-SL flatten
`UseBasketSLGuard` / `BasketSLMaxLossUsd` (currently $1,200 in the live config). Sums floating P&L
separately for all same-direction (BUY vs SELL) open positions across every protected magic,
fleet-wide; flattens just that direction's basket if the combined loss crosses the threshold.
Real data: at $1,200, 1 crossing episode observed, averaging only ~$541 past the threshold before
it ended on its own -- a relatively well-placed trigger (not obviously too loose).
**Important when testing different threshold values:** lower thresholds trip on a smaller losing
move, so they tend to show FEWER distinct episodes (a single big losing stretch counts as one
episode across its whole decline) while HIGHER thresholds can show MORE distinct episodes if
price oscillates back and forth across that specific level during a volatile stretch. Don't judge
"better protection" by raw fire-count alone -- look at the total $ amount capped at each level.

## Entry gates (see `ARCHITECTURE.md` for the full mechanics)

1. **1-per-bar PF-priority gate** (`GGate_ShouldOpen`) -- **had a real live bug**, fixed
   2026-10-15: `GGATE_MAX_PRIORITY_SLOTS` was smaller than the actual number of gate-pool magics,
   silently truncating the published priority list every bar. `MagicBot4_v49`, `MagicR22Pass6060`,
   and `MagicWinrate3257` never appeared in the published list for an extended period, meaning
   their 1-per-bar gate was permanently fail-open (i.e. completely inert, they always got the
   "allowed" default) the whole time. Confirmed via direct log inspection (`priority_order=` lines
   only ever printed 10 magics, every bar, before the fix). Fixed by correcting the constant to
   match the real pool size (13). **Worth re-verifying this fix is correct and the constant will
   stay in sync if the magic pool grows again** -- it's a manual constant, not derived from the
   array size automatically, which is itself a latent recurrence risk.

2. **Price-distance gate** (`GGate_PriceDistanceOk`) -- `UsePriceDistanceGate` /
   `MinReentryDistancePoints`. Blocks a new entry too close in price to the fleet's last entry.

3. **Loss-cooldown ENFORCEMENT gate** (`GGate_LossCooldownOk`) -- distinct from the fleet-wide
   LOSS_COOLDOWN brake described above; this is a per-direction enforcement that actual trading
   EAs check before opening. `UseLossCooldownGate`.

4. **Fleet-wide same-instant pile-on gate** (`GGate_FleetOpenCooldownOk` /
   `GGate_StampFleetOpen`) -- newest gate (2026-10-14), `UseFleetOpenCooldownGate` /
   `FleetOpenCooldownSeconds` (currently 10 seconds, fleet-wide). Built specifically to stop
   same-second multi-magic pile-ons (confirmed live: 16 separate clusters of 2-6 different magics
   opening at the exact same minute+price despite the price-distance gate being ON, because that
   gate's snapshot only refreshes once per Guard tick -- too slow to catch simultaneous opens
   across EAs ticking independently off the same feed). **Verify this is actually suppressing the
   same-second clusters after being enabled** -- it was built in direct response to a confirmed
   bug, not yet long-term field-verified at export time.

## Closure-reason tagging (data-quality issue, not a trading-risk issue)

`GGate_BuildCloseComment()` is supposed to tag every close with WHY it closed (EA's own TP/SL
logic vs. Guard's flatten) so the resulting trade history can be attributed. **Confirmed broken
at export time**: the OPEN side tags correctly on every trade, but the CLOSE side writes nothing
useful on ANY magic, including trades closed the same day as the check -- verified by reading the
raw MT5 Deals export directly, not inferred. This means there is currently no way to tell from
trade history alone whether a losing trade was the EA's own strategy failing or Guard cutting it
short. Needs a full trace of every close-side `OrderSend`/`PositionClose()` call across all 6
trading EAs and the Guard's own flatten code to find where the tag gets dropped.
