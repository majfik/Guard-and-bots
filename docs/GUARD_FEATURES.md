# Guard features

Current behavior is the source plus the set that is actually loaded. Two set directories exist:

- [VALIDATED_LIVE_CONFIGS](../VALIDATED_LIVE_CONFIGS) is the historical baseline. It is pinned by [historical_baseline_sha256.json](../tests/historical_baseline_sha256.json). Do not edit it. It is not a deployment instruction for this source tree.
- [VALIDATED_LIVE_CONFIGS_V2](../VALIDATED_LIVE_CONFIGS_V2) is a candidate. Bundle status is `BLOCKED_PENDING_RUNTIME_CONFIRMATION` because bot4 `DonchianExitPeriod=1`. A clean MetaEditor compile does not clear that block. It is not deployed and not economically validated. See [CONFIGURATION_MATRIX.md](CONFIGURATION_MATRIX.md).

Source defaults are not the historical values. In particular, profit-target flatten is on in both the historical Guard set and the V2 Guard set, and the cooldown length in both sets is 360 minutes, not the source default of 120.

No number in an old source comment is a profitability claim for this tree.

## Classifications

| Class | Meaning here |
| --- | --- |
| active | The named flag is true in the historical Guard set and in the V2 Guard set, or the code path runs on every entry. |
| risk-reducing | The mechanism can block or close. That is not evidence it improves results. |
| unproven | A candidate change whose economic effect has not been revalidated. |
| blocked | Must not be deployed. bot4 `DonchianExitPeriod=1`, and therefore the whole V2 bundle. |
| disabled | The flag exists and is false in both Guard sets, or the magic was removed from the deployment. |

## Guard set: historical versus V2

File: `EA_G_PortfolioGuard_MultiEA_PRODUCTION_20261013.set`.

| Input | Source default | Historical set | V2 candidate |
| --- | --- | --- | --- |
| `FtmoInitialBalance` | 10000 | 100000 | 100000 |
| `UseLossCooldown` | true | true | true |
| `LossCooldownMinutes` | 120 | 360 | 360 |
| `LossCooldownMinNetLossUsd` | 5.0 | omitted; new source uses 5.0 | 5.0, written explicitly |
| `LossCooldownArmOnBasketSL` | true | omitted; new source uses true | true, written explicitly |
| `UseProfitTargetFlatten` | false | true | true |
| `ProfitTargetUsd` | 1000 | 1000 | 1000 |
| `UseBasketSLGuard` | false | true | true |
| `BasketSLMaxLossUsd` | 1000 | 1200 | 1200 |
| `UseFlattenOnHardFloor` | false | false | false |
| `UseFlattenOnDailyFloor` | false | false | false |
| `UseGapBlock` | true | true | true |
| `GapDetectHours` / `GapBlockHours` | 6 / 2 | 6 / 2 | 6 / 2 |
| `UseFridayBackstop` | true | true | true |
| `FridayBackstopHour` | 16 | 20 | 20 |
| `GateTimeframe` | source default is M5 | 30 (`PERIOD_M30`) | 30 (`PERIOD_M30`) |
| `UsePriceDistanceGate` | false | true | true |
| `MinReentryDistancePoints` | 150 | 300 | 300 |
| `UseLossCooldownGate` | false | true | true |
| `UseFleetOpenCooldownGate` | false | true | true |
| `FleetOpenCooldownSeconds` | 10 | 10 | 10 |
| `MagicTest4_v52` | 54340 | input absent | 54340 |
| `MagicBot4_v50` | removed from this source | 60001 | removed |

V2 also drops obsolete `MagicBot4_v50`. Loading the historical Guard set onto this source ignores that removed input and takes `MagicTest4_v52=54340` from the source default. The V2 set writes that membership explicitly. Both files are `PENDING_REVALIDATION` because this source is not the build those files were baselined on. The Guard file itself is not the Donchian blocker. The bundle is blocked because bot4 is.

## Pools

Both pools, historical intent and current source, are the 14 magics in [ARCHITECTURE.md](ARCHITECTURE.md). 54322, 40001, and 54340 are in the gate pool and the protected flatten pool. 61998 is in neither. 60001 is not a pool member.

The old statement that 54322 and 40001 are gate-only is stale.

## BLOCK_NEW

Class: active, risk-reducing, unproven as a performance change.

Every entry path in all five trading EAs calls `GGate_EntryBlocked` before `PositionOpen`, `Buy`, or `Sell`. A coherent fresh `MEG_<symbol>_BLOCK_NEW >= 0.5` refuses the order and logs the veto. Missing, stale, or torn state fail-opens. Guard `OnInit` publishes veto `107` (`STARTUP`) with `BLOCK_NEW` 1 until the first tick computes real state. That startup block is fail-closed only while the snapshot is fresh. `FLAT_REQ` is not an input to that decision.

test4 magic 54340 takes TP1 once and TP2 once per ticket. That replaces repeated per-tick partials. No set threshold changed. The stage is stored in `T4STG_<login>_<symbol>_<position identifier>` and restored after a reload, so a completed stage does not re-fire. This is a material executable change and is mandatory revalidation. It is not a profitability result.

`BLOCK_NEW` is 1 for every non-OK `ComputeVeto` result. That includes the blanket loss cooldown. It also includes hard-floor and daily-floor breaches even when the matching flatten flag is false: the account can be blocked from new entries without Guard closing positions.

## Blanket cooldown versus directional cooldown

These are different mechanisms.

Blanket, class active. `UseLossCooldown=true` and `LossCooldownMinutes=360` in both sets. After a protected position is fully closed, Guard computes lifecycle net (profit + swap + commission of every deal on that position id). It arms only when that net is strictly below `-LossCooldownMinNetLossUsd` (5.0 USD in the source and in V2). A commission-only scratch at or above `-5` does not arm. The arm writes `MEG_<symbol>_LOSS_COOLDOWN_UNTIL` and the direction key, and `ComputeVeto` publishes `LOSS_COOLDOWN`, which sets `BLOCK_NEW` for the whole fleet until that datetime. One position id is marked once in `MEG_CDMARK_*` so it cannot arm twice. `LossCooldownArmOnBasketSL=true` means a basket-SL full close may arm. Exact basket close orders are exempt only when that flag is false.

Directional gate, class active in both sets (`UseLossCooldownGate=true`). `GGate_LossCooldownOk` reads only `LOSS_COOLDOWN_UNTIL_BUY` or `_SELL` for the candidate direction, and only when Guard has published the enable flag. It does not clear or narrow `BLOCK_NEW`.

The source default of 120 minutes is not the historical value and not the V2 value.

## Profit, basket, hard floor, daily floor

Profit target, class active and risk-reducing. Both sets set `UseProfitTargetFlatten=true` and `ProfitTargetUsd=1000`. When protected floating P&L reaches 1000 with at least one protected position open, Guard latches and closes those legs, and `BLOCK_NEW` stays up while the latch is active. The latch expires after 3600 seconds if legs remain. This is not "off" and it is not a measured improvement.

Basket SL, class active and risk-reducing. Both sets set `UseBasketSLGuard=true` and `BasketSLMaxLossUsd=1200`. One direction across the gate-pool magics is closed with reason `BSK`. The other direction is left. This does not publish a `MEG_VETO_*` code. It can arm the loss cooldown when the lifecycle net qualifies.

Hard floor, flatten disabled, veto still possible. `UseFlattenOnHardFloor=false` in both sets, so Guard does not close on the hard floor. `ComputeVeto` still returns `HARD_FLOOR` when equity is at or below `HardFloorLevel()`: `FtmoInitialBalance - FtmoInitialBalance * (FtmoMaxLossPct/100) + HardFloorBufferUsd`. Both sets use 100000, 10 percent, and a 50 USD buffer, which is the level 90050. New entries can still be blocked. Positions are not flattened by this flag while it is false.

Daily floor, same split. `UseFlattenOnDailyFloor=false`. `DailySoftLossPct=3.5`. The veto can still set `BLOCK_NEW`. The daily reset depends on `ServerToCetOffsetHours`, which the source marks as broker-specific. Neither set is evidence that offset is correct for a given broker.

Gap block and Friday backstop, class active brakes. They set `BLOCK_NEW`. They do not flatten. Friday hour in both sets is 20. Gap detect/block in both sets is 6 hours then 2 hours.

## Other entry gates

| Gate | Both sets | Class |
| --- | --- | --- |
| 1-per-bar priority (`GGate_ShouldOpen`) | EA default `UseGuardBarGate=true`; Guard ranks the gate pool | active, risk-reducing, unproven |
| Price distance | enabled, 300 points (source default 150) | active, risk-reducing, unproven |
| Fleet-open stamp | enabled, 10 seconds, fleet-wide | active, risk-reducing, unproven |

Priority ranking uses live history inside Guard. A magic missing from the published list fail-opens. That is not a license to treat an unranked magic as vetted.

## Candidate classifications that are not "active"

| Item | Class | Why |
| --- | --- | --- |
| V2 bundle | blocked | `DonchianExitPeriod=1` with `UseDonchianExit=true` is not a legal bot4 period (8, 10, 14). |
| V2 bot4 file | blocked | Value kept at 1 so `OnInit` fails closed. |
| Every V2 `.set` | unproven | Source behavior changed. `PENDING_REVALIDATION`. |
| 54325, 54326, 220202 distance edits | unproven | Semantic repairs. Mandatory combined A/B. Not economically validated. |
| 54510 and 54511 BOM cleanup | unproven | Potential lot-sizing change until live deal volumes show `LotType=1` was loaded. Mandatory revalidation. |
| `MagicBot4_v50` / 60001 | disabled | Not in this source's inputs and not in either pool. |

## What this page does not say

It does not say the fleet is profitable, that a profit factor in a file comment still holds, or that a gate which blocks entries is a net benefit. It does not say the V2 candidate is safe to attach. Deployment automation must use `python tests/check_config_sets.py --require-deployable`, which fails while the Donchian blocker exists.
