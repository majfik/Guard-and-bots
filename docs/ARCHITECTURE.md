# Architecture

Six programs coordinate only through MT5 GlobalVariables. They do not call each other. This page matches the current source. The name-by-name contract, units, and ownership are in [GLOBALVARIABLE_CONTRACT.md](GLOBALVARIABLE_CONTRACT.md). Feature flags versus the historical and V2 sets are in [GUARD_FEATURES.md](GUARD_FEATURES.md).

Nothing here is a profitability claim. Static checks have passed. MetaEditor compilation of this source has been run: all six experts, 0 errors and 0 warnings (`tests/compile_all.ps1`). That compile is not deployment readiness. MT5 runtime and Strategy Tester tests have not been run. The V2 candidate is `BLOCKED_PENDING_RUNTIME_CONFIRMATION` because bot4 `DonchianExitPeriod=1`.

## Components

| Program | Source | Role |
| --- | --- | --- |
| Guard | [EA_G_PortfolioGuard_MultiEA.mq5](../Experts/EA_G_PortfolioGuard_MultiEA.mq5) | Publishes brakes, may flatten. Does not open trades. `MagicGuard` default 61998. |
| bot1 regime 2.0 | [bot1_regime2.0.mq5](../Experts/bot1_regime2.0.mq5) | Trading EA. One chart instance per `.set`. |
| bot1 regime 2.1 | [bot1_regime2.1.mq5](../Experts/bot1_regime2.1.mq5) | Trading EA. |
| bot1 regime 2.2 | [bot1_regime2.2.mq5](../Experts/bot1_regime2.2.mq5) | Trading EA. |
| bot4 v1.49 | [bot4_TREND_FX_v1_49.mq5](../Experts/bot4_TREND_FX_v1_49.mq5) | Trading EA. |
| test4 v52 | [test4_clean_HYBRID_v52.mq5](../Experts/test4_clean_HYBRID_v52.mq5) | Trading EA. |
| Shared gate | [BossafxGuardGate.mqh](../Include/BossafxGuardGate.mqh) | Names, reader, close sender, filling resolver, stage check, hedging check. |
| Shared close helper | [PortfolioGuard.mqh](../Include/PortfolioGuard.mqh) | `PgCloseMagic` / `PgCancelPendings`. Included by the Guard. |

`#define PG_MAGIC_T 60001` in `PortfolioGuard.mqh` is an unused header constant. It is not `MagicBot4_v50`, it is not added to either pool, and no `.set` in this repo deploys it.

## Magic pools

Membership is the `MegAddActiveMagic` list in Guard `OnInit`, not a fixed array. `MegAddActiveMagic` adds the same magic to both `g_protectedMagics` and `g_gateMagics`. `MegPoolAdd` rejects a non-positive magic and a duplicate. `OnInit` then requires both pools to be non-empty, the same size, unique, and free of `MagicGuard`.

Current order and defaults:

| Input | Magic | Both pools |
| --- | --- | --- |
| `MagicSwingM5` | 54321 | yes |
| `MagicSwingM15` | 54322 | yes |
| `MagicScalp1x1` | 54323 | yes |
| `MagicScalp3x1` | 54324 | yes |
| `MagicR21A` | 54510 | yes |
| `MagicR21B` | 54511 | yes |
| `MagicBot4_v49` | 40001 | yes |
| `MagicTest4_v52` | 54340 | yes |
| `MagicR22Pass6060` | 220001 | yes |
| `MagicWinrate1250` | 54325 | yes |
| `MagicWinrate3257` | 54327 | yes |
| `MagicWinrate667` | 54326 | yes |
| `MagicR22CDHV2098` | 220202 | yes |
| `MagicR22CDHV7794` | 220201 | yes |

`MagicGuard` (61998) is in neither pool. 54322 and 40001 are in both pools. There is no priority-slot cap: `GGate_RankAndPublish` writes the full ranked array. A published count outside `1..64` (`GGATE_PRIORITY_COUNT_SANITY_MAX`) is treated as corrupt and fail-opens.

The gate pool is what Guard ranks and what basket-SL walks. The protected pool is what hard-floor, daily-floor, and profit-target flattens close. This deployment puts every active trading magic in both. The two arrays stay separate so a later build can split them.

## Symbol-scoped heartbeat and publish sequence

Liveness is not `BOSSAFX_GuardBarGate_BarTime`. That key is only the priority-list publish stamp. Production `GateTimeframe` is M30, so that stamp is old for most of the bar on purpose.

Guard owns, per symbol:

- `BOSSAFX_GuardHeartbeat_<symbol>` — `TimeCurrent()` in seconds, written only from `GGate_PublishEnd`.
- `BOSSAFX_GuardPubSeq_<symbol>` — integer stored in a double. Odd means a publication is in progress. Even and greater than zero means the last publication finished.

`Publish()` calls `GGate_PublishBegin` (force the sequence odd), writes the `MEG_<symbol>_*` snapshot, then `GGate_PublishEnd` (force the sequence even, then write the heartbeat). A fresh heartbeat means a completed snapshot for this symbol.

The unsuffixed names are legacy. The first publication copies an unsuffixed value into the symbol key only when the symbol key is absent. It never overwrites a key this symbol already has.

Priority keys, signal keys, distance keys, and the fleet-open keys are terminal-wide, not symbol-scoped. Two symbols on one terminal still share those. Heartbeat, publish sequence, and `MEG_<symbol>_*` do not.

## Coherent reader

`GGate_ReadEntryBlock` accepts a snapshot only when all of the following hold:

1. `BOSSAFX_GuardPubSeq_<symbol>` exists, is greater than zero, and is even.
2. The symbol heartbeat exists and `TimeCurrent() - heartbeat <= staleSeconds` (callers pass 400).
3. Both `MEG_<symbol>_BLOCK_NEW` and `MEG_<symbol>_VETO` exist. They are read together. `FLAT_REQ` is not read.
4. The publish sequence is read again and is the same even value.
5. The heartbeat is still fresh.

`GGate_GuardEntryAllowed` tries that read once more if the first attempt fails. Then:

- Still incoherent and the heartbeat is stale: allow the order, reason `FAIL_OPEN_STALE_HEARTBEAT`.
- Still incoherent for any other reason: allow the order, reason `FAIL_OPEN_TORN_OR_MISSING`.
- Coherent and `BLOCK_NEW < 0.5`: allow, reason `ALLOWED`.
- Coherent and `BLOCK_NEW >= 0.5`: refuse. The log reason is the published `VETO` code (`HARD_FLOOR`, `DAILY_FLOOR`, `LOSS_COOLDOWN`, `GAP_BLOCK`, `FRIDAY`, `PROFIT_TARGET`). If the veto value is `0` while `BLOCK_NEW` is set, the reason is `BLOCK_NEW`.

`GGate_EntryBlocked` is that check plus one log line, `[GGATE-BLOCK] MN:<magic> <where> skipped -- Guard BLOCK_NEW veto=<n> reason=<text>`. It returns true when the order must not be sent.

## Fail-open policy

A missing, stale, odd, or torn Guard snapshot does not block a new entry. That is deliberate: a dead Guard must not freeze the fleet. It also means a silent Guard failure looks like "no brake".

Successful Guard `OnInit` is the narrow exception. It does not publish `MEG_VETO_OK`. It publishes veto `107` (`STARTUP`), `BLOCK_NEW` 1, and `FLAT_REQ` 0, with an even sequence and a fresh heartbeat. The first `OnTick` replaces that with `ComputeVeto` and `ComputeFlattenReason`. While that startup snapshot is coherent and fresh, new entries are blocked. After the heartbeat goes stale, or if `OnInit` never published, the trading EAs fail open again.

The same fail-open applies to `GGate_ShouldOpen`, `GGate_PriceDistanceOk`, `GGate_LossCooldownOk`, and `GGate_FleetOpenCooldownOk` when their enable flag or snapshot is missing, the feature is published off, or the heartbeat is stale. `GGate_ShouldOpen` also fail-opens when this magic is absent from the published ranking.

Fail-open does not apply to `OnInit`. A non-hedging account, an illegal staged-exit pair, a negative `LossCooldownMinNetLossUsd`, or an illegal bot4 `DonchianExitPeriod` while `UseDonchianExit` is true returns `INIT_FAILED`.

Trading EAs do not read `FLAT_REQ`. Flattening is Guard's own close loop, not an entry-side request.

## Entry gates

On each trading EA the checks that sit in front of a new order are:

1. `GGate_ShouldOpen(magic)` when `UseGuardBarGate` is true. The call publishes `BOSSAFX_GuardSignal_<magic>` for the current M5 bar, then allows the order unless a strictly higher-ranked magic has also signaled that same M5 bar.
2. `GGate_PriceDistanceOk()` — last fleet entry price versus `MinReentryDistancePoints`, only when Guard has published the distance gate enabled.
3. `GGate_LossCooldownOk(direction)` — directional `MEG_<symbol>_LOSS_COOLDOWN_UNTIL_BUY` or `_SELL`, only when `UseLossCooldownGate` is published on.
4. `GGate_FleetOpenCooldownOk()` — seconds since `BOSSAFX_GuardFleetOpenGate_LastOpenTime`, only when `UseFleetOpenCooldownGate` is published on.
5. `GGate_EntryBlocked` — the coherent `BLOCK_NEW` read. This one is not behind `UseGuardBarGate`.

After a successful open, the trading EA calls `GGate_StampFleetOpen()`, which writes the fleet-open timestamp itself. Guard only publishes the enable flag and the seconds.

`BLOCK_NEW` is the blanket brake. Every non-OK veto sets it, including startup, loss cooldown, gap, Friday, hard floor, daily floor, and profit target. `UseLossCooldown` decides whether the cooldown veto is computed. `UseLossCooldownGate` is only the directional consumer. It does not narrow `BLOCK_NEW`.

## Entry paths

The static test counts every `PositionOpen`, `Buy`, and `Sell` and requires `GGate_EntryBlocked` earlier in that function. Current counts:

| EA | Entry sends | `GGate_EntryBlocked` path name |
| --- | --- | --- |
| `bot1_regime2.0.mq5` | 4 | `trend` (`MagicNumber`) and `countertrend` (`Bot1CounterTrendMagic`) |
| `bot1_regime2.1.mq5` | 4 | `trend` and `countertrend` |
| `bot1_regime2.2.mq5` | 4 | `trend` and `countertrend` |
| `bot4_TREND_FX_v1_49.mq5` | 2 | `pyramid` and `basket` |
| `test4_clean_HYBRID_v52.mq5` | 2 | `hybrid` |

Each bot1 count is the trend buy, trend sell, counter-trend buy, and counter-trend sell. test4 is the hybrid buy and hybrid sell. bot4 is the pyramid add and the basket entry.

## Flatten trigger precedence and latches

`ComputeVeto` is the status code written to `VETO` and mirrored into `BLOCK_NEW`. It does not decide whether a close is sent. Order, first match wins:

1. Equity at or below the hard floor, even if `UseFlattenOnHardFloor` is false.
2. Equity at or below the daily floor, even if `UseFlattenOnDailyFloor` is false.
3. Profit-target latch active, or (`UseProfitTargetFlatten` and fleet floating P&L of protected positions has reached `ProfitTargetUsd`).
4. Blanket loss cooldown (`LOSS_COOLDOWN_UNTIL` still in the future and `UseLossCooldown`).
5. Gap block.
6. Friday backstop (`UseFridayBackstop`, Friday, hour at or after `FridayBackstopHour`).
7. `MEG_VETO_OK` (0).

`ComputeFlattenReason` is the close path. Only enabled triggers count, in this order: hard floor, daily floor, then profit target. An active profit latch keeps returning `MEG_VETO_PROFIT_TARGET` after floating P&L falls back under the target, until the snapshotted legs are closed or the latch hits `MEG_PT_LATCH_MAX_SEC` (3600 seconds). A disabled hard or daily floor falls through; it must not stamp `HARD_FLOOR` or `DAILY_FLOOR` onto a profit flatten.

`FLAT_REQ` is 1 only when `ComputeFlattenReason` is not OK. Trading EAs ignore it.

Basket SL is not a veto code. `UpdateBasketSL` sums floating P&L by direction across `g_gateMagics`. When `UseBasketSLGuard` is true and a direction's loss reaches `BasketSLMaxLossUsd`, Guard closes that direction with reason `BSK`. Schedule brakes (cooldown, gap, Friday) never flatten.

Hard-floor and daily-floor closes use reason `GRD` through `PgCloseMagic` on `g_protectedMagics`, and pending orders for those magics are cancelled. Profit-target closes go through the latch and attribute `PROFIT_TARGET` only for the episode that is active when the latch starts. A floor reason that is no longer true is cleared while protected positions remain, so later closes are not kept on a stale floor label.

## Hedging-only requirement

`GGate_RequireHedgingAccount` requires `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`. On any other mode it prints `[GGATE] INIT FAILED: hedging account required` and the caller returns `INIT_FAILED`. That call is the first check in `OnInit` of the Guard and all five trading EAs. Netting and exchange accounts are not supported. The close and basket logic assumes multiple positions per symbol can exist.

## Close outcome state machine

`GGate_CloseVolumeCore` returns one of:

| Code | Name | Meaning |
| --- | --- | --- |
| 0 | `GGATE_CLOSE_NONE` | Nothing executed and nothing working. The same amount may be retried. |
| 1 | `GGATE_CLOSE_PARTIAL` | This call filled some of the request (`outFilled > 0`). The rest did not. |
| 2 | `GGATE_CLOSE_FULL` | This call filled the whole request. |
| 3 | `GGATE_CLOSE_PENDING` | A close order is working on the server. Do not send another. |

`outFilled` is only the volume executed by this result. A partial-close plan stores the unfilled remainder and will not recompute a fresh percentage of the leftover position. Stage advances only when the plan for that stage completes.

The pending registry is one slot per position (`g_ggPendPos` and the parallel arrays). A full-close caller resolves a partial slot, so the TTL cancel still runs. While that order is working the full caller returns `PENDING` and does not report the old partial fill as its own deal. TP1 and TP2 partial callers do not resolve each other's slots. After `GGATE_PENDING_CLOSE_TTL_SEC` (30 seconds) the working order is cancelled once. The slot stays until the order is in history, or is confirmed gone after the cancel, so a retry cannot overlap the first order.

`TRADE_RETCODE_TIMEOUT` and `TRADE_RETCODE_CONNECTION` do not take the emergency `CTrade` fallback. The close records an in-memory uncertain slot and returns `PENDING`. The next call checks live volume, a working close order, and out-deals. It retries only after `GGATE_UNCERTAIN_RETRY_SEC` (30 seconds) with the volume unchanged and no live close order. A definite reject is still allowed to use the fallback.

Market-deal filling comes from `GGate_MarketDealFilling`. `SYMBOL_FILLING_*` values are bit flags. `ORDER_FILLING_*` values are enum constants and are not used as bits. Request and instant execution use FOK. Market execution uses FOK if flagged, otherwise IOC if flagged, and never `ORDER_FILLING_RETURN`. Exchange execution uses FOK, else IOC, else RETURN. If no legal mode exists the function returns false and the caller must not guess. Close paths do not hardcode `ORDER_FILLING_IOC`.

## Restart limitations

These live only in the EA process and are empty after a reload or terminal restart:

- The pending-close registry and the ambiguous-close observe slot. A close order that is still working at the broker can be joined by a second close the new process sends. An unresolved `TIMEOUT` is not remembered across a reload.
- The profit-target latch and its snapshotted legs.
- The in-memory loss-cooldown queue. `OnTradeTransaction` does not replay deals that happened while Guard was down.
- Fleet episode MFE/MAE state.

These survive EA reload because `GlobalVariableSet` has no TTL of its own. They last until deleted or the terminal store is cleared:

- Heartbeat, publish sequence, `MEG_<symbol>_*`, priority list, signals, distance snapshot, fleet-open stamp.
- `MEG_CDMARK_*` position-id marks (128 slots per account login). A marked position is not armed again. An unmarked close that happened while Guard was stopped is not discovered on startup.

test4 stores each position's stage in `T4STG_<login>_<symbol>_<position identifier>`. `OnInit` restores it, and a completed TP1 or TP2 does not run again after a reload. The key is deleted only after history confirms the position is fully closed. Deal comments containing `|TP1` or `|TP2` are a fallback when the key is absent; broker storage of those comments is still unverified.

A successful Guard `OnInit` publishes `STARTUP` with `BLOCK_NEW` 1 before the first tick computes real state. If that heartbeat later goes stale, or Guard never published, entry gates fail open.

## Deal-reason attribution

Close requests are commented with `GGate_BuildCloseComment`: `<magic>|<reason>` plus an optional tail, cut to 31 characters. The magic and the reason code are not the part that is cut. Reason codes include `TP1`, `TP2`, `SL`, `TSL`, `GRD`, `FCT`, `MAN`, and basket `BSK`.

The static tests check that trading closes go through the tagged helpers and that bot1 regime 2.2 has no direct `PositionClose`. They do not read a live deal history. Whether the broker copies that comment onto the closing deal is unverified. Older deals exported before this wiring are not evidence that current closes are tagged.

Guard's close helper saves and restores the trade object's magic. A flatten must not leave `MagicGuard` stuck on `g_trade` for a later send.
