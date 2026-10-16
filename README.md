# BOSSAFX Gold Multi-EA Fleet + Portfolio Guard

This repo is a **full code export** of everything currently running in production on a live
MT5 demo account (BOSSAFX-Demo, account 55772, GOLD symbol), for the purpose of running an
independent, from-scratch code review/validation pass with a different/stronger LLM than the
one used for day-to-day operation. It is NOT a tutorial or a clean reference implementation --
it is the real, messy, heavily-commented production source, including inline dated comments
documenting bugs found and fixed over time. Read those comments; they are a debugging log, not
noise, and explain WHY things are built the way they are.

## What this system actually is

A fleet of **6 independent MT5 Expert Advisors**, all trading the same symbol (GOLD) on the same
account, plus **1 separate "Guard" EA** that has no trading logic of its own and exists purely to
watch the other 6 and veto/flatten them under portfolio-level risk conditions. Each EA is a
standalone compiled program (its own chart, own magic number(s), own `.set` parameter file) --
they do not call each other directly. They coordinate ONLY through **MT5 GlobalVariables**
(a simple shared key-value store all EAs on the same terminal can read/write), which is the
single most important thing to understand about how this system works end to end.

## Files in this repo

```
Experts/
  bot1_regime2.0.mq5              -- trading EA, magics 54321-54327 (6 live configs)
  bot1_regime2.1.mq5               -- trading EA, magics 54510-54511 (2 live configs)
  bot1_regime2.2.mq5               -- trading EA, magics 220001/220201/220202 (3 live configs)
  bot4_TREND_FX_v1_49.mq5          -- trading EA, magic 40001 (1 live config)
  test4_clean_HYBRID_v52.mq5       -- trading EA, magic 54340 (1 live config)
  EA_G_PortfolioGuard_MultiEA.mq5  -- the Guard EA (no trading of its own, magic 61998)
Include/
  BossafxGuardGate.mqh             -- shared library: entry gates every trading EA calls
  PortfolioGuard.mqh               -- shared library: the Guard EA's own close/count helpers
VALIDATED_LIVE_CONFIGS/
  *.set                            -- every currently-deployed production parameter file,
                                      one per magic/config, read DIRECTLY off the live terminal
docs/
  ARCHITECTURE.md                  -- how all 7 EAs interact via GlobalVariables (read this first)
  GUARD_FEATURES.md                -- every Guard gate/flatten feature, what it does, current state
```

## How to validate this

1. Read `docs/ARCHITECTURE.md` first -- it explains the GlobalVariable coordination contract that
   `BossafxGuardGate.mqh` implements and every trading EA calls into.
2. Read `docs/GUARD_FEATURES.md` for a feature-by-feature breakdown of what the Guard EA does,
   current ON/OFF state, and known issues already found.
3. Cross-reference each `VALIDATED_LIVE_CONFIGS/*.set` file against its EA's `input` declarations
   to see the actual live parameter values -- the magic number declared in each `.set`
   (`MagicNumber=...`) tells you which EA+config combination it belongs to.
4. Every `.mq5`/`.mqh` file has extensive dated inline comments (`// 2026-10-XX: ...`) documenting
   bugs found/fixed in place -- these are real incident notes, treat them as authoritative context
   for "why is this line here," not boilerplate.

## Known open items (as of 2026-10-16, still true at export time)

- Guard's closure-reason tagging (`GGate_BuildCloseComment()` in `BossafxGuardGate.mqh`) writes
  correctly on the OPEN side of every trade but the CLOSE side never carries a reason tag in the
  live MT5 deal history, on any magic -- confirmed by direct inspection of the account's raw
  Deals export. This means there is currently no way to externally distinguish "closed by the
  EA's own TP/SL logic" vs "closed by Guard's flatten" from trade history alone. Worth having a
  fresh set of eyes trace every OrderSend-based close path in all 6 EAs + the Guard's flatten
  code to find where the tag is getting dropped.
- `MagicSwingM15` (54322) and `MagicBot4_v49` (40001) participate in the Guard's bar-priority
  entry gate pool but are NOT in `g_protectedMagics[]` (the basket-SL/profit-target
  flatten-protection list) -- may be intentional, may not be; flagged in `GUARD_FEATURES.md`.
