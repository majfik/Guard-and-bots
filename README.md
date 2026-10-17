# BOSSAFX Gold fleet and Portfolio Guard

This tree is the current source for six MT5 programs: five trading EAs and one Guard, plus the shared headers they include. They coordinate only through terminal GlobalVariables. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing a gate or a close path.

`VALIDATED_LIVE_CONFIGS/` is the historical baseline. It is pinned, and it must stay byte-identical. It is not the candidate to attach, and it is not evidence that this source is profitable. The candidate copies live in `VALIDATED_LIVE_CONFIGS_V2/`. That bundle is **not deployed**. Its status is `BLOCKED_PENDING_RUNTIME_CONFIRMATION`.

## Source requirements

- MT5 retail hedging account. `GGate_RequireHedgingAccount` returns `INIT_FAILED` on any other margin mode. Netting and exchange accounts are unsupported.
- One Guard chart per symbol. Heartbeat and publish sequence are `BOSSAFX_GuardHeartbeat_<symbol>` and `BOSSAFX_GuardPubSeq_<symbol>`. Priority, distance, and fleet-open keys are terminal-wide.
- The Guard chart's symbol must be the symbol the trading EAs trade. `MEG_<symbol>_*` keys do not cross symbols.
- `GateTimeframe=30` in the historical and V2 Guard sets is `PERIOD_M30`. Do not "correct" it to M5 because the source default is M5.
- `ServerToCetOffsetHours` must match the broker before the daily floor is trusted. The source default is 0.
- MetaEditor compiles this tree through [tests/compile_all.ps1](tests/compile_all.ps1). That script builds an isolated include tree and does not write into the terminal installation. The recorded result on this source is 0 errors and 0 warnings for all six experts. A successful compile is not deployment readiness.

## Safe setup

Do not attach `VALIDATED_LIVE_CONFIGS_V2`. Do not treat a passing Python test as permission to go live.

1. Leave `VALIDATED_LIVE_CONFIGS/` untouched.
2. Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/compile_all.ps1`. It must exit 0, with 0 errors and 0 warnings on every `Experts/*.mq5`. That is the recorded result for this source. Re-run it after any source edit.
3. Run the static checks below. `check_guard_safety.py` and `check_config_sets.py` may pass while the candidate is still blocked.
4. Deployment automation must run `python tests/check_config_sets.py --require-deployable`. That command exits 1 while bot4 `DonchianExitPeriod=1` remains.
5. On a hedging account only, a future attach order is Guard first, then trading EAs. Guard `OnInit` publishes a fail-closed `STARTUP` block. The first tick replaces it with computed state. A missing or stale heartbeat still fail-opens.
6. The historical bot4 set also contains `DonchianExitPeriod=1` with `UseDonchianExit=true`. This bot4 source rejects that value in `OnInit`. Loading the historical file on this source fails closed. It does not pick 8, 10, or 14.

## V2 status and the Donchian blocker

`ENUM_H1_EXIT_PERIOD` is 8, 10, or 14. The V2 file `bot4_v149_R23_rank2_MAGIC40001.set` keeps `DonchianExitPeriod=1` and `UseDonchianExit=true`. Static review cannot choose a legal period. bot4 prints `[BOT4] INIT FAILED: DonchianExitPeriod=1` and returns `INIT_FAILED`. The manifest marks that file and the whole bundle `BLOCKED_PENDING_RUNTIME_CONFIRMATION`. Every other V2 set is `PENDING_REVALIDATION` because this source differs from the build the historical files were taken from.

Three stage files are semantic repairs, not behavior-preserving edits, and need a combined A/B before any attach: `bot1_regime2.0_PRODUCTION_1250_MAGIC54325_M5.set`, `bot1_regime2.0_PRODUCTION_667_MAGIC54326_M5.set`, and `bot1_regime2.2_PRODUCTION_2098_MAGIC220202.set`. The 220202 A/B must include the `UseStagedBE` move that becomes reachable at 500 points. The 54510 and 54511 files dropped embedded U+FEFF characters from `LotType`. That is a possible sizing change (`LOT_RISK` 1 versus source default `LOT_FIXED` 0) until live deal volumes show which value was loaded. Details: [docs/GUARD_FEATURES.md](docs/GUARD_FEATURES.md) and [docs/CONFIGURATION_MATRIX.md](docs/CONFIGURATION_MATRIX.md).

## Compile and test

Static checks, from the repo root:

```text
python tests/check_guard_safety.py
python tests/check_config_sets.py
python tests/check_config_sets.py --require-deployable
powershell -NoProfile -ExecutionPolicy Bypass -File tests/compile_all.ps1
```

The first two are allowed to exit 0. They print `UNRESOLVED_BLOCKER` for `DonchianExitPeriod=1` and state that a code pass is not deployment readiness. The third must exit 1 until that blocker is gone. The compile script has been run on this source and exited 0: all six experts, 0 errors and 0 warnings. That does not clear the Donchian block. MT5 runtime and Strategy Tester runs are listed in [docs/TEST_PLAN.md](docs/TEST_PLAN.md) and have not been run.

## Rollout and rollback

There is no rollout of this tree.

When a later build is actually cleared by `--require-deployable` and a human revalidation, and `tests/compile_all.ps1` still exits 0:

1. Record the terminal's current `.set` files and GlobalVariable names before attaching anything.
2. Attach the Guard and confirm a fresh `BOSSAFX_GuardHeartbeat_<symbol>` and an even `BOSSAFX_GuardPubSeq_<symbol>` before any trading EA is allowed to open.
3. Attach trading EAs one magic at a time. Confirm `[GGATE-BLOCK]` appears when `MEG_<symbol>_BLOCK_NEW` is 1, and that entries still happen when that key is missing (fail-open), so a dead Guard is visible in the journal rather than assumed safe.
4. Do not attach a bot4 set whose `DonchianExitPeriod` is not 8, 10, or 14.

Rollback is to remove the candidate charts and load the previous known terminal sets. Do not copy `VALIDATED_LIVE_CONFIGS_V2` back over `VALIDATED_LIVE_CONFIGS`. Do not edit the historical folder to "match" V2. If this source is what is compiled, the historical bot4 set will still fail `OnInit` until a confirmed Donchian period is chosen and the backtests are rerun.

## Docs

| Doc | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, pools, reader, gates, flattens, close outcomes |
| [docs/GLOBALVARIABLE_CONTRACT.md](docs/GLOBALVARIABLE_CONTRACT.md) | Key, owner, unit, freshness |
| [docs/GUARD_FEATURES.md](docs/GUARD_FEATURES.md) | Historical values versus V2, feature classification |
| [docs/CONFIGURATION_MATRIX.md](docs/CONFIGURATION_MATRIX.md) | All 15 sets |
| [docs/TEST_PLAN.md](docs/TEST_PLAN.md) | Static commands and the MT5 tests still required |
| [docs/REMEDIATION_REPORT.md](docs/REMEDIATION_REPORT.md) | Findings F1–F12 and review follow-ups |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Unreleased, not deployed |

## Not claimed

Static checks passed. MetaEditor compilation of all six experts passed with 0 errors and 0 warnings. MT5 runtime and Strategy Tester tests did not run. `--require-deployable` fails because `DonchianExitPeriod=1`. A successful compile is not deployment readiness. All configs need revalidation because the source changed. No profitability claim is made.
