//+------------------------------------------------------------------+
//| bot1_regime2_2.mq5                                               |
//| Regime 2.2 — PRESET CLEANUP + PERSISTENCE BRANCH (2026-10-01),   |
//| re-forked from the CURRENT bot1_regime2.1.mq5 (post file-lock-   |
//| collision fix, post-PARDO, post-shadow-pool -- NOT the stale     |
//| Sep-23 snapshot the first 2.2 attempt was built on). Builds on   |
//| 2.1's continuous-regime-score direction with two concrete changes:|
//|                                                                   |
//|   1. PRESET REMOVAL: 2.1 still carried ENUM_ENTRY_PRESET          |
//|      (EntryPreset A-E) and ENUM_REGIME_PRESET (RegimePreset),     |
//|      each silently overwriting ~10 individual Use* booleans when  |
//|      set to a non-MANUAL value (confirmed in the PARDO sweep      |
//|      analysis to confound dead-parameter detection in 64-81%% of  |
//|      passes). Both enums + their override blocks in               |
//|      Bot1ResolveArch() are REMOVED in 2.2 -- every Use* boolean   |
//|      across Layer 1 / Layer 2 / Layer 3 / Regime Suite / strength |
//|      filters is now independently sweepable with zero confound.   |
//|      None of the frozen presets (A-E) were ever validated under   |
//|      the current SCORE_PARDO criterion anyway (PARDO sweep found  |
//|      MANUAL beat every preset outright) -- nothing of value lost. |
//|                                                                   |
//|   2. REGIME CONFIRMATION BARS: new sweepable RegimeConfirmBars     |
//|      input (default 0 = off, byte-for-byte identical to 2.1)      |
//|      ports the persistence/smoothing concept validated visually   |
//|      in the standalone RegimeSuite_*.mq5 indicators (raw Regime   |
//|      Suite voters flip every 1-3 bars on real GOLD M5 data; a     |
//|      requirement of N consecutive agreeing bars before the gate's |
//|      verdict is allowed to flip removes most of that noise).      |
//|      Applies uniformly to the combined Regime Suite verdict       |
//|      (Bot1RegimeSuiteSaysTrending), not per-voter -- keeps the    |
//|      sweep space small (1 new int) instead of 10 new ones.        |
//|                                                                   |
//|   Per the standing noisy-voter findings (confirmed on real GOLD   |
//|   M5, not just the earlier EURUSD mismatch): UseRegimeER,         |
//|   UseRegimeLinReg, UseRegimeMMI, UseRegime21Score, and             |
//|   UseRegimeATRRatio (suspected session-cycle artifact, not a      |
//|   real trend/range read) are left in place and independently      |
//|   switchable -- same off-by-default posture as 2.1, NOT deleted,  |
//|   so a wide sweep can still rediscover them if RegimeConfirmBars  |
//|   changes their usefulness. UseRegimeADX and UseRegimeCHOP are    |
//|   confirmed the two cleanest/lowest-flip voters and are the       |
//|   recommended starting point for RegimeSuiteVoteMode exploration. |
//|                                                                   |
//|   Own magic-number range + file prefix reserved below so 2.2's    |
//|   Tester runs never collide with 2.0/2.1/test4's logs. Standing   |
//|   constraints carried forward unchanged: 2.0 and 2.1 stay         |
//|   untouched; 2.2 runs Tester-only until it earns a validated      |
//|   config; DD ceiling 3.5%% at test lot size.                       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAU/USD Multi-layer EA -- REGIME 2.2 v1.00. Re-forked from current bot1_regime2.1.mq5. PRESET CLEANUP: EntryPreset/RegimePreset removed -- every Use* boolean now independently sweepable, zero confound. Added RegimeConfirmBars persistence filter. Tester-only until validated."
// v6.17 (2026-09-11): EntryPreset (PRESET_MANUAL/A/B/C). The 27-dimension WIDE_WEEKEND
// sweep (17 entry booleans + 10 exit-mechanics params) under-converged -- GA spread its
// budget too thin, TrailingActivation matched-pairs test showed 100% "no effect" despite
// a clear per-value mean-profit trend, proving the population never diversified enough to
// isolate it cleanly. Fix: freeze 3 diverse, already-validated entry-signal families
// (sweep4 M15 winner / sweep5b M5 candD / sweep3 alt-family) behind ONE int input
// (EntryPreset 0-3) instead of 17 correlated booleans. A sweep can now vary EntryPreset
// x the 8 exit-mechanics dims cleanly, with real convergence room on each. PRESET_MANUAL
// (default, =0) leaves all existing .set files' individual Use* ticks untouched -- zero
// behavior change unless a sweep explicitly sets EntryPreset>0.
// v6.16 (2026-09-10): STAGE-LINKED BE + IMMEDIATE TSL AFTER TP2. User request:
// once TP1 partial fires, move SL to ~breakeven (with a small buffer so
// normal price oscillation doesn't clip it) instead of leaving the original
// wide stop in place; once TP2 partial fires, start the trailing stop
// moving WITH price immediately instead of waiting for TrailingActivation's
// separate point-distance threshold. Added UseStagedBE (fires inside the
// existing TP1_PARTIAL block, reuses the same StageTracker.beApplied flag
// and BREAKEVEN_MOVE log event as the v6.15 UseBreakevenMove mechanism --
// mutually exclusive in intent, test one at a time) and
// TrailImmediatelyAfterTP2 (widens the trail-activation OR-condition to
// include Bot1GetStage(ticket)>=2, no change to TrailingDistance itself).
// Both off by default, zero effect on existing behavior unless enabled.
// v6.15 (2026-09-10): WIDE_SL_BE branch. Single-run MFE/MAE audit of candB_815t/
// candC_1002t (2026.01.01-2026.09.10, real ticks) found winners still dip a
// median 0.53R / p90 0.99R against the position before recovering (uniformly
// tighter SL would cut real winners), while ~48-52% of eventual FULL losers
// already touched >=0.5R profit before reversing all the way to a stop-out
// (median 4-4.5 bars to peak). Added two independently-toggleable inputs,
// both off by default, isolated from TP1/TP2/trailing/RRLinkedTP: UseWideSL
// (multiplies the computed SL distance by WideSLMultiplier, applied after
// basis selection, before broker min-distance enforcement) and
// UseBreakevenMove (moves SL to entry+BreakevenBufferPts once profit reaches
// BreakevenTriggerR fraction of the trade's own initial risk distance, fires
// once per ticket via new StageTracker.beApplied field, logs a new
// BREAKEVEN_MOVE event to the existing bot1_trades CSV). Next sweep: TP1/TP2
// held near current (1.0R/2.0R) or slightly lower, cross with
// WideSLMultiplier x BreakevenTriggerR x BreakevenBufferPts to find whether
// a wider initial stop + earlier BE-lock beats today's ADR*0.3 fixed SL on
// win-rate and average-R without regressing DD.
// v6.14 (2026-09-09): Jun-Aug GOLD M5 Model=4 (15.2M ticks, 100% real ticks). Six-way
// exit matrix. Winner: RR_PARTIAL + trail 80 after 2R + Kumo off: +2279, PF 1.18,
// DD 4.13%, OnTester +1.19. RR hold-to-3R was -505 / PF 0.96. STAGED+trail 80
// exploded to 471 opens / PF 0.51 — do not combine point-partials with trail.
// Trail still clears the 3R order TP; that is why it beat hold on this window.
// v6.13 (2026-09-09): GOLD exit defaults from logged tests. Lot 0.05 (not 0.50).
// ExitMode=RR_PARTIAL 50%@1R then 50% of remaining@2R, remainder rides 3R order TP.
// UseTrailingOnRemainder=false (trail still clears order TP). TrailingDistance 20->80
// so it is GOLD-legal if you turn trail on; ManageStagedProfits CLAMPS up to broker
// min+5 instead of silently skipping. UseKumoSL=false (log: Kumo pulled SL to 8.01).
// Isolation/parity .set files still force AGILE exits (lot 0.1, STAGED 30/50, Kumo on).
// Also: RR_PARTIAL had stageClose2 hardcoded to 1.0 (flattened 3R rider on 0.05 lots
// after min-lot rounding). TP1/TP2 now keep at least one min-lot unless you set
// TP2_ClosePercent=1.0.
// v5.96 (2026-08-30): systematic audit of every Max*/Min*/Cap/Fraction/
// Floor/Ceiling/Threshold/Buffer input's call sites, prompted by finding
// MaxRiskPerTradeFraction silently clamping RiskPercent flat above ~1.5%
// in a LOT_RISK sweep. Findings: (1) SafetyBuffer was fully dead code --
// declared once, referenced nowhere -- removed. (2) Confirmed
// TradeTrendingOnly=true correctly (not buggily) implies not-ranging AND
// not-low-vol -- refactored IsMarketTradable() to evaluate all three
// conditions independently instead of sequential early-returns (behavior-
// identical, verified by exhaustive truth-table check) purely for
// readability; the real actionable finding is that AvoidRanging/
// AvoidLowVol become REDUNDANT search dimensions whenever TradeTrendingOnly
// is held fixed true in a .set file -- this happened in the v5.94 MAJORITY
// optimization (AvoidRanging flagged Y/optimize while TradeTrendingOnly was
// fixed true), wasting search budget across all 1536 passes on a parameter
// that could never change any outcome. No other guard/cap issues found
// across the remaining 30 audited inputs.

// v5.94 (2026-08-29): regime-filter audit and consolidation, requested
// after v5.93's OnTester patch surfaced how tangled the filter set had
// become across v3-v5 branch history. Four separate changes, each
// independently reasoned about above at its own site:
//  (1) DEAD CODE REMOVED: UseMarketFilter, UseTrendStrength (never referenced
//      anywhere outside their own declaration) and StrongADXThreshold
//      (legend display color only, no trading effect) deleted. These were
//      silently inflating the .set file / optimizer search space with
//      parameters that did nothing.
//  (2) ATR-RATIO DUPLICATION MERGED: UseVolatilityRatio (always-on, 3-way
//      TRENDING/RANGING/LOW_VOL gate) and g_UseRegimeATRRatio (Regime Suite
//      vote input) computed the IDENTICAL fast/slow ATR ratio via two
//      separate indicator handles with the same default periods (5/20).
//      Now one computation (regimeAtrFastHandle/regimeAtrSlowHandle),
//      read by both decision layers. This was flagged as a live risk in
//      v5.3's changelog (Round 16 testing the Regime Suite while this
//      always-on gate ran unaware of it, unconditionally, the whole time)
//      -- plausible confound in that "AND-gating measured worse than
//      nothing" result.
//  (3) TWO SESSION GATES MERGED INTO ONE: g_UseRegimeSession (Regime Suite)
//      and UseSessionGate (former Community Filters) computed the same
//      broker/server-hour window with separate toggles/defaults. Now one
//      filter (g_UseRegimeSession), one vote input.
//  (4) THREE TRIGGER SOURCES REDUCED TO TWO, FULL VOTE UNIFICATION: the
//      former UseCommunityFilterGate (AND-only, ATR band/spike/session/
//      Asian-range) is RETIRED -- those four filters are now voters in the
//      SAME RegimeSuiteVoteMode suite as the six academic filters, governed
//      by g_UseRegimeSuiteGate. Previously RegimeSuiteVoteMode (added v5.3)
//      only ever governed 6 of the 10 total filters; the other 4 sat on a
//      separate hardcoded-AND path never covered by the AND/OR/MAJORITY
//      re-test. UseRegimeKillSwitch (reactive, the strategy's OWN realized
//      win rate) remains fully separate and OFF by default, per explicit
//      instruction -- a fundamentally different signal type (own performance
//      vs external indicator classification), not folded into the vote.
//  (5) RR-LINKED TP: new UseRRLinkedTP (default true) + RRMultiple (default
//      3.0) derives the order-level TP as a straight multiple of the ACTUAL
//      SL distance actually used for this entry (post Kumo-override, post
//      broker min-distance enforcement), instead of SL and TP being two
//      fully independent optimizer dimensions (ADRMultiplierSL/
//      ADRMultiplierTP or StopLoss/TakeProfit). Cuts genetic-search
//      dimensionality on the exit side and keeps every candidate at a
//      trader-sane RR instead of letting the optimizer wander into
//      nonsensical SL/TP combinations. Does not touch the TP1/TP2 staged-
//      exit system or range-mode's own tight symmetric SL/TP -- only the
//      order-level TP set at position-open time. Toggle off to A/B against
//      the pre-v5.94 independent-TP behavior.
// All five changes compiled clean (0 errors, 0 warnings, MetaEditor64,
// BOSSAFX 5 build) and are individually toggleable/reversible where a
// toggle made sense; (1)-(4) have no toggle since they're pure duplication/
// dead-code removal with identical behavior at default settings.
// v5.3 (2026-08-28): two independent, separately-motivated changes bundled
// under one version bump (both scoped to OnTester/regime-suite, neither
// touches entry/exit/trade-management logic, so both are safe to A/B
// against v5.2 in isolation via their own toggles):
//  (1) FTMO daily-loss gate. OptMaxDDPctAllowed tightened 10.0 -> 5.0 to
//      actually match the funded-account overall-DD ceiling being traded
//      under. Added a SEPARATE UseDailyDDGate (default true) +
//      OptMaxDailyDDPctAllowed (5.0) that reconstructs each calendar day's
//      P&L from closed-deal history (same per-deal-history technique as
//      CalculateUlcerIndex, new CalculateWorstDailyDDPct) and disqualifies
//      any run whose worst single day breached it -- STAT_EQUITY_DDREL_PERCENT
//      alone only ever reports the single worst peak-to-trough across the
//      WHOLE test and can silently pass a run that blew a daily limit mid-
//      test but recovered later in the same run. This is a same-account-size
//      proxy computed from Strategy Tester deal history, not an official
//      FTMO API check -- still verify a candidate's actual day-by-day figures
//      before treating any run as prop-firm-safe.
//  (2) Regime-suite combine logic no longer hardcoded to AND/veto. Round 16
//      found the v4 academic suite (ADX/ER/CHOP/LinReg/ATR-ratio/MMI) under
//      AND-gating measured worse than doing nothing, across all 128 tested
//      combinations -- but AND-gating six independent filters simultaneously
//      is strict enough that it could veto genuine trend entries alongside
//      bad ones, and that specific hypothesis (gate-strictness vs filters-
//      themselves-uninformative) was never isolated since only AND was ever
//      tested. Added RegimeSuiteVoteMode (AND/OR/MAJORITY, default AND --
//      reproduces pre-v5.3 behavior exactly) so the SAME six filters can be
//      re-optimized under OR (any one enabled filter confirming "trending"
//      passes) or MAJORITY (>=half agree) before concluding the filters
//      carry no real signal on gold. Diagnostics now print the active vote
//      mode alongside each filter's raw value/verdict.
// v5.2 (2026-08-17): OnTester()'s scoring formula previously only
// penalized the single worst drawdown (OptMaxDDPctAllowed, a hard gate)
// and rewarded profit%/PF/trade-count -- nothing measured the SHAPE of
// the equity curve getting there, so a genetic pass could favor a run
// that nets positive despite grinding down for months before recovering.
// Added CalculateUlcerIndex() (Peter Martin, 1987): reconstructs the
// equity curve from closed-deal history, tracks drawdown% from the
// running peak at each deal, squares it, averages across the test --
// duration and depth of underwater periods both get punished, an
// equity curve allowed to oscillate but trending up scores well, one
// that bleeds down for an extended stretch scores poorly even if it
// never breaches the existing single-worst-DD gate. Applied as a
// divisor on the final score, gated by UseUlcerPenalty (default true)
// for easy A/B comparison against the pre-v5.2 formula.
// v5.1 (2026-08-17): smoke-test log analysis (39,557 diagnostic bars,
// GOLD_test M5, full 2026 H1) found ATRBandFloorPoints=30.0 sat below
// this run's entire observed ATR distribution (125.9-8160.2 points) --
// same silent no-op failure class as the v4.1 MMI threshold, just
// harmless this time since the ceiling was still doing real work.
// Recalibrated floor to 250.0 (~p4 of the observed distribution). Checked
// the other three v5 filters (ATRSpikeMultiplier, AsianRangeMinFrac/
// MaxFrac, session hours) against the same failure pattern -- none
// qualified: those three are exact values from named external sources
// (MQL5 forum 504875, GoldLondonBreakout), not data-fit parameters, and
// their verdict splits (0.6%, 14%, 39%/61%) were never degenerate.
// v5 (2026-08-16): added a SEPARATE, practitioner/forum-sourced filter
// suite -- Stage 1 (ATR floor/ceiling band; exact community ATR-spike
// rule from MQL5 forum 504875, M1-based: ATR(M1,2) >= 2xATR(M1,1440) =
// skip) and Stage 2 (session gate; Asian-range-vs-Daily-ATR fraction test
// ported from the free MQL5 CodeBase EA "GoldLondonBreakout" #75586,
// 0.15-0.70x band). Deliberately distinct from the v4 academic regime
// suite, which measured worse across all 128 combinations tested in Round
// 16 -- this is a fresh empirical test of community-described mechanisms,
// not a continuation of that result. UseCommunityFilterGate ORs this
// suite's "blocked" verdict into the SAME suppress/adapt trigger the
// win-rate switch and academic suite already use -- all three trigger
// sources (UseRegimeKillSwitch, g_UseRegimeSuiteGate, UseCommunityFilterGate)
// are independently toggleable and can be tested alone or combined. All
// new filters default OFF; with UseCommunityFilterGate=false this file
// behaves identically to v4.1. LogCommunityFilterDiagnostics prints every
// enabled filter's raw value + verdict once per bar, same validation role
// as the v4 suite's diagnostic print.
// v4.1 (2026-08-15): smoke-test log analysis (39,557 diagnostic bars,
// GOLD_test M5, full 2026 H1) found RegimeMMITrendMax=65.0 sat above this
// reimplementation's entire observed MMI range (28.3-61.6, mean 45.3) --
// the filter registered "trending" on literally 100% of bars, 0% ranging,
// making it a silent permanent no-op regardless of actual conditions. The
// other five filters (ADXR, ER, CHOP, LinReg R², ATR ratio) all showed
// genuine, meaningful trending/ranging splits in the same run -- this was
// isolated to MMI's calibration, not a structural bug in the gate logic.
// Recalibrated default to 47.0 based on the observed distribution. Weak
// but correctly-signed correlation with ADXR (-0.08) in the same data
// confirms the underlying direction (falling MMI = trending) wasn't
// backwards, just uncalibrated.
// v4 (2026-08-11): added a regime-detection suite -- six independently-
// toggleable, literature-standard trend-vs-range filters (ADX/ADXR,
// Kaufman Efficiency Ratio, Choppiness Index, Linear Regression R², ATR
// fast/slow ratio, Market Meanness Index) plus a session filter, per
// project research into established gold-EA regime detection practice
// (Wilder 1978, Kaufman 1995, Dreiss 1993, Lotter/Financial Hacker).
// g_UseRegimeSuiteGate feeds the suite's combined "ranging" verdict into
// the SAME suppress/adapt response the v2/v3 win-rate kill switch already
// uses (OR'd together via UseRegimeKillSwitch) -- so the win-rate
// detector, the new suite, or both together can be A/B tested
// independently. All new filters default OFF and cost nothing when
// disabled -- with g_UseRegimeSuiteGate=false (default), this file behaves
// identically to v3. Filters combine with AND logic (confluence gate, any
// one enabled filter can veto) -- deliberately conservative rather than a
// voting system, per the research recommendation not to stack redundant
// filters and let a heavy optimizer curve-fit many thresholds at once.
// LogRegimeSuiteDiagnostics prints every enabled filter's raw value and
// verdict once per bar -- the validation tool for confirming none of this
// is silently broken before trusting it.
// v3 (2026-08-11): added UseRangeModeAdaptation. Round 13 (proper back/fwd
// comparison, not a single anecdote) showed the v2 suppression response
// makes things WORSE once the exit-mechanism bugs (v5.8/v5.9) are fixed:
// fwd PF 0.92 with suppression vs 1.08 doing nothing at all, robust rate
// 17% vs 50%. The "regime change" symptom was substantially the old bugs,
// not a persistent market shift needing a hard stop. This tests a
// different response instead of abandoning the detector: when it's
// active, don't refuse to trade -- trade with a tight symmetric SL/TP
// (RangeModeSL_Points/RangeModeTP_Points) instead of the normal ADR-based
// trend stops, on the theory that the detector is picking up ranging
// rather than trending conditions. Entries are untouched (same L1/L2/L3
// signal) -- only new-position SL/TP placement changes, via
// g_useRangeModeForThisEntry consulted in CalculateStopLoss/
// CalculateTakeProfit. OFF by default (UseRangeModeAdaptation=false) --
// with it off, behaves identically to v2.
// v2 (2026-08-11): fixed two bugs found from the v1 single-test log:
// (1) Bot1GetRollingWinRate's warm-up guard only checked n<=0, so as few
// as 1-2 real closed trades could compute a "win rate" and trip the
// switch -- confirmed in testing: tripped after exactly 2 trades (one
// loss), rolling win rate reported as "0.0% over last 15 trades" when
// only 2 had actually closed. Now requires a FULL RegimeLookbackTrades
// window before it can trip at all.
// (2) self-locking: suppressing entries also stops the trade outcomes
// needed to ever reassess, so once tripped the switch could never
// release -- confirmed in the same log, zero trades for the rest of a
// 7-month test after tripping on bar ~5000 of ~40000. Added
// RegimeProbeIntervalBars: while suppressed, lets exactly one signal
// through every N bars so the rolling window keeps moving and the switch
// can potentially recover. Set to 0 to deliberately restore the v1
// hard-lock behavior.
// BRANCH FILE, not mainline -- do not confuse with the v5.9
// test4_clean_HYBRID_bot1_v1.mq5 you already have. This adds ONE new,
// clearly-scoped feature (Bot1RecordTradeOutcome/Bot1GetRollingWinRate/
// Bot1RegimeKillSwitchActive, gated by UseRegimeKillSwitch, default OFF)
// on top of the identical v5.9 mainline codebase. With UseRegimeKillSwitch
// left at its default false, this file's behavior is byte-for-byte
// identical to mainline v5.9. Merge back into mainline only once you've
// validated the switch actually helps -- don't let this become a silent
// fork of the real development line.
//
// Built in response to Round 12: 819/819 back-tested TP-stack combos
// profitable, 0/819 profitable forward, tightly clustered regardless of
// exit parameters -- meaning something about the market changed, not a
// tuning problem. Deliberately watches the STRATEGY'S OWN realized win
// rate rather than trying to classify market regime from an external
// indicator (ADX/ATR/etc) -- this project's own history already shows an
// external-indicator regime-gate failed on GoldGuardian's trend/range
// branch (lost money OOS in both ON and OFF conditions, removed). Run a
// single full-period test with LogRegimeKillSwitch=true (default) and read
// the printed TRIPPED/RELEASED timestamps directly off the log -- that IS
// the regime-timing diagnostic, no separate price-data pull needed.
// v5.9 (2026-08-11): closed the same unguarded-retry gap in the last
// remaining place it existed -- the trailing-stop-modify branch (Stage 3b)
// had no backoff on a rejected PositionModify (e.g. market closed), same
// exposure v5.7 fixed for final-close-target and v5.8 fixed for TP1/TP2.
// Added a SEPARATE cooldown tracker (Bot1IsOnTrailCooldown/
// Bot1SetTrailCooldown) rather than reusing the close-cooldown one, so a
// TP1/TP2 failure on a ticket can't accidentally suppress a legitimate,
// unrelated trailing update on that same ticket. This should be the last
// of this specific bug class in the file -- all four trade-action call
// sites (TP1 partial, TP2 partial, final-close, trailing-modify) now have
// the same throttled-retry protection.
// v5.8 (2026-08-11): fixed the repeated-TP1/TP2-partial-close pattern
// confirmed in production logs (hundreds of "TP2 Hit: Closed 0.01" lines
// for a single ticket). ManageStagedProfits checked raw profitDistance
// thresholds every tick with no memory of what had already fired, so a
// position sitting above TP1/g_TP2_Distance kept getting a fresh minimum-lot
// partial close on nearly every favorable tick instead of one clean
// g_TP1_ClosePercent/g_TP2_ClosePercent close -- decay instead of the intended
// single scale-out. Fix wires in the StageTracker struct that already
// existed in the file (declared, initialized in OnInit, never read or
// written anywhere else) -- its own field comment documents the intended
// one-shot state machine (0=open -> 1=TP1 closed -> 2=TP2 closed ->
// 3=trailing); this restores that design rather than inventing new state.
// TP1/TP2 now fire once each per position; on the rare failure case, retry
// is throttled via the same cooldown added in v5.7 rather than retried
// every tick. Trailing (STAGE 3b) is untouched -- its every-tick SL update
// is correct, continuous behavior, not the bug being fixed here.
// v5.7 (2026-08-11): bug fix, not performance -- ManageStagedProfits'
// final-close-target branch retried trade.PositionClose() every single
// tick with no backoff on failure. Confirmed in a production log: 158
// consecutive rejections in ~2m47s during a market-closed window
// (retcode 10018), one wasted attempt and one log line per tick. Added a
// 60-second per-ticket cooldown (Bot1IsOnCloseCooldown/Bot1SetCloseCooldown)
// -- the position still gets closed once the market reopens, it just
// isn't retried every tick while it can't be. NOTE: the same unguarded-
// retry pattern exists in the TP1/TP2 partial-close and trailing-modify
// branches too -- not touched here since only the final-close-target
// branch was confirmed to actually hit it in the log; flagged separately.
// v5.6 (2026-08-10): the largest per-bar fix so far. Bot1CaptureLayer1/2/3
// each called every sub-indicator function directly to log its raw value,
// then called the layer's aggregator (GetLayer1Trend/CheckLayer2Momentum/
// GetLayer3Trigger) -- which called every one of those same sub-indicator
// functions AGAIN internally to compute the aggregate. Every indicator in
// all three layers (Ichimoku's 5 CopyBuffer + 2 CopyClose, ADX's 3
// CopyBuffer, Donchian's up-to-DonchianPeriod iHigh/iLow loop, etc.) was
// being read twice per bar for no reason, every bar, every pass. Added
// GetLayer1TrendFromSignals / CheckLayer2MomentumFromSignals /
// GetLayer3TriggerFromSignals -- identical aggregation formulas, but taking
// the already-computed sub-signals as arguments instead of recomputing
// them. Bot1CaptureLayer1/2/3 now call these. The original GetLayer1Trend/
// CheckLayer2Momentum/GetLayer3Trigger functions are untouched and still
// used by CheckIndicatorFilters/DrawLeftLegend -- both legend-only paths,
// already skipped during non-visual optimization since v5.3.
// v5.5 (2026-08-10): found a second layer of the same ADR problem -- v5.3
// moved CalculateADR() from per-tick to per-M5-bar, but ADR is a D1-period
// value that only changes once a day. Added a D1-bar cache so it's now
// only recomputed when the daily bar actually rolls, ~288x fewer calls
// than the v5.3 level on M5. No change to the value used anywhere.
// v5.4 (2026-08-10): follow-up performance fix -- the "[BOT1-L1]" diagnostic
// Print in CheckForTradingSignals had NO gating flag at all, unlike every
// other diagnostic in the file (its own neighboring comment said it shared
// LogBot1L2L3Diagnostics's cadence, but the toggle was never wired). It ran
// every bar, every optimization pass, unconditionally. Now gated behind
// LogBot1L2L3Diagnostics like its L2L3 counterpart. No change to content or
// cadence when the flag is on; this is very likely the larger remaining
// cost after v5.3, since it fired tens of thousands of times per pass
// (once per M5 bar over a multi-month test) versus v5.3's per-tick fixes.
// v5.3 (2026-08-10): performance-only patch, no trading-logic change --
// ADR moved off the per-tick path onto new-bar only; legend rendering and
// ChartRedraw() skipped during non-visual Strategy Tester runs; the four
// BOT1 log files now use a persistent handle instead of reopening/closing
// on every row; removed an unused ATR indicator handle (CalculateADR reads
// raw iHigh/iLow, never this handle). See IsMarketTradable()'s wiring into
// CheckForTradingSignals (already present, from the prior session) --
// unrelated to this patch, not reverted.

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <BossafxGuardGate.mqh>  // 2026-10-13: wired into both Guard gates (bar-priority +
                                 // min re-entry distance) -- previously missing entirely from
                                 // this file despite 2.2 being in the Guard's protected pool
                                 // (MagicR22Pass6060=220001); bot1_regime2.0/2.1 already had this

//+------------------------------------------------------------------+
//| ENUMS                                                            
//+------------------------------------------------------------------+
enum ENUM_LOT_TYPE {
   LOT_FIXED = 0,
   LOT_RISK = 1
};

// Regime 2.0 forks — mutually exclusive engines, not additive toggles.
enum ENUM_LAYER1_MODE {
   L1_LEGACY           = 0,  // Ichimoku + EMA + PSAR, existing Use* flags, 2-of-3
   L1_SUPERTREND_ADD   = 1,  // Ichimoku + EMA + SuperTrend (PSAR out), 2-of-3
   L1_SUPERTREND_ONLY  = 2,  // SuperTrend + EMA200 bias only, 2-of-2
   L1_EMA_BIAS         = 3   // EMA200 bias only (slot TREND_EMA_BIAS)
};

enum ENUM_LAYER2_RSI_MODE {
   RSI_LEVEL50     = 0,  // AGILE parity: RSI vs RSIMomentumLevel (default 50)
   RSI_EXTREME75   = 1,  // gold-tuned continuation: RSI>=Overbought bull, RSI<=Oversold bear, else 0
   RSI_BAND_VETO   = 2   // 50-direction AND not through 75/25 exhaustion
};

enum ENUM_LAYER3_MODE {
   L3_LEGACY          = 0,  // Bollinger + Donchian (+ OBV if g_UseOBV)
   L3_DISABLED        = 1,  // skip Layer 3; live gate treats L3 as pass; g_ExcludeWhenL3Fires ignored
   L3_RETEST_BREAKOUT = 2,  // Donchian break, then pullback-and-hold
   L3_VWAP_RECLAIM    = 3   // session VWAP reclaim/rejection in L1 direction
};

enum ENUM_LAYER3_GATE {
   L3_GATE_OFF     = 0,  // L3 not in the live path (ticks still log)
   L3_GATE_CONFIRM = 1,  // RequireL3: L3 vote must match L1. Do not combine with L2 ticks (16-combo collapse)
   L3_GATE_EXCLUDE = 2   // skip the entry when L3 vote PASSES (isolation: exclude-legacy helped a little)
};

enum ENUM_REGIME_SUITE_PRESET {
   PRESET_FULL10 = 0,  // existing 10 voters + RegimeSuiteVoteMode
   PRESET_LEAN4  = 1   // force ADX-slope + CHOP + BB-width-percentile + Session; ignore other UseRegime* flags
};

enum ENUM_STOP_BASIS {
   SL_ADR = 0,  // AGILE: adr * ADRMultiplierSL
   SL_ATR = 1   // chart iATR(ATRStopPeriod) * g_ATRStopMultiplier; Kumo override still applies
};

enum ENUM_ARCH_PRESET {
   ARCH_PARITY      = 0,  // iso_00 / AGILE-equivalent live path
   ARCH_ISO_ST_ONLY = 1,  // isolation step 06
   ARCH_ISO_LEAN4   = 2,  // isolation step 08
   ARCH_LIVE_LEAN   = 3,  // SuperTrend-only + one regime (ADX>25), NOT stacked with LEAN4
   ARCH_SWEEP       = 4,  // optimizer uses the four slot enums
   ARCH_RAW         = 5   // no remap -- old 232-input behavior
};

enum ENUM_TREND_ENGINE {
   TREND_ICHI_PSAR = 0,  // L1_LEGACY Ichimoku+PSAR 2-of-3
   TREND_ST_ONLY   = 1,  // L1_SUPERTREND_ONLY
   TREND_ST_ADD    = 2,  // L1_SUPERTREND_ADD
   TREND_EMA_BIAS  = 3   // EMA200 bias only
};

enum ENUM_MOMENTUM_ENGINE {
   MOM_NONE      = 0,
   MOM_RSI       = 1,
   MOM_MACD      = 2,
   MOM_ADX_SLOPE = 3,
   MOM_CCI       = 4
};

enum ENUM_TRIGGER_ENGINE {
   TRIG_NONE           = 0,
   TRIG_EXCLUDE_LEGACY = 1,  // g_ExcludeWhenL3Fires + L3_LEGACY
   TRIG_RETEST         = 2,
   TRIG_VWAP_RECLAIM   = 3,
   TRIG_DONCHIAN_ONLY  = 4
};

enum ENUM_REGIME_ENGINE {
   REG_NONE  = 0,
   REG_ADX25 = 1,  // ADX/ADXR > 25
   REG_CHOP  = 2,  // CHOP 38.2/61.8 (existing RangeMax 61.8)
   REG_LEAN4 = 3,  // isolation survivor -- do not stack with ST_ONLY as a default
   REG_ER    = 4   // Kaufman ER >= 0.35
};

enum ENUM_EXIT_MODE {
   EXIT_STAGED     = 0,  // current TP1/TP2 point distances
   EXIT_RR_PARTIAL = 1,  // 50% at 1R, TP2_ClosePercent of remaining at 2R, rider to 3R TP
   EXIT_FULL_HOLD  = 2   // no staged partials; ride order-level RR TP
};

enum ENUM_CT_MODE {
   CT_OFF           = 0,
   CT_ON_WHEN_RANGE = 1   // module on only if a regime voter (or LEAN4) is ticked
};

enum ENUM_OPT_SCORE {
   SCORE_RF_SOFT = 0,  // Recovery Factor backbone, no PF multiply, soft ramps
   SCORE_UPI     = 1,  // profit% / Ulcer Index as the whole score
   SCORE_LEGACY  = 2,  // pre-v6.10 profit% * PF * sqrt(N) / DD
   SCORE_PARDO   = 3,  // 2026-09-27: Pardo pessimistic-profit + Sterling cushion + hard DD gate (see OnTester())
   SCORE_WINRATE = 4   // PORTED FROM 2.0 2026-10-11: pure directional-accuracy score -- % of trades with
                        // positive net final P&L, gated by a minimum avg-R/trade floor so a config can't
                        // win by taking a token-sized TP that barely tests the market (see OnTester()).
};


//+------------------------------------------------------------------+
//| BOT1 SHADOW LOGGING STRUCTS                                     |
//| Raw values captured ONCE per bar-close, shared by strict trade  |
//| gate (L1 only) and shadow/analysis columns (L2/L3/vol/time).    |
//| No values are ever dropped because a filter is disabled --      |
//| disabled just means it doesn't gate the trade, it still logs.   |
//+------------------------------------------------------------------+
struct Bot1Layer1State {
   int    ichi_signal;
   int    ema_signal;
   int    psar_signal;
   int    st_signal;          // SuperTrend: 1/-1/0 — always populated when ST handles exist
   int    l1_confirmations;
   int    l1_result;
   bool   l1_pass_strict;
   int    l1_vote_n;          // denominator actually used this bar (2 or 3)
};

struct Bot1Layer2State {
   int    macd_signal;
   int    rsi_signal;
   double rsi_value;
   bool   adx_ok;
   double adx_value;
   double plus_di;
   double minus_di;
   double adx_slope;
   int    cci_signal;
   double cci_value;
   bool   rsi_voter_active;   // after g_PreferCCIInTrend substitution
   bool   cci_voter_active;
   int    l2_confirmations;
   bool   l2_pass_strict;
};

struct Bot1Layer3State {
   int    boll_signal;
   int    obv_signal;
   int    donchian_signal;
   int    retest_signal;
   int    vwap_reclaim_signal;
   int    l3_result;
   bool   l3_pass_strict;
   int    retest_pending_dir;
   int    retest_bars_left;
};

struct Bot1VolState {
   double atr_ratio;
   int    vol_state;
   bool   vol_filter_pass_strict;
};

struct Bot1RiskContext {
   int    day_of_week;
   int    hour_utc;
   double spread_pips;
   bool   time_filter_pass;
};

//+------------------------------------------------------------------+
//| INPUTS - CORE SETTINGS                                          
//+------------------------------------------------------------------+
input group "═══ General Settings ═══"
input ENUM_LOT_TYPE LotType = LOT_FIXED;
input double LotSize = 0.05;
input double RiskPercent = 1.0;
input int MagicNumber = 220001;            // 2.2 branch: reserved range 220001-220099 (per user convention: 22xxxx = version 2.2), separate from 2.0's 54320-54326, 2.1's 54500-54599, and test4's 54401-54403
input bool UseGuardBarGate = true;  // 2026-10-13: added -- previously missing from this file.
                                     // user default ON; fail-open if EA_G_PortfolioGuard_MultiEA
                                     // isn't running or hasn't published a gate decision yet --
                                     // see BossafxGuardGate.mqh GGate_ShouldOpen()/GGate_PriceDistanceOk()
input string ConfigLabel = "R21_DEV";      // short tag embedded in every trade comment, e.g. "AGG"/"BAL"/"LT" -- lets you tell which live config placed a given position
input bool CloseOpposite = false;
input int MaxBuyPositions = 1;
input int MaxSellPositions = 1;
input bool OneTradePerBar = true;
input int Bot1MagicRangeStart = 100001;    // used ONLY to count concurrent bot1 positions across symbols for logging
input int Bot1MagicRangeEnd   = 100020;    // does not affect trading logic, widen if you add more bot1 symbols
// v6.21 (2026-09-15): CONCURRENT-POSITION RISK SPLIT branch. CalculateLotSize()
// computes each NEW position's risk independently from current balance/equity --
// it does not know how many positions are already open. So raising
// MaxBuyPositions/MaxSellPositions above 1 (to fix the runner-leg 51%-occupancy
// bottleneck found on the scalper config) would silently let 2 concurrent
// positions each carry full RiskPercent -- up to ~2x intended risk exposure.
// Off by default (matches existing 1/1 behavior exactly, zero risk to anything
// already validated). When on, effective per-trade risk = RiskPercent /
// (1 + concurrent same-direction open positions at entry time) -- e.g. opening
// a 2nd buy while one is already open uses half RiskPercent for both.
input bool UseConcurrentRiskSplit = false; // divide RiskPercent by (1 + same-direction open count) when MaxBuy/SellPositions > 1

input group "═══ EXITS (read the comments — staged vs RR vs trail interact) ═══"
// Three independent pieces. Tick what you want; they do not silently overwrite each other.
// (1) ORDER TP at open: UseRRLinkedTP → TP = SL distance × RRMultiple (AGILE default 3R).
//     If false, TP comes from ADRMultiplierTP / TakeProfit.
// (2) PARTIALS while the trade is open (ExitMode):
//     EXIT_STAGED     = close TP1_ClosePercent at TP1_Distance POINTS, then TP2 at TP2_Distance.
//                       GOLD point=0.01 so 30 points = 0.30 price, not "30 pips" of 0.1.
//     EXIT_RR_PARTIAL = close ExitRR_Close1Pct at 1R from the ORIGINAL SL, then
//                       TP2_ClosePercent of the REMAINING volume at ExitRR_TP2R.
//                       Remainder rides the 3R order TP until trail starts.
//                       Trail on this mode waits until AFTER the 2R partial (stage>=2)
//                       so it does not delete the order TP on the first 50-point tick.
//     EXIT_FULL_HOLD  = no partials. Ride the order TP. Trailing is skipped in this mode
//                       (trail used to call PositionModify(..., tp=0) which DELETES the order TP).
// (3) TRAIL: UseTrailingOnRemainder. Only runs when ExitMode is STAGED or RR_PARTIAL.
//     When trail first fires it sets TP=0 (removes order TP) so the remainder can run.
//     UseFinalCloseTarget=true skips trail and closes 100% at TPFinal_Distance instead.
input ENUM_EXIT_MODE ExitMode = EXIT_RR_PARTIAL;  // default: 50% at 1R, 50% of remainder at 2R, then trail (v6.14 Jun-Aug ticks)
input bool UseStageExits = true;           
input int TP1_Distance = 30;               
input double TP1_ClosePercent = 0.25;      
input int TP2_Distance = 50;               
input double TP2_ClosePercent = 0.50;      
input double ExitRR_TP1R = 1.0;            
input double ExitRR_TP2R = 2.0;            
input double ExitRR_Close1Pct = 0.50;
input bool UseTrailingOnRemainder = true;  
input int TrailingActivation = 80;        
input int TrailingDistance = 80;           
input bool UseFinalCloseTarget = false;
input int TPFinal_Distance = 80;
input int Bot1FallbackMinStopPoints = 30;

input group "═══ RISK MANAGEMENT ═══"
input bool UseADR = true;
input int ADRPeriod = 14;
input double ADRMultiplierSL = 0.3;
input double ADRMultiplierTP = 0.9;
input int StopLoss = 100;
input int TakeProfit = 200;
input bool UseKumoSL = false;              

// v5.94 (2026-08-29): SL and TP were two fully independent optimizer
// dimensions (ADRMultiplierSL/ADRMultiplierTP, or StopLoss/TakeProfit in
// fixed-point mode) -- a genetic pass exploring both freely can land on
// nonsensical risk:reward combinations (e.g. wider TP than SL inverted, or
// RR so low no amount of win rate covers costs) and burns search budget on
// SL/TP JOINT combinations instead of SL alone. UseRRLinkedTP collapses TP
// to a single multiple of whatever SL actually ends up being (AFTER the
// Kumo override and broker min-distance enforcement in CalculateStopLoss --
// so this reflects the REAL risk taken, not the pre-override ADR figure).
// Default ON at 3.0 (the 3:1 RR the user trades this system at) -- turn off
// to restore the old ADRMultiplierTP/TakeProfit-driven behavior for direct
// A/B comparison. Does NOT affect the separate TP1/TP2 staged-exit system
// (fixed point distances, a different mechanism) or RangeModeTP_Points
// (v3 branch, tight symmetric range-mode exits) -- only the order-level TP
// set at position-open time.
input bool   UseRRLinkedTP = true;    // TP = actual SL distance x RRMultiple, instead of ADRMultiplierTP/TakeProfit independently

input group "═══ WIDE_SL_BE BRANCH (2026-09-10): wide initial SL, shrink to breakeven ═══"
// Rationale (from candB_815t/candC_1002t single-run MFE/MAE audits, 2026-09-10):
// winners still dip a median 0.53R / p90 0.99R against the position before
// recovering -- a uniformly tighter initial SL would cut real winners, not
// just losers. Instead: widen the initial SL (give the trade more room to
// prove itself) and shrink it to breakeven once price has moved far enough
// in favor to demonstrate the trade is real. ~48-52% of eventual full losers
// in the audited data already touched >=0.5R profit before reversing all
// the way to a stop-out -- BE-move targets exactly that population.
// Fully isolated from TP1/TP2/trailing: independently toggleable, off by
// default so existing behavior is unchanged unless explicitly enabled.
input bool   UseWideSL          = false;  
input double WideSLMultiplier   = 1.5;    
input bool   UseBreakevenMove   = false;  
input double BreakevenTriggerR  = 0.5;    
input int    BreakevenBufferPts = 10;    

input group "═══ v6.16 (2026-09-10): STAGE-LINKED BE + IMMEDIATE TSL AFTER TP2 ═══"
// Different trigger than UseBreakevenMove above (that one fires at an
// independent R-fraction). This one is tied directly to the TP1/TP2 partial
// closes that already happen -- the same "stage" the EA already tracks.
// Plain-language: as soon as TP1 partial-closes (stage 1), snap the stop to
// just past entry (a few points of buffer so normal price wiggle doesn't
// clip it) -- the trade can no longer become a full loser. Then as soon as
// TP2 partial-closes (stage 2), start the trailing stop moving WITH price
// immediately instead of waiting for a separate point-distance trigger --
// the remainder either trails to a bigger win or gets stopped near TP2,
// never back at entry or worse. UseStagedBE and UseBreakevenMove are
// mutually exclusive in intent (both moving SL) -- test one at a time.
input bool UseStagedBE              = false; 
input int  BEBufferAfterTP1Pts      = 15;    
input bool TrailImmediatelyAfterTP2 = false; 
// 2.2 NEW (2026-10-01): ratchets the SL up progressively in the TP1->TP2
// window (stage==1, BE already set by UseStagedBE), instead of leaving the
// SL frozen at breakeven until TP2 fires. Mirrors the EXACT same trailing
// math as the post-TP2 trailing block below (TrailingDistance points behind
// price, only ever improves -- never loosens -- the stop), just active one
// stage earlier. Default false = byte-for-byte identical to 2.1 (and to the
// rest of 2.2 with this off) -- zero risk to existing .set files. Only
// meaningful when UseStagedBE=true and g_ExitMode==EXIT_RR_PARTIAL; a no-op
// otherwise since there is no TP1->TP2 window to trail inside.
input bool UseTrailBetweenTP1TP2    = false;
input double RRMultiple    = 3.0;    

input group "═══ MAX TRADE AGE / TIME-STOP (2026-09-19) ═══"
// User observation (real validation run, EntryPreset=4/SCALP-NATIVE#1 GA winner):
// median hold time 188min/3.1h, mean 598min/10h, max 6328min/105h -- NOT
// scalper behavior despite the preset's name, and win% climbs steadily with
// hold duration (<30min=18.5%, 30min-2h=24.4%, 2h-8h=29.4%, 8h-24h=47.4%,
// >24h=54.1%) -- strongly suggesting many losers are fast, low-conviction
// SL hits dragging the average down, not genuinely bad setups. This is a
// NEW, independent lever (time in trade) that nothing else in this file
// controls -- existing exits are all price-distance-based (TP/SL/trailing),
// none are duration-based. Reuses the MFE-tracker's existing per-ticket
// g_mfeBarsElapsed[] bar counter (already computed every tick for
// mfe_price/mae_price logging) -- zero new per-tick cost, just a threshold
// check in ManageStagedProfits(). Off by default (MaxTradeAgeBars=0), so
// this is a pure opt-in addition, zero behavior change unless swept on.
input bool UseMaxTradeAge   = false;   // master switch, off by default
input int  MaxTradeAgeBars  = 0;       // close the position at market if still open after this many CLOSED bars since entry (0 = disabled, no matter what UseMaxTradeAge says)
input bool MaxTradeAgeOnlyIfLosing = true;  // if true, the age-stop only fires while the position is currently underwater (protects winners that are just taking their time -- e.g. the 24h+ bucket's 54.1% win rate above) -- if false, closes ANY position past the age limit regardless of current P&L

input group "═══ REGIME 2.0: STOP BASIS + ADR EXHAUSTION ═══"
// SL_ATR is the new-branch default (pick B). Kumo-edge override still applies
// on top of whichever basis is selected. g_UseADRExhaustionFilter (pick C) reads
// ADR as ENTRY CONTEXT even when the stop itself is ATR-based — the two
// picks do not conflict. Exhaustion skips TREND entries only, never CT.
input ENUM_STOP_BASIS StopBasisMode          = SL_ADR;  // AGILE: adr * ADRMultiplierSL. SL_ATR is opt-in (isolation 1.5× was 5× churn)
input int             ATRStopPeriod          = 14;
input double          ATRStopMultiplier      = 1.5;
input bool            UseADRExhaustionFilter = false;  // isolation: this knob HURT vs parity; off by default
input double          ADRExhaustionPct       = 0.85;  // skip trend entry when today's realized range >= this fraction of ADR

input group "═══ POST-STOP COOLDOWN (2026-09-02, added after live whipsaw loss) ═══"
// 2026-09-02: BAL/LT stopped out by trailing stop at 13:19:45-48, then
// re-entered SAME direction on the very next bar (13:20:00) into what was
// still choppy price action, got stopped out again 7 min later for a much
// bigger loss (SL distance on the re-entry was only 7pts vs ~76-108pts on
// the original entry -- see MinSLDistanceFilter below for the other half
// of this fix). This cooldown blocks same-direction re-entry for N bars
// after a stop-loss hit on this MagicNumber, giving choppy conditions time
// to resolve before trying the same side again.
input bool UseCooldownAfterSL   = true;
input int  CooldownBarsAfterSL  = 3;      // bars to block same-direction re-entry after this MagicNumber's position is stopped out

input group "═══ MIN SL DISTANCE SANITY FILTER (2026-09-02) ═══"
// Companion fix to the cooldown above: an anomalously tight ADR/Kumo-derived
// SL (e.g. 7pts when this symbol's recent trades have averaged 70-100pts) is
// usually a sign the ADR/Kumo reading is stale or unrepresentative for
// current volatility, not a genuinely tighter opportunity -- and since
// CalculateLotSize() scales lot size UP to hold constant $ risk, a too-tight
// SL means a much LARGER position on a low-confidence read. Skip the entry
// instead. Uses a rolling average of this MagicNumber's own recent real SL
// distances, so it's self-calibrating per symbol/config rather than a fixed
// point threshold.
input bool   UseMinSLDistanceFilter = true;
input double MinSLDistanceFraction  = 0.4;   // skip entry if candidate SL distance < this fraction of the rolling average
input int    SLDistanceHistoryLen   = 20;    // rolling window size (number of past trades averaged)
input int    SLDistanceMinSamples   = 5;     // don't apply the filter until at least this many real trades are on record
input int    SLDistanceMaxStaleBars = 500;   // SELF-LOCK FIX (2026-09-18): the rolling average only updates when a real trade opens -- if MinSLDistanceFraction is set high (e.g. >=0.8) and a volatility regime shift makes every new candidate's SL fail the bar, the average can NEVER update again (nothing opens -> nothing records -> average stays frozen forever). Confirmed via a real single-run validation: MinSLDistanceFraction=1.1 caused a genuine PERMANENT lockout from Feb to Aug on a 2026 GOLD_test run, while the genetic-optimizer XML claimed 100 trades for the same params (the XML result did not reproduce -- see session notes). Fix: if this many bars pass with zero updates to the rolling average, treat it as stale and stop enforcing the filter (allow the next candidate through) until a fresh real trade re-establishes a current average. 0 = disable this safety net (old, lockable behavior).

input group "═══ HEARTBEAT & DIAGNOSTIC LOGGING (2026-09-04) ═══"
// Added after the EA appeared to "stop trading" on demo -- root cause was an
// unrelated Tester /config launch restarting the whole terminal and closing
// the live charts, but there was no way to tell that from the logs alone
// (no periodic proof-of-life independent of bar closes/trades). These three
// logs are deliberately separate from LogBot1Candidates/LogBot1Trades so they
// can stay on permanently in production without the per-bar candidate-log
// volume -- heartbeat is time-interval-driven, regime-events is
// transition-driven (near-zero row count unless something actually changes).
input bool LogBot1Heartbeat         = true;
input int  HeartbeatIntervalSeconds = 300;    // proof-of-life row every N seconds, independent of bars/trades/ticks
input bool LogBot1RegimeEvents      = true;   // event-driven: only writes a row when a gate/regime/cooldown STATE actually changes
input bool LogRegime2Diagnostics    = true;   // Regime 2.0: per-bar [BOT1-R2-*] prints + diag CSV. Skipped under MQL_OPTIMIZATION.

input group "═══ FTMO PROTECTION ═══"
// v5.97 (2026-08-31): FIXED a scale-mismatch bug. InitialBalance/
// MaxDailyLossAmount/MaxOverallLossAmount were flat-dollar constants
// calibrated for a $10,000 reference account (10000/500/1000), but the
// real Tester deposit is 100,000 PLN (confirmed via
// TesterStatistics(STAT_INITIAL_DEPOSIT) and the account's own currency).
// This silently clamped CalculateLotSize()'s per-trade risk to a fixed
// ~$200 ceiling (MaxDailyLossAmount x MaxRiskPerTradeFraction) REGARDLESS
// of RiskPercent or account size -- confirmed via a real optimization
// report where every RiskPercent value 0.25-2.0 produced byte-identical
// trade counts/profit, because CalculateLotSize's hard-dollar cap bound
// every value to the same lot size. Converted to percentage-of-balance,
// matching the pattern OnTester()'s DD gates already used correctly
// (OptMaxDDPctAllowed/OptMaxDailyDDPctAllowed). This now scales correctly
// on any account size -- $10k demo, 100k PLN, or a real funded account --
// without needing to hand-tune dollar constants per account.
input double MaxDailyLossPct    = 5.0;   // daily loss ceiling as % of the day's starting balance -- matches FTMO's actual daily-loss rule directly
input double MaxOverallLossPct  = 10.0;  // overall loss ceiling as % of the EA's starting balance -- matches FTMO's actual overall-loss rule directly
input double MaxRiskPerTradeFraction = 0.5;  // a single trade may use at most this fraction of the REMAINING daily loss budget -- unchanged in meaning, now scales off a % budget instead of a flat $ one

input group "═══ ENTRY FILTERS (MORE FLEXIBLE!) ═══"
// v6.17-v6.22 EntryPreset/RegimePreset enums REMOVED in 2.2 (preset cleanup --
// see header comment). Every Use* boolean below is now independently sweepable
// with zero preset-induced override confound. Non-essential indicator-derived
// inputs relocated to the bottom of this input list (see "MISC / LEGACY" group).
//
// RE-ADDED 2026-10-11 (user request: "remember about having new on custom from
// 2.0 to 2.2"): EntryPreset/RegimePreset PORTED BACK from 2.0, byte-identical
// definitions/values/comments. Default PRESET_MANUAL/REGIME_MANUAL = exactly
// 2.2's current preset-free behavior, zero change to any existing .set file
// unless a sweep deliberately sets EntryPreset/RegimePreset != 0. Reason to
// re-add rather than leave removed: lets a SCORE_WINRATE sweep on THIS EA
// explore the same proven entry-signal families 2.0's win-rate candidates came
// from (PRESET_A/C in particular -- the families behind 1250/816 and
// 3257/4099/2164/3965/865), now combined with 2.2's RegimeConfirmBars
// persistence filter, which did not exist when those 2.0 candidates were found.
enum ENUM_ENTRY_PRESET {
   PRESET_MANUAL = 0,  // use the individual Use* ticks below, unchanged
   PRESET_A      = 1,  // sweep4 M15 winner family: PSAR+EMACross+SuperTrend, L3=EXCLUDE, Bollinger+Donchian
   PRESET_B      = 2,  // sweep5b M5 candD family: PSAR+EMACross (no SuperTrend), full L2 vote, L3=EXCLUDE, OBV+Retest+VWAP
   PRESET_C      = 3,  // sweep3 alt family: PSAR+EMACross+SuperTrend+EMA200Bias, L3=CONFIRM, VWAPReclaim only
   PRESET_D      = 4,  // SCALP-NATIVE #1 (2026-09-14): fast-only L1 (PSAR+EMACross, no SuperTrend -- ATR(14)x3
                        // HTF band is a swing-speed filter, deliberately dropped here), light single-voter L2
                        // (RSI only -- fastest oscillator, no MACD/ADX lag), L3=VWAPReclaim only (reacts same-bar
                        // to price crossing session VWAP, no lookback window like Bollinger/Donchian need)
   PRESET_E      = 5   // SCALP-NATIVE #2 (2026-09-14): PSAR-only L1 (single fastest trend read, no confirmation
                        // lag from a 2nd voter), L2=ADX+RSI (strength+momentum, both fast), L3=Retest (precise
                        // pullback-and-hold entry -- more selective/precise than a raw breakout, matches "precise
                        // entries" request over "any signal fires")
};
input ENUM_ENTRY_PRESET EntryPreset = PRESET_MANUAL;  // sweep this instead of 17 individual booleans to explore proven combos
// RegimePreset -- same idea as EntryPreset, applied to the 10 Regime Suite voters
// (ADX/ER/CHOP/LinReg/ATRRatio/MMI/Session/ATRBandGate/ATRSpikeFilter/AsianRangeFilter)
// + RegimeSuiteVoteMode. Lets ONE int dimension explore 5 interpretable regime-filter
// combos instead of a 2^10 combinatorial explosion.
enum ENUM_REGIME_PRESET {
   REGIME_MANUAL      = 0,  // use individual UseRegime*/UseATR*/UseAsianRange ticks below, unchanged
   REGIME_NONE         = 1,  // all 10 voters OFF -- trade every session/volatility state, no regime gating at all
   REGIME_SESSION_ONLY = 2,  // ONLY UseRegimeSession=true (London/NY hours) -- tests if scalp edge is session-dependent
   REGIME_VOL_BAND     = 3,  // ONLY UseATRBandGate+UseATRSpikeFilter -- avoid dead-quiet AND panic-spike bars, trade the middle
   REGIME_TREND_ONLY   = 4,  // ONLY UseRegimeADX+UseRegimeER (trend-strength duo) -- classic "only trade when trending" filter
   REGIME_KITCHEN_SINK = 5   // ADX+ER+MMI+Session, RS_VOTE_MAJORITY -- broad multi-voter gate, majority so one dissenter doesn't veto
};
input ENUM_REGIME_PRESET RegimePreset = REGIME_MANUAL;  // sweep this instead of 10 individual regime-voter booleans

input bool UseStrictLayers = false;
input int Layer1MinConfirmations = 2;      // Need 2/3 from Layer 1 (was 3/3)
input int Layer2MinConfirmations = 1;      // Need 1/3 from Layer 2 (was 2/3)
input int Layer3MinConfirmations = 1;      // Need 1/3 from Layer 3 (was 2/3)

input group "═══ VOLATILITY FILTER (CRITICAL) ═══"
// v5.94 (2026-08-29): ATRShortPeriod/ATRLongPeriod removed -- this filter
// was computing ATR(short=5)/ATR(long=20) via its OWN indicator handles
// (atrShortHandle/atrLongHandle), while the Regime Suite's g_UseRegimeATRRatio
// below computed the IDENTICAL ratio (RegimeATRFastPeriod=5/RegimeATRSlowPeriod=20,
// same defaults) via a SEPARATE pair of handles. Two independent readings of
// the same underlying concept could silently drift or disagree, and
// IsMarketTradable() (this filter, always active regardless of
// g_UseRegimeSuiteGate) ran completely unaware of what the Regime Suite's vote
// concluded -- plausible cause of the "AND-suite measured worse than doing
// nothing" result in Round 16, since the suite was never actually tested in
// isolation; this always-on gate was fighting/double-counting with it the
// whole time. Now GetVolatilityRatio() reads the SAME regimeAtrFastHandle/
// regimeAtrSlowHandle the suite uses (allocated whenever either this filter
// or g_UseRegimeATRRatio is enabled) -- one ATR ratio number, two decision
// layers reading it: this filter's 3-way TRENDING/RANGING/LOW_VOL
// classification (always-on hard gate, richer than a binary vote) and the
// Regime Suite's binary trending vote (opt-in, part of RegimeSuiteVoteMode).
// Set RegimeATRFastPeriod/RegimeATRSlowPeriod below to change the shared period.
input bool UseVolatilityRatio = true;
input double VolatilityRatioTrendMin = 1.15;
input double VolatilityRatioRangeMax = 1.1;
input double VolatilityRatioRangeMin = 0.9;
input double VolatilityRatioLowVol = 0.8;
input bool TradeTrendingOnly = false;
input bool AvoidLowVol = true;
input bool AvoidRanging = false;

input group "═══ Layer 1: Baseline (HTF) — tick = live vote ═══"
// Tick the engines that vote. SuperTrend-only = ONLY UseSuperTrend=true (EMA200 is a separate tick).
// No Layer1Mode enum: the ticks are the engine. Need  Layer1MinConfirmations of the ticked set (capped at majority if more).
input bool UseIchimoku = true;
input bool UsePSAR = true;
input bool UseEMACross = false;            // EMA50/EMA200 cross (not the same as EMA200 bias)
input bool UseSuperTrend = false;          // HTF ATR(14)×3.0 SuperTrend
input bool UseEMA200Bias = false;          // price vs EMA200 on HTF — tick this IN ADDITION if you want it with SuperTrend
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H1;
input int IchimokuTenkan = 9;
input int IchimokuKijun = 26;
input int IchimokuSenkou = 52;
input bool UseChikou = true;
input bool UseKumoTwist = true;
input int EMAFastPeriod = 50;
input int EMASlowPeriod = 200;
input double PSARStep = 0.02;
input double PSARMax = 0.2;
input int    SuperTrendATRPeriod   = 14;
input double SuperTrendMultiplier  = 3.0;
input int    SuperTrendWarmupBars  = 80;

input group "═══ Layer 2: Momentum — tick = live vote (none ticked = L2 not in gate) ═══"
// AGILE live path does NOT use L2. Defaults are all false so ticks-are-live matches AGILE.
// Tick MACD (only) to require MACD. Tick several to vote Layer2MinConfirmations of them.
input bool UseMACD = false;
input bool UseRSI = false;
input bool UseADX = false;
input bool UseLayer2CCI = false;
input int ADXPeriod = 14;
input double ADXThreshold = 20.0;
input int MACDFast = 12;
input int MACDSlow = 26;
input int MACDSignal = 9;
input ENUM_APPLIED_PRICE MACDPrice = PRICE_CLOSE;
input int RSIPeriod = 14;
input double RSIMomentumLevel = 50.0;
input ENUM_LAYER2_RSI_MODE Layer2RSIMode = RSI_LEVEL50;
input double RSIOverbought = 75.0;
input double RSIOversold   = 25.0;
input bool   UseADXSlope        = false;  // when UseADX: slope+DI instead of ADXThreshold+DI
input int    ADXSlopeLookback   = 3;
input int    Layer2CCIPeriod    = 20;
input bool   PreferCCIInTrend   = false;  // extra substitution RSI<->CCI; leave false unless you mean it

input group "═══ Layer 3: Triggers — tick engines, then pick Off / Confirm / Exclude ═══"
// Layer3Gate=Off: ticks do not block entries (AGILE). Confirm: L3 must match L1. Exclude: skip when L3 passes.
// Do not use Confirm together with any Layer 2 tick (OnInit will demote Confirm → Exclude).
input ENUM_LAYER3_GATE Layer3Gate = L3_GATE_OFF;
input bool UseBollinger = false;
input bool UseOBV = false;
input bool UseDonchian = false;
input bool UseRetest = false;              // Donchian break then pullback-and-hold
input bool UseVWAPReclaim = false;         // session VWAP reclaim/rejection
input int BollingerPeriod = 20;
input double BollingerDev = 2.0;
input int DonchianPeriod = 20;
input int    RetestExpireBars   = 8;
input int    VwapAnchorHour     = 8;
input double VwapDevSigma       = 2.0;

input group "═══ Time Filter ═══"
input bool UseTimeFilter = false;
input string StartTime = "00:00";
input string EndTime = "23:59";
input bool AvoidFriday = true;
input int FridayCloseHour = 16;

input group "═══ REGIME KILL SWITCH (branch feature, 2026-08-11) ═══"
// BRANCH, not mainline: this whole group is new to this file, defaults to
// OFF so behavior is byte-for-byte identical to v5.9 unless deliberately
// enabled. Built in response to Round 12's finding: 819/819 TP-stack combos
// were profitable back, 0/819 profitable forward, with tight clustering --
// no exit-parameter tuning escaped it, meaning something about the market
// itself changed rather than any parameter being wrong. Deliberately does
// NOT try to classify market regime from an external indicator (ADX/ATR/
// etc) -- this project's own history shows that approach already failed
// once (GoldGuardian's trend/range branch lost money OOS in both ON and
// OFF conditions, removed). Instead this watches the STRATEGY'S OWN rolling
// realized performance and suppresses new entries when it degrades -- "stop
// trading when the edge stops working," not "predict when it will."
input bool   UseRegimeKillSwitch = false;   // OFF by default -- branch is inert until explicitly turned on
input int    RegimeLookbackTrades = 15;     // rolling window of most recent FULLY CLOSED positions (not partial legs)
input double RegimeMinWinRate = 0.30;       // suppress new entries if rolling win rate over the lookback window falls below this
input int    RegimeProbeIntervalBars = 500; // v2 fix: while suppressed, let exactly one signal through every N bars as a "probe" so the rolling window can keep updating -- without this, suppressing entries also stops the trade outcomes needed to ever re-evaluate, and the switch can never release itself once tripped. ~500 M5 bars is roughly 1.7 days; tune to taste.
input bool   LogRegimeKillSwitch = true;    // print once each time the switch trips or releases -- this IS the diagnostic requested: read these timestamps directly off a single full-period run to see exactly when the strategy's own edge degraded, no external price data needed

input group "═══ RANGE MODE ADAPTATION (branch v3, 2026-08-11) ═══"
// v3: Round 13 showed suppressing entries while the regime detector is
// active makes things WORSE once the trade-management bugs are fixed
// (fwd PF 0.92 suppressed vs 1.08 doing nothing) -- the "regime change"
// symptom turned out to be substantially the old exit bugs, not a
// persistent market shift needing a hard stop. This tests a different
// response: instead of refusing to trade, trade DIFFERENTLY -- swap the
// normal ADR-based trend stops/staged exits for a tight, symmetric
// SL/TP band while the detector is active, on the theory (yours) that
// the period the detector fires in behaves more like a ranging market
// than a trending one. Distinct from GoldGuardian's failed regime
// gating: that branched ENTRY logic on a predicted external regime
// classification; this leaves entries untouched (still the same L1/L2/L3
// signal) and only changes exit placement, triggered by the strategy's
// own observed performance rather than a predicted indicator state.
input bool UseRangeModeAdaptation = false;   // OFF by default. If true, a tripped kill switch no longer suppresses entries -- it switches new entries to the range-mode SL/TP below instead. If UseRegimeKillSwitch=false, this has no effect (nothing ever trips).
input int  RangeModeSL_Points = 40;          // symmetric SL distance in points from entry, replaces the ADR/Kumo-based stop for entries opened while the detector is active
input int  RangeModeTP_Points = 40;          // symmetric TP distance in points from entry, replaces UseADR's TP. Keep this smaller than TP1_Distance -- if it isn't, the order-level TP won't fire before the staged TP1/TP2 system would have, and the two systems will interleave in ways this branch doesn't explicitly handle.

input group "═══ COUNTER-TREND MODULE (v2 AGILE, 2026-09-06) ═══"
// The single biggest architectural gap in every branch to date: when the
// regime suite calls a period "ranging," the ONLY responses ever built are
// (a) suppress entries entirely (v2 default) or (b) keep the SAME L1
// trend-following signal but with a tighter symmetric bracket (v3
// UseRangeModeAdaptation) -- neither one is a genuinely DIFFERENT source of
// profit for that condition, they're both just "do less of the trend
// strategy." bot4's own research (see bot4_EA_Optimization_Knowledge.md
// §8) found that tuning EXITS cannot manufacture more-distributed profit
// out of a fundamentally trend-following entry logic -- the fix has to be
// a genuinely different ENTRY mechanism for ranging conditions, not more
// exit-tuning on the same signal. This module is that: an independent,
// opt-in mean-reversion entry (Bollinger-band extreme + RSI reversal
// confirmation, using indicators ALREADY loaded for L2/L3 -- no new
// indicator handles) that ONLY fires when the regime suite says ranging,
// runs under its OWN MagicNumber offset (so it never contends with
// MaxBuyPositions/MaxSellPositions/OneTradePerBar accounting for the trend
// side), and uses the SAME fixed symmetric SL/TP bracket already built for
// range mode (RangeModeSL_Points/RangeModeTP_Points) rather than a new exit
// mechanism -- deliberately simple, no staged partials/trailing, since a
// mean-reversion trade in a genuinely ranging market is a much shorter,
// smaller-target trade by design.
//
// Reuses the SAME cooldown-after-SL and min-SL-distance-outlier guards the
// trend side already has (both keyed by MagicNumber, so this module's own
// history is tracked independently from the trend side's) -- no bypass of
// either safety mechanism just because this is a "different" signal type.
//
// Requires g_UseRegimeSuiteGate=true to ever fire (it has no meaning without
// a regime verdict to react to) -- defaults OFF, zero effect on existing
// bot1 behavior until explicitly enabled.
input ENUM_CT_MODE CTMode = CT_OFF;        // OFF = module off. ON_WHEN_RANGE = fire only when a regime tick is on AND suite says RANGE
input bool   UseCounterTrendModule   = false;   // also forced from CTMode in OnInit; leave false unless CTMode=ON_WHEN_RANGE
input int    CounterTrendMagicOffset = 900;     // this module's positions use MagicNumber+CounterTrendMagicOffset -- keeps them fully separate from trend-side position counting/cooldown/SL-history
input double CounterTrendRSIOversold  = 25.0;   // MEAN-REVERSION: RSI below this = BUY candidate. Opposite of L2 RSIOverbought-as-bull.
input double CounterTrendRSIOverbought= 75.0;   // MEAN-REVERSION: RSI above this = SELL candidate. Opposite of L2 RSIOverbought-as-bull.
input double CounterTrendLotSize      = 0.01;   // fixed lot -- deliberately NOT wired to CalculateLotSize()/RiskPercent, keeps this module's risk trivially small and independent of the trend side's sizing while it's unproven
input int    CounterTrendMaxPositions = 1;      // max concurrent counter-trend positions (own count, independent of MaxBuyPositions/MaxSellPositions)
input bool   RequireCloseBackInsideBand = true; // pick C: don't fire on raw band-touch; wait for a close back inside
input bool   UseStochasticTrigger       = true; // pick D: Stochastic %K extreme as alternative CT trigger (same polarity as CT RSI)
input int    StochKPeriod               = 14;
input int    StochDPeriod               = 3;
input int    StochSlowing               = 3;
input double StochOversold              = 20.0;
input double StochOverbought            = 80.0;
input bool   UseVWAPDeviationTrigger    = true; // pick E: fade session VWAP ± VwapDevSigma — REUSES GetSessionVWAP(), no second VWAP

input group "═══ REGIME DETECTION SUITE (branch v4, 2026-08-11) ═══"
// Six independently-toggleable, literature-standard trend-vs-range filters
// plus a session filter, researched specifically for gold M5 regime
// detection. Each defaults OFF and costs ~nothing when disabled -- same
// "if(!Use...) return early" discipline as every other filter in this
// file. When g_UseRegimeSuiteGate=true, the suite's combined verdict is OR'd
// into the SAME suppress/adapt trigger the win-rate kill switch already
// uses -- so UseRegimeKillSwitch and g_UseRegimeSuiteGate can be tested
// alone or together.
//
// Filters combine with AND logic: ALL enabled filters must agree
// "trending" for the suite to call the regime trend-favorable -- any one
// enabled filter can veto. This is the standard confluence-gate pattern;
// deliberately conservative rather than a majority vote.
// Tick the voters that participate. None ticked = suite OFF (AGILE).
// UseRegimeLEAN4 is the isolation survivor (ADX-slope + CHOP + BB-width% + session).
// Do not also tick SuperTrend-only L1 as a "default stack" with LEAN4.
input bool UseRegimeLEAN4 = false;         // force the 4 lean voters; ignores other UseRegime* ticks
input int    BBWidthLookback        = 100;
input double BBWidthPctileTrendMin  = 50.0;  // LEAN4: current BB width percentile >= this = trending (expansion)

input group "── Regime Suite: ADX/ADXR (trend strength) ──"
input bool UseRegimeADX = false;
input int  RegimeADXPeriod = 14;         // Wilder's standard period
input double RegimeADXTrendMin = 25.0;   // ADXR >= this = trending (Wilder's own cutoff; 20 is the more lenient alternative some traders use)

input group "── Regime Suite: Kaufman Efficiency Ratio ──"
input bool UseRegimeER = false;
input int  RegimeERPeriod = 14;
input double RegimeERTrendMin = 0.35;    // ER >= this = trending (net directional move / total path length, 0-1)

input group "── Regime Suite: Choppiness Index ──"
input bool UseRegimeCHOP = false;
input int  RegimeCHOPPeriod = 14;
input double RegimeCHOPRangeMax = 61.8;  // CHOP >= this = ranging (Fibonacci cutoff, Dreiss' original); trending requires CHOP below it

input group "── Regime Suite: Linear Regression R² ──"
input bool UseRegimeLinReg = false;
input int  RegimeLinRegPeriod = 20;
input double RegimeLinRegR2Min = 0.20;   // R² >= this = trending (fraction of price variance explained by the fitted line, 0-1)

input group "── Regime Suite: ATR fast/slow ratio ──"
input bool UseRegimeATRRatio = false;
input int  RegimeATRFastPeriod = 5;
input int  RegimeATRSlowPeriod = 20;
input double RegimeATRRatioMin = 1.0;    // fast/slow ATR >= this = volatility expansion (trend-supportive). v5.94: shares handles/periods with UseVolatilityRatio's GetVolatilityRatio() -- one ATR-ratio computation feeding both this suite's binary vote and that filter's 3-way gate.

input group "── Regime Suite: Market Meanness Index ──"
input bool UseRegimeMMI = false;
input int  RegimeMMILookback = 100;      // Financial Hacker's original default is 200; reduced here to bound the per-bar sort cost. Override for the original scale if you want it.
input double RegimeMMITrendMax = 47.0;   // MMI <= this = trending (falling MMI = trend developing, per Lotter). RECALIBRATED 2026-08-15: the textbook ~75 random-walk baseline did not hold for this reimplementation on GOLD_test M5 (observed range 28.3-61.6, mean 45.3, confirmed via smoke-test log analysis -- the original 65.0 default sat above the entire observed range, making the filter a permanent no-op). 47.0 sits near this distribution's mean/p50, giving the filter actual discriminating power. Re-validate if you change symbol, timeframe, or lookback.

input group "── Regime Suite: Session Filter (Stage 2) ──"
input bool UseRegimeSession = false;
input int  RegimeSessionStartHour = 7;   // broker/server time -- London-open area. Adjust to your broker's server timezone.
input int  RegimeSessionEndHour = 16;    // through the London/NY overlap close -- narrows out the low-liquidity Asian session where gold tends to chop

input group "── Regime Suite: Diagnostics ──"
input bool LogRegimeSuiteDiagnostics = false;   // prints every enabled filter's raw value + verdict once per bar. This IS the validation tool -- read it and confirm the numbers look sane before trusting the gate.

input group "── Regime Suite: ATR Floor/Ceiling Band (community-sourced) ──"
// v5.94: merged from the former separate "Community Filters" group --
// UseCommunityFilterGate is retired, this is now just another voter in
// g_UseRegimeSuiteGate's unified vote (RegimeSuiteVoteMode) below.
// "ATR filter" / "volatility filter" / "dead-market filter" -- generic
// community rule: only trade while ATR sits inside a sane band, avoiding
// both dead-quiet chop (too low) and news-driven blowouts (too high).
// Values are on the EA's own trading timeframe.
// RECALIBRATED 2026-08-17 from smoke-test log analysis (39,557 diagnostic
// bars, GOLD_test M5, full 2026 H1): observed ATR range was 125.9-8160.2
// points -- the original 30.0 floor sat below the entire distribution
// (would have blocked 0 bars, a silent no-op, same failure class as the
// v4.1 MMI threshold). Floor recalibrated to 250.0 (~p4 of the observed
// distribution, blocks ~3.6% of the lowest-volatility bars -- a modest,
// meaningful prune rather than either a no-op or an overly aggressive
// cut). Ceiling was NOT a no-op (p90=1106, p95=1479, p99=2798 -- 1000.0
// already sits just below p90 and blocked 12.5% of bars in the same run,
// closely matching that percentile) -- left unchanged, already doing real
// work. Re-validate both if you change symbol, timeframe, or period.
input bool   UseATRBandGate = false;
input int    ATRBandPeriod = 14;
input double ATRBandFloorPoints = 250.0;
input double ATRBandCeilingPoints = 1000.0;

input group "── Regime Suite: ATR Spike Filter (exact community rule, M1-based) ──"
// Verbatim rule from MQL5 forum thread 504875: "ATR(M1, 2) >= ATR(M1,
// 1440) x 2 -> Do not take trade" -- comparing a 2-bar M1 ATR to the
// trailing 24-hour (1440-bar M1) average. Implemented on M1 exactly as
// described, via dedicated handles, regardless of the EA's own trading
// timeframe -- this is a spike/news-shock detector, not a regime
// classifier, and the source was explicit about the M1 basis.
input bool   UseATRSpikeFilter = false;
input int    ATRSpikeShortPeriod = 2;
input int    ATRSpikeLongPeriod = 1440;
input double ATRSpikeMultiplier = 2.0;

input group "── Regime Suite: Asian Range vs Daily ATR (GoldLondonBreakout rule) ──"
// From the free MQL5 CodeBase EA "GoldLondonBreakout" (#75586, XAUUSD,
// published 2026-08-01) -- its published defaults, ported directly:
// track the Asian-session high/low, then for the REST of that calendar
// day, only allow trading if that range falls between 0.15x and 0.70x
// the Daily ATR(14). Too tight = dead session, unlikely to break out
// meaningfully; too wide = already-blown-out/news day, chasing a move
// that's largely over. The verdict is computed once per day, when the
// Asian window closes, and held for the remainder of that day -- not
// re-evaluated bar by bar (matches the source's "skip the day" design).
input bool   UseAsianRangeFilter = false;
input int    AsianRangeStartHour = 0;     // broker/server time
input int    AsianRangeEndHour = 7;
input int    AsianRangeDailyATRPeriod = 14;
input double AsianRangeMinFrac = 0.15;
input double AsianRangeMaxFrac = 0.70;


input group "═══ Display ═══"
input bool ShowLeftLegend = true;
input bool ShowRightLegend = true;
input int LegendFontSize = 8;              // Font size for legend

input group "═══ BOT1 Shadow Logging (POC) ═══"
input bool   LogBot1Candidates = true;     // log full signal snapshot every bar-close
input bool   LogBot1Trades = true;         // log trade lifecycle (open/TP1/TP2/trail/close)
input string Bot1FilePrefix = "bot1r22";   // OWN prefix (was "bot1r21" in 2.1) -- prevents CSV file-lock collisions, keeps 2.2's Tester/live logs in dedicated files, never mixed with 2.0's/2.1's/test4's
input bool   LogBot1Postmortem = true;     // track price for N bars after every full close -- validates whether SL-hit trades reverse or keep trending, BEFORE building any recovery/pyramid logic
input int    Bot1PostmortemBars = 20;      // bars to track after close (separate CSV, does not touch bot1_trades_*.csv)
input bool   LogBot1L2L3Diagnostics = true; // ONE consolidated line per bar (not per-indicator) showing raw MACD/RSI/ADX/Bollinger/OBV/Donchian values + ichi/psar -- added 2026-07-21 to check whether any of these are silently "stuck" the way Ichimoku's Chikou requirement was. Same once-per-bar cadence as the existing [BOT1-L1] print, not a new spam source. Turn off once the investigation concludes.

input group "═══ BOT1 Shadow POOL (multi-trade MFE/MAE sample builder, 2026-09-25) ═══"
// SEPARATE on/off switch from LogBot1Candidates -- this is a different feature
// (a POOL of many concurrent hypothetical trades, not the single g_shadowActive
// simulation above) built specifically to solve the "only 3 actionable trades in
// 28 real ones" sample-size problem found in the 2026-09-24 MFE/MAE forensic
// analysis. Default OFF: this is new, unproven code -- must be explicitly
// switched on per the user's "switchable on/off" requirement, and should not
// change any existing live behavior when off (zero cost: every function below
// returns immediately at the top when this is false).
input bool   UseShadowPool           = false;  // master on/off for the shadow-trade POOL (independent of LogBot1Candidates)
input int    ShadowPoolMaxConcurrent = 8;      // how many hypothetical trades can be "in flight" at once -- lets MULTIPLE overlapping shadow trades exist within/across the same bars, unlike the single g_shadowActive slot above
input bool   ShadowPoolEntryOnEveryBar = true; // open a new hypothetical trade on EVERY bar-close where l1_result != 0 (not gated by whether one is already active) -- this is what generates "multi trades within the bar" density; only capped by ShadowPoolMaxConcurrent
input bool   ShadowPoolTrackTickMFE  = true;   // if true, MFE/MAE for pool trades update on EVERY TICK (not just once per bar like the g_mfe* tracker) -- closes the "KNOWN FIDELITY GAP" noted on the existing shadow sim (bar-cadence checks miss intrabar TP/SL touches)
input string ShadowPoolFilePrefix    = "";     // empty = reuse Bot1FilePrefix; set to isolate pool logs from the main trade/shadow logs entirely

//+------------------------------------------------------------------+
//| GLOBALS                                                          
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
COrderInfo order;

int ichimokuHandleHTF = INVALID_HANDLE;
int ichimokuHandleCur = INVALID_HANDLE;
int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;
int psarHandle = INVALID_HANDLE;
int macdHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;
int bollHandle = INVALID_HANDLE;
int obvHandle = INVALID_HANDLE;
int superTrendAtrHandle = INVALID_HANDLE;   // HTF ATR for hand-rolled SuperTrend
int atrStopHandle = INVALID_HANDLE;         // chart-TF ATR for SL_ATR
int cciHandle = INVALID_HANDLE;
int stochHandle = INVALID_HANDLE;

// v6.11: g_* are the live path. Copied from Use* ticks in OnInit (inputs are read-only).
ENUM_EXIT_MODE            g_ExitMode;
ENUM_CT_MODE              g_CTMode;
ENUM_LAYER3_GATE          g_Layer3Gate;
ENUM_LAYER2_RSI_MODE      g_Layer2RSIMode;
ENUM_STOP_BASIS           g_StopBasisMode;
bool   g_RequireL2ForLive;
bool   g_RequireL3ForLive;
bool   g_ExcludeWhenL3Fires;
bool   g_UseRegimeSuiteGate;
int    g_RegimeSuiteVoteMode;  // copied straight from input RegimeSuiteVoteMode (int, not enum -- avoids forward-decl issue since ENUM_REGIME_SUITE_VOTE is defined later in the file). No preset override in 2.2.
bool   g_UseIchimoku, g_UsePSAR, g_UseEMACross, g_UseSuperTrend, g_UseEMA200Bias;
bool   g_UseMACD, g_UseRSI, g_UseADX, g_UseADXSlope, g_UseLayer2CCI, g_PreferCCIInTrend;
bool   g_UseBollinger, g_UseOBV, g_UseDonchian, g_UseRetest, g_UseVWAPReclaim;
bool   g_UseCounterTrendModule;
bool   g_UseADRExhaustionFilter;
bool   g_UseStageExits;
bool   g_UseRegimeLEAN4;
bool   g_UseRegimeADX, g_UseRegimeER, g_UseRegimeCHOP, g_UseRegimeLinReg;
bool   g_UseRegimeATRRatio, g_UseRegimeMMI, g_UseRegimeSession;
bool   g_UseATRBandGate, g_UseATRSpikeFilter, g_UseAsianRangeFilter;
bool   g_RequireCloseBackInsideBand, g_UseStochasticTrigger, g_UseVWAPDeviationTrigger;
int    g_Layer1MinConfirmations, g_Layer2MinConfirmations, g_Layer3MinConfirmations;
int    g_TP1_Distance, g_TP2_Distance;
double g_TP1_ClosePercent, g_TP2_ClosePercent;
double g_RSIOverbought, g_RSIOversold;
double g_ATRStopMultiplier;
double g_ExitRR_TP1R, g_ExitRR_TP2R, g_ExitRR_Close1Pct;


// v5.94: regimeAtrFastHandle/regimeAtrSlowHandle (below) now serve BOTH
// UseVolatilityRatio (this file's always-on TRENDING/RANGING/LOW_VOL gate)
// AND g_UseRegimeATRRatio (the Regime Suite's binary vote input) -- one ATR
// ratio computation, two independent decision layers reading it. Previously
// two separate handle pairs computed the identical ratio; see the
// VOLATILITY FILTER input group comment for why that was a problem.
int regimeAdxHandle = INVALID_HANDLE;
int regimeAtrFastHandle = INVALID_HANDLE;
int regimeAtrSlowHandle = INVALID_HANDLE;

// ── REGIME 2.1 continuous score (v2, independent-ingredients redesign):
// no dedicated indicator handles needed -- ER/CHOP are computed directly
// from Copy{High,Low,Close}() (same technique as the 2.0 Regime Suite's own
// GetRegimeER()/GetRegimeCHOP(), but with 2.1's own period inputs so this
// module never shares state with the 2.0 Regime Suite toggles).
int    g_r21LogHandle = INVALID_HANDLE;
struct Bot1Regime21State {
   double erValue;         // Kaufman Efficiency Ratio, 0-1
   double chopValue;       // Choppiness Index, roughly 0-100 (high = congested)
   double sessionValue;    // 0-1 liquidity-window score, 1.0 inside the configured hours
   double compositeScore; // blended 0-1 continuous regime-strength score
   datetime barTime;
};
Bot1Regime21State g_r21;

// ── REGIME 2.1 v3: multi-indicator classifier state (separate from the v2
// blended score above -- this is deliberately NOT blended, each voter kept
// distinct per the user's explicit direction).
int g_r21BucketLogHandle = INVALID_HANDLE;
enum ENUM_REGIME21_BUCKET { R21_BUCKET_TREND, R21_BUCKET_CHOP, R21_BUCKET_MIXED };
struct Bot1Regime21BucketState {
   bool adxVote;      // true = trending, per RegimeADXTrending()
   bool erVote;
   bool chopVote;
   bool linRegVote;
   bool atrRatioVote;
   bool mmiVote;
   int  votersActive;   // how many of the 6 are actually enabled (UseRegime* on) -- majority is relative to this, not a fixed 6
   int  trendVotes;
   ENUM_REGIME21_BUCKET bucket;
   bool sessionActive;  // context only, not counted in the majority vote
   datetime barTime;
   // DIRECTIONAL LEAN (2026-09-19): the 6 voters above only answer "IS the
   // market trending", never "which way". User's own observation, confirmed
   // via a real data check: the SELL+TREND population's own L2 +DI/-DI
   // fields were 0/0 for every single trade in this branch's config (UseADX
   // toggle is L2-scoped, separate from the classifier's UseRegimeADX) --
   // i.e. the classifier genuinely had ZERO directional information behind
   // its "TREND" label the whole time. A bar can be correctly labeled TREND
   // while price is moving in EITHER direction, so a SELL could fire during
   // a real downtrend (correct) or during a strong UPTREND that still
   // scores as "trending" by ADX/ER/CHOP/etc (wrong-way) -- and nothing
   // caught the difference. direction is computed from 3 things already
   // available for free (LinReg slope sign -- was computed and thrown away
   // by RegimeLinRegTrending(), HTF EMA200 bias, HTF SuperTrend direction):
   // +1 = lean up, -1 = lean down, 0 = no majority lean.
   int  direction;
   int  directionVotes;      // how many of the 3 direction-capable signals agreed on the winning direction
   bool directionAgreesWithSignal;   // filled in per-trade at entry time by Bot1Regime21DirectionAgrees(), not here
   // REGIME-FLIP TIMING (2026-09-19): "how many bars ago did the bucket or
   // the direction last CHANGE". User's own idea -- rather than just
   // knowing the current label, catch the MOMENT the regime is switching,
   // since that's exactly where the fast PSAR/EMA entry logic tends to
   // fire ahead of the slower direction voters (see DISAGREE finding).
   int  barsSinceBucketFlip;      // 0 = bucket changed THIS bar; grows every bar it stays the same
   int  barsSinceDirectionFlip;   // same idea, for the 3-vote directional lean
};
Bot1Regime21BucketState g_r21b;

// Previous-bar state for flip detection -- separate from g_r21b itself so
// "this bar's read" vs "what it was last bar" can never be confused.
ENUM_REGIME21_BUCKET g_r21bPrevBucket = R21_BUCKET_MIXED;
int                  g_r21bPrevDirection = 0;
bool                 g_r21bFlipStateInit = false;   // first bar has no "previous" to compare against

// v5 branch: community-sourced filters (Stage 1: volatility, Stage 2:
// session/Asian-range). Dedicated handles, independent of every other
// ATR-based filter in this file.
int communityAtrBandHandle = INVALID_HANDLE;         // Stage 1a: ATR floor/ceiling, on the EA's own trading timeframe
int communityAtrSpikeShortHandle = INVALID_HANDLE;   // Stage 1b: M1 short-window ATR, per the exact community rule (M1 not M5)
int communityAtrSpikeLongHandle = INVALID_HANDLE;    // Stage 1b: M1 long-window (~24h) ATR
int communityDailyAtrHandle = INVALID_HANDLE;        // Stage 2b: D1 ATR, for the Asian-range-vs-daily-ATR fraction test

// Stage 2b state: Asian session high/low is tracked bar-by-bar during the
// configured window, then the day's tradeable/blocked verdict is computed
// once when the window closes and held for the rest of that day -- mirrors
// GoldLondonBreakout's "skip the day" semantics, not a per-bar re-evaluation.
datetime g_asianRangeTrackedDay = 0;    // which calendar day g_asianRangeHigh/Low belong to
double   g_asianRangeHigh = 0.0;
double   g_asianRangeLow = 0.0;
bool     g_asianRangeWindowSeen = false;    // true once at least one bar inside the Asian window has been tracked for the current day
bool     g_asianRangeVerdictComputed = false;   // true once this day's allow/block verdict has been finalized
bool     g_asianRangeDayAllowed = true;     // the day's verdict -- defaults to allowed until computed, and before the window has ever closed once in a fresh test

double adr = 0.0;
datetime lastBarTime = 0;
// v3 branch: set once per bar in CheckForTradingSignals, right before this
// bar's entry attempt (if any). Read by CalculateStopLoss/CalculateTakeProfit
// to decide whether THIS specific new entry uses the tight symmetric
// range-mode band instead of the normal ADR/Kumo-based stops. Known minor
// limitation: DrawLeftLegend's hypothetical SL/TP preview also calls these
// functions every tick for display purposes and will read whatever this
// flag was last set to -- cosmetic only (legend is skipped during
// non-visual optimization anyway since v5.3), not a real trading effect.
bool g_useRangeModeForThisEntry = false;
// PERF FIX (v5.5): tracks the D1 bar ADR was last computed for. v5.3 moved
// the CalculateADR() call from per-tick to per-M5-bar, which was the big
// win, but ADR only actually changes once per D1 bar -- on M5 that's still
// ~288 redundant recomputations of the same value every single day. Same
// pattern as the original bug, one level up.
datetime lastADRCalcDay = 0;

// PERF FIX: these four log files were previously FileOpen'd and FileClose'd
// on EVERY row write (every bar for candidates, every trade event for
// trades, etc). Held open for the life of the EA instead -- same file
// content and layout, no I/O overhead from constant reopen/reseek/close
// across months of bar/tick data. Opened lazily on first use, closed in
// OnDeinit.
int g_candidateLogHandle   = INVALID_HANDLE;
int g_tradeLogHandle       = INVALID_HANDLE;
int g_postmortemLogHandle  = INVALID_HANDLE;
int g_shadowTradeLogHandle = INVALID_HANDLE;
int g_heartbeatLogHandle   = INVALID_HANDLE;
int g_regimeEventLogHandle = INVALID_HANDLE;
int g_shadowOutcomeLogHandle = INVALID_HANDLE;
int g_r2DiagLogHandle        = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| REGIME 2.0 per-bar shared cache                                  |
//| Invalidated when the chart bar time changes. ADX-slope and VWAP  |
//| have TWO consumers each -- both MUST read these cached fields,   |
//| never recompute. [BOT1-R2-SHARE] dumps the canonical values.     |
//+------------------------------------------------------------------+
struct Bot1Regime2Cache {
   datetime barTime;
   bool     valid;
   double   adxSlope;
   double   adxValue;
   double   sessionVwap;
   double   vwapStdev;
   double   vwapUpper;
   double   vwapLower;
   double   bbWidthPctile;
   double   bbWidth;
   int      superTrendDir;     // 1/-1/0
   double   superTrendLine;
   int      ema200Bias;        // 1/-1/0 close vs slow EMA on HTF
   double   cciValue;
   int      cciSignal;
   double   stochK;
   double   atrStop;
   double   exhaustionFrac;    // today's range / ADR; 0 if ADR unavailable
   bool     exhaustionSkip;
   // Donchian retest state (persists across bars; not reset on cache miss)
};
Bot1Regime2Cache g_r2;
int      g_retestPendingDir = 0;
double   g_retestLevel = 0.0;
int      g_retestBarsLeft = 0;
string   g_ctTriggerReason = "";
int      g_lastCtSignal = 0;

//+------------------------------------------------------------------+
//| HEARTBEAT state (2026-09-04)                                     |
//+------------------------------------------------------------------+
datetime g_lastHeartbeatTime = 0;
ulong    g_ticksSinceLastHeartbeat = 0;

//+------------------------------------------------------------------+
//| REGIME EVENT LOG state (2026-09-04) -- last-known values so we    |
//| only write a row on an actual transition, not every bar.         |
//+------------------------------------------------------------------+
bool g_lastRegimeDegraded   = false;   // last Bot1RegimeSuiteSaysRanging() verdict

// PERF FIX (v2 AGILE, 2026-09-07): Bot1RegimeSuiteSaysRanging() internally
// recomputes up to 10 filters (several loop over 14-100 bars each: ER, CHOP,
// LinReg, MMI) and was being called 3x per single bar-close (regime-event
// check, counter-trend gate, main signal gate) -- the verdict cannot change
// mid-bar, so this is pure redundant work. Cache it once per bar; every
// caller within the same bar reads the cache instead of recomputing.
bool     g_regimeRangingCacheValid = false;
datetime g_regimeRangingCacheBar   = 0;
bool     g_regimeRangingCacheValue = false;

// PERF FIX (2026-09-17): the 6 individual Regime Suite voters (ADX, ER, CHOP,
// LinReg, ATRRatio, MMI) are each real per-bar computations (ER/CHOP loop
// over their lookback period, MMI loops+sorts up to 100 bars) and were being
// evaluated TWICE per bar once the v3 classifier (Bot1ComputeRegime21Bucket)
// was added -- once via Bot1RegimeSuiteSaysTrending()'s own direct calls,
// and again independently inside the classifier. Same "compute once per bar"
// discipline as g_regimeRangingCacheValue above, but caching the individual
// vote booleans themselves so BOTH the existing gate and the new classifier
// read the same single evaluation.
bool     g_voteCacheValid      = false;
datetime g_voteCacheBar        = 0;
bool     g_voteCacheADX        = false;
bool     g_voteCacheER         = false;
bool     g_voteCacheCHOP       = false;
bool     g_voteCacheLinReg     = false;
bool     g_voteCacheATRRatio   = false;
bool     g_voteCacheMMI        = false;

bool g_lastKillSwitchActive = false;
bool g_lastCooldownBuyActive  = false;
bool g_lastCooldownSellActive = false;
string g_lastRegimeGateSnapshot = "";  // concatenated per-filter T/R string, compared to detect ANY individual gate flip

//+------------------------------------------------------------------+
//| SHADOW-OUTCOME MULTI-STRICTNESS TRACKING (2026-09-04)             |
//| Extends the existing single-shadow (g_shadow*) simulation, which  |
//| only ever tracks ONE hypothetical position gated at L1-only. This |
//| adds a second, independently-gated hypothetical position at a    |
//| stricter threshold (2-of-3 layers OR full regime-suite pass) so   |
//| the two can be compared: did the extra strictness actually avoid  |
//| the losers, or did it just cut winners too? Mirrors g_shadow*     |
//| naming/lifecycle exactly, just a second independent slot.        |
//+------------------------------------------------------------------+
bool     g_shadow2Active = false;
int      g_shadow2Dir = 0;
double   g_shadow2Entry = 0, g_shadow2SL = 0, g_shadow2TrailSL = 0, g_shadow2InitialRisk = 0;
bool     g_shadow2TP1Hit = false, g_shadow2TP2Hit = false;
datetime g_shadow2OpenTime = 0;
int      g_shadow2BarsElapsed = 0;
string   g_shadow2GateLabel = "";   // which stricter gate this instance represents, e.g. "2OF3" or "REGIME_STRICT"

//+------------------------------------------------------------------+
//| BOT1 MFE/MAE TRACKING (per open ticket, updated every tick)     |
//| Fixed-size parallel arrays -- position counts here are always   |
//| tiny (MaxBuyPositions/MaxSellPositions default to 1), 20 slots  |
//| is generous headroom, not a real capacity constraint.           |
//+------------------------------------------------------------------+
#define BOT1_MFE_SLOTS 20
ulong  g_mfeTicket[BOT1_MFE_SLOTS];
double g_mfePeak[BOT1_MFE_SLOTS];    // best price achieved in favor of the position
double g_mfeTrough[BOT1_MFE_SLOTS];  // worst price achieved against the position
double g_mfeEntry[BOT1_MFE_SLOTS];
int    g_mfeDir[BOT1_MFE_SLOTS];     // 1=buy, -1=sell
bool   g_mfeUsed[BOT1_MFE_SLOTS];
int    g_mfeBarsElapsed[BOT1_MFE_SLOTS]; // bars since open, incremented once per NEW BAR only
int    g_mfeBarsToPeak[BOT1_MFE_SLOTS];   // bar count at which the current peak was set
int    g_mfeBarsToTrough[BOT1_MFE_SLOTS]; // bar count at which the current trough was set

// EARLY PRICE-ACTION SNAPSHOT (2026-09-21): parallel to the MFE/MAE tracker above,
// records signed points-in-favor at exactly bar 1/3/5 after entry (captured once,
// on the new-bar boundary matching g_mfeBarsElapsed==1/3/5 -- never overwritten after
// that bar passes). Tests the "how did price behave right after entry" hypothesis --
// distinct from MFE/MAE, which track the eventual best/worst over the WHOLE trade life;
// these fields freeze early, before staged-BE/trailing/TP1 can influence anything.
// Sentinel -999999 means "not yet captured" (position closed before that bar count).
double g_earlyPx1Bar[BOT1_MFE_SLOTS];
double g_earlyPx3Bar[BOT1_MFE_SLOTS];
double g_earlyPx5Bar[BOT1_MFE_SLOTS];
#define BOT1_EARLY_PX_SENTINEL -999999.0

// Dedupe: any deal our own code manually logs (TP1/TP2/final-close-target)
// gets marked here so OnTradeTransaction's generic DEAL_ENTRY_OUT catch-all
// doesn't ALSO log it as "CLOSE" -- DEAL_ENTRY_OUT fires for partial closes
// too, not just full closes, which was silently double-counting P&L.
#define BOT1_DEDUPE_SLOTS 10
ulong g_loggedDeals[BOT1_DEDUPE_SLOTS];
int   g_loggedDealsIdx = 0;

//+------------------------------------------------------------------+
//| BOT1 SHADOW TRADE SIMULATION                                    |
//| Answers "if we HAD taken this L1 signal, what would have         |
//| happened" -- not just whether the gate would fire. ONE           |
//| hypothetical position at a time per symbol (mirrors              |
//| OneTradePerBar) -- deliberately NOT one-per-firing-bar, which     |
//| would produce wildly overlapping near-duplicate "trades" and     |
//| inflate N without adding independent information. A new          |
//| hypothetical only starts once the previous one has fully closed. |
//| Uses the SAME CalculateStopLoss/CalculateTakeProfit functions as |
//| real trades for SL/TP realism -- but fills are instantaneous at  |
//| the reference price with no slippage/rejection modeling, so      |
//| simulated results are somewhat OPTIMISTIC vs real fills. State   |
//| here does NOT survive an EA reinit (same known limitation as the |
//| MFE tracker) -- a shadow trade in progress during a redeploy is  |
//| silently lost, not corrupted, so this is a lost-N cost, not a    |
//| data-quality bug.                                                 |
//+------------------------------------------------------------------+
bool     g_shadowActive = false;
int      g_shadowDir = 0;              // 1=buy, -1=sell
double   g_shadowEntry = 0;
double   g_shadowSL = 0;
double   g_shadowInitialRisk = 0;      // |entry - original SL|, denominator for R-multiples
double   g_shadowTrailSL = 0;          // 0 until trailing activates, mirrors real trailingStopPrice
bool     g_shadowTP1Hit = false;
bool     g_shadowTP2Hit = false;
datetime g_shadowOpenTime = 0;
int      g_shadowBarsElapsed = 0;
// Entry-state snapshot, captured once at hypothetical open, written to
// the outcome row at close so the resulting CSV can be sliced by ANY
// hypothetical gate combination downstream (would_open_l2_or_l3 etc),
// exactly like bot1_parameter_scan.py already does for real trades.
int      g_shadowL1Result = 0;
bool     g_shadowL2PassStrict = false;
bool     g_shadowL3PassStrict = false;
double   g_shadowRsiValue = 0, g_shadowAdxValue = 0, g_shadowAtrRatio = 0;
int      g_shadowVolState = 0, g_shadowHourUtc = 0, g_shadowDayOfWeek = 0;

//+------------------------------------------------------------------+
//| BOT1 SHADOW POOL (2026-09-25) -- multi-trade concurrent sample   |
//| builder for MFE/MAE forensic analysis. Unlike g_shadow* above    |
//| (exactly ONE hypothetical trade in flight at a time), this is a  |
//| fixed-size POOL: a new hypothetical trade can open on EVERY bar  |
//| where l1_result != 0, even while others are still running, up to |
//| ShadowPoolMaxConcurrent overlapping trades. This directly attacks|
//| the small-sample problem found in the 2026-09-24/25 MFE/MAE      |
//| forensic analysis (only 28 real trades total, 3 actionable) --   |
//| many more (still-real, forward-tested, not backtest-guessed)     |
//| samples of "what would have happened" accumulate per week.       |
//|                                                                    |
//| Full MFE/MAE tracked per pool slot (peak/trough price + bar count |
//| to each), same fields as the real Bot1GetMFEMAE tracker, PLUS the |
//| full entry-context snapshot (regime bucket, ADX/RSI, momentum,    |
//| HTF bias) already captured for real R21 trades -- so the resulting|
//| CSV can answer "which indicator values predict MFE actually       |
//| getting captured vs reversing" directly, not just "did it work".  |
//|                                                                    |
//| Entirely gated on UseShadowPool (default false) -- zero behavior  |
//| change, zero added cost, when off. Independent of LogBot1Candidates|
//| /g_shadowActive above; can run alongside or instead of them.      |
//+------------------------------------------------------------------+
#define BOT1_SHADOW_POOL_SLOTS 32   // hard cap on the array; ShadowPoolMaxConcurrent (input) further limits how many are used at once, must be <= this
bool     g_poolUsed[BOT1_SHADOW_POOL_SLOTS];
int      g_poolDir[BOT1_SHADOW_POOL_SLOTS];
double   g_poolEntry[BOT1_SHADOW_POOL_SLOTS];
double   g_poolSL[BOT1_SHADOW_POOL_SLOTS];
double   g_poolInitialRisk[BOT1_SHADOW_POOL_SLOTS];
double   g_poolTrailSL[BOT1_SHADOW_POOL_SLOTS];
bool     g_poolTP1Hit[BOT1_SHADOW_POOL_SLOTS];
bool     g_poolTP2Hit[BOT1_SHADOW_POOL_SLOTS];
datetime g_poolOpenTime[BOT1_SHADOW_POOL_SLOTS];
int      g_poolBarsElapsed[BOT1_SHADOW_POOL_SLOTS];
// Full-life MFE/MAE (peak/trough price seen at any point, tick-level if
// ShadowPoolTrackTickMFE, else updated only on the once-per-bar pool tick)
double   g_poolMfePeak[BOT1_SHADOW_POOL_SLOTS];
double   g_poolMaeTrough[BOT1_SHADOW_POOL_SLOTS];
int      g_poolBarsToMfe[BOT1_SHADOW_POOL_SLOTS];
int      g_poolBarsToMae[BOT1_SHADOW_POOL_SLOTS];
// Entry-context snapshot -- same fields already proven useful in
// bot1r21_trades_GOLD.csv's extended columns, captured once at hypothetical
// open so the closed-trade row can be sliced by any of these downstream.
string   g_poolBucketAtEntry[BOT1_SHADOW_POOL_SLOTS];
int      g_poolBucketTrendVotes[BOT1_SHADOW_POOL_SLOTS];
double   g_poolAdxAtEntry[BOT1_SHADOW_POOL_SLOTS];
double   g_poolRsiAtEntry[BOT1_SHADOW_POOL_SLOTS];
int      g_poolHourUtcAtEntry[BOT1_SHADOW_POOL_SLOTS];
int      g_poolDayOfWeekAtEntry[BOT1_SHADOW_POOL_SLOTS];
int      g_shadowPoolLogHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| BOT1 POST-STOP-OUT PRICE TRACKING                                |
//| Validates (does not implement) the pyramiding/recovery question: |
//| after a position closes, does price actually reverse or keep     |
//| trending? Tracks for Bot1PostmortemBars bars, then logs ONE      |
//| summary row per closed ticket to a SEPARATE file (never touches  |
//| bot1_trades_*.csv's schema).                                     |
//+------------------------------------------------------------------+
#define BOT1_PM_SLOTS 10
ulong  g_pmTicket[BOT1_PM_SLOTS];
double g_pmClosePrice[BOT1_PM_SLOTS];
int    g_pmDir[BOT1_PM_SLOTS];          // 1 = was BUY, -1 = was SELL
string g_pmReason[BOT1_PM_SLOTS];
double g_pmMaxFavorable[BOT1_PM_SLOTS]; // best price move back toward the original trade's profit direction
double g_pmMaxAdverse[BOT1_PM_SLOTS];   // worst further move continuing the original adverse direction
int    g_pmBarsElapsed[BOT1_PM_SLOTS];
bool   g_pmUsed[BOT1_PM_SLOTS];
datetime lastTradeBarTime = 0;
double startDayBalance = 0.0;
datetime lastCestDayStart = 0;
double g_eaStartBalance = 0.0;  // v5.97: captured once in OnInit() as AccountInfoDouble(ACCOUNT_BALANCE) -- replaces the old flat-dollar InitialBalance input, so MaxOverallLossPct scales off the REAL starting balance on any account size

//+------------------------------------------------------------------+
//| POST-STOP COOLDOWN state (2026-09-02)                            |
//| Set in OnTradeTransaction() when a position on this MagicNumber  |
//| closes via DEAL_REASON_SL; checked in the entry gate before      |
//| opening a new position in the SAME direction.                    |
//+------------------------------------------------------------------+
datetime g_cooldownUntilBuyBar  = 0;   // bar-time up to (and including) which new BUY entries are blocked
datetime g_cooldownUntilSellBar = 0;   // bar-time up to (and including) which new SELL entries are blocked

//+------------------------------------------------------------------+
//| MIN SL DISTANCE rolling history (2026-09-02)                     |
//| Tracks this MagicNumber's own recent REAL SL distances (points), |
//| recorded at position-open time in the BUY/SELL entry blocks.     |
//| A candidate entry whose computed SL distance is an outlier vs    |
//| this rolling average is skipped -- see UseMinSLDistanceFilter.   |
//+------------------------------------------------------------------+
double g_slDistanceHistory[];
int    g_slDistanceCount = 0;   // total real samples ever recorded (for SLDistanceMinSamples gate; array itself wraps at SLDistanceHistoryLen)

// CONSECUTIVE LOSS TRACKER (2026-09-19): counts this MagicNumber's own
// current losing streak (resets to 0 on any winning close). Written onto
// every new OPEN_* trade log row as consec_losses_at_entry -- lets us see
// streak-state at the MOMENT of entry (a 25-consecutive-loss run was found
// in a real validation, Jan12-15 2026, during a whipsaw period the regime
// classifier mislabeled as TREND -- this makes future streaks like that
// directly visible/filterable in the trade CSV instead of needing to
// reconstruct them after the fact from raw PnL).
int g_consecLosses = 0;
datetime g_slDistanceLastUpdateBar = 0;  // bar-time of the last REAL trade that updated the rolling average -- see Bot1SLDistanceIsOutlier staleness fix (2026-09-18)

//+------------------------------------------------------------------+
//| BOT1 COUNTER-TREND TICKET TRACKING (v2 AGILE, 2026-09-06)         |
//| BUG FOUND during smoke test: MT5's DEAL_MAGIC on a broker/server- |
//| triggered SL/TP close (i.e. NOT closed via our own                |
//| trade.PositionClose()) does not reliably carry the original       |
//| position's magic -- confirmed directly: a counter-trend position  |
//| (ticket 16, opened under magic 55221) got stopped out, and its    |
//| CLOSE row in bot1_trades_XAUUSD.csv was written under magic 54321 |
//| (the trend side's own MagicNumber) instead. This is a genuine MT5 |
//| platform quirk, not something introduced by this module -- it     |
//| would silently mis-attribute ANY server-triggered close whenever  |
//| more than one MagicNumber is active in the same EA process, on    |
//| both the trend and counter-trend sides. Fix: track ticket->magic  |
//| ourselves at OPEN time (which we DO control), and consult that    |
//| instead of trusting DEAL_MAGIC at close time.                     |
//+------------------------------------------------------------------+
#define BOT1_MAGIC_TRACK_SLOTS 50
ulong g_trackedTicket[BOT1_MAGIC_TRACK_SLOTS];
long  g_trackedMagic[BOT1_MAGIC_TRACK_SLOTS];
bool  g_trackedUsed[BOT1_MAGIC_TRACK_SLOTS];

void Bot1TrackPositionMagic(ulong ticket, long magic) {
   for(int i = 0; i < BOT1_MAGIC_TRACK_SLOTS; i++) {
      if(!g_trackedUsed[i]) {
         g_trackedUsed[i] = true;
         g_trackedTicket[i] = ticket;
         g_trackedMagic[i] = magic;
         return;
      }
   }
   // All slots full (shouldn't happen given MaxBuyPositions/MaxSellPositions/
   // CounterTrendMaxPositions are all small) -- overwrite the oldest slot
   // rather than silently dropping tracking for this ticket.
   g_trackedUsed[0] = true;
   g_trackedTicket[0] = ticket;
   g_trackedMagic[0] = magic;
}

// Returns the tracked magic for this ticket, or -1 if never tracked (falls
// back to DEAL_MAGIC at the call site in that case).
long Bot1LookupTrackedMagic(ulong ticket) {
   for(int i = 0; i < BOT1_MAGIC_TRACK_SLOTS; i++) {
      if(g_trackedUsed[i] && g_trackedTicket[i] == ticket) return g_trackedMagic[i];
   }
   return -1;
}

void Bot1ReleaseTrackedMagic(ulong ticket) {
   for(int i = 0; i < BOT1_MAGIC_TRACK_SLOTS; i++) {
      if(g_trackedUsed[i] && g_trackedTicket[i] == ticket) { g_trackedUsed[i] = false; return; }
   }
}

//+------------------------------------------------------------------+
//| BOT1 CLOSE-RETRY COOLDOWN (v5.7 bug fix)                          |
//| Found in production log 2026-08-11: the final-close-target branch |
//| in ManageStagedProfits retried trade.PositionClose() every single |
//| tick with no backoff whenever it failed (observed: 158 consecutive|
//| rejections in ~2m47s during a market-closed window, retcode 10018)|
//| Tracks the last-attempt time per ticket so a failed close waits   |
//| BOT1_CLOSE_RETRY_COOLDOWN_SEC before trying again instead of      |
//| retrying every tick. Does not change WHETHER the position         |
//| eventually closes -- only how often a failing attempt is retried. |
//+------------------------------------------------------------------+
#define BOT1_COOLDOWN_SLOTS 4
#define BOT1_CLOSE_RETRY_COOLDOWN_SEC 60
ulong    g_closeCooldownTicket[BOT1_COOLDOWN_SLOTS];
datetime g_closeCooldownUntil[BOT1_COOLDOWN_SLOTS];

bool Bot1IsOnCloseCooldown(ulong ticket) {
   for(int i = 0; i < BOT1_COOLDOWN_SLOTS; i++)
      if(g_closeCooldownTicket[i] == ticket && TimeCurrent() < g_closeCooldownUntil[i]) return true;
   return false;
}

void Bot1SetCloseCooldown(ulong ticket) {
   for(int i = 0; i < BOT1_COOLDOWN_SLOTS; i++) {
      if(g_closeCooldownTicket[i] == 0 || g_closeCooldownTicket[i] == ticket) {
         g_closeCooldownTicket[i] = ticket;
         g_closeCooldownUntil[i] = TimeCurrent() + BOT1_CLOSE_RETRY_COOLDOWN_SEC;
         return;
      }
   }
   // All slots full -- should be rare given MaxBuyPositions/MaxSellPositions
   // are small. Overwrite the first slot rather than silently drop the
   // cooldown; worst case one ticket retries a bit sooner than intended,
   // never worse than the original every-tick behavior.
   g_closeCooldownTicket[0] = ticket;
   g_closeCooldownUntil[0] = TimeCurrent() + BOT1_CLOSE_RETRY_COOLDOWN_SEC;
}

// v5.9 bug fix: separate tracker from the close-cooldown above, on purpose.
// The trailing-modify branch has the same unguarded-retry-every-tick
// exposure TP1/TP2/final-close-target had before v5.7/v5.8 (a rejected
// PositionModify, e.g. market closed, was retried every tick with no
// backoff). Sharing the close-cooldown tracker would risk a TP1/TP2
// failure on a ticket incorrectly suppressing a legitimate, unrelated
// trailing update on that same ticket -- different actions, should fail
// independently.
ulong    g_trailCooldownTicket[BOT1_COOLDOWN_SLOTS];
datetime g_trailCooldownUntil[BOT1_COOLDOWN_SLOTS];

bool Bot1IsOnTrailCooldown(ulong ticket) {
   for(int i = 0; i < BOT1_COOLDOWN_SLOTS; i++)
      if(g_trailCooldownTicket[i] == ticket && TimeCurrent() < g_trailCooldownUntil[i]) return true;
   return false;
}

void Bot1SetTrailCooldown(ulong ticket) {
   for(int i = 0; i < BOT1_COOLDOWN_SLOTS; i++) {
      if(g_trailCooldownTicket[i] == 0 || g_trailCooldownTicket[i] == ticket) {
         g_trailCooldownTicket[i] = ticket;
         g_trailCooldownUntil[i] = TimeCurrent() + BOT1_CLOSE_RETRY_COOLDOWN_SEC;
         return;
      }
   }
   g_trailCooldownTicket[0] = ticket;
   g_trailCooldownUntil[0] = TimeCurrent() + BOT1_CLOSE_RETRY_COOLDOWN_SEC;
}

//+------------------------------------------------------------------+
//| REGIME KILL SWITCH (branch feature)                              |
//| Ring buffer of the last BOT1_REGIME_WINDOW FULLY CLOSED positions |
//| (whole-position P&L, summed across TP1/TP2/final legs via         |
//| HistorySelectByPosition -- not individual partial-close legs,     |
//| which would misclassify a position that took TP1+TP2 profit then |
//| gave part of it back on the remainder as a "loss" for that leg    |
//| alone). Recorded once per position, at the point it's fully       |
//| closed, from whichever code path closes it (broker-side SL/TP/   |
//| manual, or the final-close-target branch).                        |
//+------------------------------------------------------------------+
#define BOT1_REGIME_WINDOW 50   // headroom above any reasonable RegimeLookbackTrades
bool g_regimeTradeWin[BOT1_REGIME_WINDOW];
int  g_regimeWriteIdx = 0;
int  g_regimeTradeCount = 0;
bool g_regimeKillSwitchWasActive = false;   // edge-detect for the trip/release print
int  g_regimeBarsSinceSuppressed = 0;       // counts bars while the switch is active, for the probe-trade release valve

double Bot1GetPositionTotalProfit(ulong positionId) {
   double total = 0;
   if(!HistorySelectByPosition(positionId)) return total;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      total += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      total += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      total += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   }
   return total;
}

void Bot1RecordTradeOutcome(ulong positionId) {
   double totalProfit = Bot1GetPositionTotalProfit(positionId);
   g_regimeTradeWin[g_regimeWriteIdx % BOT1_REGIME_WINDOW] = (totalProfit >= 0);
   g_regimeWriteIdx++;
   g_regimeTradeCount++;
}

double Bot1GetRollingWinRate(int lookback) {
   int n = MathMin(lookback, BOT1_REGIME_WINDOW);
   // v1 bug fix: the original guard only checked n<=0, so as few as 1-2
   // real trades could compute a "win rate" and trip the switch -- exactly
   // what happened in testing (tripped permanently after 2 trades, one
   // loss). Require a FULL lookback window of closed trades before this
   // can return anything but the neutral "don't trip" value.
   if(g_regimeTradeCount < n) return 1.0;
   int wins = 0;
   for(int i = 1; i <= n; i++) {
      int idx = ((g_regimeWriteIdx - i) % BOT1_REGIME_WINDOW + BOT1_REGIME_WINDOW) % BOT1_REGIME_WINDOW;
      if(g_regimeTradeWin[idx]) wins++;
   }
   return (double)wins / n;
}

bool Bot1RegimeKillSwitchActive() {
   if(!UseRegimeKillSwitch) return false;
   bool active = (Bot1GetRollingWinRate(RegimeLookbackTrades) < RegimeMinWinRate);

   if(LogRegimeKillSwitch && active != g_regimeKillSwitchWasActive) {
      if(active) {
         Print("[BOT1-REGIME] ", _Symbol, " kill switch TRIPPED at ", TimeToString(TimeCurrent()),
               " -- rolling win rate ", DoubleToString(Bot1GetRollingWinRate(RegimeLookbackTrades)*100, 1),
               "% over last ", RegimeLookbackTrades, " trades, below ", DoubleToString(RegimeMinWinRate*100, 1),
               "% threshold. New entries suppressed.");
      } else {
         Print("[BOT1-REGIME] ", _Symbol, " kill switch RELEASED at ", TimeToString(TimeCurrent()),
               " -- rolling win rate recovered to ", DoubleToString(Bot1GetRollingWinRate(RegimeLookbackTrades)*100, 1),
               "%. New entries resumed.");
      }
      g_regimeKillSwitchWasActive = active;
      g_regimeBarsSinceSuppressed = 0;
   }

   if(!active) {
      g_regimeBarsSinceSuppressed = 0;
      return false;
   }

   // v2 fix: suppressing entries also stops the trade outcomes needed to
   // ever reassess -- without this, a trip is permanent (confirmed in
   // testing: tripped on bar ~5000 of ~40000, never fired again). Let
   // exactly one signal through every RegimeProbeIntervalBars bars so the
   // rolling window keeps moving. Set RegimeProbeIntervalBars=0 to disable
   // probing and restore the original hard-lock behavior deliberately.
   g_regimeBarsSinceSuppressed++;
   if(RegimeProbeIntervalBars > 0 && g_regimeBarsSinceSuppressed >= RegimeProbeIntervalBars) {
      g_regimeBarsSinceSuppressed = 0;
      if(LogRegimeKillSwitch) {
         Print("[BOT1-REGIME] ", _Symbol, " probe trade allowed through at ", TimeToString(TimeCurrent()),
               " despite active kill switch -- testing whether performance has recovered.");
      }
      return false;   // this one signal is let through despite the switch being "active"
   }

   return true;
}

struct StageTracker {
   ulong ticket;
   int stage;           // 0=open, 1=TP1 closed, 2=TP2 closed, 3=trailing
   double profitLocked;
   double initialRiskDist;  // |entry-SL| at OPEN. RR_PARTIAL uses this, not the trailed SL.
   bool   beApplied;    // WIDE_SL_BE branch (2026-09-10): breakeven-move fired once, never retried
};
StageTracker stages[];

// v5.8 bug fix: this struct existed, was initialized in OnInit, and was
// NEVER READ OR WRITTEN ANYWHERE ELSE. Its own field comment documents the
// intended one-shot state machine (0=open -> 1=TP1 closed -> 2=TP2 closed
// -> 3=trailing) -- exactly the mechanism that should have prevented the
// repeated-TP1/TP2-partial-close bug: ManageStagedProfits checked raw
// profitDistance thresholds every tick with no memory of what had already
// fired, so a position sitting above g_TP2_Distance for hours got a fresh
// 0.01-lot partial close on nearly every tick instead of one clean partial
// close. Wiring the struct in as originally designed, not inventing new
// state.
int Bot1FindStageTracker(ulong ticket) {
   for(int i = 0; i < ArraySize(stages); i++)
      if(stages[i].ticket == ticket) return i;
   return -1;
}

int Bot1GetStage(ulong ticket) {
   int idx = Bot1FindStageTracker(ticket);
   return (idx >= 0) ? stages[idx].stage : 0;  // ticket not seen yet = stage 0, nothing closed
}

void Bot1SetStage(ulong ticket, int stage) {
   int idx = Bot1FindStageTracker(ticket);
   if(idx < 0) {
      idx = ArraySize(stages);
      ArrayResize(stages, idx + 1);
      stages[idx].ticket = ticket;
      stages[idx].profitLocked = 0;
      stages[idx].initialRiskDist = 0;
      stages[idx].stage = 0;
      stages[idx].beApplied = false;
   }
   if(stage > stages[idx].stage) stages[idx].stage = stage;  // monotonic -- never step backwards
}

// WIDE_SL_BE branch (2026-09-10): breakeven-move state, separate from the
// TP1/TP2/trailing stage machine above -- fires exactly once per ticket,
// independent of ExitMode (works under STAGED, RR_PARTIAL, and FULL_HOLD).
bool Bot1GetBEApplied(ulong ticket) {
   int idx = Bot1FindStageTracker(ticket);
   return (idx >= 0) ? stages[idx].beApplied : false;
}

void Bot1SetBEApplied(ulong ticket, bool val) {
   int idx = Bot1FindStageTracker(ticket);
   if(idx < 0) {
      idx = ArraySize(stages);
      ArrayResize(stages, idx + 1);
      stages[idx].ticket = ticket;
      stages[idx].profitLocked = 0;
      stages[idx].initialRiskDist = 0;
      stages[idx].stage = 0;
      stages[idx].beApplied = false;
   }
   stages[idx].beApplied = val;
}

void Bot1RememberInitialRisk(ulong ticket, double riskDist) {
   if(ticket == 0 || riskDist <= 0) return;
   int idx = Bot1FindStageTracker(ticket);
   if(idx < 0) {
      idx = ArraySize(stages);
      ArrayResize(stages, idx + 1);
      stages[idx].ticket = ticket;
      stages[idx].stage = 0;
      stages[idx].profitLocked = 0;
      stages[idx].initialRiskDist = 0;
      stages[idx].beApplied = false;
   }
   if(stages[idx].initialRiskDist <= 0) stages[idx].initialRiskDist = riskDist;
}

double Bot1InitialRiskDist(ulong ticket, double entryPrice, double currentSL) {
   int idx = Bot1FindStageTracker(ticket);
   if(idx >= 0 && stages[idx].initialRiskDist > _Point)
      return stages[idx].initialRiskDist;
   double slDist = MathAbs(entryPrice - currentSL);
   if(slDist < _Point) slDist = MathMax(1.0, (double)g_TP1_Distance) * _Point;
   return slDist;
}

bool Bot1TrailAllowed() {
   return (g_ExitMode != EXIT_FULL_HOLD && UseTrailingOnRemainder && !UseFinalCloseTarget);
}

int Bot1BrokerMinStopPts() {
   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long effectiveMinPts = (stopsLevelPts > 0) ? stopsLevelPts : Bot1FallbackMinStopPoints;
   return (int)(effectiveMinPts + 5);
}

int Bot1LegalTrailPts() {
   int legal = Bot1BrokerMinStopPts();
   return (TrailingDistance > legal) ? TrailingDistance : legal;
}

// Called when a position fully closes, so `stages[]` doesn't grow
// unbounded over a multi-month/hundreds-of-trades test.
void Bot1ReleaseStageTracker(ulong ticket) {
   int idx = Bot1FindStageTracker(ticket);
   if(idx < 0) return;
   int last = ArraySize(stages) - 1;
   stages[idx] = stages[last];
   ArrayResize(stages, last);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                
//+------------------------------------------------------------------+
double ValuePerPoint() {
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0) return tick_value;
   return tick_value * (_Point / tick_size);
}

double NormalizeVolume(double lots) {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   if(stepLot > 0.0) lots = MathRound(lots / stepLot) * stepLot;
   return NormalizeDouble(lots, 2);
}

// Peel a fraction and keep at least one min-lot rider for the order TP / trail.
// fraction >= 0.999 means flatten (legacy "close remainder at TP2").
double Bot1PartialCloseVolume(double remaining, double fraction) {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0.0) minLot = 0.01;
   if(remaining <= minLot + 1e-8) return 0.0;
   if(fraction >= 0.999) return remaining;
   double closeVol = NormalizeVolume(remaining * fraction);
   if(closeVol > remaining - minLot + 1e-8)
      closeVol = NormalizeVolume(remaining - minLot);
   if(closeVol < minLot - 1e-8) return 0.0;
   return closeVol;
}

double CalculateADR(const int period) {
   if(period <= 0) return 0.0;
   double sum = 0.0;
   int bars = Bars(_Symbol, PERIOD_D1);
   int usable = MathMin(period, bars-1);
   if(usable <= 0) return 0.0;

   for(int i=1; i<=usable; i++) {
      double hi = iHigh(_Symbol, PERIOD_D1, i);
      double lo = iLow(_Symbol, PERIOD_D1, i);
      if(hi > 0 && lo > 0) sum += (hi - lo);
   }
   return sum / usable;
}

int TimeStringToMinutes(const string timeStr) {
   string parts[];
   if(StringSplit(timeStr, ':', parts) != 2) return -1;
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h<0 || h>23 || m<0 || m>59) return -1;
   return h*60 + m;
}

bool IsTradingTimeAllowed() {
   if(!UseTimeFilter) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int cur = t.hour*60 + t.min;
   int st = TimeStringToMinutes(StartTime);
   int en = TimeStringToMinutes(EndTime);
   if(st < 0 || en < 0) return false;

   bool inRange = (st <= en) ? (cur >= st && cur <= en) : (cur >= st || cur <= en);
   if(!inRange) return false;
   if(AvoidFriday && t.day_of_week == 5 && t.hour >= FridayCloseHour) return false;
   return true;
}

double GetVolatilityRatio() {
   if(!UseVolatilityRatio) return 1.0;
   // v5.94: shared with the Regime Suite's ATR-ratio filter -- see input
   // group comment above. No longer a separate atrShortHandle/atrLongHandle.
   if(regimeAtrFastHandle == INVALID_HANDLE || regimeAtrSlowHandle == INVALID_HANDLE) return 1.0;

   double s[], l[];
   ArraySetAsSeries(s,true);
   ArraySetAsSeries(l,true);
   if(CopyBuffer(regimeAtrFastHandle,0,0,1,s)<1) return 1.0;
   if(CopyBuffer(regimeAtrSlowHandle,0,0,1,l)<1) return 1.0;
   if(l[0] <= 0.0) return 1.0;
   return s[0]/l[0];
}

int GetVolatilityState() {
   if(!UseVolatilityRatio) return 0;
   double r = GetVolatilityRatio();
   if(r > VolatilityRatioTrendMin) return 1;     // TRENDING
   if(r >= VolatilityRatioRangeMin && r <= VolatilityRatioRangeMax) return 0;  // RANGING
   if(r < VolatilityRatioLowVol) return -1;      // LOW VOL
   return 0;
}

bool IsMarketTradable() {
   if(UseVolatilityRatio) {
      int volState = GetVolatilityState();
      // v5.95: BUG FIX -- these three used to be sequential early-returns,
      // which meant TradeTrendingOnly=true silently made AvoidLowVol and
      // AvoidRanging unreachable dead code (TradeTrendingOnly already
      // vetoes every volState except 1, so the later checks for volState
      // -1/0 could never fire). Confirmed this happened in the v5.94
      // MAJORITY optimization: AvoidRanging was flagged Y (optimize) while
      // TradeTrendingOnly was fixed true, so 1536 passes "searched" a
      // parameter that could never affect a single outcome. Now each flag
      // is independently evaluated -- all three can genuinely combine.
      bool blockedByTrendOnly = (TradeTrendingOnly && volState != 1);
      bool blockedByLowVol    = (AvoidLowVol && volState == -1);
      bool blockedByRanging   = (AvoidRanging && volState == 0);
      if(blockedByTrendOnly || blockedByLowVol || blockedByRanging) return false;
   }
   return true;
}

bool Bot1R2DiagOn() {
   return LogRegime2Diagnostics && !MQLInfoInteger(MQL_OPTIMIZATION);
}


// --- ARCH RESOLVE BEGIN ---
void Bot1CopyInputsToGlobals() {
   g_ExitMode = ExitMode;
   g_CTMode = CTMode;
   g_Layer3Gate = Layer3Gate;
   g_Layer2RSIMode = Layer2RSIMode;
   g_StopBasisMode = StopBasisMode;
   g_UseIchimoku = UseIchimoku;
   g_UsePSAR = UsePSAR;
   g_UseEMACross = UseEMACross;
   g_UseSuperTrend = UseSuperTrend;
   g_UseEMA200Bias = UseEMA200Bias;
   g_UseMACD = UseMACD;
   g_UseRSI = UseRSI;
   g_UseADX = UseADX;
   g_UseADXSlope = UseADXSlope;
   g_UseLayer2CCI = UseLayer2CCI;
   g_PreferCCIInTrend = PreferCCIInTrend;
   g_UseBollinger = UseBollinger;
   g_UseOBV = UseOBV;
   g_UseDonchian = UseDonchian;
   g_UseRetest = UseRetest;
   g_UseVWAPReclaim = UseVWAPReclaim;
   g_UseCounterTrendModule = UseCounterTrendModule;

   // RE-ADDED 2026-10-11: EntryPreset override, ported back from 2.0 byte-identical. Fires AFTER
   // the individual Use* ticks are copied above, so PRESET_MANUAL (default) leaves everything
   // exactly as the .set file specified (zero behavior change for existing configs). Any
   // non-MANUAL preset stomps the g_Use*/g_Layer3Gate globals with a frozen, previously-validated
   // combo -- lets a sweep vary ONE int input (EntryPreset: 0-5) instead of 17 correlated booleans.
   if(EntryPreset == PRESET_A) {
      g_UseIchimoku = false; g_UsePSAR = true; g_UseEMACross = true; g_UseSuperTrend = true;
      g_UseEMA200Bias = false; g_UseMACD = false; g_UseRSI = false; g_UseADX = false;
      g_UseADXSlope = false; g_UseLayer2CCI = false; g_PreferCCIInTrend = true;
      g_Layer3Gate = L3_GATE_EXCLUDE; g_UseBollinger = true; g_UseOBV = false;
      g_UseDonchian = true; g_UseRetest = false; g_UseVWAPReclaim = false;
   } else if(EntryPreset == PRESET_B) {
      g_UseIchimoku = false; g_UsePSAR = true; g_UseEMACross = true; g_UseSuperTrend = false;
      g_UseEMA200Bias = false; g_UseMACD = true; g_UseRSI = true; g_UseADX = true;
      g_UseADXSlope = true; g_UseLayer2CCI = true; g_PreferCCIInTrend = true;
      g_Layer3Gate = L3_GATE_EXCLUDE; g_UseBollinger = false; g_UseOBV = true;
      g_UseDonchian = false; g_UseRetest = true; g_UseVWAPReclaim = true;
   } else if(EntryPreset == PRESET_C) {
      g_UseIchimoku = false; g_UsePSAR = true; g_UseEMACross = true; g_UseSuperTrend = true;
      g_UseEMA200Bias = true; g_UseMACD = false; g_UseRSI = true; g_UseADX = true;
      g_UseADXSlope = false; g_UseLayer2CCI = true; g_PreferCCIInTrend = false;
      g_Layer3Gate = L3_GATE_CONFIRM; g_UseBollinger = false; g_UseOBV = false;
      g_UseDonchian = true; g_UseRetest = true; g_UseVWAPReclaim = false;
   } else if(EntryPreset == PRESET_D) {
      g_UseIchimoku = false; g_UsePSAR = true; g_UseEMACross = true; g_UseSuperTrend = false;
      g_UseEMA200Bias = false; g_UseMACD = false; g_UseRSI = true; g_UseADX = false;
      g_UseADXSlope = false; g_UseLayer2CCI = false; g_PreferCCIInTrend = false;
      g_Layer3Gate = L3_GATE_EXCLUDE; g_UseBollinger = false; g_UseOBV = false;
      g_UseDonchian = false; g_UseRetest = false; g_UseVWAPReclaim = true;
   } else if(EntryPreset == PRESET_E) {
      g_UseIchimoku = false; g_UsePSAR = true; g_UseEMACross = false; g_UseSuperTrend = false;
      g_UseEMA200Bias = false; g_UseMACD = false; g_UseRSI = true; g_UseADX = true;
      g_UseADXSlope = false; g_UseLayer2CCI = false; g_PreferCCIInTrend = false;
      g_Layer3Gate = L3_GATE_EXCLUDE; g_UseBollinger = false; g_UseOBV = false;
      g_UseDonchian = false; g_UseRetest = true; g_UseVWAPReclaim = false;
   }
   // PRESET_MANUAL: no override, individual Use* ticks from the .set file stand as-is.

   // v6.17-v6.22: EntryPreset override originally REMOVED in 2.2 (preset cleanup -- see
   // header comment), RE-ADDED above on 2026-10-11 (see comment at the input declaration).

   g_UseADRExhaustionFilter = UseADRExhaustionFilter;
   g_UseStageExits = UseStageExits;
   g_UseRegimeLEAN4 = UseRegimeLEAN4;
   g_UseRegimeADX = UseRegimeADX;
   g_UseRegimeER = UseRegimeER;
   g_UseRegimeCHOP = UseRegimeCHOP;
   g_UseRegimeLinReg = UseRegimeLinReg;
   g_UseRegimeATRRatio = UseRegimeATRRatio;
   g_UseRegimeMMI = UseRegimeMMI;
   g_UseRegimeSession = UseRegimeSession;
   g_UseATRBandGate = UseATRBandGate;
   g_UseATRSpikeFilter = UseATRSpikeFilter;
   g_UseAsianRangeFilter = UseAsianRangeFilter;
   g_RequireCloseBackInsideBand = RequireCloseBackInsideBand;
   g_UseStochasticTrigger = UseStochasticTrigger;
   g_UseVWAPDeviationTrigger = UseVWAPDeviationTrigger;

   // v6.22: RegimePreset override originally REMOVED in 2.2 (preset cleanup), RE-ADDED 2026-10-11
   // byte-identical to 2.0. Fires after the individual g_UseRegime*/g_UseATR* ticks are copied
   // above, same pattern as EntryPreset. REGIME_MANUAL (default) leaves everything as the .set
   // file specified -- zero behavior change for existing configs.
   g_RegimeSuiteVoteMode = RegimeSuiteVoteMode;
   if(RegimePreset == REGIME_NONE) {
      g_UseRegimeADX = false; g_UseRegimeER = false; g_UseRegimeCHOP = false;
      g_UseRegimeLinReg = false; g_UseRegimeATRRatio = false; g_UseRegimeMMI = false;
      g_UseRegimeSession = false; g_UseATRBandGate = false; g_UseATRSpikeFilter = false;
      g_UseAsianRangeFilter = false;
   } else if(RegimePreset == REGIME_SESSION_ONLY) {
      g_UseRegimeADX = false; g_UseRegimeER = false; g_UseRegimeCHOP = false;
      g_UseRegimeLinReg = false; g_UseRegimeATRRatio = false; g_UseRegimeMMI = false;
      g_UseRegimeSession = true; g_UseATRBandGate = false; g_UseATRSpikeFilter = false;
      g_UseAsianRangeFilter = false;
   } else if(RegimePreset == REGIME_VOL_BAND) {
      g_UseRegimeADX = false; g_UseRegimeER = false; g_UseRegimeCHOP = false;
      g_UseRegimeLinReg = false; g_UseRegimeATRRatio = false; g_UseRegimeMMI = false;
      g_UseRegimeSession = false; g_UseATRBandGate = true; g_UseATRSpikeFilter = true;
      g_UseAsianRangeFilter = false;
   } else if(RegimePreset == REGIME_TREND_ONLY) {
      g_UseRegimeADX = true; g_UseRegimeER = true; g_UseRegimeCHOP = false;
      g_UseRegimeLinReg = false; g_UseRegimeATRRatio = false; g_UseRegimeMMI = false;
      g_UseRegimeSession = false; g_UseATRBandGate = false; g_UseATRSpikeFilter = false;
      g_UseAsianRangeFilter = false;
   } else if(RegimePreset == REGIME_KITCHEN_SINK) {
      g_UseRegimeADX = true; g_UseRegimeER = true; g_UseRegimeCHOP = false;
      g_UseRegimeLinReg = false; g_UseRegimeATRRatio = false; g_UseRegimeMMI = true;
      g_UseRegimeSession = true; g_UseATRBandGate = false; g_UseATRSpikeFilter = false;
      g_UseAsianRangeFilter = false;
      g_RegimeSuiteVoteMode = 2; // RS_VOTE_MAJORITY (hardcoded int -- ENUM_REGIME_SUITE_VOTE is defined later in the file, RS_VOTE_MAJORITY=2 there)
   }
   // REGIME_MANUAL: no override, individual ticks from the .set file stand as-is.

   g_Layer1MinConfirmations = Layer1MinConfirmations;
   g_Layer2MinConfirmations = Layer2MinConfirmations;
   g_Layer3MinConfirmations = Layer3MinConfirmations;
   g_TP1_Distance = TP1_Distance;
   g_TP2_Distance = TP2_Distance;
   g_TP1_ClosePercent = TP1_ClosePercent;
   g_TP2_ClosePercent = TP2_ClosePercent;
   g_RSIOverbought = RSIOverbought;
   g_RSIOversold = RSIOversold;
   g_ATRStopMultiplier = ATRStopMultiplier;
   g_ExitRR_TP1R = ExitRR_TP1R;
   g_ExitRR_TP2R = ExitRR_TP2R;
   g_ExitRR_Close1Pct = ExitRR_Close1Pct;
}

bool Bot1AnyL2Live() {
   return (g_UseMACD || g_UseRSI || g_UseADX || g_UseLayer2CCI);
}

bool Bot1AnyL3Engine() {
   return (g_UseBollinger || g_UseOBV || g_UseDonchian || g_UseRetest || g_UseVWAPReclaim);
}

bool Bot1AnyRegimeVoter() {
   if(g_UseRegimeLEAN4) return true;
   return (g_UseRegimeADX || g_UseRegimeER || g_UseRegimeCHOP || g_UseRegimeLinReg ||
           g_UseRegimeATRRatio || g_UseRegimeMMI || g_UseRegimeSession ||
           g_UseATRBandGate || g_UseATRSpikeFilter || g_UseAsianRangeFilter);
}

void Bot1ResolveArch() {
   Bot1CopyInputsToGlobals();

   g_RequireL2ForLive = Bot1AnyL2Live();

   if(g_Layer3Gate == L3_GATE_OFF || !Bot1AnyL3Engine()) {
      g_Layer3Gate = L3_GATE_OFF;
      g_RequireL3ForLive = false;
      g_ExcludeWhenL3Fires = false;
   } else if(g_Layer3Gate == L3_GATE_CONFIRM) {
      g_RequireL3ForLive = true;
      g_ExcludeWhenL3Fires = false;
   } else {
      g_RequireL3ForLive = false;
      g_ExcludeWhenL3Fires = true;
   }

   if(g_RequireL2ForLive && g_RequireL3ForLive) {
      g_Layer3Gate = L3_GATE_EXCLUDE;
      g_RequireL3ForLive = false;
      g_ExcludeWhenL3Fires = true;
      Print("[BOT1-LIVE] CLAMP: L2 ticks + Layer3Gate=Confirm is the 16-combo collapse pairing. Demoted L3 to EXCLUDE.");
   }

   g_UseRegimeSuiteGate = Bot1AnyRegimeVoter();

   // REGIME 2.1 v3 SAFETY: prevent the classifier's underlying voters from
   // silently activating 2.0's own live entry-suppression gate. See the
   // Regime21ClassifierPassiveOnly input comment for the full rationale.
   if(UseRegime21Classifier && Regime21ClassifierPassiveOnly) {
      g_UseRegimeSuiteGate = false;
   }

   if(g_ExitMode == EXIT_FULL_HOLD) {
      g_UseStageExits = false;
   } else if(g_ExitMode == EXIT_RR_PARTIAL) {
      g_UseStageExits = true;
      g_TP1_ClosePercent = g_ExitRR_Close1Pct;
      // Do NOT force TP2 to 100%. Remainder must exist for 3R order TP or trail.
      // g_TP2_ClosePercent stays as the Inputs tab (fraction of remaining volume).
   } else {
      g_UseStageExits = true;
   }

   if(g_CTMode == CT_OFF)
      g_UseCounterTrendModule = false;
   else {
      g_UseCounterTrendModule = g_UseRegimeSuiteGate;
      if(g_UseCounterTrendModule) {
         g_RequireCloseBackInsideBand = true;
         g_UseStochasticTrigger = true;
         g_UseVWAPDeviationTrigger = true;
      }
   }
}
// --- ARCH RESOLVE END ---

bool Bot1Lean4Active() {
   return g_UseRegimeLEAN4;
}

bool Bot1NeedsSuperTrend() {
   return g_UseSuperTrend;
}

bool Bot1NeedsSessionVwap() {
   return g_UseVWAPReclaim || (g_UseCounterTrendModule && g_UseVWAPDeviationTrigger);
}

string Bot1Layer1TickTag() {
   string s = "";
   if(g_UseIchimoku)    s += "Ichi ";
   if(g_UsePSAR)        s += "PSAR ";
   if(g_UseEMACross)    s += "EMAx ";
   if(g_UseSuperTrend)  s += "ST ";
   if(g_UseEMA200Bias)  s += "EMA200 ";
   if(s == "") s = "NONE";
   return s;
}

string Bot1Layer3TickTag() {
   string s = EnumToString(g_Layer3Gate) + "|";
   if(g_UseBollinger)    s += "BB ";
   if(g_UseOBV)          s += "OBV ";
   if(g_UseDonchian)     s += "Don ";
   if(g_UseRetest)       s += "Retest ";
   if(g_UseVWAPReclaim)  s += "VWAP ";
   if(s == EnumToString(g_Layer3Gate) + "|") s += "NONE";
   return s;
}

string Bot1RegimeTickTag() {
   if(g_UseRegimeLEAN4) return "LEAN4";
   if(!g_UseRegimeSuiteGate) return "OFF";
   string s = "";
   if(g_UseRegimeADX)        s += "ADX ";
   if(g_UseRegimeER)         s += "ER ";
   if(g_UseRegimeCHOP)       s += "CHOP ";
   if(g_UseRegimeLinReg)     s += "LinReg ";
   if(g_UseRegimeATRRatio)   s += "ATRRatio ";
   if(g_UseRegimeMMI)        s += "MMI ";
   if(g_UseRegimeSession)    s += "Session ";
   if(g_UseATRBandGate)      s += "ATRBand ";
   if(g_UseATRSpikeFilter)   s += "ATRSpike ";
   if(g_UseAsianRangeFilter) s += "AsianRange ";
   if(s == "") s = "OFF";
   return s;
}

datetime Bot1SessionAnchorTime(datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.min = 0; dt.sec = 0;
   int anchor = VwapAnchorHour;
   if(anchor < 0) anchor = 0;
   if(anchor > 23) anchor = 23;
   if(dt.hour >= anchor) {
      dt.hour = anchor;
      return StructToTime(dt);
   }
   datetime today0 = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   return today0 - (datetime)((24 - anchor) * 3600);
}

void Bot1ComputeSuperTrend(int &outDir, double &outLine) {
   outDir = 0; outLine = 0.0;
   if(superTrendAtrHandle == INVALID_HANDLE) return;
   int warmup = SuperTrendWarmupBars;
   if(warmup < 10) warmup = 10;
   int need = warmup + SuperTrendATRPeriod + 2;
   double atr[], hi[], lo[], cl[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(cl, true);
   if(CopyBuffer(superTrendAtrHandle, 0, 0, need, atr) < need) return;
   if(CopyHigh(_Symbol, HigherTimeframe, 0, need, hi) < need) return;
   if(CopyLow(_Symbol, HigherTimeframe, 0, need, lo) < need) return;
   if(CopyClose(_Symbol, HigherTimeframe, 0, need, cl) < need) return;

   // Recurse oldest -> newest. Arrays are series, so index need-1 is oldest.
   int oldest = need - 1;
   double prevUp = 0, prevDn = 0;
   int trend = 1;
   double stLine = 0;
   bool started = false;
   for(int k = oldest; k >= 0; k--) {
      if(atr[k] <= 0.0) continue;
      double src = (hi[k] + lo[k]) * 0.5;
      double up = src - SuperTrendMultiplier * atr[k];
      double dn = src + SuperTrendMultiplier * atr[k];
      if(!started) {
         prevUp = up; prevDn = dn; trend = (cl[k] >= src) ? 1 : -1;
         stLine = (trend == 1) ? up : dn;
         started = true;
         continue;
      }
      int prev = k + 1;
      if(cl[prev] > prevUp) up = MathMax(up, prevUp);
      if(cl[prev] < prevDn) dn = MathMin(dn, prevDn);
      if(trend == 1) {
         if(cl[k] < prevUp) trend = -1;
      } else {
         if(cl[k] > prevDn) trend = 1;
      }
      prevUp = up; prevDn = dn;
      stLine = (trend == 1) ? up : dn;
   }
   if(!started) return;
   outDir = trend;
   outLine = stLine;
}

void Bot1ComputeSessionVwap(double &outVwap, double &outStdev) {
   outVwap = 0.0; outStdev = 0.0;
   datetime now = TimeCurrent();
   datetime anchor = Bot1SessionAnchorTime(now);
   int bars = Bars(_Symbol, _Period);
   if(bars < 2) return;

   double sumPV = 0.0, sumV = 0.0, sumPV2 = 0.0;
   int used = 0;
   // Walk newest->oldest until we pass the session anchor. Cap at 2000 bars.
   int cap = MathMin(bars - 1, 2000);
   for(int i = 0; i <= cap; i++) {
      datetime bt = iTime(_Symbol, _Period, i);
      if(bt == 0) break;
      if(bt < anchor) break;
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      long vol = iTickVolume(_Symbol, _Period, i);
      if(h <= 0 || l <= 0 || c <= 0 || vol <= 0) continue;
      double tp = (h + l + c) / 3.0;
      double v = (double)vol;
      sumPV += tp * v;
      sumV += v;
      sumPV2 += tp * tp * v;
      used++;
   }
   if(sumV <= 0.0 || used <= 0) return;
   outVwap = sumPV / sumV;
   double var = (sumPV2 / sumV) - (outVwap * outVwap);
   if(var < 0.0) var = 0.0;
   outStdev = MathSqrt(var);
}

double Bot1ComputeBBWidthPercentile() {
   if(bollHandle == INVALID_HANDLE) return 50.0;
   int n = BBWidthLookback;
   if(n < 5) n = 5;
   double upper[], lower[], mid[];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(mid, true);
   if(CopyBuffer(bollHandle, 1, 0, n, upper) < n) return 50.0;
   if(CopyBuffer(bollHandle, 2, 0, n, lower) < n) return 50.0;
   if(CopyBuffer(bollHandle, 0, 0, n, mid) < n) return 50.0;
   double widths[];
   ArrayResize(widths, n);
   int valid = 0;
   for(int i = 0; i < n; i++) {
      double w = upper[i] - lower[i];
      if(w < 0) w = 0;
      // relative width when mid is usable, else absolute
      if(mid[i] > 0) w = w / mid[i];
      widths[i] = w;
      valid++;
   }
   if(valid <= 1) return 50.0;
   double current = widths[0];
   int below = 0;
   for(int i = 0; i < valid; i++)
      if(widths[i] <= current) below++;
   return 100.0 * (double)below / (double)valid;
}

double Bot1ComputeADXSlope() {
   if(adxHandle == INVALID_HANDLE) return 0.0;
   int lb = ADXSlopeLookback;
   if(lb < 1) lb = 1;
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(adxHandle, 0, 0, lb + 1, adx) < lb + 1) return 0.0;
   return adx[0] - adx[lb];
}

double Bot1ComputeExhaustionFrac() {
   if(adr <= 0.0) return 0.0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(dayStart == 0) return 0.0;
   // Realized range of the current D1 bar (today so far).
   double hi = iHigh(_Symbol, PERIOD_D1, 0);
   double lo = iLow(_Symbol, PERIOD_D1, 0);
   if(hi <= 0 || lo <= 0 || hi < lo) return 0.0;
   return (hi - lo) / adr;
}

void Bot1RefreshRegime2Cache() {
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(g_r2.valid && g_r2.barTime == curBar) return;

   g_r2.barTime = curBar;
   g_r2.valid = true;

   // REGIME 2.1 scaffold: compute+log the new continuous score once per bar,
   // same cadence as the rest of this cache. Inert (returns immediately)
   // unless UseRegime21Score=true.
   Bot1ComputeRegime21Score();
   Bot1WriteRegime21DiagCsv();

   // REGIME 2.1 v3: multi-indicator classifier, same cadence. Inert unless
   // UseRegime21Classifier=true.
   Bot1ComputeRegime21Bucket();
   Bot1WriteRegime21BucketCsv();

   g_r2.adxSlope = Bot1ComputeADXSlope();
   g_r2.adxValue = 0.0;
   if(adxHandle != INVALID_HANDLE) {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(adxHandle, 0, 0, 1, adx) >= 1) g_r2.adxValue = adx[0];
   }

   g_r2.sessionVwap = 0.0; g_r2.vwapStdev = 0.0; g_r2.vwapUpper = 0.0; g_r2.vwapLower = 0.0;
   if(Bot1NeedsSessionVwap() || Bot1R2DiagOn()) {
      Bot1ComputeSessionVwap(g_r2.sessionVwap, g_r2.vwapStdev);
      g_r2.vwapUpper = g_r2.sessionVwap + VwapDevSigma * g_r2.vwapStdev;
      g_r2.vwapLower = g_r2.sessionVwap - VwapDevSigma * g_r2.vwapStdev;
   }

   g_r2.bbWidthPctile = 50.0; g_r2.bbWidth = 0.0;
   if(Bot1Lean4Active() || Bot1R2DiagOn()) {
      g_r2.bbWidthPctile = Bot1ComputeBBWidthPercentile();
      if(bollHandle != INVALID_HANDLE) {
         double u[], l[];
         ArraySetAsSeries(u, true); ArraySetAsSeries(l, true);
         if(CopyBuffer(bollHandle, 1, 0, 1, u) >= 1 && CopyBuffer(bollHandle, 2, 0, 1, l) >= 1)
            g_r2.bbWidth = u[0] - l[0];
      }
   }

   g_r2.superTrendDir = 0; g_r2.superTrendLine = 0.0;
   if(Bot1NeedsSuperTrend() || Bot1R2DiagOn())
      Bot1ComputeSuperTrend(g_r2.superTrendDir, g_r2.superTrendLine);

   g_r2.ema200Bias = 0;
   if(emaSlowHandle != INVALID_HANDLE) {
      double s[];
      ArraySetAsSeries(s, true);
      if(CopyBuffer(emaSlowHandle, 0, 0, 1, s) >= 1) {
         double c = iClose(_Symbol, HigherTimeframe, 0);
         if(c > s[0]) g_r2.ema200Bias = 1;
         else if(c < s[0]) g_r2.ema200Bias = -1;
      }
   }

   g_r2.cciValue = 0.0; g_r2.cciSignal = 0;
   if(cciHandle != INVALID_HANDLE) {
      double cci[];
      ArraySetAsSeries(cci, true);
      if(CopyBuffer(cciHandle, 0, 0, 1, cci) >= 1) {
         g_r2.cciValue = cci[0];
         if(cci[0] > 0) g_r2.cciSignal = 1;
         else if(cci[0] < 0) g_r2.cciSignal = -1;
      }
   }

   g_r2.stochK = 50.0;
   if(stochHandle != INVALID_HANDLE) {
      double k[];
      ArraySetAsSeries(k, true);
      if(CopyBuffer(stochHandle, 0, 0, 1, k) >= 1) g_r2.stochK = k[0];
   }

   g_r2.atrStop = 0.0;
   if(atrStopHandle != INVALID_HANDLE) {
      double a[];
      ArraySetAsSeries(a, true);
      if(CopyBuffer(atrStopHandle, 0, 0, 1, a) >= 1) g_r2.atrStop = a[0] * g_ATRStopMultiplier;
   }

   g_r2.exhaustionFrac = Bot1ComputeExhaustionFrac();
   g_r2.exhaustionSkip = (g_UseADRExhaustionFilter && g_r2.exhaustionFrac >= ADRExhaustionPct && adr > 0.0);
}

double GetADXSlope() {
   Bot1RefreshRegime2Cache();
   return g_r2.adxSlope;
}

double GetSessionVWAP() {
   Bot1RefreshRegime2Cache();
   return g_r2.sessionVwap;
}

void GetVWAPDeviationBands(double sigma, double &upper, double &lower) {
   Bot1RefreshRegime2Cache();
   upper = g_r2.sessionVwap + sigma * g_r2.vwapStdev;
   lower = g_r2.sessionVwap - sigma * g_r2.vwapStdev;
}

int GetSuperTrendSignal() {
   Bot1RefreshRegime2Cache();
   return g_r2.superTrendDir;
}

int GetEMA200Bias() {
   Bot1RefreshRegime2Cache();
   return g_r2.ema200Bias;
}

int GetCCIMomentum() {
   Bot1RefreshRegime2Cache();
   return g_r2.cciSignal;
}

double GetBBWidthPercentile() {
   Bot1RefreshRegime2Cache();
   return g_r2.bbWidthPctile;
}

bool RegimeADXSlopeTrending() {
   return GetADXSlope() > 0.0;
}

bool RegimeBBWidthTrending() {
   return GetBBWidthPercentile() >= BBWidthPctileTrendMin;
}

void Bot1UpdateDonchianRetest() {
   datetime curBar = iTime(_Symbol, _Period, 0);
   static datetime s_retestUpdatedBar = 0;
   if(s_retestUpdatedBar == curBar) return;
   s_retestUpdatedBar = curBar;

   // Uses the same "prior Donchian" definition as GetDonchianTrigger:
   // bands from bars 1..DonchianPeriod, break evaluated on close[0] vs close[1].
   int needed = DonchianPeriod + 1;
   double high[], low[], closeArr[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(closeArr, true);
   if(CopyHigh(_Symbol, _Period, 0, needed, high) < needed) return;
   if(CopyLow(_Symbol, _Period, 0, needed, low) < needed) return;
   if(CopyClose(_Symbol, _Period, 0, 2, closeArr) < 2) return;

   double upperBand = high[1];
   double lowerBand = low[1];
   for(int i = 1; i < DonchianPeriod; i++) {
      if(high[i] > upperBand) upperBand = high[i];
      if(low[i] < lowerBand) lowerBand = low[i];
   }

   if(g_retestPendingDir != 0) {
      g_retestBarsLeft--;
      if(g_retestBarsLeft <= 0) {
         g_retestPendingDir = 0;
         g_retestLevel = 0.0;
      }
   }

   // Fresh breakout starts (or refreshes) a pending retest. Evaluated
   // even while one is pending so a new break can replace a stale one.
   if(closeArr[1] <= upperBand && closeArr[0] > upperBand) {
      g_retestPendingDir = 1;
      g_retestLevel = upperBand;
      g_retestBarsLeft = RetestExpireBars;
   } else if(closeArr[1] >= lowerBand && closeArr[0] < lowerBand) {
      g_retestPendingDir = -1;
      g_retestLevel = lowerBand;
      g_retestBarsLeft = RetestExpireBars;
   }
}

int GetDonchianRetestTrigger() {
   if(g_retestPendingDir == 0 || g_retestLevel <= 0.0) return 0;
   // Same bar we armed is the breakout — wait for a later bar to pull back.
   if(g_retestBarsLeft >= RetestExpireBars) return 0;
   double c = iClose(_Symbol, _Period, 0);
   double h = iHigh(_Symbol, _Period, 0);
   double l = iLow(_Symbol, _Period, 0);
   if(g_retestPendingDir == 1) {
      // pullback: low tagged the broken high, close held above it
      if(l <= g_retestLevel && c > g_retestLevel) return 1;
   } else if(g_retestPendingDir == -1) {
      if(h >= g_retestLevel && c < g_retestLevel) return -1;
   }
   return 0;
}

int GetVWAPReclaimTrigger() {
   double vwap = GetSessionVWAP();
   if(vwap <= 0.0) return 0;
   double c0 = iClose(_Symbol, _Period, 0);
   double c1 = iClose(_Symbol, _Period, 1);
   if(c0 <= 0 || c1 <= 0) return 0;
   // Away on the previous bar, close back through VWAP this bar.
   if(c1 < vwap && c0 > vwap) return 1;
   if(c1 > vwap && c0 < vwap) return -1;
   return 0;
}

void Bot1WriteRegime2DiagCsv() {
   if(!Bot1R2DiagOn()) return;
   string filename = Bot1FilePrefix + "_regime2_diag_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_r2DiagLogHandle, filename,
      "event_time,symbol,adx,adx_slope,vwap,vwap_stdev,bb_width,bb_width_pctile,"
      "st_dir,st_line,cci,stoch_k,exhaustion_frac,atr_stop,layer1_mode,layer3_mode,preset\n");
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + ","
      + DoubleToString(g_r2.adxValue, 4) + "," + DoubleToString(g_r2.adxSlope, 4) + ","
      + DoubleToString(g_r2.sessionVwap, _Digits) + "," + DoubleToString(g_r2.vwapStdev, _Digits) + ","
      + DoubleToString(g_r2.bbWidth, _Digits) + "," + DoubleToString(g_r2.bbWidthPctile, 2) + ","
      + IntegerToString(g_r2.superTrendDir) + "," + DoubleToString(g_r2.superTrendLine, _Digits) + ","
      + DoubleToString(g_r2.cciValue, 4) + "," + DoubleToString(g_r2.stochK, 2) + ","
      + DoubleToString(g_r2.exhaustionFrac, 4) + "," + DoubleToString(g_r2.atrStop, _Digits) + ","
      + Bot1Layer1TickTag() + "," + Bot1Layer3TickTag() + "," + Bot1RegimeTickTag() + "\n");
}

void Bot1LogRegime2Share() {
   if(!Bot1R2DiagOn()) return;
   Print("[BOT1-R2-SHARE] ", _Symbol,
         " adx_slope=", DoubleToString(g_r2.adxSlope, 4),
         " adx=", DoubleToString(g_r2.adxValue, 2),
         " vwap=", DoubleToString(g_r2.sessionVwap, _Digits),
         " vwap_stdev=", DoubleToString(g_r2.vwapStdev, _Digits),
         " bb_width_pctile=", DoubleToString(g_r2.bbWidthPctile, 1),
         " st_dir=", g_r2.superTrendDir,
         " exhaustion_frac=", DoubleToString(g_r2.exhaustionFrac, 3),
         " atr_stop=", DoubleToString(g_r2.atrStop, _Digits),
         " cache_bar=", TimeToString(g_r2.barTime));
}

// ── REGIME 2.1: continuous regime-strength score (v2, 2026-09-17 redesign).
// v1 (ADX level+slope+ATR%ile) was found via per-trade cross-check to NEVER
// be low at any bar where the existing L1/L2/L3 signal fired -- it was just
// re-deriving information the entry logic already required, so no threshold
// ever did anything but strictly remove otherwise-fine trades (verified: a
// 321-point exhaustive threshold sweep never beat the unfiltered baseline).
// v2 uses INDEPENDENT ingredients the entry stack has no equivalent of:
//   - Kaufman Efficiency Ratio: net directional move / total path length,
//     0-1. Orthogonal to PSAR/EMA/ADX -- a momentum signal can fire while
//     price chops back and forth net-sideways (low ER) or moves cleanly
//     (high ER); the entry logic cannot see this distinction today.
//   - Choppiness Index (Dreiss): true-range-sum vs high-low range, ~0-100,
//     HIGH = congested/choppy. Measures micro-structure noise independent
//     of trend direction.
//   - Session/liquidity timing: 0-1, peaks inside [Regime21SessionStartHour,
//     Regime21SessionEndHour] (broker time), linearly tapers to 0 over
//     Regime21SessionTaperHours on either side. The entry logic has ZERO
//     time-of-day awareness today -- this is genuinely new information, not
//     a re-derivation.
// Computes and logs only until Regime21MinScoreToTrade > 0 deliberately
// gates on it (same off-by-default discipline as v1).
void Bot1ComputeRegime21Score() {
   if(!UseRegime21Score) return;

   // --- Kaufman Efficiency Ratio ---
   int erN = Regime21ERPeriod;
   double erValue = 0.0;
   if(erN > 0) {
      double closeArr[];
      ArraySetAsSeries(closeArr, true);
      if(CopyClose(_Symbol, _Period, 0, erN + 1, closeArr) >= erN + 1) {
         double netMove = MathAbs(closeArr[0] - closeArr[erN]);
         double pathSum = 0.0;
         for(int i = 0; i < erN; i++) pathSum += MathAbs(closeArr[i] - closeArr[i + 1]);
         if(pathSum > 0.0) erValue = netMove / pathSum;
      }
   }

   // --- Choppiness Index ---
   int chopN = Regime21CHOPPeriod;
   double chopValue = 50.0; // neutral default if data unavailable
   if(chopN > 1) {
      double highArr[], lowArr[], closeArr2[];
      ArraySetAsSeries(highArr, true);
      ArraySetAsSeries(lowArr, true);
      ArraySetAsSeries(closeArr2, true);
      int needed = chopN + 1;
      if(CopyHigh(_Symbol, _Period, 0, needed, highArr) >= needed
         && CopyLow(_Symbol, _Period, 0, needed, lowArr) >= needed
         && CopyClose(_Symbol, _Period, 0, needed, closeArr2) >= needed) {
         double atrSum = 0.0;
         double hh = highArr[0], ll = lowArr[0];
         for(int i = 0; i < chopN; i++) {
            double tr = MathMax(highArr[i] - lowArr[i],
                        MathMax(MathAbs(highArr[i] - closeArr2[i + 1]), MathAbs(lowArr[i] - closeArr2[i + 1])));
            atrSum += tr;
            if(highArr[i] > hh) hh = highArr[i];
            if(lowArr[i] < ll) ll = lowArr[i];
         }
         double range = hh - ll;
         if(range > 0.0 && atrSum > 0.0)
            chopValue = 100.0 * MathLog10(atrSum / range) / MathLog10((double)chopN);
      }
   }

   // --- Session/liquidity timing ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   int startH = Regime21SessionStartHour;
   int endH = Regime21SessionEndHour;
   int taper = MathMax(1, Regime21SessionTaperHours);
   double sessionValue;
   if(hour >= startH && hour <= endH) {
      sessionValue = 1.0;
   } else {
      int distOutside = (hour < startH) ? (startH - hour) : (hour - endH);
      sessionValue = MathMax(0.0, 1.0 - (double)distOutside / taper);
   }

   g_r21.erValue = erValue;
   g_r21.chopValue = chopValue;
   g_r21.sessionValue = sessionValue;

   double erNorm = MathMax(0.0, MathMin(erValue, 1.0));           // already 0-1
   double chopNorm = 1.0 - MathMax(0.0, MathMin(chopValue / 100.0, 1.0)); // invert: low CHOP (uncongested) = high score
   double sessionNorm = sessionValue;                              // already 0-1

   g_r21.compositeScore = Regime21WeightER * erNorm
                         + Regime21WeightCHOP * chopNorm
                         + Regime21WeightSession * sessionNorm;
   g_r21.barTime = iTime(_Symbol, _Period, 0);
}

void Bot1WriteRegime21DiagCsv() {
   if(!UseRegime21Score || !LogRegime21Diagnostics) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // per-bar disk I/O -- must not run during optimization passes (matches every other per-bar diagnostic writer in this file)
   string filename = Bot1FilePrefix + "_regime21_score_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_r21LogHandle, filename,
      "event_time,symbol,er_value,chop_value,session_value,composite_score\n");
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + ","
      + DoubleToString(g_r21.erValue, 4) + "," + DoubleToString(g_r21.chopValue, 2) + ","
      + DoubleToString(g_r21.sessionValue, 4) + ","
      + DoubleToString(g_r21.compositeScore, 4) + "\n");
}

// ── REGIME 2.1 v3: multi-indicator classifier (majority vote, NOT blended).
// Reuses 2.0's own 6 trend-vs-range Regime Suite voters exactly as they
// exist today (same Get*/Regime*Trending() functions, same UseRegime* on/
// off toggles, same calibrated thresholds -- RegimeADXTrendMin etc.). Only
// voters whose UseRegime* flag is enabled count toward the majority; a
// disabled voter is excluded entirely, not counted as either side (this
// matters because each *Trending() function returns `true`/no-veto when
// its own flag is off, which would otherwise silently bias every bucket
// toward TREND). Session is logged as separate context, not voted.
void Bot1ComputeRegime21Bucket() {
   if(!UseRegime21Classifier) return;

   Bot1RefreshVoteCache();

   int trendVotes = 0;
   int activeVoters = 0;

   if(g_UseRegimeADX)      { g_r21b.adxVote = g_voteCacheADX;      activeVoters++; if(g_r21b.adxVote) trendVotes++; } else g_r21b.adxVote = false;
   if(g_UseRegimeER)       { g_r21b.erVote = g_voteCacheER;        activeVoters++; if(g_r21b.erVote) trendVotes++; } else g_r21b.erVote = false;
   if(g_UseRegimeCHOP)     { g_r21b.chopVote = g_voteCacheCHOP;    activeVoters++; if(g_r21b.chopVote) trendVotes++; } else g_r21b.chopVote = false;
   if(g_UseRegimeLinReg)   { g_r21b.linRegVote = g_voteCacheLinReg; activeVoters++; if(g_r21b.linRegVote) trendVotes++; } else g_r21b.linRegVote = false;
   if(g_UseRegimeATRRatio) { g_r21b.atrRatioVote = g_voteCacheATRRatio; activeVoters++; if(g_r21b.atrRatioVote) trendVotes++; } else g_r21b.atrRatioVote = false;
   if(g_UseRegimeMMI)      { g_r21b.mmiVote = g_voteCacheMMI;      activeVoters++; if(g_r21b.mmiVote) trendVotes++; } else g_r21b.mmiVote = false;

   g_r21b.votersActive = activeVoters;
   g_r21b.trendVotes = trendVotes;
   g_r21b.sessionActive = RegimeSessionAllowed();

   if(activeVoters == 0) {
      g_r21b.bucket = R21_BUCKET_MIXED;   // no voters enabled -- can't classify, not a silent TREND default
   } else {
      int chopVotes = activeVoters - trendVotes;
      int majorityThreshold = MathMin(Regime21BucketMajority, activeVoters); // clamp so the threshold never exceeds however many voters are actually active
      if(trendVotes >= majorityThreshold) g_r21b.bucket = R21_BUCKET_TREND;
      else if(chopVotes >= majorityThreshold) g_r21b.bucket = R21_BUCKET_CHOP;
      else g_r21b.bucket = R21_BUCKET_MIXED;
   }
   g_r21b.barTime = iTime(_Symbol, _Period, 0);

   // DIRECTIONAL LEAN (2026-09-19): 3 free directional reads, majority vote.
   // 1) LinReg slope sign -- reuses g_UseRegimeLinReg's own computation
   //    (GetRegimeLinRegR2's outSlope was computed and discarded before
   //    today; only requires g_UseRegimeLinReg to be on, same as the CHOP
   //    voter it's already sitting next to).
   // 2) HTF EMA200 bias (g_r2.ema200Bias) -- already computed every bar for
   //    the Layer 1 signal regardless of any Regime21 toggle.
   // 3) HTF SuperTrend direction (g_r2.superTrendDir) -- same, always live.
   // Deliberately does NOT touch L2's ADX +DI/-DI (that's a SEPARATE toggle,
   // UseADX, not UseRegimeADX -- confirmed via real data it was 0/0 for
   // every trade in the config that surfaced this whole investigation, so
   // building on it would have silently inherited the same blind spot).
   int upVotes = 0, downVotes = 0, dirVotersActive = 0;
   if(g_UseRegimeLinReg) {
      double slope;
      GetRegimeLinRegR2(slope);
      dirVotersActive++;
      if(slope > 0) upVotes++; else if(slope < 0) downVotes++;
   }
   if(g_r2.ema200Bias != 0) {
      dirVotersActive++;
      if(g_r2.ema200Bias > 0) upVotes++; else downVotes++;
   }
   if(g_r2.superTrendDir != 0) {
      dirVotersActive++;
      if(g_r2.superTrendDir > 0) upVotes++; else downVotes++;
   }
   if(dirVotersActive == 0) {
      g_r21b.direction = 0;
      g_r21b.directionVotes = 0;
   } else if(upVotes > downVotes) {
      g_r21b.direction = 1;
      g_r21b.directionVotes = upVotes;
   } else if(downVotes > upVotes) {
      g_r21b.direction = -1;
      g_r21b.directionVotes = downVotes;
   } else {
      g_r21b.direction = 0;   // tie -- no lean either way
      g_r21b.directionVotes = upVotes;
   }

   // FLIP TIMING: compare this bar's bucket/direction against what they
   // were last bar. First bar ever (g_r21bFlipStateInit==false) has no
   // real "previous" to compare against, so treat it as "just flipped"
   // (0 bars) rather than fabricating a fake long-standing state.
   if(!g_r21bFlipStateInit) {
      g_r21b.barsSinceBucketFlip = 0;
      g_r21b.barsSinceDirectionFlip = 0;
      g_r21bFlipStateInit = true;
   } else {
      if(g_r21b.bucket != g_r21bPrevBucket) g_r21b.barsSinceBucketFlip = 0;
      else g_r21b.barsSinceBucketFlip++;

      if(g_r21b.direction != g_r21bPrevDirection) g_r21b.barsSinceDirectionFlip = 0;
      else g_r21b.barsSinceDirectionFlip++;
   }
   g_r21bPrevBucket = g_r21b.bucket;
   g_r21bPrevDirection = g_r21b.direction;
}

// Returns true if a candidate trade's DIRECTION agrees with the regime
// classifier's own directional lean computed above -- e.g. a SELL when
// g_r21b.direction == -1, or a BUY when g_r21b.direction == 1. Returns
// true (does not block) when direction==0 (no lean either way) -- this is
// a NEW, currently PASSIVE diagnostic only; nothing calls this as a gate
// yet, it just gets logged onto every trade so we can validate whether it
// actually explains SELL+TREND's weak win rate before wiring it into any
// real entry-blocking logic (same log-first discipline as the rest of the
// v3 classifier build).
bool Bot1Regime21DirectionAgrees(int tradeDirection) {
   if(g_r21b.direction == 0) return true;
   return (tradeDirection > 0 && g_r21b.direction > 0) || (tradeDirection < 0 && g_r21b.direction < 0);
}

string Bot1Regime21BucketToString(ENUM_REGIME21_BUCKET b) {
   if(b == R21_BUCKET_TREND) return "TREND";
   if(b == R21_BUCKET_CHOP) return "CHOP";
   return "MIXED";
}

void Bot1WriteRegime21BucketCsv() {
   if(!UseRegime21Classifier || !LogRegime21BucketCsv) return;
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // per-bar disk I/O -- must not run during optimization passes (matches every other per-bar diagnostic writer in this file)
   string filename = Bot1FilePrefix + "_regime21_bucket_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_r21BucketLogHandle, filename,
      "event_time,symbol,adx_vote,er_vote,chop_vote,linreg_vote,atrratio_vote,mmi_vote,voters_active,trend_votes,session_active,bucket\n");
   if(handle == INVALID_HANDLE) return;
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + ","
      + (g_r21b.adxVote ? "1" : "0") + "," + (g_r21b.erVote ? "1" : "0") + ","
      + (g_r21b.chopVote ? "1" : "0") + "," + (g_r21b.linRegVote ? "1" : "0") + ","
      + (g_r21b.atrRatioVote ? "1" : "0") + "," + (g_r21b.mmiVote ? "1" : "0") + ","
      + IntegerToString(g_r21b.votersActive) + "," + IntegerToString(g_r21b.trendVotes) + ","
      + (g_r21b.sessionActive ? "1" : "0") + "," + Bot1Regime21BucketToString(g_r21b.bucket) + "\n");
}

void Bot1LogRegime2Layers(Bot1Layer1State &l1, Bot1Layer2State &l2, Bot1Layer3State &l3) {
   if(!Bot1R2DiagOn()) return;
   Print("[BOT1-R2-L1] ", _Symbol, " ticks=", Bot1Layer1TickTag(),
         " n=", l1.l1_vote_n,
         " ichi=", l1.ichi_signal, " ema=", l1.ema_signal, " psar=", l1.psar_signal,
         " st=", l1.st_signal, " st_line=", DoubleToString(g_r2.superTrendLine, _Digits),
         " ema200bias=", g_r2.ema200Bias, " -> ", l1.l1_result);
   Print("[BOT1-R2-L2] ", _Symbol, " rsi_mode=", EnumToString(g_Layer2RSIMode),
         " rsi=", DoubleToString(l2.rsi_value, 2), " rsi_sig=", l2.rsi_signal,
         " rsi_active=", (l2.rsi_voter_active ? "Y" : "N"),
         " adx=", DoubleToString(l2.adx_value, 2), " slope=", DoubleToString(l2.adx_slope, 4),
         " adx_src=", (g_UseADXSlope ? "slope" : "level"), " adx_ok=", (l2.adx_ok ? "Y" : "N"),
         " cci=", DoubleToString(l2.cci_value, 2), " cci_sig=", l2.cci_signal,
         " cci_active=", (l2.cci_voter_active ? "Y" : "N"),
         " prefer=", (g_PreferCCIInTrend ? "Y" : "N"),
         " ranging=", (Bot1RegimeSuiteSaysRanging() ? "Y" : "N"),
         " confirm=", l2.l2_confirmations, " pass=", (l2.l2_pass_strict ? "Y" : "N"));
   Print("[BOT1-R2-L3] ", _Symbol, " ticks=", Bot1Layer3TickTag(),
         " boll=", l3.boll_signal, " obv=", l3.obv_signal, " donch=", l3.donchian_signal,
         " retest=", l3.retest_signal, " pending=", l3.retest_pending_dir,
         " bars_left=", l3.retest_bars_left,
         " vwap_reclaim=", l3.vwap_reclaim_signal,
         " vwap=", DoubleToString(g_r2.sessionVwap, _Digits),
         " -> ", l3.l3_result, " pass=", (l3.l3_pass_strict ? "Y" : "N"));
   Print("[BOT1-R2-REGIME] ", _Symbol, " ticks=", Bot1RegimeTickTag(),
         " vote=", EnumToString(RegimeSuiteVoteMode),
         " adx_slope=", DoubleToString(g_r2.adxSlope, 4), (RegimeADXSlopeTrending() ? "(T)" : "(R)"),
         " chop=", DoubleToString(GetRegimeCHOP(), 1), (RegimeCHOPTrending() ? "(T)" : "(R)"),
         " bb_pctile=", DoubleToString(g_r2.bbWidthPctile, 1), (RegimeBBWidthTrending() ? "(T)" : "(R)"),
         " session=", (RegimeSessionAllowed() ? "IN" : "OUT"),
         " -> ", (Bot1RegimeSuiteSaysRanging() ? "RANGE" : "TREND"));
   Print("[BOT1-R2-SL] ", _Symbol, " basis=", EnumToString(g_StopBasisMode),
         " atr_dist=", DoubleToString(g_r2.atrStop, _Digits),
         " adr=", DoubleToString(adr, _Digits),
         " exhaustion_frac=", DoubleToString(g_r2.exhaustionFrac, 3),
         " skip=", (g_r2.exhaustionSkip ? "YES" : "NO"));
}

//+------------------------------------------------------------------+
//| REGIME DETECTION SUITE (branch v4)                               |
//| Six independently-toggleable filters + a session filter. Every   |
//| Get* function returns 0.0/false-safe defaults and every Trending |
//| check returns TRUE (never vetoes) when its own Use flag is off - |
//| same "disabled costs nothing, disabled never blocks" discipline  |
//| used throughout this file. See input group comments for sourcing|
//| and threshold rationale (Wilder 1978, Kaufman 1995, Dreiss 1993, |
//| Lotter/Financial Hacker).                                        |
//+------------------------------------------------------------------+

// --- ADX/ADXR: Wilder's own regime cutoff is ADXR, the average of the
// current ADX and ADX from N bars ago, not raw ADX alone.
double GetRegimeADXR() {
   if(!g_UseRegimeADX || regimeAdxHandle == INVALID_HANDLE) return 0.0;
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   int needed = RegimeADXPeriod + 1;
   if(CopyBuffer(regimeAdxHandle, 0, 0, needed, adxBuf) < needed) return 0.0;
   return (adxBuf[0] + adxBuf[RegimeADXPeriod]) / 2.0;
}
bool RegimeADXTrending() {
   if(!g_UseRegimeADX) return true;
   return GetRegimeADXR() >= RegimeADXTrendMin;
}

// --- Kaufman Efficiency Ratio: net directional move / total path length.
double GetRegimeER() {
   if(!g_UseRegimeER) return 0.0;
   int n = RegimeERPeriod;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, n+1, closeArr) < n+1) return 0.0;
   double netMove = MathAbs(closeArr[0] - closeArr[n]);
   double pathSum = 0.0;
   for(int i = 0; i < n; i++) pathSum += MathAbs(closeArr[i] - closeArr[i+1]);
   if(pathSum <= 0.0) return 0.0;
   return netMove / pathSum;
}
bool RegimeERTrending() {
   if(!g_UseRegimeER) return true;
   return GetRegimeER() >= RegimeERTrendMin;
}

// --- Choppiness Index (Dreiss 1993): 100*log10(sum(TR,n)/(HH-LL)) / log10(n).
// High = choppy/congested, low = trending -- opposite polarity to ADX.
double GetRegimeCHOP() {
   if(!g_UseRegimeCHOP && !Bot1Lean4Active()) return 0.0;
   int n = RegimeCHOPPeriod;
   if(n <= 1) return 0.0;
   double highArr[], lowArr[], closeArr[];
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   ArraySetAsSeries(closeArr, true);
   int needed = n + 1;
   if(CopyHigh(_Symbol, _Period, 0, needed, highArr) < needed) return 0.0;
   if(CopyLow(_Symbol, _Period, 0, needed, lowArr) < needed) return 0.0;
   if(CopyClose(_Symbol, _Period, 0, needed, closeArr) < needed) return 0.0;

   double atrSum = 0.0;
   double hh = highArr[0], ll = lowArr[0];
   for(int i = 0; i < n; i++) {
      double tr = MathMax(highArr[i] - lowArr[i],
                  MathMax(MathAbs(highArr[i] - closeArr[i+1]), MathAbs(lowArr[i] - closeArr[i+1])));
      atrSum += tr;
      if(highArr[i] > hh) hh = highArr[i];
      if(lowArr[i] < ll) ll = lowArr[i];
   }
   double range = hh - ll;
   if(range <= 0.0 || atrSum <= 0.0) return 0.0;
   return 100.0 * MathLog10(atrSum / range) / MathLog10((double)n);
}
bool RegimeCHOPTrending() {
   if(!g_UseRegimeCHOP && !Bot1Lean4Active()) return true;
   return GetRegimeCHOP() < RegimeCHOPRangeMax;
}

// --- Linear Regression R²: fraction of price variance explained by the
// least-squares line over the lookback. Also returns slope by reference.
double GetRegimeLinRegR2(double &outSlope) {
   outSlope = 0.0;
   if(!g_UseRegimeLinReg) return 0.0;
   int n = RegimeLinRegPeriod;
   if(n < 2) return 0.0;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, n, closeArr) < n) return 0.0;

   double sumX=0, sumY=0, sumXY=0, sumX2=0, sumY2=0;
   for(int i = 0; i < n; i++) {
      double x = (double)i;
      double y = closeArr[n-1-i];   // oldest first, so x increases forward in time
      sumX += x; sumY += y; sumXY += x*y; sumX2 += x*x; sumY2 += y*y;
   }
   double denom = (n*sumX2 - sumX*sumX);
   if(denom == 0.0) return 0.0;
   outSlope = (n*sumXY - sumX*sumY) / denom;

   double denCorr = MathSqrt((n*sumX2 - sumX*sumX) * (n*sumY2 - sumY*sumY));
   if(denCorr == 0.0) return 0.0;
   double r = (n*sumXY - sumX*sumY) / denCorr;
   return r*r;
}
bool RegimeLinRegTrending() {
   if(!g_UseRegimeLinReg) return true;
   double slope;
   return GetRegimeLinRegR2(slope) >= RegimeLinRegR2Min;
}

// --- ATR fast/slow ratio: volatility expansion vs contraction. v5.94:
// shares regimeAtrFastHandle/regimeAtrSlowHandle with UseVolatilityRatio's
// GetVolatilityRatio() above -- same underlying computation, two decision
// layers (this suite's binary vote input, and UseVolatilityRatio's 3-way
// TRENDING/RANGING/LOW_VOL always-on gate). No longer a duplicate handle.
double GetRegimeATRRatio() {
   if(!g_UseRegimeATRRatio || regimeAtrFastHandle == INVALID_HANDLE || regimeAtrSlowHandle == INVALID_HANDLE) return 1.0;
   double f[], s[];
   ArraySetAsSeries(f, true);
   ArraySetAsSeries(s, true);
   if(CopyBuffer(regimeAtrFastHandle, 0, 0, 1, f) < 1) return 1.0;
   if(CopyBuffer(regimeAtrSlowHandle, 0, 0, 1, s) < 1) return 1.0;
   if(s[0] <= 0.0) return 1.0;
   return f[0] / s[0];
}
bool RegimeATRRatioTrending() {
   if(!g_UseRegimeATRRatio) return true;
   return GetRegimeATRRatio() >= RegimeATRRatioMin;
}

// --- Market Meanness Index (Lotter/Financial Hacker): counts how often
// price crosses back toward its own rolling median vs continuing away
// from it. Falling MMI = trend developing; ~75 is the random-walk
// baseline. Faithful reimplementation from the published description, not
// a copy of proprietary source -- direction and threshold scale match the
// original, exact formula details may vary slightly.
double GetRegimeMMI() {
   if(!g_UseRegimeMMI) return 0.0;
   int n = RegimeMMILookback;
   if(n < 3) return 0.0;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, n, closeArr) < n) return 0.0;

   double sorted[];
   ArrayCopy(sorted, closeArr);
   ArraySort(sorted);
   double median = (n % 2 == 1) ? sorted[n/2] : (sorted[n/2 - 1] + sorted[n/2]) / 2.0;

   int reversionCount = 0;
   for(int i = 0; i < n-1; i++) {
      // price above median but pulling back down toward it, or below
      // median but pulling back up toward it -- a "reversion" crossing
      if(closeArr[i] > median && closeArr[i] < closeArr[i+1]) reversionCount++;
      if(closeArr[i] < median && closeArr[i] > closeArr[i+1]) reversionCount++;
   }
   return 100.0 * reversionCount / (double)(n-1);
}
bool RegimeMMITrending() {
   if(!g_UseRegimeMMI) return true;
   return GetRegimeMMI() <= RegimeMMITrendMax;
}

// --- Session filter: v5.94 merged with the former Community-filter
// "UseSessionGate" (Stage 2a) -- both computed the identical broker/server-
// hour in/out window with separate toggles and separate default hours; now
// one filter (this one), one toggle, feeding the SAME vote as every other
// Regime Suite filter instead of a second, differently-scoped gate.
bool RegimeSessionAllowed() {
   if(!g_UseRegimeSession && !Bot1Lean4Active()) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(RegimeSessionStartHour <= RegimeSessionEndHour)
      return (h >= RegimeSessionStartHour && h < RegimeSessionEndHour);
   else
      return (h >= RegimeSessionStartHour || h < RegimeSessionEndHour);   // wraps past midnight
}

// --- Stage 1a: ATR floor/ceiling band, on the EA's own trading timeframe.
// v5.94: was part of a SEPARATE "Community Filters" AND-only gate
// (UseCommunityFilterGate) with its own trigger path. Merged into the
// unified Regime Suite vote below -- no longer a second independent gate.
double GetATRBandPoints() {
   if(!g_UseATRBandGate || communityAtrBandHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(communityAtrBandHandle, 0, 0, 1, buf) < 1) return 0.0;
   return buf[0] / _Point;
}
bool ATRBandAllows() {
   if(!g_UseATRBandGate) return true;
   double atrPts = GetATRBandPoints();
   if(atrPts <= 0.0) return true;   // no data yet (e.g. cold start) -- don't block
   return (atrPts >= ATRBandFloorPoints && atrPts <= ATRBandCeilingPoints);
}

// --- Stage 1b: ATR spike filter, exact community rule -- M1-based
// regardless of the EA's own trading timeframe (MQL5 forum 504875).
double GetATRSpikeShort() {
   if(!g_UseATRSpikeFilter || communityAtrSpikeShortHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(communityAtrSpikeShortHandle, 0, 0, 1, buf) < 1) return 0.0;
   return buf[0];
}
double GetATRSpikeLong() {
   if(!g_UseATRSpikeFilter || communityAtrSpikeLongHandle == INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(communityAtrSpikeLongHandle, 0, 0, 1, buf) < 1) return 0.0;
   return buf[0];
}
bool ATRSpikeAllows() {
   if(!g_UseATRSpikeFilter) return true;
   double longAtr = GetATRSpikeLong();
   if(longAtr <= 0.0) return true;   // insufficient M1 history yet (start of test) -- don't block
   double shortAtr = GetATRSpikeShort();
   return !(shortAtr >= ATRSpikeMultiplier * longAtr);
}

// --- Asian range vs Daily ATR (GoldLondonBreakout rule). Called once per
// new bar from OnTick. Tracks the Asian window's high/low for the current
// calendar day, and finalizes that day's allow/block verdict exactly once,
// at the moment the window closes -- held for the rest of the day, not
// re-evaluated bar by bar (matches the source's "skip the day" design).
void Bot1UpdateAsianRangeTracking() {
   if(!g_UseAsianRangeFilter) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != g_asianRangeTrackedDay) {
      g_asianRangeTrackedDay = today;
      g_asianRangeHigh = 0.0;
      g_asianRangeLow = 0.0;
      g_asianRangeWindowSeen = false;
      g_asianRangeVerdictComputed = false;
      // g_asianRangeDayAllowed deliberately NOT reset here -- holds its
      // previous value until this new day's own verdict is computed, so
      // bars before the window closes today aren't blocked by a stale
      // reset-to-false.
   }

   int h = dt.hour;
   bool inWindow;
   if(AsianRangeStartHour <= AsianRangeEndHour)
      inWindow = (h >= AsianRangeStartHour && h < AsianRangeEndHour);
   else
      inWindow = (h >= AsianRangeStartHour || h < AsianRangeEndHour);

   if(inWindow) {
      double hi = iHigh(_Symbol, _Period, 0);
      double lo = iLow(_Symbol, _Period, 0);
      if(!g_asianRangeWindowSeen) {
         g_asianRangeHigh = hi;
         g_asianRangeLow = lo;
         g_asianRangeWindowSeen = true;
      } else {
         if(hi > g_asianRangeHigh) g_asianRangeHigh = hi;
         if(lo < g_asianRangeLow) g_asianRangeLow = lo;
      }
   } else if(g_asianRangeWindowSeen && !g_asianRangeVerdictComputed) {
      double dailyAtrBuf[];
      ArraySetAsSeries(dailyAtrBuf, true);
      if(communityDailyAtrHandle != INVALID_HANDLE &&
         CopyBuffer(communityDailyAtrHandle, 0, 0, 1, dailyAtrBuf) >= 1 && dailyAtrBuf[0] > 0.0) {
         double range = g_asianRangeHigh - g_asianRangeLow;
         double frac = range / dailyAtrBuf[0];
         g_asianRangeDayAllowed = (frac >= AsianRangeMinFrac && frac <= AsianRangeMaxFrac);
      } else {
         g_asianRangeDayAllowed = true;   // no daily ATR yet (very start of test) -- don't block
      }
      g_asianRangeVerdictComputed = true;
   }
}
bool AsianRangeFilterAllows() {
   if(!g_UseAsianRangeFilter) return true;
   return g_asianRangeDayAllowed;
}

// --- Composite verdict: vote-mode selectable via RegimeSuiteVoteMode.
// v5.94 (2026-08-29): full consolidation. Previously THREE independent
// trigger sources existed (this suite AND-only, a separate
// UseCommunityFilterGate AND-only gate, and the win-rate kill switch),
// each OR'd together at the entry-signal call site with no shared
// combine logic -- so re-testing "AND vs OR vs MAJORITY" (added v5.3)
// only ever covered the 6 academic filters, while the 4 community filters
// (ATR band, ATR spike, session, Asian-range) stayed on a separate,
// always-AND, never-vote-mode-tested path. Now ALL 10 possible filters
// (6 academic + ATR band + ATR spike + session + Asian-range) are voters
// in ONE suite, governed by ONE RegimeSuiteVoteMode. UseCommunityFilterGate
// and the separate Bot1CommunityFiltersSayBlocked()/UseSessionGate/
// RegimeSessionAllowed split are RETIRED -- g_UseRegimeSuiteGate is now the
// single master switch for every indicator/session/volatility-band filter
// in the file; only the win-rate kill switch (UseRegimeKillSwitch, reactive
// -- the strategy's own realized performance, a fundamentally different
// signal type) remains a separate, independently OR'd trigger.
//
// v5.3 (2026-08-28): Round 16 found the AND/veto suite (any one enabled
// filter can call "ranging" and block) measured worse than doing nothing at
// all, across all 128 combinations tested -- but that result conflated
// "these filters carry no signal" with "AND-gating many filters at once is
// too strict", AND (as of v5.94) was never even testing the full filter
// set, since 4 of the 10 filters were on a separate always-AND path the
// whole time. RegimeSuiteVoteMode (AND/OR/MAJORITY) lets the SAME full
// filter set be re-tested under all three combine logics before concluding
// anything about the filters themselves.
enum ENUM_REGIME_SUITE_VOTE {
   RS_VOTE_AND      = 0,   // ALL enabled filters must say "trending"/"allow" (strictest, most likely to veto real trends too)
   RS_VOTE_OR       = 1,   // ANY enabled filter saying "trending"/"allow" is enough (most lenient, most likely to let range noise through)
   RS_VOTE_MAJORITY = 2    // >=half of enabled filters must say "trending"/"allow" (round up on ties)
};
input group "── Regime Suite: Combine Logic (v5.94, 2026-08-29) ──"
input ENUM_REGIME_SUITE_VOTE RegimeSuiteVoteMode = RS_VOTE_AND;   // how ALL enabled filters below (academic + volatility-band + session + Asian-range) combine into one trending/ranging verdict. Re-test AND vs OR vs MAJORITY on the SAME full filter set -- prior rounds never tested this on the complete set, only a subset.
input int RegimeConfirmBars = 0;   // 2.2 NEW: require this many consecutive agreeing bar-closes before the Regime Suite verdict is allowed to flip. 0 or 1 = OFF (raw per-bar verdict, identical to 2.1). Ports the persistence/smoothing concept validated visually in the standalone RegimeSuite_*.mq5 indicators -- raw voters were found to flip every 1-3 bars on real GOLD M5 data. Sweep 2-5.

// PERF FIX (2026-09-17): populates g_voteCache* exactly once per bar. Called
// by both Bot1RegimeSuiteSaysTrending() (existing entry-gate path) and
// Bot1ComputeRegime21Bucket() (v3 classifier) so the 6 voters -- several of
// which loop over their own lookback window (ER/CHOP: ~14 bars, MMI: up to
// 100 bars with a sort) -- are computed once per bar, not once per caller.
// MOMENTUM/ACCELERATION SNAPSHOT (2026-09-19): plain rate-of-change over a
// short lookback, computed ONLY at entry time (not per-bar, no new cache
// needed) -- "how fast and in what direction was price already moving right
// before this signal fired". Deliberately simple/cheap: two CopyClose calls,
// no new indicator handle. Added after a deep-dive into losing SELL+TREND
// trades found NO explanatory signal in ADX/RSI/ADR/spread (confirmed via a
// permutation test that ruled out overfitting) -- momentum direction/
// magnitude right before entry is a genuinely different axis none of those
// capture (e.g. was price already decelerating into resistance when the
// SELL fired, vs accelerating cleanly downward).
double Bot1MomentumPts(int lookbackBars) {
   if(lookbackBars < 1) return 0.0;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, lookbackBars + 1, closeArr) < lookbackBars + 1) return 0.0;
   return (closeArr[0] - closeArr[lookbackBars]) / _Point;
}

// DAY-RANGE POSITION (2026-09-19): where does the current price sit within
// TODAY's high/low so far, as a 0-1 fraction (0 = at today's low, 1 = at
// today's high, 0.5 = midpoint). Uses the current forming D1 bar (index 0),
// which MT5 keeps live-updated intrabar in both live trading and Tester --
// no separate day-boundary tracking needed. Returns -1 (sentinel, logged as
// blank) if today's range is degenerate (high==low, e.g. the very first
// tick of a new day) or data isn't available yet.
double Bot1DayRangePosition(double currentPrice) {
   double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dayLow  = iLow(_Symbol, PERIOD_D1, 0);
   if(dayHigh <= 0 || dayLow <= 0 || dayHigh <= dayLow) return -1.0;
   double pos = (currentPrice - dayLow) / (dayHigh - dayLow);
   return MathMax(0.0, MathMin(1.0, pos));   // clamp -- entry fill price can very rarely sit a tick outside the D1 bar's own high/low due to spread/fill timing
}

// PRICE VS 1H OPEN (2026-09-19): signed distance in points between the
// current price and the OPEN of the current forming H1 bar (index 0) --
// literally "are we above or below where price was at the start of this
// hour". Same live-updating-bar-0 approach as the day-range function above.
// Positive = price has moved up since the hour started, negative = down.
double Bot1PriceVsHourOpenPts(double currentPrice) {
   double hourOpen = iOpen(_Symbol, PERIOD_H1, 0);
   if(hourOpen <= 0) return -999999;
   return (currentPrice - hourOpen) / _Point;
}

// MULTI-TIMEFRAME SLOPE (2026-09-19): user's own idea -- take the SAME
// linear-regression-slope math already used by GetRegimeLinRegR2() (just
// slope, not R2), but at 3 different lookback lengths on the EA's own
// trading timeframe, to see whether short/mid/long-term price direction
// actually agree with each other -- and with the classifier's regime
// label and direction. A real uptrend SHOULD show positive slope at all
// 3 horizons; disagreement between them is itself informative (e.g. a
// short-term bounce inside a longer-term downtrend). Returns slope in
// POINTS PER BAR (normalized by _Point) so the 3 lookbacks are directly
// comparable to each other despite covering different bar counts.
double Bot1SlopePtsPerBar(int lookbackBars) {
   if(lookbackBars < 2) return 0.0;
   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, lookbackBars, closeArr) < lookbackBars) return 0.0;

   int n = lookbackBars;
   double sumX=0, sumY=0, sumXY=0, sumX2=0;
   for(int i = 0; i < n; i++) {
      double x = (double)i;
      double y = closeArr[n-1-i];   // oldest first, so x increases forward in time -- same convention as GetRegimeLinRegR2
      sumX += x; sumY += y; sumXY += x*y; sumX2 += x*x;
   }
   double denom = (n*sumX2 - sumX*sumX);
   if(denom == 0.0) return 0.0;
   double slope = (n*sumXY - sumX*sumY) / denom;
   return slope / _Point;
}

void Bot1RefreshVoteCache() {
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(g_voteCacheValid && g_voteCacheBar == curBar) return;
   g_voteCacheADX      = RegimeADXTrending();
   g_voteCacheER       = RegimeERTrending();
   g_voteCacheCHOP     = RegimeCHOPTrending();
   g_voteCacheLinReg   = RegimeLinRegTrending();
   g_voteCacheATRRatio = RegimeATRRatioTrending();
   g_voteCacheMMI      = RegimeMMITrending();
   g_voteCacheValid    = true;
   g_voteCacheBar      = curBar;
}

bool Bot1RegimeSuiteSaysTrendingRaw() {
   int enabledCount = 0;
   int trendingCount = 0;

   if(Bot1Lean4Active()) {
      // Force the lean-4 voters. Other UseRegime* flags are ignored so a
      // leftover FULL10 .set cannot silently mix filters into this preset.
      enabledCount = 4;
      if(RegimeADXSlopeTrending()) trendingCount++;
      if(RegimeCHOPTrending())     trendingCount++;
      if(RegimeBBWidthTrending())  trendingCount++;
      if(RegimeSessionAllowed())   trendingCount++;
   } else {
      Bot1RefreshVoteCache();
      if(g_UseRegimeADX)        { enabledCount++; if(g_voteCacheADX)      trendingCount++; }
      if(g_UseRegimeER)         { enabledCount++; if(g_voteCacheER)       trendingCount++; }
      if(g_UseRegimeCHOP)       { enabledCount++; if(g_voteCacheCHOP)     trendingCount++; }
      if(g_UseRegimeLinReg)     { enabledCount++; if(g_voteCacheLinReg)   trendingCount++; }
      if(g_UseRegimeATRRatio)   { enabledCount++; if(g_voteCacheATRRatio) trendingCount++; }
      if(g_UseRegimeMMI)        { enabledCount++; if(g_voteCacheMMI)      trendingCount++; }
      if(g_UseRegimeSession)    { enabledCount++; if(RegimeSessionAllowed())   trendingCount++; }
      if(g_UseATRBandGate)      { enabledCount++; if(ATRBandAllows())          trendingCount++; }
      if(g_UseATRSpikeFilter)   { enabledCount++; if(ATRSpikeAllows())         trendingCount++; }
      if(g_UseAsianRangeFilter) { enabledCount++; if(AsianRangeFilterAllows()) trendingCount++; }
   }

   if(enabledCount == 0) return true;   // vacuously "trending" (no gate) if nothing enabled

   switch(g_RegimeSuiteVoteMode) {
      case RS_VOTE_OR:       return trendingCount >= 1;
      case RS_VOTE_MAJORITY: return trendingCount * 2 >= enabledCount;   // >=50%, rounds in favor of "trending" on odd counts
      case RS_VOTE_AND:
      default:                return trendingCount == enabledCount;
   }
}

// 2.2 NEW: persistence/confirmation wrapper around the raw per-bar verdict.
// Ports the "N consecutive agreeing bars" concept validated visually in the
// standalone RegimeSuite_*.mq5 indicators (raw voters were found to flip
// 1-3 times every ~50 bars on real GOLD M5 data). RegimeConfirmBars=0 (the
// default) is byte-for-byte identical to 2.1's always-raw behavior -- zero
// risk to existing .set files. RegimeConfirmBars>=2 requires that many
// consecutive bar-closes to agree on the raw verdict before the STABLE
// verdict (the one every caller below actually reads) is allowed to flip,
// damping the single-bar noise the indicators demonstrated.
bool g_regimeStableVerdict      = true;
bool g_regimeConfirmLastRaw     = true;
int  g_regimeConfirmRun         = 0;
datetime g_regimeConfirmLastBar = 0;

bool Bot1RegimeSuiteSaysTrending() {
   bool raw = Bot1RegimeSuiteSaysTrendingRaw();
   if(RegimeConfirmBars <= 1) return raw;   // off (default) -- unchanged 2.1 behavior

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar != g_regimeConfirmLastBar) {
      g_regimeConfirmLastBar = curBar;
      if(raw == g_regimeConfirmLastRaw) {
         g_regimeConfirmRun++;
      } else {
         g_regimeConfirmLastRaw = raw;
         g_regimeConfirmRun = 1;
      }
      if(g_regimeConfirmRun >= RegimeConfirmBars) {
         g_regimeStableVerdict = raw;
      }
      // else: keep the previous stable verdict, raw hasn't held long enough yet
   }
   return g_regimeStableVerdict;
}
bool Bot1RegimeSuiteSaysRanging() {
   bool anyEnabled;
   if(Bot1Lean4Active()) {
      anyEnabled = true;   // four force-voters; verdict is always defined
   } else {
      anyEnabled = g_UseRegimeADX || g_UseRegimeER || g_UseRegimeCHOP || g_UseRegimeLinReg ||
                    g_UseRegimeATRRatio || g_UseRegimeMMI || g_UseRegimeSession ||
                    g_UseATRBandGate || g_UseATRSpikeFilter || g_UseAsianRangeFilter;
   }
   if(!anyEnabled) return false;   // nothing enabled -- never gate

   // PERF FIX (v2 AGILE, 2026-09-07): this function fans out into up to 10
   // sub-filter computations (several loop over 14-100 bars: ER, CHOP,
   // LinReg, MMI) and was being called 3x per single bar-close (regime-event
   // transition check, counter-trend gate, main signal gate) -- the verdict
   // cannot change mid-bar, so recomputing it more than once per bar is pure
   // waste. Cache it; every caller within the same bar reads the cache.
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(g_regimeRangingCacheValid && g_regimeRangingCacheBar == curBar) {
      return g_regimeRangingCacheValue;
   }
   bool result = !Bot1RegimeSuiteSaysTrending();
   g_regimeRangingCacheValid = true;
   g_regimeRangingCacheBar   = curBar;
   g_regimeRangingCacheValue = result;
   return result;
}

// --- Diagnostics: prints every ENABLED filter's raw value, its own
// verdict, and the combined suite verdict, once per bar. This is the
// validation tool -- read it and confirm the numbers look sane before
// trusting the gate. Costs nothing when LogRegimeSuiteDiagnostics is
// false, and naturally costs nothing per-filter for any filter that's
// individually disabled, since each Get*/Allows function short-circuits
// on its own Use flag.
void Bot1LogRegimeSuiteDiagnostics() {
   if(!LogRegimeSuiteDiagnostics || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   string s = "[BOT1-REGIME-SUITE] " + _Symbol + " ";
   if(g_UseRegimeADX)        s += StringFormat("ADXR=%.1f(%s) ", GetRegimeADXR(), RegimeADXTrending() ? "T" : "R");
   if(g_UseRegimeER)         s += StringFormat("ER=%.2f(%s) ", GetRegimeER(), RegimeERTrending() ? "T" : "R");
   if(g_UseRegimeCHOP)       s += StringFormat("CHOP=%.1f(%s) ", GetRegimeCHOP(), RegimeCHOPTrending() ? "T" : "R");
   if(g_UseRegimeLinReg)     { double sl; double r2 = GetRegimeLinRegR2(sl); s += StringFormat("R2=%.2f slope=%.5f(%s) ", r2, sl, RegimeLinRegTrending() ? "T" : "R"); }
   if(g_UseRegimeATRRatio)   s += StringFormat("ATRratio=%.2f(%s) ", GetRegimeATRRatio(), RegimeATRRatioTrending() ? "T" : "R");
   if(g_UseRegimeMMI)        s += StringFormat("MMI=%.1f(%s) ", GetRegimeMMI(), RegimeMMITrending() ? "T" : "R");
   if(g_UseRegimeSession)    s += StringFormat("Session=%s ", RegimeSessionAllowed() ? "IN" : "OUT");
   if(g_UseATRBandGate)      s += StringFormat("ATRBand=%.1fpts(%s) ", GetATRBandPoints(), ATRBandAllows() ? "OK" : "BLOCK");
   if(g_UseATRSpikeFilter)   s += StringFormat("ATRSpike short=%.5f long=%.5f(%s) ", GetATRSpikeShort(), GetATRSpikeLong(), ATRSpikeAllows() ? "OK" : "BLOCK");
   if(g_UseAsianRangeFilter) s += StringFormat("AsianRange high=%.3f low=%.3f verdict=%s ", g_asianRangeHigh, g_asianRangeLow, g_asianRangeDayAllowed ? "ALLOWED" : "BLOCKED");
   s += StringFormat("[vote=%s] ", EnumToString(RegimeSuiteVoteMode));
   s += Bot1RegimeSuiteSaysTrending() ? "-> TREND" : "-> RANGE";
   Print(s);
}

//+------------------------------------------------------------------+
//| LAYER 1: BASELINE TREND                                         
//+------------------------------------------------------------------+
int GetIchimokuTrend() {
   if(!g_UseIchimoku || ichimokuHandleHTF==INVALID_HANDLE) return 0;

   double tenkan[], kijun[], senA[], senB[], chikou[], price[], price26[];
   ArraySetAsSeries(tenkan,true);
   ArraySetAsSeries(kijun,true);
   ArraySetAsSeries(senA,true);
   ArraySetAsSeries(senB,true);
   ArraySetAsSeries(chikou,true);
   ArraySetAsSeries(price,true);
   ArraySetAsSeries(price26,true);

   if(CopyBuffer(ichimokuHandleHTF,0,0,1,tenkan)<1) return 0;
   if(CopyBuffer(ichimokuHandleHTF,1,0,1,kijun)<1) return 0;
   if(CopyBuffer(ichimokuHandleHTF,2,0,1,senA)<1) return 0;
   if(CopyBuffer(ichimokuHandleHTF,3,0,1,senB)<1) return 0;
   if(CopyBuffer(ichimokuHandleHTF,4,0,1,chikou)<1) return 0;
   if(CopyClose(_Symbol,HigherTimeframe,0,1,price)<1) return 0;
   if(CopyClose(_Symbol,HigherTimeframe,26,1,price26)<1) return 0;

   double top = MathMax(senA[0], senB[0]);
   double bot = MathMin(senA[0], senB[0]);
   bool bull = (price[0] > top) && (tenkan[0] > kijun[0]);
   bool bear = (price[0] < bot) && (tenkan[0] < kijun[0]);

   if(UseChikou) {
      bull = bull && (chikou[0] > price26[0]);
      bear = bear && (chikou[0] < price26[0]);
   }

   if(bull) return 1;
   if(bear) return -1;
   return 0;
}

int GetEMACrossTrend() {
   if(!g_UseEMACross || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE) return 0;

   double f[], s[];
   ArraySetAsSeries(f,true);
   ArraySetAsSeries(s,true);
   if(CopyBuffer(emaFastHandle,0,0,1,f)<1) return 0;
   if(CopyBuffer(emaSlowHandle,0,0,1,s)<1) return 0;

   if(f[0] > s[0]) return 1;
   if(f[0] < s[0]) return -1;
   return 0;
}

int GetPSARTrend() {
   if(!g_UsePSAR || psarHandle==INVALID_HANDLE) return 0;

   double p[];
   ArraySetAsSeries(p,true);
   if(CopyBuffer(psarHandle,0,0,1,p)<1) return 0;
   double c = iClose(_Symbol, HigherTimeframe, 0);

   if(p[0] < c) return 1;
   if(p[0] > c) return -1;
   return 0;
}

int GetLayer1Trend() {
   return GetLayer1TrendFromSignals(GetIchimokuTrend(), GetEMACrossTrend(), GetPSARTrend(),
                                    GetSuperTrendSignal(), GetEMA200Bias());
}

int GetLayer1TrendFromSignals(int ichiSig, int emaSig, int psarSig, int stSig=0, int ema200Sig=0) {
   int sum=0, n=0;
   if(g_UseIchimoku)   { sum += ichiSig; n++; }
   if(g_UseEMACross)   { sum += emaSig; n++; }
   if(g_UsePSAR)       { sum += psarSig; n++; }
   if(g_UseSuperTrend) { sum += stSig; n++; }
   if(g_UseEMA200Bias) { sum += ema200Sig; n++; }
   if(n<=0) return 0;

   int thr = UseStrictLayers ? ((n+1)/2) : (g_Layer1MinConfirmations);
   if(thr > n) thr = (n+1)/2;

   if(sum >= thr) return 1;
   if(sum <= -thr) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| LAYER 2: MOMENTUM CONFIRMATION                                  
//+------------------------------------------------------------------+
int GetMACDMomentum() {
   if(!g_UseMACD || macdHandle==INVALID_HANDLE) return 0;

   double m[], s[];
   ArraySetAsSeries(m,true);
   ArraySetAsSeries(s,true);
   if(CopyBuffer(macdHandle,0,0,1,m)<1) return 0;
   if(CopyBuffer(macdHandle,1,0,1,s)<1) return 0;

   if(m[0] > s[0] && m[0] > 0) return 1;
   if(m[0] < s[0] && m[0] < 0) return -1;
   return 0;
}

int GetRSIMomentum() {
   if(!g_UseRSI || rsiHandle==INVALID_HANDLE) return 0;

   double r[];
   ArraySetAsSeries(r,true);
   if(CopyBuffer(rsiHandle,0,0,1,r)<1) return 0;

   if(g_Layer2RSIMode == RSI_EXTREME75) {
      if(r[0] >= g_RSIOverbought) return 1;
      if(r[0] <= g_RSIOversold) return -1;
      return 0;
   }
   if(g_Layer2RSIMode == RSI_BAND_VETO) {
      if(r[0] > RSIMomentumLevel && r[0] < g_RSIOverbought) return 1;
      if(r[0] < RSIMomentumLevel && r[0] > g_RSIOversold) return -1;
      return 0;
   }
   if(r[0] > RSIMomentumLevel) return 1;
   if(r[0] < RSIMomentumLevel) return -1;
   return 0;
}

bool GetADXStrength(int trend) {
   if(!g_UseADX || adxHandle==INVALID_HANDLE) return false;

   double adx[], pdi[], mdi[];
   ArraySetAsSeries(adx,true);
   ArraySetAsSeries(pdi,true);
   ArraySetAsSeries(mdi,true);

   if(CopyBuffer(adxHandle,0,0,1,adx)<1) return false;
   if(CopyBuffer(adxHandle,1,0,1,pdi)<1) return false;
   if(CopyBuffer(adxHandle,2,0,1,mdi)<1) return false;

   bool dirAlign = (trend == 1) ? (pdi[0] > mdi[0]) : (mdi[0] > pdi[0]);
   if(g_UseADXSlope)
      return (GetADXSlope() > 0.0 && dirAlign);
   return (adx[0] > ADXThreshold && dirAlign);
}

void Bot1GetL2VoterFlags(bool &useMacd, bool &useRsi, bool &useAdx, bool &useCci) {
   useMacd = g_UseMACD;
   useAdx  = g_UseADX;
   useRsi  = g_UseRSI;
   useCci  = g_UseLayer2CCI;
   if(g_UseLayer2CCI && g_PreferCCIInTrend) {
      bool ranging = Bot1RegimeSuiteSaysRanging();
      if(ranging) { useCci = false; useRsi = g_UseRSI; }
      else        { useRsi = false; useCci = true; }
   }
}

bool CheckLayer2Momentum(int trend) {
   int macdSig = GetMACDMomentum();
   int rsiSig  = GetRSIMomentum();
   bool adxOk  = GetADXStrength(trend);
   int cciSig  = GetCCIMomentum();
   bool useMacd, useRsi, useAdx, useCci;
   Bot1GetL2VoterFlags(useMacd, useRsi, useAdx, useCci);
   return CheckLayer2MomentumFromSignals(trend, macdSig, rsiSig, adxOk, cciSig, useMacd, useRsi, useAdx, useCci);
}

bool CheckLayer2MomentumFromSignals(int trend, int macdSig, int rsiSig, bool adxOk,
                                    int cciSig=0, bool useMacd=true, bool useRsi=true,
                                    bool useAdx=true, bool useCci=false) {
   int count=0, aligned=0;
   if(useMacd) {
      if(macdSig == trend) aligned++;
      count++;
   }
   if(useRsi) {
      if(rsiSig == trend) aligned++;
      count++;
   }
   if(useAdx) {
      if(adxOk) aligned++;
      count++;
   }
   if(useCci) {
      if(cciSig == trend) aligned++;
      count++;
   }
   if(count == 0) return false;

   int thr = UseStrictLayers ? (count/2 + 1) : g_Layer2MinConfirmations;
   if(thr > count) thr = (count/2 + 1);

   return (aligned >= thr);
}

//+------------------------------------------------------------------+
//| LAYER 3: ENTRY TRIGGERS                                         
//+------------------------------------------------------------------+
int GetBollingerTrigger() {
   if(!g_UseBollinger || bollHandle==INVALID_HANDLE) return 0;

   double lower[], upper[], close[];
   ArraySetAsSeries(lower,true);
   ArraySetAsSeries(upper,true);
   ArraySetAsSeries(close,true);

   if(CopyBuffer(bollHandle,2,0,2,lower)<2) return 0;
   if(CopyBuffer(bollHandle,1,0,2,upper)<2) return 0;
   if(CopyClose(_Symbol,_Period,0,2,close)<2) return 0;

   if(close[1] <= lower[1] && close[0] > lower[0]) return 1;
   if(close[1] >= upper[1] && close[0] < upper[0]) return -1;
   return 0;
}

int GetOBVTrigger() {
   if(!g_UseOBV || obvHandle==INVALID_HANDLE) return 0;

   double obv[];
   ArraySetAsSeries(obv,true);
   if(CopyBuffer(obvHandle,0,0,3,obv)<3) return 0;

   if(obv[0] > obv[1] && obv[1] > obv[2]) return 1;
   if(obv[0] < obv[1] && obv[1] < obv[2]) return -1;
   return 0;
}

int GetDonchianTrigger() {
   if(!g_UseDonchian) return 0;

   double high[], low[], close[];
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   int needed = DonchianPeriod+1;
   if(CopyHigh(_Symbol,_Period,0,needed,high) < needed) return 0;
   if(CopyLow(_Symbol,_Period,0,needed,low) < needed) return 0;
   if(CopyClose(_Symbol,_Period,0,2,close) < 2) return 0;

   double upperBand = high[1];
   double lowerBand = low[1];
   for(int i=1; i<DonchianPeriod; i++) {
      if(high[i] > upperBand) upperBand = high[i];
      if(low[i] < lowerBand) lowerBand = low[i];
   }

   if(close[1] <= upperBand && close[0] > upperBand) return 1;
   if(close[1] >= lowerBand && close[0] < lowerBand) return -1;
   return 0;
}

int GetLayer3Trigger() {
   if(g_UseRetest) Bot1UpdateDonchianRetest();
   return GetLayer3TriggerFromSignals(GetBollingerTrigger(), GetOBVTrigger(), GetDonchianTrigger(),
                                      GetDonchianRetestTrigger(), GetVWAPReclaimTrigger());
}

int GetLayer3TriggerFromSignals(int bollSig, int obvSig, int donchSig, int retestSig=0, int vwapSig=0) {
   int sum=0, n=0;
   if(g_UseBollinger)    { sum += bollSig; n++; }
   if(g_UseOBV)          { sum += obvSig; n++; }
   if(g_UseDonchian)     { sum += donchSig; n++; }
   if(g_UseRetest)       { sum += retestSig; n++; }
   if(g_UseVWAPReclaim)  { sum += vwapSig; n++; }
   if(n<=0) return 0;

   int thr = UseStrictLayers ? ((n+1)/2) : g_Layer3MinConfirmations;
   if(thr > n) thr = (n+1)/2;

   if(sum >= thr) return 1;
   if(sum <= -thr) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| MAIN ENTRY SIGNAL CHECK (More Flexible!)                        
//+------------------------------------------------------------------+
int CheckIndicatorFilters() {
   if(!IsMarketTradable()) return 0;

   int trend = GetLayer1Trend();
   if(trend == 0) return 0;

   if(g_RequireL2ForLive && !CheckLayer2Momentum(trend)) return 0;

   if(g_RequireL3ForLive) {
      int trigger = GetLayer3Trigger();
      if(trigger != trend) return 0;
   } else if(g_ExcludeWhenL3Fires) {
      int trigger = GetLayer3Trigger();
      if(trigger == trend) return 0;
   }

   return trend;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT                                                 
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| POST-STOP COOLDOWN + MIN SL DISTANCE helpers (2026-09-02)        |
//+------------------------------------------------------------------+

// Called from OnTradeTransaction() when this MagicNumber's position closes
// via DEAL_REASON_SL. origDir: 1 = the closed position was a BUY, -1 = SELL.
void Bot1RegisterCooldown(int origDir) {
   if(!UseCooldownAfterSL) return;
   datetime barTime = iTime(_Symbol, _Period, 0);
   datetime blockUntil = barTime + (datetime)(CooldownBarsAfterSL * PeriodSeconds(_Period));
   if(origDir == 1)  g_cooldownUntilBuyBar  = blockUntil;
   else               g_cooldownUntilSellBar = blockUntil;
   Print("[BOT1-COOLDOWN] ", _Symbol, " MN:", MagicNumber, " ", (origDir==1?"BUY":"SELL"),
         " stopped out -- blocking same-direction re-entry until bar >= ", TimeToString(blockUntil));
}

// Returns true if a new entry in this direction should be BLOCKED by cooldown.
bool Bot1CooldownBlocks(int direction) {
   if(!UseCooldownAfterSL) return false;
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(direction == 1)  return barTime < g_cooldownUntilBuyBar;
   else                 return barTime < g_cooldownUntilSellBar;
}

// Record a real SL distance (points) at position-open time, into the
// rolling window used by the min-SL-distance sanity filter.
void Bot1RecordSLDistance(double slDistancePoints) {
   if(slDistancePoints <= 0) return;
   int len = SLDistanceHistoryLen;
   if(len < 1) len = 1;
   if(ArraySize(g_slDistanceHistory) != len) ArrayResize(g_slDistanceHistory, len);
   g_slDistanceHistory[g_slDistanceCount % len] = slDistancePoints;
   g_slDistanceCount++;
   g_slDistanceLastUpdateBar = iTime(_Symbol, _Period, 0);
}

// Returns the rolling average SL distance (points) over the recorded window,
// or 0.0 if not enough samples yet (caller should treat 0.0 as "filter not
// applicable").
double Bot1AvgSLDistance() {
   int len = SLDistanceHistoryLen;
   if(len < 1) len = 1;
   int samples = MathMin(g_slDistanceCount, len);
   if(samples < SLDistanceMinSamples) return 0.0;
   double sum = 0.0;
   for(int i = 0; i < samples; i++) sum += g_slDistanceHistory[i];
   return sum / samples;
}

// Returns true if the candidate SL distance should be REJECTED as an outlier
// (too tight relative to this MagicNumber's own recent history).
bool Bot1SLDistanceIsOutlier(double candidateEntryPrice, double candidateSL) {
   if(!UseMinSLDistanceFilter) return false;
   double avg = Bot1AvgSLDistance();
   if(avg <= 0.0) return false;  // not enough history yet -- don't block

   // SELF-LOCK FIX (2026-09-18): if the rolling average hasn't been updated by
   // a real trade in SLDistanceMaxStaleBars bars, it's stale -- keep enforcing
   // it forever risks a permanent lockout (this exact failure mode was
   // confirmed on a real single-run validation with MinSLDistanceFraction=1.1:
   // once no candidate could clear the bar, the average could never update
   // again, and the EA silently stopped trading for months). 0 disables this
   // check (old behavior, can still lock up at extreme fraction settings).
   if(SLDistanceMaxStaleBars > 0 && g_slDistanceLastUpdateBar > 0) {
      datetime curBar = iTime(_Symbol, _Period, 0);
      long barsSinceUpdate = (long)((curBar - g_slDistanceLastUpdateBar) / PeriodSeconds(_Period));
      if(barsSinceUpdate >= SLDistanceMaxStaleBars) return false;  // stale -- don't block, let a fresh trade through to re-anchor the average
   }

   double candidateDistPoints = MathAbs(candidateEntryPrice - candidateSL) / _Point;
   double minAllowed = avg * MinSLDistanceFraction;
   return candidateDistPoints < minAllowed;
}

double CalculateStopLoss(ENUM_POSITION_TYPE posType, double entryPrice, bool logDiagnostics = false) {
   double sl = 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // v3 branch: range-mode entries use a tight symmetric stop instead of
   // ADR/Kumo trend-oriented sizing. Still falls through to the shared
   // min-distance enforcement below, same safety net as every other path.
   if(g_useRangeModeForThisEntry) {
      sl = (posType == POSITION_TYPE_BUY) ?
           entryPrice - (RangeModeSL_Points * _Point) :
           entryPrice + (RangeModeSL_Points * _Point);
   } else if(UseADR && adr > 0 && g_StopBasisMode == SL_ADR) {
      sl = (posType == POSITION_TYPE_BUY) ? 
           entryPrice - (adr * ADRMultiplierSL) : 
           entryPrice + (adr * ADRMultiplierSL);
   } else if(g_StopBasisMode == SL_ATR) {
      Bot1RefreshRegime2Cache();
      double atrDist = g_r2.atrStop;
      if(atrDist <= 0.0 && atrStopHandle != INVALID_HANDLE) {
         double a[];
         ArraySetAsSeries(a, true);
         if(CopyBuffer(atrStopHandle, 0, 0, 1, a) >= 1) atrDist = a[0] * g_ATRStopMultiplier;
      }
      if(atrDist > 0.0) {
         sl = (posType == POSITION_TYPE_BUY) ?
              entryPrice - atrDist :
              entryPrice + atrDist;
      } else if(UseADR && adr > 0) {
         sl = (posType == POSITION_TYPE_BUY) ?
              entryPrice - (adr * ADRMultiplierSL) :
              entryPrice + (adr * ADRMultiplierSL);
      } else if(StopLoss > 0) {
         sl = (posType == POSITION_TYPE_BUY) ?
              entryPrice - (StopLoss * _Point) :
              entryPrice + (StopLoss * _Point);
      }
   } else if(StopLoss > 0) {
      sl = (posType == POSITION_TYPE_BUY) ? 
           entryPrice - (StopLoss * _Point) : 
           entryPrice + (StopLoss * _Point);
   }
   double adrBasedSL = sl;  // keep a fallback in case Kumo override ends up too tight

   if(UseKumoSL && ichimokuHandleCur != INVALID_HANDLE && !g_useRangeModeForThisEntry) {
      double senA[], senB[];
      ArraySetAsSeries(senA,true);
      ArraySetAsSeries(senB,true);

      if(CopyBuffer(ichimokuHandleCur,2,0,1,senA)>=1 && CopyBuffer(ichimokuHandleCur,3,0,1,senB)>=1) {
         double kumoTop = MathMax(senA[0], senB[0]);
         double kumoBottom = MathMin(senA[0], senB[0]);

         if(posType == POSITION_TYPE_BUY) {
            double kumoSL = kumoBottom - 10 * _Point;
            if(kumoSL > sl && kumoSL < entryPrice) sl = kumoSL;
         } else {
            double kumoSL = kumoTop + 10 * _Point;
            if((sl == 0 || kumoSL < sl) && kumoSL > entryPrice) sl = kumoSL;
         }
      }
   }

   // WIDE_SL_BE branch (2026-09-10): widen the initial SL distance by a
   // multiplier, applied AFTER basis selection (ADR/ATR/Kumo/fixed) so it
   // scales whatever was actually chosen, and BEFORE the broker min-distance
   // enforcement below (widening only ever increases distance, never
   // conflicts with that floor). Independently toggleable; no effect on
   // TP1/TP2/RRLinkedTP sizing, which read Bot1InitialRiskDist() = the
   // actual final |entry-SL| below, so R-based exits stay consistent with
   // whatever SL width is actually live for this trade.
   if(UseWideSL && sl > 0 && WideSLMultiplier > 0) {
      double baseDist = MathAbs(entryPrice - sl);
      double widenedDist = baseDist * WideSLMultiplier;
      sl = (posType == POSITION_TYPE_BUY) ? entryPrice - widenedDist : entryPrice + widenedDist;
   }

   // BUG FIX 2026-07-10: the Kumo override above had zero minimum-distance
   // enforcement -- if price sits close to the cloud edge, it could produce
   // a stop as tight as a few points, which the broker rejects as INVALID_STOPS
   // (confirmed: DE40 entry=25238.0 sl=25236.3, a 1.7-point stop). Enforce the
   // broker's actual minimum here instead of discovering it via a rejected order.
   if(sl > 0) {
      long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      // CONFIRMED 2026-07-15: a reported StopsLevel of 0 does NOT mean no
      // minimum exists -- GBPJPY/US500 both report 0 and still generated 11
      // real INVALID_STOPS rejections. Fall back to a conservative floor.
      long effectiveMinPts = (stopsLevelPts > 0) ? stopsLevelPts : Bot1FallbackMinStopPoints;
      double minDistance = (effectiveMinPts + 5) * _Point;  // +5pt buffer beyond the (possibly fallback) minimum
      double actualDistance = MathAbs(entryPrice - sl);
      if(actualDistance < minDistance) {
         // Kumo (or even ADR, in theory) produced a too-tight stop. Fall back
         // to the ADR-based distance if that clears the minimum; otherwise
         // widen directly to the minimum allowed distance.
         double adrDistance = MathAbs(entryPrice - adrBasedSL);
         if(adrBasedSL > 0 && adrDistance >= minDistance) {
            sl = adrBasedSL;
         } else {
            sl = (posType == POSITION_TYPE_BUY) ? entryPrice - minDistance : entryPrice + minDistance;
         }
         // 2026-07-20 FIX: this Print was firing on EVERY TICK for EVERY
         // symbol because CalculateStopLoss() is also called from the
         // dashboard/legend code to preview a hypothetical SL for display --
         // it's not exclusive to real trade opens. 70k+ lines/day of log
         // spam from this single line. Now silent unless the caller is
         // opening a real position.
         if(logDiagnostics) {
            Print("[BOT1-INFO] ", _Symbol, " SL widened to respect StopsLevel (broker_reported=", stopsLevelPts,
                  " effective_min=", effectiveMinPts, "): requested_distance=",
                  DoubleToString(actualDistance, digits), " min_required=", DoubleToString(minDistance, digits));
         }
      }
   }

   return (sl > 0) ? NormalizeDouble(sl, digits) : 0.0;
}

// v5.94: added slForRR (optional, default 0 = unused) -- when
// UseRRLinkedTP=true, TP is derived as a straight RRMultiple of the
// ACTUAL SL distance (post Kumo-override, post broker-min-distance
// enforcement) instead of being computed independently from
// ADRMultiplierTP/TakeProfit. Pass the sl already computed by
// CalculateStopLoss() for this same entry -- callers that don't have one
// yet (e.g. legend/dashboard hypothetical previews) can omit it and fall
// through to the pre-v5.94 ADR/fixed-point behavior.
double CalculateTakeProfit(ENUM_POSITION_TYPE posType, double entryPrice, double slForRR = 0.0) {
   double tp = 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // v3 branch: range-mode entries use a tight symmetric target instead of
   // ADR-based trend sizing. RR-linking deliberately does NOT apply here --
   // range mode has its own tight symmetric SL/TP band, a different regime
   // response, not the normal trend-following exit.
   if(g_useRangeModeForThisEntry) {
      tp = (posType == POSITION_TYPE_BUY) ?
           entryPrice + (RangeModeTP_Points * _Point) :
           entryPrice - (RangeModeTP_Points * _Point);
   } else if(UseRRLinkedTP && slForRR > 0.0) {
      double slDistance = MathAbs(entryPrice - slForRR);
      tp = (posType == POSITION_TYPE_BUY) ?
           entryPrice + (slDistance * RRMultiple) :
           entryPrice - (slDistance * RRMultiple);
   } else if(UseADR && adr > 0) {
      tp = (posType == POSITION_TYPE_BUY) ? 
           entryPrice + (adr * ADRMultiplierTP) : 
           entryPrice - (adr * ADRMultiplierTP);
   } else if(TakeProfit > 0) {
      tp = (posType == POSITION_TYPE_BUY) ? 
           entryPrice + (TakeProfit * _Point) : 
           entryPrice - (TakeProfit * _Point);
   }

   return (tp > 0) ? NormalizeDouble(tp, digits) : 0.0;
}

double CalculateLotSize(double sl, double entryPrice, int concurrentSameDirCount = 0, double riskMultiplier = 1.0) {
   if(LotType == LOT_FIXED) return NormalizeVolume(LotSize);
   if(sl == 0.0 || MathAbs(entryPrice - sl) < _Point) return NormalizeVolume(LotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // v5.97: dailyFloor/overallFloor now derive from %-of-balance budgets
   // (MaxDailyLossPct/MaxOverallLossPct) instead of flat-dollar constants --
   // see FTMO PROTECTION group comment for why the old flat-$ version was
   // a real bug (silently clamped every RiskPercent to the same lot size).
   double dailyLossBudget = startDayBalance * (MaxDailyLossPct / 100.0);
   double overallLossBudget = g_eaStartBalance * (MaxOverallLossPct / 100.0);
   double dailyFloor = startDayBalance - dailyLossBudget;
   double overallFloor = g_eaStartBalance - overallLossBudget;

   // REGIME 2.1 v3 (2026-09-17): riskMultiplier defaults to 1.0 (byte-identical
   // to pre-existing behavior at every call site that doesn't pass it). Used by
   // the CHOP-bucket size boost below -- see Regime21ChopSizeMultiplier input
   // comment for the full rationale (confirmed via 27-trade real backtest data:
   // entries firing during a CHOP-labeled bar go on to transition to TREND
   // within ~7 bars 96% of the time, and outperform TREND-bucket entries on
   // win%/PF/avg-$-per-trade -- this multiplier lets us size those specific
   // entries up without touching the trend-side entry logic itself).
   double riskAmount = balance * (RiskPercent / 100.0) * MathMax(0.1, riskMultiplier);
   double remainingDaily = equity - dailyFloor;
   double remainingOverall = equity - overallFloor;
   double maxRiskFromBuffer = MathMin(remainingDaily, remainingOverall) * 0.9;
   double maxRiskFromDaily = dailyLossBudget * MaxRiskPerTradeFraction;

   riskAmount = MathMin(riskAmount, maxRiskFromBuffer);
   riskAmount = MathMin(riskAmount, maxRiskFromDaily);

   if(riskAmount <= 0) return NormalizeVolume(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double slDistance = MathAbs(entryPrice - sl);
   double slPoints = slDistance / _Point;
   double valuePerPt = ValuePerPoint();

   if(valuePerPt <= 0.0 || slPoints <= 0.0) return NormalizeVolume(LotSize);

   double lotSize = riskAmount / (slPoints * valuePerPt);

   // v6.21: CONCURRENT-POSITION RISK SPLIT -- off by default (concurrentSameDirCount
   // defaults to 0, no effect). When UseConcurrentRiskSplit=true and a 2nd same-direction
   // position is opening while one is already live, divide the lot down so combined risk
   // across both stays near the original single-position RiskPercent instead of stacking.
   if(UseConcurrentRiskSplit && concurrentSameDirCount > 0) {
      lotSize = lotSize / (1.0 + concurrentSameDirCount);
   }

   return NormalizeVolume(lotSize);
}

//+------------------------------------------------------------------+
//| STAGE PROFIT MANAGEMENT (NEW!)                                  
//+------------------------------------------------------------------+
void ManageStagedProfits() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
         position.Magic() == MagicNumber) {

         ulong ticket = position.Ticket();
         double entryPrice = position.PriceOpen();
         ENUM_POSITION_TYPE posType = position.PositionType();
         double currentPrice = (posType == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                               SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         double profitDistance = 0;
         if(posType == POSITION_TYPE_BUY) {
            profitDistance = (currentPrice - entryPrice) / _Point;
         } else {
            profitDistance = (entryPrice - currentPrice) / _Point;
         }

         double mfePx = 0, maePx = 0;
         int barsToMfePx = 0, barsToMaePx = 0;
         Bot1GetMFEMAE(ticket, mfePx, maePx, barsToMfePx, barsToMaePx);

         // MAX TRADE AGE (2026-09-19): close at market if the position has
         // been open too long. Checked BEFORE breakeven/staged-exit logic so
         // an aging loser gets cut even if it never reached BE/TP1 -- see
         // input group comment for the real-data rationale (win% climbing
         // steadily with hold duration suggests many losers are fast,
         // low-conviction SL hits, not genuinely bad setups that deserve
         // more time; MaxTradeAgeOnlyIfLosing defaults true specifically so
         // this does NOT cut the 8h-24h/24h+ buckets that showed the
         // strongest win rates in that same data).
         if(UseMaxTradeAge && MaxTradeAgeBars > 0) {
            int ageBars = Bot1GetTradeAgeBars(ticket);
            bool ageLimitHit = (ageBars >= 0 && ageBars >= MaxTradeAgeBars);
            bool currentlyLosing = (profitDistance < 0);
            if(ageLimitHit && (!MaxTradeAgeOnlyIfLosing || currentlyLosing)) {
               double ageClosePrice = currentPrice;
                  double ageVolume = position.Volume();
                  double agePnl = position.Profit();
                  double ageEarlyPx1Bar, ageEarlyPx3Bar, ageEarlyPx5Bar;
                  Bot1GetEarlyPriceAction(ticket, ageEarlyPx1Bar, ageEarlyPx3Bar, ageEarlyPx5Bar);
                  trade.PositionClose(ticket);
               uint ageRc = trade.ResultRetcode();
               bool ageOk = (ageRc == TRADE_RETCODE_DONE || ageRc == TRADE_RETCODE_DONE_PARTIAL);
               if(ageOk) {
                     Bot1WriteTradeLog(ticket, "CLOSE", ageClosePrice, ageVolume, agePnl, 0,
                        "MAX_TRADE_AGE_HIT", position.StopLoss(), position.TakeProfit(), 0, 0, 0,
                        mfePx, maePx, barsToMfePx, barsToMaePx, 0, -1,
                        "", -1, -1, "", -1, -1, -1, -1, -999999, -1,
                        -999999, -999999, -99, -99, -1, -999999, -99, "", -1, -1,
                        -999999, -999999, -999999,
                        ageEarlyPx1Bar, ageEarlyPx3Bar, ageEarlyPx5Bar);
                     if(agePnl > 0) g_consecLosses = 0; else if(agePnl < 0) g_consecLosses++;
                     continue;   // position is gone -- skip the rest of this iteration's staged-exit logic
               } else {
                  Print("[BOT1-ERROR] Max-trade-age close REJECTED for ", _Symbol, " ticket=", ticket,
                        " age_bars=", ageBars, " retcode=", ageRc);
               }
            }
         }

         // WIDE_SL_BE branch (2026-09-10): breakeven-move, independent of
         // ExitMode/TP1/TP2/trailing below. Fires once per ticket when
         // profitDistance reaches BreakevenTriggerR fraction of the trade's
         // own initial risk distance (works whether that distance came from
         // a normal or WideSL-widened stop). Targets the audited finding
         // that ~48-52% of eventual full losers already touched >=0.5R
         // profit before reversing all the way to a stop-out -- this
         // converts that population into a scratch/small-win instead of a
         // full-R loss, without touching how far winners are allowed to run.
         if(UseBreakevenMove && !Bot1GetBEApplied(ticket) && !Bot1IsOnCloseCooldown(ticket)) {
            double beRiskDist = Bot1InitialRiskDist(ticket, entryPrice, position.StopLoss());
            if(beRiskDist > _Point) {
               double beRNow = (profitDistance * _Point) / beRiskDist;
               if(beRNow >= BreakevenTriggerR) {
                  double beSL = (posType == POSITION_TYPE_BUY) ?
                     entryPrice + (BreakevenBufferPts * _Point) :
                     entryPrice - (BreakevenBufferPts * _Point);
                  bool beImprovesOnCurrent = (posType == POSITION_TYPE_BUY) ?
                     (beSL > position.StopLoss() + _Point) :
                     (beSL < position.StopLoss() - _Point);
                  if(beImprovesOnCurrent) {
                     trade.PositionModify(ticket, beSL, position.TakeProfit());
                     uint beRc = trade.ResultRetcode();
                     bool beOk = (beRc == TRADE_RETCODE_DONE || beRc == TRADE_RETCODE_DONE_PARTIAL);
                     if(beOk) {
                        Bot1SetBEApplied(ticket, true);
                        Bot1WriteTradeLog(ticket, "BREAKEVEN_MOVE", currentPrice, position.Volume(), position.Profit(), 0, "breakeven_trigger_hit",
                           beSL, position.TakeProfit(), 0, 0, 0, mfePx, maePx, barsToMfePx, barsToMaePx);
                        if(!position.SelectByTicket(ticket)) continue;
                     } else {
                        Print("[BOT1-ERROR] Breakeven SL modify REJECTED for ", _Symbol, " ticket=", ticket,
                              " requested_sl=", beSL, " retcode=", beRc, " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                        Bot1SetCloseCooldown(ticket);
                     }
                  } else {
                     // current SL (e.g. already trailed past BE) is already better -- nothing to do, mark done
                     Bot1SetBEApplied(ticket, true);
                  }
               }
            }
         }

         bool stageHit1 = (profitDistance >= g_TP1_Distance);
         bool stageHit2 = (profitDistance >= g_TP2_Distance);
         double stageClose1 = g_TP1_ClosePercent;
         double stageClose2 = g_TP2_ClosePercent;
         if(g_ExitMode == EXIT_RR_PARTIAL) {
            double slDist = Bot1InitialRiskDist(ticket, entryPrice, position.StopLoss());
            double rNow = (profitDistance * _Point) / slDist;
            stageHit1 = (rNow >= g_ExitRR_TP1R);
            stageHit2 = (rNow >= g_ExitRR_TP2R);
            stageClose1 = g_ExitRR_Close1Pct;
            stageClose2 = g_TP2_ClosePercent;  // remaining fraction at 2R; was hardcoded 1.0 which flattened the 3R rider
         }

         // STAGE 1: Close 25% at 30 pips
         // v5.8: gated on Bot1GetStage(ticket) < 1 -- previously this fired
         // on EVERY tick that profitDistance stayed above g_TP1_Distance,
         // producing a decaying series of minimum-lot partial closes
         // instead of one clean g_TP1_ClosePercent close. Now fires once;
         // failure (rare) is throttled via the same cooldown as the
         // final-close-target fix, not retried every tick.
         if(g_UseStageExits && stageHit1 && position.Volume() > 0.01
            && Bot1GetStage(ticket) < 1 && !Bot1IsOnCloseCooldown(ticket)) {
            double volumeToClose = Bot1PartialCloseVolume(position.Volume(), stageClose1);
            if(volumeToClose >= 0.01) {
               if(trade.PositionClosePartial(ticket, volumeToClose)) {
                  Print("TP1 Hit: Closed ", volumeToClose, " at ", g_TP1_Distance, " pips");
                  double pComm = 0, pSwap = 0, pRealized = 0;
                  ulong pDeal = trade.ResultDeal();
                  if(pDeal != 0 && HistoryDealSelect(pDeal)) {
                     pComm = HistoryDealGetDouble(pDeal, DEAL_COMMISSION);
                     pSwap = HistoryDealGetDouble(pDeal, DEAL_SWAP);
                     pRealized = HistoryDealGetDouble(pDeal, DEAL_PROFIT);
                  }
                  Bot1MarkDealLogged(pDeal);
                  Bot1WriteTradeLog(ticket, "TP1_PARTIAL", currentPrice, volumeToClose, pRealized, 0, "TP1_Distance_hit",
                     position.StopLoss(), position.TakeProfit(), 0, pComm, pSwap, mfePx, maePx, barsToMfePx, barsToMaePx);
                  Bot1SetStage(ticket, 1);
                  // P0: ClosePartial leaves CPositionInfo volume stale/zero on
                  // this object. 1-Min OHLC can jump TP1 and TP2 on one tick
                  // (GOLD 2026.08.24 00:05:40). Re-select so TP2 sees 0.07 not 0.
                  if(!position.SelectByTicket(ticket)) continue;

                  // v6.16 STAGE-LINKED BE: fires right here, same tick TP1
                  // partial-closes -- not a separate MFE-based check. Snap SL
                  // to entry+/-BEBufferAfterTP1Pts so the remainder can never
                  // turn into a full loser, while leaving BEBufferAfterTP1Pts
                  // of room for normal oscillation instead of a dead-zero stop.
                  if(UseStagedBE && !Bot1GetBEApplied(ticket)) {
                     double stagedBeSL = (posType == POSITION_TYPE_BUY) ?
                        entryPrice + (BEBufferAfterTP1Pts * _Point) :
                        entryPrice - (BEBufferAfterTP1Pts * _Point);
                     bool stagedBeImproves = (posType == POSITION_TYPE_BUY) ?
                        (stagedBeSL > position.StopLoss() + _Point) :
                        (stagedBeSL < position.StopLoss() - _Point);
                     if(stagedBeImproves) {
                        trade.PositionModify(ticket, stagedBeSL, position.TakeProfit());
                        uint sbRc = trade.ResultRetcode();
                        if(sbRc == TRADE_RETCODE_DONE || sbRc == TRADE_RETCODE_DONE_PARTIAL) {
                           Bot1SetBEApplied(ticket, true);
                           Bot1WriteTradeLog(ticket, "BREAKEVEN_MOVE", currentPrice, position.Volume(), position.Profit(), 0, "staged_be_after_tp1",
                              stagedBeSL, position.TakeProfit(), 0, 0, 0, mfePx, maePx, barsToMfePx, barsToMaePx);
                           if(!position.SelectByTicket(ticket)) continue;
                        } else {
                           Print("[BOT1-ERROR] Staged BE SL modify REJECTED for ", _Symbol, " ticket=", ticket,
                                 " requested_sl=", stagedBeSL, " retcode=", sbRc);
                        }
                     } else {
                        Bot1SetBEApplied(ticket, true);
                     }
                  }
               } else {
                  Print("[BOT1-ERROR] TP1 partial close REJECTED for ", _Symbol, " ticket=", ticket,
                        " retcode=", trade.ResultRetcode(), " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                  Bot1SetCloseCooldown(ticket);
               }
            }
         }

         // 2.2 NEW: trail SL upward in the TP1->TP2 window (stage==1).
         // Runs every tick this branch is reached (not gated on stageHit1
         // being freshly true this tick) so the stop keeps ratcheting with
         // price for as long as the position sits in stage 1, right up
         // until TP2 fires and closes the remainder. Same trail math/legal-
         // distance clamp as the post-TP2 trailing block below; only ever
         // IMPROVES the stop (tighter), mirroring Bot1PositionModify's
         // existing one-directional guard pattern used for staged BE above.
         if(UseTrailBetweenTP1TP2 && Bot1GetStage(ticket) == 1
            && !Bot1IsOnTrailCooldown(ticket)) {
            int betweenTrailPts = Bot1LegalTrailPts();
            double betweenTrailSL = 0;
            bool betweenTrailImproves = false;
            if(posType == POSITION_TYPE_BUY) {
               betweenTrailSL = currentPrice - (betweenTrailPts * _Point);
               betweenTrailImproves = (betweenTrailSL > position.StopLoss() + _Point);
            } else {
               betweenTrailSL = currentPrice + (betweenTrailPts * _Point);
               betweenTrailImproves = (betweenTrailSL < position.StopLoss() - _Point);
            }
            if(betweenTrailImproves) {
               trade.PositionModify(ticket, betweenTrailSL, position.TakeProfit());
               uint btRc = trade.ResultRetcode();
               if(btRc == TRADE_RETCODE_DONE || btRc == TRADE_RETCODE_DONE_PARTIAL) {
                  Bot1WriteTradeLog(ticket, "TRAIL_UPDATE", betweenTrailSL, position.Volume(), position.Profit(), 0, "trail_between_tp1_tp2",
                     betweenTrailSL, position.TakeProfit(), 0, 0, 0, mfePx, maePx, barsToMfePx, barsToMaePx);
                  if(!position.SelectByTicket(ticket)) continue;
               } else {
                  Print("[BOT1-ERROR] Between-TP1/TP2 trail SL modify REJECTED for ", _Symbol, " ticket=", ticket,
                        " requested_sl=", betweenTrailSL, " retcode=", btRc, " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                  Bot1SetTrailCooldown(ticket);
               }
            }
         }

         // STAGE 2: Close 30% at 50 pips
         // v5.8: same one-shot fix as STAGE 1 above.
         if(g_UseStageExits && stageHit2 && position.Volume() > 0.01
            && Bot1GetStage(ticket) < 2 && !Bot1IsOnCloseCooldown(ticket)) {
            double volumeToClose = Bot1PartialCloseVolume(position.Volume(), stageClose2);
            if(volumeToClose >= 0.01) {
               if(trade.PositionClosePartial(ticket, volumeToClose)) {
                  Print("TP2 Hit: Closed ", volumeToClose, " at ", g_TP2_Distance, " pips");
                  double pComm = 0, pSwap = 0, pRealized = 0;
                  ulong pDeal = trade.ResultDeal();
                  if(pDeal != 0 && HistoryDealSelect(pDeal)) {
                     pComm = HistoryDealGetDouble(pDeal, DEAL_COMMISSION);
                     pSwap = HistoryDealGetDouble(pDeal, DEAL_SWAP);
                     pRealized = HistoryDealGetDouble(pDeal, DEAL_PROFIT);
                  }
                  Bot1MarkDealLogged(pDeal);
                  Bot1WriteTradeLog(ticket, "TP2_PARTIAL", currentPrice, volumeToClose, pRealized, 0, "TP2_Distance_hit",
                     position.StopLoss(), position.TakeProfit(), 0, pComm, pSwap, mfePx, maePx, barsToMfePx, barsToMaePx);
                  Bot1SetStage(ticket, 2);
                  if(!position.SelectByTicket(ticket)) continue;
               } else {
                  Print("[BOT1-ERROR] TP2 partial close REJECTED for ", _Symbol, " ticket=", ticket,
                        " retcode=", trade.ResultRetcode(), " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                  Bot1SetCloseCooldown(ticket);
               }
            }
         }

         // STAGE 3 (final-target mode, epoch-2 option): close 100% of the
         // remainder at a fixed Y+Z distance instead of trailing indefinitely.
         // Mutually exclusive with the trailing stage below -- pick one per epoch.
         // v5.7: added !Bot1IsOnCloseCooldown(ticket) -- see cooldown block
         // above. Previously retried every tick with no backoff on failure.
         if(g_UseStageExits && UseFinalCloseTarget && profitDistance >= TPFinal_Distance && position.Volume() > 0.01
            && !Bot1IsOnCloseCooldown(ticket)) {
            double remainingVol = position.Volume();
            if(trade.PositionClose(ticket)) {
               double pComm = 0, pSwap = 0, pRealized = 0;
               ulong pDeal = trade.ResultDeal();
               if(pDeal != 0 && HistoryDealSelect(pDeal)) {
                  pComm = HistoryDealGetDouble(pDeal, DEAL_COMMISSION);
                  pSwap = HistoryDealGetDouble(pDeal, DEAL_SWAP);
                  pRealized = HistoryDealGetDouble(pDeal, DEAL_PROFIT);
               }
               Bot1MarkDealLogged(pDeal);
               Print("Final close target hit: closed remaining ", remainingVol, " at ", TPFinal_Distance, " pips");
               Bot1WriteTradeLog(ticket, "FINAL_CLOSE_TARGET", currentPrice, remainingVol, pRealized, 0, "TPFinal_Distance_hit",
                  position.StopLoss(), position.TakeProfit(), 0, pComm, pSwap, mfePx, maePx, barsToMfePx, barsToMaePx);
               Bot1ReleaseMFESlot(ticket);
               Bot1ReleaseStageTracker(ticket);
               Bot1RecordTradeOutcome(ticket);
               Bot1RegisterPostmortemWatch(ticket, currentPrice, (posType == POSITION_TYPE_BUY) ? 1 : -1, "TPFinal_Distance_hit");
            } else {
               Print("[BOT1-ERROR] Final close target REJECTED for ", _Symbol, " ticket=", ticket,
                     " retcode=", trade.ResultRetcode(), " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
               Bot1SetCloseCooldown(ticket);
            }
         }

         // STAGE 3b: Trail remaining -- skipped entirely when UseFinalCloseTarget is active
         // v5.9: added !Bot1IsOnTrailCooldown(ticket) -- same unguarded-retry
         // exposure as v5.7/v5.8 fixed elsewhere, now closed here too.
         // v6.16: TrailImmediatelyAfterTP2 bypasses the TrailingActivation
         // point-distance gate once stage>=2 (TP2 already closed) -- trail
         // starts moving with price on the very next tick instead of waiting
         // for profitDistance to separately climb past TrailingActivation.
         bool trailActivationMet = (profitDistance >= TrailingActivation) ||
            (TrailImmediatelyAfterTP2 && Bot1GetStage(ticket) >= 2);
         if(Bot1TrailAllowed() && trailActivationMet
            && !Bot1IsOnTrailCooldown(ticket)
            && (g_ExitMode != EXIT_RR_PARTIAL || Bot1GetStage(ticket) >= 2)) {
            int trailPts = Bot1LegalTrailPts();
            double trailingStopPrice = 0;
            if(posType == POSITION_TYPE_BUY) {
               trailingStopPrice = currentPrice - (trailPts * _Point);
               if(position.StopLoss() < trailingStopPrice - _Point) {
                  trade.PositionModify(ticket, trailingStopPrice, 0);
                  uint rc = trade.ResultRetcode();
                  bool modifyOk = (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL);
                  if(modifyOk) {
                     Bot1WriteTradeLog(ticket, "TRAIL_UPDATE", trailingStopPrice, position.Volume(), position.Profit(), 0, "trail_buy",
                        trailingStopPrice, position.TakeProfit(), 0, 0, 0, mfePx, maePx, barsToMfePx, barsToMaePx);
                  } else {
                     Print("[BOT1-ERROR] Trailing SL modify REJECTED for ", _Symbol, " ticket=", ticket,
                           " requested_sl=", trailingStopPrice, " retcode=", rc, " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                     Bot1SetTrailCooldown(ticket);
                  }
               }
            } else {
               trailingStopPrice = currentPrice + (trailPts * _Point);
               if(position.StopLoss() > trailingStopPrice + _Point) {
                  trade.PositionModify(ticket, trailingStopPrice, 0);
                  uint rc = trade.ResultRetcode();
                  bool modifyOk = (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL);
                  if(modifyOk) {
                     Bot1WriteTradeLog(ticket, "TRAIL_UPDATE", trailingStopPrice, position.Volume(), position.Profit(), 0, "trail_sell",
                        trailingStopPrice, position.TakeProfit(), 0, 0, 0, mfePx, maePx, barsToMfePx, barsToMaePx);
                  } else {
                     Print("[BOT1-ERROR] Trailing SL modify REJECTED for ", _Symbol, " ticket=", ticket,
                           " requested_sl=", trailingStopPrice, " retcode=", rc, " -- will retry in ", BOT1_CLOSE_RETRY_COOLDOWN_SEC, "s");
                     Bot1SetTrailCooldown(ticket);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| BOT1 LOGGING HELPERS                                             |
//+------------------------------------------------------------------+
string Bot1SanitizeCSV(string s) {
   StringReplace(s, ",", ";");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
}

// PERF FIX helper: opens `filename` once and caches the handle in
// `handleRef` for the life of the EA, writing `header` only the first time
// the file is created. Every subsequent call just returns the cached
// handle -- callers still FileSeek to end before writing (cheap on an
// already-open handle, unlike the FileOpen/FileClose it replaces).
int Bot1GetLogHandle(int &handleRef, string filename, string header) {
   if(handleRef != INVALID_HANDLE) return handleRef;
   // Tester /config + ShutdownTerminal wipes the sandbox Files folder.
   // FILE_COMMON keeps CSVs in Terminal\Common\Files so we can read them after the run.
   int commonFlag = 0;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      commonFlag = FILE_COMMON;
   bool exists = FileIsExist(filename, commonFlag);
   ResetLastError();
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | commonFlag);
   if(handle == INVALID_HANDLE) {
      Print("[BOT1-ERROR] Log FileOpen FAILED for ", _Symbol, " file=", filename, " err=", GetLastError());
      return INVALID_HANDLE;
   }
   if(!exists || FileSize(handle) == 0) {
      FileWriteString(handle, header);
   } else {
      FileSeek(handle, 0, SEEK_END);
   }
   handleRef = handle;
   return handleRef;
}

//+------------------------------------------------------------------+
//| HEARTBEAT LOG (2026-09-04)                                       |
//| Proof-of-life independent of bars/ticks/trades. Call once per    |
//| tick from OnTick() -- internally rate-limits to                  |
//| HeartbeatIntervalSeconds so it costs nothing beyond a datetime    |
//| comparison on every other tick.                                  |
//+------------------------------------------------------------------+
void Bot1WriteHeartbeat() {
   if(!LogBot1Heartbeat || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   // v2 AGILE (2026-09-06): gate on MQL_TESTER, ported preemptively from a
   // bot4 lesson -- TimeCurrent() is SIMULATED time inside the Strategy
   // Tester, not wall-clock time, so a 300s interval races through
   // continuously across an 8-month backtest (bot4 measured ~70,000 writes
   // in a SINGLE pass, collapsing sweep throughput from thousands/hour to
   // ~32/hour). Heartbeat has zero analytical value in any deterministic
   // backtest anyway -- "is a human-facing live chart still alive" isn't a
   // question that exists there. Live/demo only.
   if(MQLInfoInteger(MQL_TESTER)) return;
   g_ticksSinceLastHeartbeat++;
   datetime now = TimeCurrent();
   if(g_lastHeartbeatTime != 0 && (now - g_lastHeartbeatTime) < HeartbeatIntervalSeconds) return;

   string filename = Bot1FilePrefix + "_heartbeat_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_heartbeatLogHandle, filename,
      "event_time,symbol,config_label,magic,ticks_since_last,spread_points,"
      "open_positions_this_magic,balance,equity,last_bar_time,seconds_since_last_bar,"
      "cooldown_buy_active,cooldown_sell_active,terminal_connected\n");
   if(handle == INVALID_HANDLE) return;

   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber) posCount++;
   }
   double spreadPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   datetime barTime = iTime(_Symbol, _Period, 0);
   long secsSinceBar = (long)(now - barTime);
   bool cdBuy = (now < g_cooldownUntilBuyBar);
   bool cdSell = (now < g_cooldownUntilSellBar);

   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + ConfigLabel + "," + IntegerToString(MagicNumber) + ","
      + IntegerToString((long)g_ticksSinceLastHeartbeat) + "," + DoubleToString(spreadPts, 1) + ","
      + IntegerToString(posCount) + "," + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ","
      + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "," + TimeToString(barTime) + ","
      + IntegerToString((int)secsSinceBar) + "," + (cdBuy ? "YES" : "NO") + "," + (cdSell ? "YES" : "NO") + ",YES\n");

   g_lastHeartbeatTime = now;
   g_ticksSinceLastHeartbeat = 0;
}

//+------------------------------------------------------------------+
//| REGIME EVENT LOG (2026-09-04)                                    |
//| Event-driven: writes a row ONLY when kill-switch, regime-suite    |
//| verdict, an individual regime gate, or cooldown state actually    |
//| CHANGES since the last bar. Call once per bar close.              |
//+------------------------------------------------------------------+
void Bot1WriteRegimeEvent(string eventType, string detail) {
   if(!LogBot1RegimeEvents || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   string filename = Bot1FilePrefix + "_regime_events_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_regimeEventLogHandle, filename,
      "event_time,symbol,config_label,magic,event_type,detail,"
      "adx_gate,er_gate,chop_gate,linreg_gate,atrratio_gate,mmi_gate,session_gate,"
      "atrband_gate,atrspike_gate,asianrange_gate,vote_mode,rolling_win_rate\n");
   if(handle == INVALID_HANDLE) return;

   string g_adx = g_UseRegimeADX ? (RegimeADXTrending() ? "T" : "R") : "-";
   string g_er  = g_UseRegimeER ? (RegimeERTrending() ? "T" : "R") : "-";
   string g_chop = g_UseRegimeCHOP ? (RegimeCHOPTrending() ? "T" : "R") : "-";
   string g_lr = g_UseRegimeLinReg ? (RegimeLinRegTrending() ? "T" : "R") : "-";
   string g_atrr = g_UseRegimeATRRatio ? (RegimeATRRatioTrending() ? "T" : "R") : "-";
   string g_mmi = g_UseRegimeMMI ? (RegimeMMITrending() ? "T" : "R") : "-";
   string g_sess = g_UseRegimeSession ? (RegimeSessionAllowed() ? "IN" : "OUT") : "-";
   string g_band = g_UseATRBandGate ? (ATRBandAllows() ? "OK" : "BLOCK") : "-";
   string g_spike = g_UseATRSpikeFilter ? (ATRSpikeAllows() ? "OK" : "BLOCK") : "-";
   string g_asian = g_UseAsianRangeFilter ? (g_asianRangeDayAllowed ? "ALLOWED" : "BLOCKED") : "-";

   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + ConfigLabel + "," + IntegerToString(MagicNumber) + ","
      + eventType + "," + Bot1SanitizeCSV(detail) + ","
      + g_adx + "," + g_er + "," + g_chop + "," + g_lr + "," + g_atrr + "," + g_mmi + "," + g_sess + ","
      + g_band + "," + g_spike + "," + g_asian + "," + EnumToString(RegimeSuiteVoteMode) + ","
      + DoubleToString(Bot1GetRollingWinRate(RegimeLookbackTrades), 3) + "\n");
}

// Checks all regime/kill-switch/cooldown state against the last-known
// snapshot and writes a Bot1WriteRegimeEvent row for whichever ones
// changed. Call once per bar close, AFTER the gates have been evaluated
// for this bar (so the values reflect what actually applied).
void Bot1CheckRegimeTransitions() {
   if(!LogBot1RegimeEvents || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   // v2 AGILE (2026-09-06): bar-driven (not wall-clock), so this doesn't
   // have heartbeat's runaway-write-count problem, but bot4's lesson still
   // applies during a MASS optimization sweep -- thousands of passes all
   // appending transition rows to the SAME shared file adds up, and a
   // single pass's regime transitions have no analytical value when nobody
   // will ever read that specific pass's file. Skip only for MASS sweeps;
   // keep it for single-run verify (genuinely useful there) and live/demo.
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;

   bool killActive = Bot1RegimeKillSwitchActive();
   if(killActive != g_lastKillSwitchActive) {
      Bot1WriteRegimeEvent(killActive ? "KILLSWITCH_TRIPPED" : "KILLSWITCH_RELEASED", "");
      g_lastKillSwitchActive = killActive;
   }

   bool regimeDegraded = g_UseRegimeSuiteGate && Bot1RegimeSuiteSaysRanging();
   if(regimeDegraded != g_lastRegimeDegraded) {
      Bot1WriteRegimeEvent(regimeDegraded ? "REGIME_DEGRADED" : "REGIME_CLEARED", "");
      g_lastRegimeDegraded = regimeDegraded;
   }

   // Individual-gate snapshot: catches a single filter flipping even when
   // the combined vote verdict doesn't change (e.g. MAJORITY mode with
   // several filters already agreeing).
   string snapshot = (g_UseRegimeADX ? (RegimeADXTrending()?"T":"R") : "-")
      + (g_UseRegimeER ? (RegimeERTrending()?"T":"R") : "-")
      + (g_UseRegimeCHOP ? (RegimeCHOPTrending()?"T":"R") : "-")
      + (g_UseRegimeLinReg ? (RegimeLinRegTrending()?"T":"R") : "-")
      + (g_UseRegimeATRRatio ? (RegimeATRRatioTrending()?"T":"R") : "-")
      + (g_UseRegimeMMI ? (RegimeMMITrending()?"T":"R") : "-")
      + (g_UseRegimeSession ? (RegimeSessionAllowed()?"I":"O") : "-")
      + (g_UseATRBandGate ? (ATRBandAllows()?"O":"B") : "-")
      + (g_UseATRSpikeFilter ? (ATRSpikeAllows()?"O":"B") : "-")
      + (g_UseAsianRangeFilter ? (g_asianRangeDayAllowed?"A":"B") : "-");
   if(snapshot != g_lastRegimeGateSnapshot && g_lastRegimeGateSnapshot != "") {
      Bot1WriteRegimeEvent("GATE_FLIP", g_lastRegimeGateSnapshot + " -> " + snapshot);
   }
   g_lastRegimeGateSnapshot = snapshot;

   bool cdBuy = (TimeCurrent() < g_cooldownUntilBuyBar);
   bool cdSell = (TimeCurrent() < g_cooldownUntilSellBar);
   if(cdBuy != g_lastCooldownBuyActive) {
      Bot1WriteRegimeEvent(cdBuy ? "COOLDOWN_START_BUY" : "COOLDOWN_END_BUY", "");
      g_lastCooldownBuyActive = cdBuy;
   }
   if(cdSell != g_lastCooldownSellActive) {
      Bot1WriteRegimeEvent(cdSell ? "COOLDOWN_START_SELL" : "COOLDOWN_END_SELL", "");
      g_lastCooldownSellActive = cdSell;
   }
}

string Bot1Timestamp() {
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d", mdt.year, mdt.mon, mdt.day, mdt.hour, mdt.min, mdt.sec);
}

// Captures every raw value ONCE per bar-close. Disabled filters still
// populate their field (function returns 0/false safely) -- they are
// never omitted from the row, only excluded from the live trade gate.
void Bot1CaptureLayer1(Bot1Layer1State &st) {
   st.ichi_signal = GetIchimokuTrend();
   st.ema_signal  = GetEMACrossTrend();
   st.psar_signal = GetPSARTrend();
   st.st_signal   = GetSuperTrendSignal();
   int ema200Sig  = GetEMA200Bias();
   st.l1_result   = GetLayer1TrendFromSignals(st.ichi_signal, st.ema_signal, st.psar_signal, st.st_signal, ema200Sig);
   st.l1_confirmations = 0;
   st.l1_vote_n = 0;
   if(g_UseIchimoku)   { st.l1_confirmations += st.ichi_signal; st.l1_vote_n++; }
   if(g_UseEMACross)   { st.l1_confirmations += st.ema_signal;  st.l1_vote_n++; }
   if(g_UsePSAR)       { st.l1_confirmations += st.psar_signal; st.l1_vote_n++; }
   if(g_UseSuperTrend) { st.l1_confirmations += st.st_signal;   st.l1_vote_n++; }
   if(g_UseEMA200Bias) { st.l1_confirmations += ema200Sig;      st.l1_vote_n++; }
   st.l1_pass_strict = (st.l1_result != 0);
}

void Bot1CaptureLayer2(Bot1Layer2State &st, int trend) {
   st.macd_signal = GetMACDMomentum();
   st.rsi_signal  = GetRSIMomentum();
   st.adx_ok      = GetADXStrength(trend);
   st.cci_signal  = GetCCIMomentum();
   st.adx_slope   = GetADXSlope();
   Bot1RefreshRegime2Cache();
   st.cci_value   = g_r2.cciValue;

   double r[]; ArraySetAsSeries(r, true);
   st.rsi_value = (rsiHandle != INVALID_HANDLE && CopyBuffer(rsiHandle, 0, 0, 1, r) >= 1) ? r[0] : 0.0;

   double adx[], pdi[], mdi[];
   ArraySetAsSeries(adx, true); ArraySetAsSeries(pdi, true); ArraySetAsSeries(mdi, true);
   if(adxHandle != INVALID_HANDLE &&
      CopyBuffer(adxHandle, 0, 0, 1, adx) >= 1 &&
      CopyBuffer(adxHandle, 1, 0, 1, pdi) >= 1 &&
      CopyBuffer(adxHandle, 2, 0, 1, mdi) >= 1) {
      st.adx_value = adx[0]; st.plus_di = pdi[0]; st.minus_di = mdi[0];
   } else { st.adx_value = 0; st.plus_di = 0; st.minus_di = 0; }

   bool useMacd, useRsi, useAdx, useCci;
   Bot1GetL2VoterFlags(useMacd, useRsi, useAdx, useCci);
   st.rsi_voter_active = useRsi;
   st.cci_voter_active = useCci;

   int aligned = 0;
   if(useMacd && st.macd_signal == trend) aligned++;
   if(useRsi && st.rsi_signal == trend) aligned++;
   if(useAdx && st.adx_ok) aligned++;
   if(useCci && st.cci_signal == trend) aligned++;
   st.l2_confirmations = aligned;
   st.l2_pass_strict = CheckLayer2MomentumFromSignals(trend, st.macd_signal, st.rsi_signal, st.adx_ok,
                                                     st.cci_signal, useMacd, useRsi, useAdx, useCci);
}

void Bot1CaptureLayer3(Bot1Layer3State &st, int trend) {
   st.boll_signal     = GetBollingerTrigger();
   st.obv_signal      = GetOBVTrigger();
   st.donchian_signal = GetDonchianTrigger();
   if(g_UseRetest || Bot1R2DiagOn()) Bot1UpdateDonchianRetest();
   st.retest_signal   = GetDonchianRetestTrigger();
   st.vwap_reclaim_signal = GetVWAPReclaimTrigger();
   st.retest_pending_dir = g_retestPendingDir;
   st.retest_bars_left   = g_retestBarsLeft;
   st.l3_result       = GetLayer3TriggerFromSignals(st.boll_signal, st.obv_signal, st.donchian_signal,
                                                   st.retest_signal, st.vwap_reclaim_signal);
   st.l3_pass_strict = (trend != 0 && st.l3_result == trend);
}

void Bot1CaptureVol(Bot1VolState &st) {
   st.atr_ratio = GetVolatilityRatio();
   st.vol_state = GetVolatilityState();
   st.vol_filter_pass_strict = IsMarketTradable();
}

void Bot1CaptureRisk(Bot1RiskContext &st) {
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   st.day_of_week = mdt.day_of_week;
   st.hour_utc    = mdt.hour;
   double spread  = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double pipSize = (_Digits == 3 || _Digits == 5) ? _Point * 10 : _Point;
   st.spread_pips = (pipSize > 0) ? spread / pipSize : 0.0;
   st.time_filter_pass = IsTradingTimeAllowed();
}

// bot1_candidates_{SYM}.csv -- every bar-close, unconditional, no gating.
// This is the raw material for the labeler/analytics: full state whether
// or not L1 gated a trade, so later we can test L2/L3/vol combinations
// we did NOT trade on live.
void Bot1WriteCandidateLog(Bot1Layer1State &l1, Bot1Layer2State &l2, Bot1Layer3State &l3,
                            Bot1VolState &vs, Bot1RiskContext &rc, bool tradeOpened,
                            string blockReason, bool slDistOutlier, bool cooldownBlocking) {
   if(!LogBot1Candidates || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   // v2 AGILE (2026-09-06): skip during MASS optimization sweeps only (bot4
   // lesson, §3.8/§6 of its knowledge doc) -- this log is bar-driven, not
   // wall-clock, so it doesn't have heartbeat's runaway write-count bug, but
   // thousands of genetic passes all appending to ONE shared candidates.csv
   // still adds real I/O overhead for data nobody will ever read per-pass.
   // Single-run verify (genuinely useful) and live/demo are unaffected.
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   string filename = Bot1FilePrefix + "_candidates_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_candidateLogHandle, filename,
      "event_time,symbol,l1_ichi,l1_ema,l1_psar,l1_confirmations,l1_result,l1_pass_strict,"
      "l2_macd,l2_rsi_signal,l2_rsi_value,l2_adx_ok,l2_adx_value,l2_plus_di,l2_minus_di,l2_confirmations,l2_pass_strict,"
      "l3_boll,l3_obv,l3_donchian,l3_result,l3_pass_strict,"
      "atr_ratio,vol_state,vol_filter_pass_strict,"
      "day_of_week,hour_utc,spread_pips,time_filter_pass,"
      "would_open_strict,would_open_l1_only,would_open_l2_or_l3,would_open_any_two_of_three,"
      "trade_opened_live,block_reason,sl_dist_would_be_outlier,cooldown_blocking,"
      "l1_st,l1_mode,l1_vote_n,l2_cci,l2_cci_value,l2_adx_slope,l2_rsi_active,l2_cci_active,"
      "l3_mode,l3_retest,l3_vwap_reclaim,vwap,exhaustion_frac,rsi_mode,stop_basis,preset\n");
   if(handle == INVALID_HANDLE) return;

   bool wouldOpenStrict = l1.l1_pass_strict && l2.l2_pass_strict && l3.l3_pass_strict && vs.vol_filter_pass_strict;
   bool wouldOpenL1Only = l1.l1_pass_strict;
   bool wouldOpenL2orL3 = l1.l1_pass_strict && (l2.l2_pass_strict || l3.l3_pass_strict);
   int  layersPassed = (l1.l1_pass_strict ? 1 : 0) + (l2.l2_pass_strict ? 1 : 0) + (l3.l3_pass_strict ? 1 : 0);
   bool wouldOpenAnyTwo = layersPassed >= 2;

   string row = Bot1Timestamp() + "," + _Symbol + ","
      + IntegerToString(l1.ichi_signal) + "," + IntegerToString(l1.ema_signal) + "," + IntegerToString(l1.psar_signal) + ","
      + IntegerToString(l1.l1_confirmations) + "," + IntegerToString(l1.l1_result) + "," + (l1.l1_pass_strict ? "YES" : "NO") + ","
      + IntegerToString(l2.macd_signal) + "," + IntegerToString(l2.rsi_signal) + "," + DoubleToString(l2.rsi_value, 2) + ","
      + (l2.adx_ok ? "YES" : "NO") + "," + DoubleToString(l2.adx_value, 2) + "," + DoubleToString(l2.plus_di, 2) + "," + DoubleToString(l2.minus_di, 2) + ","
      + IntegerToString(l2.l2_confirmations) + "," + (l2.l2_pass_strict ? "YES" : "NO") + ","
      + IntegerToString(l3.boll_signal) + "," + IntegerToString(l3.obv_signal) + "," + IntegerToString(l3.donchian_signal) + ","
      + IntegerToString(l3.l3_result) + "," + (l3.l3_pass_strict ? "YES" : "NO") + ","
      + DoubleToString(vs.atr_ratio, 3) + "," + IntegerToString(vs.vol_state) + "," + (vs.vol_filter_pass_strict ? "YES" : "NO") + ","
      + IntegerToString(rc.day_of_week) + "," + IntegerToString(rc.hour_utc) + "," + DoubleToString(rc.spread_pips, 1) + "," + (rc.time_filter_pass ? "YES" : "NO") + ","
      + (wouldOpenStrict ? "YES" : "NO") + "," + (wouldOpenL1Only ? "YES" : "NO") + "," + (wouldOpenL2orL3 ? "YES" : "NO") + "," + (wouldOpenAnyTwo ? "YES" : "NO") + ","
      + (tradeOpened ? "YES" : "NO") + "," + Bot1SanitizeCSV(blockReason) + "," + (slDistOutlier ? "YES" : "NO") + "," + (cooldownBlocking ? "YES" : "NO") + ","
      + IntegerToString(l1.st_signal) + "," + Bot1Layer1TickTag() + "," + IntegerToString(l1.l1_vote_n) + ","
      + IntegerToString(l2.cci_signal) + "," + DoubleToString(l2.cci_value, 2) + "," + DoubleToString(l2.adx_slope, 4) + ","
      + (l2.rsi_voter_active ? "YES" : "NO") + "," + (l2.cci_voter_active ? "YES" : "NO") + ","
      + Bot1Layer3TickTag() + "," + IntegerToString(l3.retest_signal) + "," + IntegerToString(l3.vwap_reclaim_signal) + ","
      + DoubleToString(g_r2.sessionVwap, _Digits) + "," + DoubleToString(g_r2.exhaustionFrac, 4) + ","
      + EnumToString(g_Layer2RSIMode) + "," + EnumToString(g_StopBasisMode) + "," + Bot1RegimeTickTag() + "\n";
   FileWriteString(handle, row);
}

// Counts open positions across ALL symbols whose magic falls in bot1's
// range (Bot1MagicRangeStart..End), EXCLUDING the ticket passed in (so a
// trade doesn't count itself). This is cross-symbol correlation exposure,
// not same-symbol duplication (already capped by MaxBuyPositions/MaxSellPositions).
// Finds this ticket's tracking slot, or claims a free one on first sight.
// Called every tick for every open bot1 position -- O(BOT1_MFE_SLOTS), trivial cost.
int Bot1FindOrCreateMFESlot(ulong ticket, double entryPrice, int dir, datetime posOpenTime) {
   for(int i = 0; i < BOT1_MFE_SLOTS; i++)
      if(g_mfeUsed[i] && g_mfeTicket[i] == ticket) return i;
   for(int i = 0; i < BOT1_MFE_SLOTS; i++) {
      if(!g_mfeUsed[i]) {
         g_mfeUsed[i] = true; g_mfeTicket[i] = ticket; g_mfeEntry[i] = entryPrice; g_mfeDir[i] = dir;
         g_mfePeak[i] = entryPrice; g_mfeTrough[i] = entryPrice;
         g_mfeBarsElapsed[i] = 0; g_mfeBarsToPeak[i] = 0; g_mfeBarsToTrough[i] = 0;
         g_earlyPx1Bar[i] = BOT1_EARLY_PX_SENTINEL; g_earlyPx3Bar[i] = BOT1_EARLY_PX_SENTINEL; g_earlyPx5Bar[i] = BOT1_EARLY_PX_SENTINEL;
         // KNOWN LIMITATION: MQL5 resets all non-static globals (including this
         // whole tracking array) on every EA reinit -- .set redeploy, recompile,
         // or manual restart. If this position was already open before that
         // reinit, tracking silently restarts from "now" instead of true entry,
         // understating MFE/MAE for that trade. This branch runs exactly once
         // per ticket, so flagging it here has zero spam risk.
         int barPeriodSeconds = PeriodSeconds(_Period);
         int ageSeconds = (int)(TimeCurrent() - posOpenTime);
         if(posOpenTime > 0 && ageSeconds > barPeriodSeconds) {
            Print("[BOT1-INFO] ", _Symbol, " ticket=", ticket, " MFE/MAE tracking started MID-LIFE "
                  "(position opened ", ageSeconds, "s before this EA reinit) -- "
                  "mfe_price/mae_price for this trade will understate the true range, not from true entry.");
         }
         return i;
      }
   }
   return -1; // all slots full -- should not happen given MaxBuyPositions/MaxSellPositions are small
}

void Bot1ReleaseMFESlot(ulong ticket) {
   for(int i = 0; i < BOT1_MFE_SLOTS; i++)
      if(g_mfeUsed[i] && g_mfeTicket[i] == ticket) { g_mfeUsed[i] = false; return; }
}

// Call once per tick for price extremes, but bar count only advances on
// new-bar boundaries (isNewBar) -- keeps "bars to peak" meaningful in the
// same units as TrailingActivation/g_TP1_Distance/Bot1PostmortemBars.
void Bot1UpdateMFETracker(bool isNewBar) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
      ulong ticket = position.Ticket();
      int dir = (position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      int slot = Bot1FindOrCreateMFESlot(ticket, position.PriceOpen(), dir, position.Time());
      if(slot < 0) continue;
      if(isNewBar) g_mfeBarsElapsed[slot]++;
      double px = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // Capture early price-action snapshots at exactly bars 1/3/5 -- signed points-in-favor
      // (positive = price moved in the trade's favor). Captured once, on the new-bar tick where
      // g_mfeBarsElapsed just became 1/3/5; sentinel stays if the trade closes before reaching
      // that bar count (handled honestly downstream, not treated as 0).
      if(isNewBar) {
         double signedPtsNow = (dir == 1) ? (px - g_mfeEntry[slot]) : (g_mfeEntry[slot] - px);
         signedPtsNow /= _Point;
         if(g_mfeBarsElapsed[slot] == 1 && g_earlyPx1Bar[slot] == BOT1_EARLY_PX_SENTINEL) g_earlyPx1Bar[slot] = signedPtsNow;
         if(g_mfeBarsElapsed[slot] == 3 && g_earlyPx3Bar[slot] == BOT1_EARLY_PX_SENTINEL) g_earlyPx3Bar[slot] = signedPtsNow;
         if(g_mfeBarsElapsed[slot] == 5 && g_earlyPx5Bar[slot] == BOT1_EARLY_PX_SENTINEL) g_earlyPx5Bar[slot] = signedPtsNow;
      }
      if(dir == 1) {
         if(px > g_mfePeak[slot]) { g_mfePeak[slot] = px; g_mfeBarsToPeak[slot] = g_mfeBarsElapsed[slot]; }
         if(px < g_mfeTrough[slot]) { g_mfeTrough[slot] = px; g_mfeBarsToTrough[slot] = g_mfeBarsElapsed[slot]; }
      } else {
         if(px < g_mfePeak[slot]) { g_mfePeak[slot] = px; g_mfeBarsToPeak[slot] = g_mfeBarsElapsed[slot]; }
         if(px > g_mfeTrough[slot]) { g_mfeTrough[slot] = px; g_mfeBarsToTrough[slot] = g_mfeBarsElapsed[slot]; }
      }
   }
}

// Returns MFE/MAE in raw price distance (not points/pips) -- caller
// divides by _Point if pip units are wanted. 0/0 if ticket was never tracked
// (e.g. position existed before this EA build was deployed). barsToMfe/
// barsToMae are the bar count at which each extreme was reached.
void Bot1GetMFEMAE(ulong ticket, double &mfePrice, double &maePrice, int &barsToMfe, int &barsToMae) {
   mfePrice = 0; maePrice = 0; barsToMfe = 0; barsToMae = 0;
   for(int i = 0; i < BOT1_MFE_SLOTS; i++) {
      if(g_mfeUsed[i] && g_mfeTicket[i] == ticket) {
         if(g_mfeDir[i] == 1) { mfePrice = g_mfePeak[i] - g_mfeEntry[i]; maePrice = g_mfeEntry[i] - g_mfeTrough[i]; }
         else                 { mfePrice = g_mfeEntry[i] - g_mfePeak[i]; maePrice = g_mfeTrough[i] - g_mfeEntry[i]; }
         barsToMfe = g_mfeBarsToPeak[i]; barsToMae = g_mfeBarsToTrough[i];
         return;
      }
   }
}

// Returns the 3 early price-action snapshots (signed points-in-favor at bar 1/3/5)
// for a tracked ticket. Sentinel -999999 means that bar count was never reached
// before the trade closed -- callers/logging must NOT treat sentinel as 0, since
// 0 is a real possible value (price exactly at entry). Same lookup pattern as
// Bot1GetMFEMAE above, same "0/sentinel if never tracked" defensive fallback.
void Bot1GetEarlyPriceAction(ulong ticket, double &px1Bar, double &px3Bar, double &px5Bar) {
   px1Bar = BOT1_EARLY_PX_SENTINEL; px3Bar = BOT1_EARLY_PX_SENTINEL; px5Bar = BOT1_EARLY_PX_SENTINEL;
   for(int i = 0; i < BOT1_MFE_SLOTS; i++) {
      if(g_mfeUsed[i] && g_mfeTicket[i] == ticket) {
         px1Bar = g_earlyPx1Bar[i]; px3Bar = g_earlyPx3Bar[i]; px5Bar = g_earlyPx5Bar[i];
         return;
      }
   }
}

// MAX TRADE AGE (2026-09-19): reuses the MFE tracker's own per-ticket bar
// counter (g_mfeBarsElapsed[], already incremented once per NEW BAR for
// every open position regardless of UseMaxTradeAge) -- zero extra per-tick
// work, just a lookup. Returns -1 if this ticket isn't tracked (shouldn't
// happen for any position opened after this EA's OnInit, per the existing
// MFE slot system's own "mid-life" limitation noted in
// Bot1FindOrCreateMFESlot -- callers should treat -1 as "don't know, don't
// act", same defensive posture as every other MFE/MAE consumer in this file).
int Bot1GetTradeAgeBars(ulong ticket) {
   for(int i = 0; i < BOT1_MFE_SLOTS; i++) {
      if(g_mfeUsed[i] && g_mfeTicket[i] == ticket) return g_mfeBarsElapsed[i];
   }
   return -1;
}

void Bot1MarkDealLogged(ulong dealTicket) {
   if(dealTicket == 0) return;
   g_loggedDeals[g_loggedDealsIdx] = dealTicket;
   g_loggedDealsIdx = (g_loggedDealsIdx + 1) % BOT1_DEDUPE_SLOTS;
}

bool Bot1WasDealLogged(ulong dealTicket) {
   for(int i = 0; i < BOT1_DEDUPE_SLOTS; i++)
      if(g_loggedDeals[i] == dealTicket) return true;
   return false;
}

// Called once per full close (both from OnTradeTransaction's broker-side
// CLOSE and from the manual FINAL_CLOSE_TARGET path). Claims a free slot
// and starts watching price for Bot1PostmortemBars bars.
void Bot1RegisterPostmortemWatch(ulong ticket, double closePrice, int dir, string reason) {
   if(!LogBot1Postmortem || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   for(int i = 0; i < BOT1_PM_SLOTS; i++) {
      if(!g_pmUsed[i]) {
         g_pmUsed[i] = true; g_pmTicket[i] = ticket; g_pmClosePrice[i] = closePrice;
         g_pmDir[i] = dir; g_pmReason[i] = reason;
         g_pmMaxFavorable[i] = 0; g_pmMaxAdverse[i] = 0; g_pmBarsElapsed[i] = 0;
         return;
      }
   }
   // All slots full -- should be rare (10 concurrent post-mortems being tracked
   // at once on one symbol). Drop silently rather than overwrite live data;
   // this only loses postmortem data, never live trading state.
}

// Called once per NEW BAR (not every tick -- "bars" means bars, matching
// how TrailingActivation/g_TP1_Distance etc are already specified).
void Bot1UpdatePostmortemTracker() {
   if(!LogBot1Postmortem || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = 0; i < BOT1_PM_SLOTS; i++) {
      if(!g_pmUsed[i]) continue;
      g_pmBarsElapsed[i]++;
      // Use the same side a same-direction position would see, so this is
      // directly comparable to the original trade's own price reference.
      double px = (g_pmDir[i] == 1) ? bid : ask;
      double moveFromClose = (g_pmDir[i] == 1) ? (px - g_pmClosePrice[i]) : (g_pmClosePrice[i] - px);
      // positive = price moved back toward what would have been profit for
      // the original direction (a "reversal"); negative = kept going the
      // adverse way (a "continuation").
      if(moveFromClose > g_pmMaxFavorable[i]) g_pmMaxFavorable[i] = moveFromClose;
      if(-moveFromClose > g_pmMaxAdverse[i]) g_pmMaxAdverse[i] = -moveFromClose;

      if(g_pmBarsElapsed[i] >= Bot1PostmortemBars) {
         Bot1WritePostmortemLog(g_pmTicket[i], g_pmDir[i], g_pmReason[i], g_pmClosePrice[i],
            g_pmBarsElapsed[i], g_pmMaxFavorable[i], g_pmMaxAdverse[i]);
         g_pmUsed[i] = false;
      }
   }
}

void Bot1WritePostmortemLog(ulong ticket, int dir, string reason, double closePrice,
                             int barsTracked, double maxFavorable, double maxAdverse) {
   string filename = Bot1FilePrefix + "_postmortem_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_postmortemLogHandle, filename,
      "event_time,symbol,ticket,direction,exit_reason,close_price,bars_tracked,"
      "max_favorable_move,max_adverse_move\n");
   if(handle == INVALID_HANDLE) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + IntegerToString((long)ticket) + ","
      + (dir == 1 ? "BUY" : "SELL") + "," + Bot1SanitizeCSV(reason) + ","
      + DoubleToString(closePrice, digits) + "," + IntegerToString(barsTracked) + ","
      + DoubleToString(maxFavorable, digits) + "," + DoubleToString(maxAdverse, digits) + "\n");
}

void Bot1WriteShadowTradeLog(string exitReason, double realizedR, bool tp1Hit, bool tp2Hit) {
   if(!LogBot1Candidates || MQLInfoInteger(MQL_OPTIMIZATION)) return; // shadow logging shares the same on/off switch as candidates  // 2026-09-23: skip disk I/O during optimization/sweeps
   string filename = Bot1FilePrefix + "_shadow_trades_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_shadowTradeLogHandle, filename,
      "event_time,symbol,direction,entry_price,exit_reason,realized_r,tp1_hit,tp2_hit,"
      "bars_held,l1_result,l2_pass_strict,l3_pass_strict,rsi_value,adx_value,atr_ratio,"
      "vol_state,hour_utc,day_of_week\n");
   if(handle == INVALID_HANDLE) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + (g_shadowDir == 1 ? "BUY" : "SELL") + ","
      + DoubleToString(g_shadowEntry, digits) + "," + exitReason + "," + DoubleToString(realizedR, 4) + ","
      + (tp1Hit ? "YES" : "NO") + "," + (tp2Hit ? "YES" : "NO") + "," + IntegerToString(g_shadowBarsElapsed) + ","
      + IntegerToString(g_shadowL1Result) + "," + (g_shadowL2PassStrict ? "YES" : "NO") + ","
      + (g_shadowL3PassStrict ? "YES" : "NO") + "," + DoubleToString(g_shadowRsiValue, 2) + ","
      + DoubleToString(g_shadowAdxValue, 2) + "," + DoubleToString(g_shadowAtrRatio, 3) + ","
      + IntegerToString(g_shadowVolState) + "," + IntegerToString(g_shadowHourUtc) + ","
      + IntegerToString(g_shadowDayOfWeek) + "\n");
}

// KNOWN FIDELITY GAP, found during build, not fixed: real trades'
// ManageStagedProfits checks exits every TICK. This simulation only checks
// once per NEW BAR (below), same cadence as the rest of Bot1's tracking.
// On a fast intrabar move, a real trade could hit TP1 within the bar it
// opened; this can't see that until the NEXT bar closes. Simulated results
// are therefore systematically SLOWER TO REACT than real trades on the
// same price path -- likely biased toward slightly worse outcomes, not
// better. Worth fixing later via a per-tick hook; not done here given the
// added complexity of reconciling bar-based state with tick-based checks.
// Called once per new bar (same cadence as CheckForTradingSignals). Advances
// the single in-flight hypothetical position by one bar, or starts a new
// one if none is active. Mirrors ManageStagedProfits' TP1/TP2/trailing
// logic but operates on the global g_shadow* state instead of a real
// CPositionInfo object, since there is no real position to query.
void Bot1UpdateShadowSimulation(Bot1Layer1State &l1st, Bot1Layer2State &l2st, Bot1Layer3State &l3st,
                                 Bot1VolState &volst, Bot1RiskContext &rcst) {
   if(!LogBot1Candidates || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // v2 AGILE: same reasoning as Bot1WriteCandidateLog above

   if(!g_shadowActive) {
      if(l1st.l1_result == 0) return;
      double refPrice = (l1st.l1_result == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalculateStopLoss((l1st.l1_result == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, refPrice, false);
      if(sl <= 0 || MathAbs(refPrice - sl) < _Point) return; // no valid/non-degenerate hypothetical SL this bar -- skip, try again next bar
      g_shadowActive = true;
      g_shadowDir = l1st.l1_result;
      g_shadowEntry = refPrice;
      g_shadowSL = sl;
      g_shadowInitialRisk = MathAbs(refPrice - sl);
      g_shadowTrailSL = 0;
      g_shadowTP1Hit = false; g_shadowTP2Hit = false;
      g_shadowOpenTime = TimeCurrent();
      g_shadowBarsElapsed = 0;
      g_shadowL1Result = l1st.l1_result;
      g_shadowL2PassStrict = l2st.l2_pass_strict;
      g_shadowL3PassStrict = l3st.l3_pass_strict;
      g_shadowRsiValue = l2st.rsi_value; g_shadowAdxValue = l2st.adx_value; g_shadowAtrRatio = volst.atr_ratio;
      g_shadowVolState = volst.vol_state; g_shadowHourUtc = rcst.hour_utc; g_shadowDayOfWeek = rcst.day_of_week;
      return; // mirrors real trades: first bar is the open, evaluated from next bar on
   }

   g_shadowBarsElapsed++;
   double price = (g_shadowDir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitDistance = (g_shadowDir == 1) ? (price - g_shadowEntry) / _Point : (g_shadowEntry - price) / _Point;

   if(g_UseStageExits && !g_shadowTP1Hit && profitDistance >= g_TP1_Distance) g_shadowTP1Hit = true;
   if(g_UseStageExits && !g_shadowTP2Hit && profitDistance >= g_TP2_Distance) g_shadowTP2Hit = true;

   // Simplified trailing: once armed, SL trails TrailingDistance behind the
   // best price seen -- same parameters as the real trailing logic, applied
   // to the hypothetical remainder as a single unit (does not model the
   // partial-close volume split; realized_r below approximates it instead).
   if(g_ExitMode != EXIT_FULL_HOLD && UseTrailingOnRemainder && profitDistance >= TrailingActivation) {
      double candidateTrail = (g_shadowDir == 1) ? price - (TrailingDistance * _Point) : price + (TrailingDistance * _Point);
      if(g_shadowTrailSL == 0) g_shadowTrailSL = candidateTrail;
      else if(g_shadowDir == 1 && candidateTrail > g_shadowTrailSL) g_shadowTrailSL = candidateTrail;
      else if(g_shadowDir == -1 && candidateTrail < g_shadowTrailSL) g_shadowTrailSL = candidateTrail;
   }
   double effectiveSL = (g_shadowTrailSL != 0) ? g_shadowTrailSL : g_shadowSL;
   bool slHit = (g_shadowDir == 1) ? (price <= effectiveSL) : (price >= effectiveSL);

   bool finalTargetHit = UseFinalCloseTarget && profitDistance >= TPFinal_Distance;

   int maxBars = Bot1PostmortemBars * 3; // generous cap so a non-trending symbol can't hold a hypothetical forever
   if(slHit || finalTargetHit || g_shadowBarsElapsed >= maxBars) {
      // Blended R-multiple: weight each closed portion by its ClosePercent,
      // same approximation ManageStagedProfits itself uses for the real
      // position (this does not model compounding lot changes across legs).
      double tp1R = g_TP1_Distance * _Point / g_shadowInitialRisk;
      double tp2R = g_TP2_Distance * _Point / g_shadowInitialRisk;
      // profitDistance already carries the correct sign (favorable=positive,
      // adverse=negative) regardless of WHY the position closed -- no need
      // to special-case SL vs trailing vs final-target, "price" at this
      // point IS the exit reference for the remaining portion.
      double finalR = profitDistance * _Point / g_shadowInitialRisk;
      double remainingFrac = 1.0;
      double blendedR = 0;
      if(g_shadowTP1Hit) { blendedR += g_TP1_ClosePercent * tp1R; remainingFrac -= g_TP1_ClosePercent; }
      if(g_shadowTP2Hit) { blendedR += g_TP2_ClosePercent * tp2R; remainingFrac -= g_TP2_ClosePercent; }
      blendedR += remainingFrac * finalR;

      string reason = finalTargetHit ? "FINAL_TARGET" : (slHit ? "SL_HIT" : "MAX_BARS_CUTOFF");
      Bot1WriteShadowTradeLog(reason, blendedR, g_shadowTP1Hit, g_shadowTP2Hit);
      g_shadowActive = false;
   }
}

//+------------------------------------------------------------------+
//| SHADOW #2 -- stricter "any 2-of-3 layers" gate (2026-09-04)       |
//| Mirrors Bot1UpdateShadowSimulation/Bot1WriteShadowTradeLog exactly,|
//| except the hypothetical entry requires layersPassed>=2 instead of |
//| L1-only. Written to a SEPARATE csv so the two strictness levels   |
//| can be diffed directly: same price history, different entry gate |
//| -- answers "would being stricter have actually helped" with real  |
//| forward-tested outcomes, not backtest guesses.                    |
//+------------------------------------------------------------------+
void Bot1WriteShadowTradeLog2(string exitReason, double realizedR, bool tp1Hit, bool tp2Hit) {
   if(!LogBot1Candidates || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   string filename = Bot1FilePrefix + "_shadow_trades_2of3_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_shadowOutcomeLogHandle, filename,
      "event_time,symbol,gate_label,direction,entry_price,exit_reason,realized_r,tp1_hit,tp2_hit,bars_held\n");
   if(handle == INVALID_HANDLE) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + g_shadow2GateLabel + "," + (g_shadow2Dir == 1 ? "BUY" : "SELL") + ","
      + DoubleToString(g_shadow2Entry, digits) + "," + exitReason + "," + DoubleToString(realizedR, 4) + ","
      + (tp1Hit ? "YES" : "NO") + "," + (tp2Hit ? "YES" : "NO") + "," + IntegerToString(g_shadow2BarsElapsed) + "\n");
}

void Bot1UpdateShadowSimulation2(Bot1Layer1State &l1st, Bot1Layer2State &l2st, Bot1Layer3State &l3st) {
   if(!LogBot1Candidates || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // v2 AGILE: same reasoning as Bot1WriteCandidateLog above

   if(!g_shadow2Active) {
      if(l1st.l1_result == 0) return;
      int layersPassed = (l1st.l1_pass_strict ? 1 : 0) + (l2st.l2_pass_strict ? 1 : 0) + (l3st.l3_pass_strict ? 1 : 0);
      if(layersPassed < 2) return;   // the stricter gate this shadow represents
      double refPrice = (l1st.l1_result == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalculateStopLoss((l1st.l1_result == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, refPrice, false);
      if(sl <= 0 || MathAbs(refPrice - sl) < _Point) return;
      g_shadow2Active = true;
      g_shadow2Dir = l1st.l1_result;
      g_shadow2Entry = refPrice;
      g_shadow2SL = sl;
      g_shadow2InitialRisk = MathAbs(refPrice - sl);
      g_shadow2TrailSL = 0;
      g_shadow2TP1Hit = false; g_shadow2TP2Hit = false;
      g_shadow2OpenTime = TimeCurrent();
      g_shadow2BarsElapsed = 0;
      g_shadow2GateLabel = "2OF3";
      return;
   }

   g_shadow2BarsElapsed++;
   double price = (g_shadow2Dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitDistance = (g_shadow2Dir == 1) ? (price - g_shadow2Entry) / _Point : (g_shadow2Entry - price) / _Point;

   if(g_UseStageExits && !g_shadow2TP1Hit && profitDistance >= g_TP1_Distance) g_shadow2TP1Hit = true;
   if(g_UseStageExits && !g_shadow2TP2Hit && profitDistance >= g_TP2_Distance) g_shadow2TP2Hit = true;

   if(g_ExitMode != EXIT_FULL_HOLD && UseTrailingOnRemainder && profitDistance >= TrailingActivation) {
      double candidateTrail = (g_shadow2Dir == 1) ? price - (TrailingDistance * _Point) : price + (TrailingDistance * _Point);
      if(g_shadow2TrailSL == 0) g_shadow2TrailSL = candidateTrail;
      else if(g_shadow2Dir == 1 && candidateTrail > g_shadow2TrailSL) g_shadow2TrailSL = candidateTrail;
      else if(g_shadow2Dir == -1 && candidateTrail < g_shadow2TrailSL) g_shadow2TrailSL = candidateTrail;
   }
   double effectiveSL = (g_shadow2TrailSL != 0) ? g_shadow2TrailSL : g_shadow2SL;
   bool slHit = (g_shadow2Dir == 1) ? (price <= effectiveSL) : (price >= effectiveSL);
   bool finalTargetHit = UseFinalCloseTarget && profitDistance >= TPFinal_Distance;

   int maxBars = Bot1PostmortemBars * 3;
   if(slHit || finalTargetHit || g_shadow2BarsElapsed >= maxBars) {
      double tp1R = g_TP1_Distance * _Point / g_shadow2InitialRisk;
      double tp2R = g_TP2_Distance * _Point / g_shadow2InitialRisk;
      double finalR = profitDistance * _Point / g_shadow2InitialRisk;
      double remainingFrac = 1.0;
      double blendedR = 0;
      if(g_shadow2TP1Hit) { blendedR += g_TP1_ClosePercent * tp1R; remainingFrac -= g_TP1_ClosePercent; }
      if(g_shadow2TP2Hit) { blendedR += g_TP2_ClosePercent * tp2R; remainingFrac -= g_TP2_ClosePercent; }
      blendedR += remainingFrac * finalR;

      string reason = finalTargetHit ? "FINAL_TARGET" : (slHit ? "SL_HIT" : "MAX_BARS_CUTOFF");
      Bot1WriteShadowTradeLog2(reason, blendedR, g_shadow2TP1Hit, g_shadow2TP2Hit);
      g_shadow2Active = false;
   }
}

//+------------------------------------------------------------------+
//| BOT1 SHADOW POOL -- write/open/update/close (2026-09-25)          |
//| See struct/global block above for rationale. Independent of       |
//| g_shadowActive/g_shadow2Active; can run standalone.                |
//+------------------------------------------------------------------+
void Bot1WriteShadowPoolLog(int slot, string exitReason) {
   if(!UseShadowPool || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // same disk-I/O-during-sweeps guard as every other logger in this file
   string prefix = (StringLen(ShadowPoolFilePrefix) > 0) ? ShadowPoolFilePrefix : Bot1FilePrefix;
   string filename = prefix + "_shadow_pool_" + _Symbol + ".csv";
   int handle = Bot1GetLogHandle(g_shadowPoolLogHandle, filename,
      "event_time,symbol,direction,entry_price,exit_reason,bars_held,"
      "tp1_hit,tp2_hit,mfe_pts,mae_pts,bars_to_mfe,bars_to_mae,"
      "bucket_at_entry,bucket_trend_votes,adx_at_entry,rsi_at_entry,"
      "hour_utc,day_of_week\n");
   if(handle == INVALID_HANDLE) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + (g_poolDir[slot] == 1 ? "BUY" : "SELL") + ","
      + DoubleToString(g_poolEntry[slot], digits) + "," + exitReason + "," + IntegerToString(g_poolBarsElapsed[slot]) + ","
      + (g_poolTP1Hit[slot] ? "YES" : "NO") + "," + (g_poolTP2Hit[slot] ? "YES" : "NO") + ","
      + DoubleToString(g_poolMfePeak[slot], 2) + "," + DoubleToString(g_poolMaeTrough[slot], 2) + ","
      + IntegerToString(g_poolBarsToMfe[slot]) + "," + IntegerToString(g_poolBarsToMae[slot]) + ","
      + g_poolBucketAtEntry[slot] + "," + IntegerToString(g_poolBucketTrendVotes[slot]) + ","
      + DoubleToString(g_poolAdxAtEntry[slot], 2) + "," + DoubleToString(g_poolRsiAtEntry[slot], 2) + ","
      + IntegerToString(g_poolHourUtcAtEntry[slot]) + "," + IntegerToString(g_poolDayOfWeekAtEntry[slot]) + "\n");
}

// Opens a new pool slot on a bar-close signal, if one is free. Called from
// CheckForTradingSignals -- same cadence/inputs as the existing single-slot
// shadow sim, but does NOT check whether one is already active (that's the
// whole point: ShadowPoolEntryOnEveryBar lets several hypothetical trades
// run concurrently, unlike g_shadowActive's single slot).
void Bot1ShadowPoolTryOpen(Bot1Layer1State &l1st, Bot1Layer2State &l2st, Bot1RiskContext &rcst) {
   if(!UseShadowPool || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if(!ShadowPoolEntryOnEveryBar) return;
   if(l1st.l1_result == 0) return;

   int maxSlots = MathMin(ShadowPoolMaxConcurrent, BOT1_SHADOW_POOL_SLOTS);
   int freeSlot = -1;
   for(int i = 0; i < maxSlots; i++) {
      if(!g_poolUsed[i]) { freeSlot = i; break; }
   }
   if(freeSlot < 0) return; // pool full this bar -- simply skip, try again next bar (does not block real trading, this is analysis-only)

   double refPrice = (l1st.l1_result == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = CalculateStopLoss((l1st.l1_result == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, refPrice, false);
   if(sl <= 0 || MathAbs(refPrice - sl) < _Point) return;

   int i = freeSlot;
   g_poolUsed[i] = true;
   g_poolDir[i] = l1st.l1_result;
   g_poolEntry[i] = refPrice;
   g_poolSL[i] = sl;
   g_poolInitialRisk[i] = MathAbs(refPrice - sl);
   g_poolTrailSL[i] = 0;
   g_poolTP1Hit[i] = false; g_poolTP2Hit[i] = false;
   g_poolOpenTime[i] = TimeCurrent();
   g_poolBarsElapsed[i] = 0;
   g_poolMfePeak[i] = 0; g_poolMaeTrough[i] = 0;
   g_poolBarsToMfe[i] = 0; g_poolBarsToMae[i] = 0;
   // Entry-context snapshot -- mirrors the fields already proven useful in
   // bot1r21_trades_GOLD.csv's extended columns (regime bucket etc).
   g_poolBucketAtEntry[i] = (UseRegime21Classifier ? Bot1Regime21BucketToString(g_r21b.bucket) : "");
   g_poolBucketTrendVotes[i] = g_r21b.trendVotes;
   g_poolAdxAtEntry[i] = l2st.adx_value;
   g_poolRsiAtEntry[i] = l2st.rsi_value;
   g_poolHourUtcAtEntry[i] = rcst.hour_utc;
   g_poolDayOfWeekAtEntry[i] = rcst.day_of_week;
}

// Advances every active pool slot by one step. Called either once per BAR
// (isNewBar branch, same cadence as g_mfe* tracker) or on EVERY TICK when
// ShadowPoolTrackTickMFE=true, from OnTick -- closes the documented
// "bar-cadence misses intrabar TP/SL touches" fidelity gap the ORIGINAL
// single-slot shadow sim explicitly left unfixed.
void Bot1ShadowPoolUpdate(bool isNewBar) {
   if(!UseShadowPool || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   int maxSlots = MathMin(ShadowPoolMaxConcurrent, BOT1_SHADOW_POOL_SLOTS);

   for(int i = 0; i < maxSlots; i++) {
      if(!g_poolUsed[i]) continue;
      // Tick-level MFE/MAE tracking only runs if ShadowPoolTrackTickMFE;
      // otherwise this whole update (including bar counting/exit checks)
      // only advances on new bars, matching the original shadow sim exactly.
      if(!ShadowPoolTrackTickMFE && !isNewBar) continue;
      if(isNewBar) g_poolBarsElapsed[i]++;

      double price = (g_poolDir[i] == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitDistance = (g_poolDir[i] == 1) ? (price - g_poolEntry[i]) : (g_poolEntry[i] - price);
      double profitPts = profitDistance / _Point;

      if(profitDistance > g_poolMfePeak[i]) { g_poolMfePeak[i] = profitDistance; g_poolBarsToMfe[i] = g_poolBarsElapsed[i]; }
      if(-profitDistance > g_poolMaeTrough[i]) { g_poolMaeTrough[i] = -profitDistance; g_poolBarsToMae[i] = g_poolBarsElapsed[i]; }

      if(g_UseStageExits && !g_poolTP1Hit[i] && profitPts >= g_TP1_Distance) g_poolTP1Hit[i] = true;
      if(g_UseStageExits && !g_poolTP2Hit[i] && profitPts >= g_TP2_Distance) g_poolTP2Hit[i] = true;

      if(g_ExitMode != EXIT_FULL_HOLD && UseTrailingOnRemainder && profitPts >= TrailingActivation) {
         double candidateTrail = (g_poolDir[i] == 1) ? price - (TrailingDistance * _Point) : price + (TrailingDistance * _Point);
         if(g_poolTrailSL[i] == 0) g_poolTrailSL[i] = candidateTrail;
         else if(g_poolDir[i] == 1 && candidateTrail > g_poolTrailSL[i]) g_poolTrailSL[i] = candidateTrail;
         else if(g_poolDir[i] == -1 && candidateTrail < g_poolTrailSL[i]) g_poolTrailSL[i] = candidateTrail;
      }
      double effectiveSL = (g_poolTrailSL[i] != 0) ? g_poolTrailSL[i] : g_poolSL[i];
      bool slHit = (g_poolDir[i] == 1) ? (price <= effectiveSL) : (price >= effectiveSL);
      bool finalTargetHit = UseFinalCloseTarget && profitPts >= TPFinal_Distance;

      int maxBars = Bot1PostmortemBars * 3;
      if(slHit || finalTargetHit || g_poolBarsElapsed[i] >= maxBars) {
         string reason = finalTargetHit ? "FINAL_TARGET" : (slHit ? "SL_HIT" : "MAX_BARS_CUTOFF");
         Bot1WriteShadowPoolLog(i, reason);
         g_poolUsed[i] = false; // free the slot for a new hypothetical trade
      }
   }
}

int Bot1CountConcurrentPositions(ulong excludeTicket) {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || ticket == excludeTicket) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= Bot1MagicRangeStart && magic <= Bot1MagicRangeEnd) count++;
   }
   return count;
}

// bot1_trades_{SYM}.csv -- lifecycle of real trades only (open/TP1/TP2/trail/close)
// EXTENDED DIAGNOSTICS LOGGER (2026-09-20): user's own request -- "go through
// the entire EA and log more than 100 items" to feed a real ML classifier
// aimed at trimming the worst 10-20% tail of entries, not another manual
// slice-by-slice sweep. Writes to a SEPARATE csv (joined back to the main
// trade log by ticket+event_time in Python) rather than extending the
// already-30-parameter Bot1WriteTradeLog signature further -- keeps this
// additive and low-risk to the proven logging pipeline. Deliberately
// EXCLUDES day_of_week/hour_utc per the user's earlier "drop calendar
// stuff" instruction. Pulls straight from the structs already computed
// this bar for L1/L2/L3/vol/regime2-cache -- zero new indicator calls.
int g_extDiagLogHandle = INVALID_HANDLE;
void Bot1WriteExtendedDiagnostics(ulong ticket, string eventType,
      const Bot1Layer1State &l1, const Bot1Layer2State &l2, const Bot1Layer3State &l3,
      const Bot1VolState &vol) {
   if(!LogBot1Trades || MQLInfoInteger(MQL_OPTIMIZATION)) return;   // reuse the same master switch as the main trade log -- no separate input needed  // 2026-09-23: skip disk I/O during optimization/sweeps
   string filename = Bot1FilePrefix + "_extdiag_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_extDiagLogHandle, filename,
      "event_time,ticket,event_type,"
      "l1_ichi,l1_ema,l1_psar,l1_st,l1_vote_n,"
      "l2_macd,l2_rsi_signal,l2_plus_di,l2_minus_di,l2_adx_slope,l2_cci_signal,l2_cci_value,"
      "l2_rsi_voter_active,l2_cci_voter_active,l2_confirmations,"
      "l3_boll,l3_obv,l3_donchian,l3_retest,l3_vwap_reclaim,l3_result,l3_retest_pending_dir,l3_retest_bars_left,"
      "vol_atr_ratio,vol_state,vol_filter_pass,"
      "r2_adx_slope,r2_session_vwap,r2_vwap_stdev,r2_vwap_upper,r2_vwap_lower,"
      "r2_bb_width_pctile,r2_bb_width,r2_cci_value,r2_cci_signal,r2_stoch_k,r2_atr_stop,"
      "r2_exhaustion_frac,r2_exhaustion_skip,"
      "r21_er_value,r21_chop_value,"
      "regime_atr_ratio_raw,regime_mmi_raw\n");
   if(handle == INVALID_HANDLE) return;
   FileSeek(handle, 0, SEEK_END);
   string line = Bot1Timestamp() + ","
      + IntegerToString((long)ticket) + "," + eventType + ","
      + IntegerToString(l1.ichi_signal) + "," + IntegerToString(l1.ema_signal) + ","
      + IntegerToString(l1.psar_signal) + "," + IntegerToString(l1.st_signal) + ","
      + IntegerToString(l1.l1_vote_n) + ","
      + IntegerToString(l2.macd_signal) + "," + IntegerToString(l2.rsi_signal) + ","
      + DoubleToString(l2.plus_di, 4) + "," + DoubleToString(l2.minus_di, 4) + ","
      + DoubleToString(l2.adx_slope, 4) + "," + IntegerToString(l2.cci_signal) + ","
      + DoubleToString(l2.cci_value, 4) + ","
      + (l2.rsi_voter_active ? "1" : "0") + "," + (l2.cci_voter_active ? "1" : "0") + ","
      + IntegerToString(l2.l2_confirmations) + ","
      + IntegerToString(l3.boll_signal) + "," + IntegerToString(l3.obv_signal) + ","
      + IntegerToString(l3.donchian_signal) + "," + IntegerToString(l3.retest_signal) + ","
      + IntegerToString(l3.vwap_reclaim_signal) + "," + IntegerToString(l3.l3_result) + ","
      + IntegerToString(l3.retest_pending_dir) + "," + IntegerToString(l3.retest_bars_left) + ","
      + DoubleToString(vol.atr_ratio, 4) + "," + IntegerToString(vol.vol_state) + ","
      + (vol.vol_filter_pass_strict ? "1" : "0") + ","
      + DoubleToString(g_r2.adxSlope, 4) + "," + DoubleToString(g_r2.sessionVwap, _Digits) + ","
      + DoubleToString(g_r2.vwapStdev, _Digits) + "," + DoubleToString(g_r2.vwapUpper, _Digits) + ","
      + DoubleToString(g_r2.vwapLower, _Digits) + ","
      + DoubleToString(g_r2.bbWidthPctile, 4) + "," + DoubleToString(g_r2.bbWidth, _Digits) + ","
      + DoubleToString(g_r2.cciValue, 4) + "," + IntegerToString(g_r2.cciSignal) + ","
      + DoubleToString(g_r2.stochK, 4) + "," + DoubleToString(g_r2.atrStop, _Digits) + ","
      + DoubleToString(g_r2.exhaustionFrac, 4) + "," + (g_r2.exhaustionSkip ? "1" : "0") + ","
      + DoubleToString(g_r21.erValue, 4) + "," + DoubleToString(g_r21.chopValue, 4) + ","
      + DoubleToString(GetRegimeATRRatio(), 4) + "," + DoubleToString(GetRegimeMMI(), 4) + "\n";
   FileWriteString(handle, line);
   FileFlush(handle);
}

void Bot1WriteTradeLog(ulong ticket, string eventType, double price, double volume,
                        double pnlUsd, double pnlPct, string reason,
                        double slPrice = 0, double tpPrice = 0, double initialRiskDist = 0,
                        double commission = 0, double swap = 0,
                        double mfePrice = 0, double maePrice = 0,
                        int barsToMfe = 0, int barsToMae = 0,
                        double requestedPrice = 0, long logMagic = -1,
                        string bucketLabel = "", int voterTrendVotes = -1, int voterActiveCount = -1,
                        string counterTrendFlag = "",
                        double adxValueAtEntry = -1, double rsiValueAtEntry = -1,
                        double spreadPtsAtEntry = -1, double adrValueAtEntry = -1,
                        double vwapDistAtEntry = -999999, int consecLossesAtEntry = -1,
                        double momentum3BarAtEntry = -999999, double momentum10BarAtEntry = -999999,
                        int htfEma200BiasAtEntry = -99, int htfSuperTrendDirAtEntry = -99,
                        double dayRangePosAtEntry = -1, double vsHourOpenPtsAtEntry = -999999,
                        int regimeDirectionAtEntry = -99, string directionAgreesAtEntry = "",
                        int barsSinceBucketFlipAtEntry = -1, int barsSinceDirectionFlipAtEntry = -1,
                        double slopeShortAtEntry = -999999, double slopeMidAtEntry = -999999, double slopeLongAtEntry = -999999,
                        double earlyPx1Bar = -999999, double earlyPx3Bar = -999999, double earlyPx5Bar = -999999) {
   if(!LogBot1Trades || MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps
   string filename = Bot1FilePrefix + "_trades_" + _Symbol + "_" + IntegerToString(MagicNumber) + ".csv";
   int handle = Bot1GetLogHandle(g_tradeLogHandle, filename,
      "event_time,symbol,magic,ticket,event_type,price,volume,pnl_usd,pnl_pct,commission,swap,"
      "sl_price,tp_price,initial_risk_distance,concurrent_positions,"
      "equity_snapshot,balance_snapshot,risk_percent_input,lot_type_input,"
      "mfe_price,mae_price,bars_to_mfe,bars_to_mae,requested_price,reason,"
      "bucket_at_entry,bucket_trend_votes,bucket_active_voters,counter_trend_flag,"
      "adx_at_entry,rsi_at_entry,spread_pts_at_entry,adr_at_entry,vwap_dist_at_entry,consec_losses_at_entry,"
      "momentum_3bar_pts,momentum_10bar_pts,htf_ema200_bias,htf_supertrend_dir,"
      "day_range_position,vs_hour_open_pts,regime_direction,direction_agrees,"
      "bars_since_bucket_flip,bars_since_direction_flip,"
      "slope_short_10bar,slope_mid_50bar,slope_long_200bar,"
      "early_px_1bar,early_px_3bar,early_px_5bar\n");
   if(handle == INVALID_HANDLE) {
      Print("[BOT1-ERROR] Trade log write skipped for ", _Symbol, " ticket=", ticket, " event=", eventType);
      return;
   }
   // v2 AGILE: logMagic defaults to -1 meaning "use the trend side's own
   // MagicNumber input" (byte-identical to pre-v2 behavior for every
   // existing call site). The counter-trend module passes its own magic
   // explicitly -- without this, every counter-trend trade row would be
   // silently mislabeled under the trend side's MagicNumber, corrupting
   // any per-magic analysis (including this doc's own weekly report script).
   long effectiveMagic = (logMagic >= 0) ? logMagic : (long)MagicNumber;
   int concurrent = Bot1CountConcurrentPositions(ticket);
   double equitySnap = AccountInfoDouble(ACCOUNT_EQUITY);
   double balanceSnap = AccountInfoDouble(ACCOUNT_BALANCE);
   // REGIME 2.1 v3 (2026-09-17): bucket_at_entry/counter_trend_flag are ONLY
   // populated on OPEN_* events (only those call sites pass non-default
   // args below) -- blank on every other event_type (TP1_PARTIAL/CLOSE/etc.)
   // by design, since the bucket at entry is what we want to analyze
   // against the eventual outcome, not a re-sampled value at close time.
   // 2026-09-19: same discipline for the 5 new diagnostic columns below --
   // real values only on OPEN_* rows (sentinel defaults elsewhere), added
   // after a "deep dive into losing trades" pass found we had NO raw
   // ADX/RSI/spread/ADR/VWAP-distance context per trade, only pass/fail
   // booleans -- couldn't tell a marginal ADX=21 trending-vote from a
   // strong ADX=45 one, or whether a losing streak coincided with spread
   // widening. consec_losses_at_entry lets us see streak-state at the
   // moment of entry (not just reconstruct it after the fact from PnL).
   FileWriteString(handle, Bot1Timestamp() + "," + _Symbol + "," + IntegerToString(effectiveMagic) + ","
      + IntegerToString((long)ticket) + "," + eventType + "," + DoubleToString(price, _Digits) + ","
      + DoubleToString(volume, 2) + "," + DoubleToString(pnlUsd, 2) + "," + DoubleToString(pnlPct, 3) + ","
      + DoubleToString(commission, 2) + "," + DoubleToString(swap, 2) + ","
      + DoubleToString(slPrice, _Digits) + "," + DoubleToString(tpPrice, _Digits) + "," + DoubleToString(initialRiskDist, _Digits) + ","
      + IntegerToString(concurrent) + ","
      + DoubleToString(equitySnap, 2) + "," + DoubleToString(balanceSnap, 2) + ","
      + DoubleToString(RiskPercent, 2) + "," + IntegerToString((int)LotType) + ","
      + DoubleToString(mfePrice, _Digits) + "," + DoubleToString(maePrice, _Digits) + ","
      + IntegerToString(barsToMfe) + "," + IntegerToString(barsToMae) + ","
      + DoubleToString(requestedPrice, _Digits) + ","
      + Bot1SanitizeCSV(reason) + ","
      + bucketLabel + "," + IntegerToString(voterTrendVotes) + "," + IntegerToString(voterActiveCount) + ","
      + counterTrendFlag + ","
      + DoubleToString(adxValueAtEntry, 2) + "," + DoubleToString(rsiValueAtEntry, 2) + ","
      + DoubleToString(spreadPtsAtEntry, 1) + "," + DoubleToString(adrValueAtEntry, _Digits) + ","
      + (vwapDistAtEntry <= -999999 ? "" : DoubleToString(vwapDistAtEntry, _Digits)) + ","
      + IntegerToString(consecLossesAtEntry) + ","
      + (momentum3BarAtEntry <= -999999 ? "" : DoubleToString(momentum3BarAtEntry, 1)) + ","
      + (momentum10BarAtEntry <= -999999 ? "" : DoubleToString(momentum10BarAtEntry, 1)) + ","
      + (htfEma200BiasAtEntry == -99 ? "" : IntegerToString(htfEma200BiasAtEntry)) + ","
      + (htfSuperTrendDirAtEntry == -99 ? "" : IntegerToString(htfSuperTrendDirAtEntry)) + ","
      + (dayRangePosAtEntry < 0 ? "" : DoubleToString(dayRangePosAtEntry, 3)) + ","
      + (vsHourOpenPtsAtEntry <= -999999 ? "" : DoubleToString(vsHourOpenPtsAtEntry, 1)) + ","
      + (regimeDirectionAtEntry == -99 ? "" : IntegerToString(regimeDirectionAtEntry)) + ","
      + directionAgreesAtEntry + ","
      + (barsSinceBucketFlipAtEntry < 0 ? "" : IntegerToString(barsSinceBucketFlipAtEntry)) + ","
      + (barsSinceDirectionFlipAtEntry < 0 ? "" : IntegerToString(barsSinceDirectionFlipAtEntry)) + ","
      + (slopeShortAtEntry <= -999999 ? "" : DoubleToString(slopeShortAtEntry, 4)) + ","
      + (slopeMidAtEntry <= -999999 ? "" : DoubleToString(slopeMidAtEntry, 4)) + ","
      + (slopeLongAtEntry <= -999999 ? "" : DoubleToString(slopeLongAtEntry, 4)) + ","
      + (earlyPx1Bar <= -999999 ? "" : DoubleToString(earlyPx1Bar, 1)) + ","
      + (earlyPx3Bar <= -999999 ? "" : DoubleToString(earlyPx3Bar, 1)) + ","
      + (earlyPx5Bar <= -999999 ? "" : DoubleToString(earlyPx5Bar, 1)) + "\n");
}

// REGIME 2.1 v3: classify whether a just-opened trade's DIRECTION agrees
// with, disagrees with, or is neutral relative to the current bucket's
// majority-vote lean. Uses the SAME g_r21b state the classifier already
// computed this bar (no extra indicator calls) -- direction is inferred
// from trend_votes vs chop_votes among active voters, compared against the
// bucket label: a BUY or SELL opened while bucket=CHOP is flagged
// "COUNTER_TO_CHOP" (the entry logic fired a trend-style signal inside a
// bar the classifier called non-trending) -- exactly the "did we trade
// against our own regime read" question. Returns "" (blank) when the
// classifier is off, so existing behavior/CSV width is unaffected unless
// UseRegime21Classifier=true.
string Bot1Regime21CounterFlag(int direction) {
   if(!UseRegime21Classifier) return "";
   if(g_r21b.bucket == R21_BUCKET_CHOP) return "COUNTER_TO_CHOP";
   if(g_r21b.bucket == R21_BUCKET_MIXED) return "ENTERED_ON_MIXED";
   return "ALIGNED_TREND";
}

// REGIME 2.1 v3 PROTOTYPE: returns Regime21ChopSizeMultiplier when the
// current bar's bucket is CHOP, else 1.0 (no-op). See that input's comment
// for the backtest evidence behind this. Called at entry time so it reads
// the SAME g_r21b state Bot1Regime21CounterFlag()/the trade log already use
// -- no extra indicator calls, no risk of it disagreeing with what gets
// logged for this same trade.
// Returns the 3-letter sign-pattern of the multi-timeframe slope at THIS
// bar, e.g. "down/down/up" -- used both for size-multiplier matching below
// and available for any future diagnostic. "flat" (slope==0 exactly) is
// rare on real tick data but handled distinctly so it never silently
// collapses into "up" or "down".
string Bot1SlopeSignPattern() {
   double s = Bot1SlopePtsPerBar(10);
   double m = Bot1SlopePtsPerBar(50);
   double l = Bot1SlopePtsPerBar(200);
   string sSign = (s > 0 ? "up" : (s < 0 ? "down" : "flat"));
   string mSign = (m > 0 ? "up" : (m < 0 ? "down" : "flat"));
   string lSign = (l > 0 ? "up" : (l < 0 ? "down" : "flat"));
   return sSign + "/" + mSign + "/" + lSign;
}

// SLOPE-PATTERN SIZE MULTIPLIER (2026-09-20): 3 patterns confirmed via
// Benjamini-Hochberg-corrected permutation testing on a 2,225-trade
// data-gathering run (see the 2 input comments above for the full
// evidence). Only SELL-side patterns cleared correction -- no BUY-side
// pattern survived, so this deliberately does nothing for BUY trades.
double Bot1Regime21SlopePatternMultiplier(int tradeDirection) {
   if(!UseRegime21Classifier) return 1.0;
   if(tradeDirection >= 0) return 1.0;   // SELL-only signal (tradeDirection < 0); no-op for BUY/flat
   string pattern = Bot1SlopeSignPattern();
   bool isChop = (g_r21b.bucket == R21_BUCKET_CHOP);
   bool isTrend = (g_r21b.bucket == R21_BUCKET_TREND);
   if(isChop && (pattern == "down/down/down" || pattern == "down/up/up")) return Regime21SlopeGoodSizeMultiplier;
   if(isTrend && pattern == "down/down/up") return Regime21SlopeBadSizeMultiplier;
   return 1.0;
}

double Bot1Regime21SizeMultiplier(int tradeDirection = 0) {
   if(!UseRegime21Classifier) return 1.0;
   double mult = 1.0;
   if(g_r21b.bucket == R21_BUCKET_CHOP) mult *= Regime21ChopSizeMultiplier;
   if(tradeDirection != 0 && !Bot1Regime21DirectionAgrees(tradeDirection)) mult *= Regime21DisagreeSizeMultiplier;
   mult *= Bot1Regime21SlopePatternMultiplier(tradeDirection);
   return mult;
}

//+------------------------------------------------------------------+
//| COUNTER-TREND MODULE (v2 AGILE, 2026-09-06)                      |
//| See input group comment for full rationale. Independent entry    |
//| mechanism for ranging conditions, own MagicNumber, own fixed      |
//| symmetric bracket -- reuses the trend side's cooldown/min-SL      |
//| guards (both keyed by MagicNumber, so this module's own history   |
//| is tracked separately) but nothing else from the trend pipeline.  |
//+------------------------------------------------------------------+
int Bot1CounterTrendMagic() {
   return MagicNumber + CounterTrendMagicOffset;
}

long Bot1EffectiveStopsLevelPts() {
   long stopsLevelPts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   return (stopsLevelPts > 0) ? stopsLevelPts : (long)Bot1FallbackMinStopPoints;
}

long Bot1SpreadPts() {
   long spreadPts = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPts > 0) ? spreadPts : 0;
}

// BUY SL is placed from Ask; the broker measures it against Bid. A 40pt
// bracket on GOLD (spread ~55) therefore lands on the wrong side of Bid
// and returns TRADE_RETCODE_INVALID_STOPS (10016). Confirmed BOSSA smoke
// 2026-09-07: 145 CT rejects, 0 fills. Widen SL by spread+StopsLevel+5
// and TP by StopsLevel+5; keep the requested RangeMode* when they already
// clear the floor. Normalize to kill 40*_Point float junk in the log.
void Bot1CounterTrendBracketPrices(const bool isBuy, const double entry, double &sl, double &tp) {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long slNeed = Bot1SpreadPts() + Bot1EffectiveStopsLevelPts() + 5;
   long tpNeed = Bot1EffectiveStopsLevelPts() + 5;
   int slPts = RangeModeSL_Points;
   int tpPts = RangeModeTP_Points;
   if(slPts < (int)slNeed) slPts = (int)slNeed;
   if(tpPts < (int)tpNeed) tpPts = (int)tpNeed;
   if(isBuy) {
      sl = NormalizeDouble(entry - slPts * _Point, digits);
      tp = NormalizeDouble(entry + tpPts * _Point, digits);
   } else {
      sl = NormalizeDouble(entry + slPts * _Point, digits);
      tp = NormalizeDouble(entry - tpPts * _Point, digits);
   }
   if(slPts != RangeModeSL_Points || tpPts != RangeModeTP_Points) {
      Print("[BOT1-R2-CT] ", _Symbol, " bracket widened SL ", RangeModeSL_Points, "->", slPts,
            " TP ", RangeModeTP_Points, "->", tpPts,
            " (spread=", Bot1SpreadPts(), " stops_eff=", Bot1EffectiveStopsLevelPts(), ")");
   }
}

// Mean-reversion candidate signal: RSI extreme + price at/beyond the
// matching Bollinger band, checked directly off the shared rsiHandle/
// bollHandle (force-allocated in OnInit whenever g_UseCounterTrendModule is
// on, regardless of the trend side's own UseRSI/g_UseBollinger toggles).
// Returns 1 (BUY candidate), -1 (SELL candidate), or 0.
int Bot1CounterTrendSignal() {
   g_ctTriggerReason = "";
   Bot1RefreshRegime2Cache();

   double rVal = 0.0;
   if(rsiHandle != INVALID_HANDLE) {
      double r[];
      ArraySetAsSeries(r, true);
      if(CopyBuffer(rsiHandle, 0, 0, 1, r) >= 1) rVal = r[0];
   }

   bool bandBuy = false, bandSell = false;
   if(bollHandle != INVALID_HANDLE) {
      double lower[], upper[], closeArr[];
      ArraySetAsSeries(lower, true);
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(closeArr, true);
      int need = g_RequireCloseBackInsideBand ? 2 : 1;
      if(CopyBuffer(bollHandle, 2, 0, need, lower) >= need &&
         CopyBuffer(bollHandle, 1, 0, need, upper) >= need &&
         CopyClose(_Symbol, _Period, 0, need, closeArr) >= need) {
         if(g_RequireCloseBackInsideBand && need == 2) {
            bandBuy  = (closeArr[1] <= lower[1] && closeArr[0] > lower[0]);
            bandSell = (closeArr[1] >= upper[1] && closeArr[0] < upper[0]);
         } else {
            bandBuy  = (closeArr[0] <= lower[0]);
            bandSell = (closeArr[0] >= upper[0]);
         }
      }
   }

   bool rsiBuy  = (rsiHandle != INVALID_HANDLE && rVal <= CounterTrendRSIOversold);
   bool rsiSell = (rsiHandle != INVALID_HANDLE && rVal >= CounterTrendRSIOverbought);
   bool stochBuy  = (g_UseStochasticTrigger && stochHandle != INVALID_HANDLE && g_r2.stochK <= StochOversold);
   bool stochSell = (g_UseStochasticTrigger && stochHandle != INVALID_HANDLE && g_r2.stochK >= StochOverbought);

   string buyWhy = "", sellWhy = "";
   if(bandBuy && rsiBuy)   buyWhy  += "RSI_BB ";
   if(bandBuy && stochBuy) buyWhy  += "STOCH_BB ";
   if(bandSell && rsiSell) sellWhy += "RSI_BB ";
   if(bandSell && stochSell) sellWhy += "STOCH_BB ";

   if(g_UseVWAPDeviationTrigger && g_r2.sessionVwap > 0.0 && g_r2.vwapStdev > 0.0) {
      double c = iClose(_Symbol, _Period, 0);
      if(c <= g_r2.vwapLower) buyWhy  += "VWAP_DEV ";
      if(c >= g_r2.vwapUpper) sellWhy += "VWAP_DEV ";
   }

   if(Bot1R2DiagOn()) {
      Print("[BOT1-R2-CT] ", _Symbol,
            " ranging=Y rsi=", DoubleToString(rVal, 1),
            " stochK=", DoubleToString(g_r2.stochK, 1),
            " vwap=", DoubleToString(g_r2.sessionVwap, _Digits),
            " vwapL=", DoubleToString(g_r2.vwapLower, _Digits),
            " vwapU=", DoubleToString(g_r2.vwapUpper, _Digits),
            " bandBuy=", (bandBuy?"Y":"N"), " bandSell=", (bandSell?"Y":"N"),
            " close_inside=", (g_RequireCloseBackInsideBand?"Y":"N"),
            " buyWhy=", buyWhy, " sellWhy=", sellWhy);
   }

   if(StringLen(buyWhy) > 0 && StringLen(sellWhy) > 0) return 0; // both sides = no trade
   if(StringLen(buyWhy) > 0) { g_ctTriggerReason = buyWhy; return 1; }
   if(StringLen(sellWhy) > 0) { g_ctTriggerReason = sellWhy; return -1; }
   return 0;
}

// Mirrors CheckForTradingSignals' BUY/SELL open blocks structurally (same
// cooldown/min-SL-outlier guards, same trade-log call, same PositionOpen
// pattern) but with its own MagicNumber, own fixed lot, and the simple
// fixed symmetric bracket instead of ADR/Kumo/staged exits -- deliberately
// NOT routed through CalculateStopLoss/CalculateTakeProfit/
// CalculateLotSize, which are all tuned for the trend side's exit shape.
void Bot1CheckCounterTrendSignal() {
   if(!g_UseCounterTrendModule) return;
   // No meaning without a regime verdict to react to -- see input comment.
   if(!g_UseRegimeSuiteGate) return;
   if(!Bot1RegimeSuiteSaysRanging()) return;

   int ctMagic = Bot1CounterTrendMagic();

   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol &&
         position.Magic() == ctMagic) {
         posCount++;
      }
   }
   if(posCount >= CounterTrendMaxPositions) return;

   int signal = Bot1CounterTrendSignal();
   if(signal == 0) return;

   // Same cooldown-after-SL protection as the trend side, but keyed by this
   // module's OWN MagicNumber-derived cooldown state -- see
   // Bot1CooldownBlocks/Bot1RegisterCooldown; both already take direction
   // as their only real input, and OnTradeTransaction below is updated to
   // register cooldowns for BOTH magic numbers, so this check is meaningful.
   if(Bot1CooldownBlocks(signal)) return;

   if(signal == 1) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = 0.0, tp = 0.0;
      Bot1CounterTrendBracketPrices(true, ask, sl, tp);

      // v2 AGILE BUG FIX (found during smoke test, 2026-09-06): originally
      // ran Bot1SLDistanceIsOutlier() here, but that filter's rolling
      // history array is SHARED across the whole EA process, not keyed per
      // MagicNumber -- the trend side's much wider ADR-based stops (often
      // 1000+ points on gold) dominate the average, so this module's
      // deliberately tight 40pt fixed bracket looked like a permanent
      // "outlier" and got rejected on 100% of candidates in the first smoke
      // test (0 counter-trend trades despite 106 RSI-extreme-during-
      // ranging candidate bars). The filter's whole premise -- "is this SL
      // suspiciously tighter than what I normally use" -- doesn't apply to
      // a module whose bracket is INTENTIONALLY fixed and small; skip it
      // here rather than trying to retrofit per-magic history tracking for
      // a still-unproven module.

      // 2026-09-29: magic-number-FIRST format -- MT5's 31-char position-comment cap was
      // silently truncating the old "CTBUY|<ConfigLabel>|MN:<magic>|MeanRev" format for any
      // longer ConfigLabel, clipping the magic number itself (confirmed real on this session's
      // live fleet, e.g. R21B's 54510 clipped to display as "5451"). Magic-first guarantees the
      // number that downstream tooling (Guard EA, trackers) depends on is never truncated,
      // regardless of future ConfigLabel length.
      string comment = StringFormat("%d|CTB|MeanRev", ctMagic);
      if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, CounterTrendLotSize, ask, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         // v2 AGILE: deliberately NOT calling Bot1RecordSLDistance here --
         // same reasoning as skipping Bot1SLDistanceIsOutlier above, in
         // reverse: feeding this module's tiny fixed-bracket distances into
         // the SHARED rolling average would drag it down and start
         // rejecting the TREND side's normal wide ADR-based stops instead.
         Bot1TrackPositionMagic(trade.ResultOrder(), ctMagic);   // v2 AGILE: see Bot1TrackPositionMagic comment -- this is what actually fixes the mislogged-close bug for this module
         Print("[BOT1-COUNTERTREND] ", _Symbol, " MN:", ctMagic, " BUY OPENED (mean-reversion): ", ask, " SL: ", sl, " TP: ", tp, " trigger=", g_ctTriggerReason);
         double entryComm = 0, entrySwap = 0;
         ulong entryDeal = trade.ResultDeal();
         if(entryDeal != 0 && HistoryDealSelect(entryDeal)) {
            entryComm = HistoryDealGetDouble(entryDeal, DEAL_COMMISSION);
            entrySwap = HistoryDealGetDouble(entryDeal, DEAL_SWAP);
         }
         double fillPrice = trade.ResultPrice();
         if(fillPrice <= 0) fillPrice = ask;
         Bot1WriteTradeLog(trade.ResultOrder(), "OPEN_BUY", fillPrice, CounterTrendLotSize, 0, 0,
            "countertrend_meanrev|" + g_ctTriggerReason, sl, tp, MathAbs(fillPrice - sl), entryComm, entrySwap,
            0, 0, 0, 0, ask, ctMagic,
            (UseRegime21Classifier ? Bot1Regime21BucketToString(g_r21b.bucket) : ""),
            g_r21b.trendVotes, g_r21b.votersActive, Bot1Regime21CounterFlag(1));
      } else {
         Print("[BOT1-ERROR] Counter-trend BUY OPEN REJECTED for ", _Symbol, " ask=", ask, " sl=", sl, " tp=", tp,
               " retcode=", trade.ResultRetcode());
      }
   } else if(signal == -1) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0.0, tp = 0.0;
      Bot1CounterTrendBracketPrices(false, bid, sl, tp);

      // v2 AGILE BUG FIX: see matching comment in the BUY block above --
      // skip the shared-history min-SL-distance filter for this module.

      // 2026-09-29: magic-number-FIRST format, see matching comment in the BUY block above.
      string comment = StringFormat("%d|CTS|MeanRev", ctMagic);
      if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, CounterTrendLotSize, bid, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         // v2 AGILE: deliberately NOT calling Bot1RecordSLDistance here -- see matching comment in the BUY block above.
         Bot1TrackPositionMagic(trade.ResultOrder(), ctMagic);   // v2 AGILE: see Bot1TrackPositionMagic comment
         Print("[BOT1-COUNTERTREND] ", _Symbol, " MN:", ctMagic, " SELL OPENED (mean-reversion): ", bid, " SL: ", sl, " TP: ", tp, " trigger=", g_ctTriggerReason);
         double entryComm = 0, entrySwap = 0;
         ulong entryDeal = trade.ResultDeal();
         if(entryDeal != 0 && HistoryDealSelect(entryDeal)) {
            entryComm = HistoryDealGetDouble(entryDeal, DEAL_COMMISSION);
            entrySwap = HistoryDealGetDouble(entryDeal, DEAL_SWAP);
         }
         double fillPrice = trade.ResultPrice();
         if(fillPrice <= 0) fillPrice = bid;
         Bot1WriteTradeLog(trade.ResultOrder(), "OPEN_SELL", fillPrice, CounterTrendLotSize, 0, 0,
            "countertrend_meanrev|" + g_ctTriggerReason, sl, tp, MathAbs(sl - fillPrice), entryComm, entrySwap,
            0, 0, 0, 0, bid, ctMagic,
            (UseRegime21Classifier ? Bot1Regime21BucketToString(g_r21b.bucket) : ""),
            g_r21b.trendVotes, g_r21b.votersActive, Bot1Regime21CounterFlag(-1));
      } else {
         Print("[BOT1-ERROR] Counter-trend SELL OPEN REJECTED for ", _Symbol, " bid=", bid, " sl=", sl, " tp=", tp,
               " retcode=", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK FOR TRADING SIGNALS                                       
//+------------------------------------------------------------------+
void CheckForTradingSignals() {
   // --- BOT1: capture full raw state ONCE per bar-close, unconditionally ---
   Bot1RefreshRegime2Cache();
   Bot1Layer1State l1st; Bot1Layer2State l2st; Bot1Layer3State l3st;
   Bot1VolState volst; Bot1RiskContext rcst;
   Bot1CaptureLayer1(l1st);
   Bot1CaptureLayer2(l2st, l1st.l1_result);
   Bot1CaptureLayer3(l3st, l1st.l1_result);
   Bot1CaptureVol(volst);
   Bot1CaptureRisk(rcst);

   Bot1UpdateShadowSimulation(l1st, l2st, l3st, volst, rcst);
   Bot1UpdateShadowSimulation2(l1st, l2st, l3st);
   Bot1ShadowPoolTryOpen(l1st, l2st, rcst);  // 2026-09-25: independent multi-trade pool, see input group comment

   Bot1LogRegime2Share();
   Bot1LogRegime2Layers(l1st, l2st, l3st);
   Bot1WriteRegime2DiagCsv();

   // PERF FIX (found during v5.3 follow-up): this print had NO gating flag
   // at all, unlike every other diagnostic call in this function -- it fired
   // every bar, every pass, regardless of any Log* setting. Its own comment
   // (below, on the L2L3 print) says it's meant to share the L2L3 print's
   // cadence and toggle; it just never got the toggle. Gated behind the
   // same flag now. Content and cadence unchanged when the flag is on.
   if(LogBot1L2L3Diagnostics) {
      Print("[BOT1-L1] ", _Symbol, " ichi=", l1st.ichi_signal, " ema=", l1st.ema_signal,
            " psar=", l1st.psar_signal, " confirmations=", l1st.l1_confirmations,
            " -> l1_result=", l1st.l1_result);
   }

   // Diagnostic: raw L2/L3 sub-signal breakdown, ONE consolidated line per
   // bar (not one print per indicator) -- same cadence as the L1 line
   // above, so this roughly doubles diagnostic volume, not multiplies it.
   // Added 2026-07-21 specifically to check whether MACD/Bollinger/OBV/
   // Donchian are silently "stuck" the way Ichimoku's Chikou requirement
   // was -- toggle LogBot1L2L3Diagnostics off once that's answered.
   if(LogBot1L2L3Diagnostics) {
      Print("[BOT1-L2L3] ", _Symbol,
            " macd=", l2st.macd_signal, " rsi_sig=", l2st.rsi_signal, " rsi_val=", DoubleToString(l2st.rsi_value, 1),
            " adx_ok=", l2st.adx_ok, " adx_val=", DoubleToString(l2st.adx_value, 1),
            " | boll=", l3st.boll_signal, " obv=", l3st.obv_signal, " donch=", l3st.donchian_signal,
            " -> l2_confirm=", l2st.l2_confirmations, " l3_result=", l3st.l3_result);
   }

   // Live gate: L1 always required. g_RequireL2ForLive/g_RequireL3ForLive are
   // per-symbol OFF by default (POC state) and are set to true by
   // bot1_param_advisor.py's .set output ONLY once bot1_strategic.py's
   // promotion bar has actually cleared for that symbol -- never hand-set
   // these without checking the strategic report first.
   int signal = l1st.l1_result;
   if(signal != 0 && !IsMarketTradable()) signal = 0;
   if(signal != 0 && g_RequireL2ForLive && !l2st.l2_pass_strict) signal = 0;
   if(signal != 0 && g_RequireL3ForLive && !l3st.l3_pass_strict) signal = 0;
   // Inverted L3 (see g_ExcludeWhenL3Fires comment): skip when L3 PASSES.
   // g_RequireL3ForLive takes precedence if someone sets both -- contradictory
   // config, warned at init, but the gate must still behave deterministically.
   if(signal != 0 && g_ExcludeWhenL3Fires && !g_RequireL3ForLive && l3st.l3_pass_strict) signal = 0;
   // BRANCH feature: strategy's own rolling realized win rate has degraded
   // below RegimeMinWinRate (reactive, unified in v5.3/v5.94 to also govern
   // the 6 academic + 4 community/volatility/session filters under ONE
   // RegimeSuiteVoteMode -- see g_UseRegimeSuiteGate's group comment). Two
   // independent trigger sources, OR'd together into one "degraded" state --
   // UseRegimeKillSwitch and g_UseRegimeSuiteGate can each be tested alone or
   // combined. Two possible responses to "degraded", controlled by
   // UseRangeModeAdaptation:
   //   false (v2 behavior): suppress the entry entirely.
   //   true  (v3): let the entry through, but flag it to use the tight
   //   symmetric range-mode SL/TP instead of the normal ADR-based stops --
   //   set here, read by CalculateStopLoss/CalculateTakeProfit at the
   //   point this specific entry is opened below.
   // Checked last, after every other gate, so it doesn't mask which OTHER
   // filter would have vetoed the trade anyway.
   Bot1LogRegimeSuiteDiagnostics();
   bool killSwitchDegraded = Bot1RegimeKillSwitchActive();   // still advances the probe counter / prints trip-release regardless of g_UseRegimeSuiteGate
   bool regimeSuiteDegraded = g_UseRegimeSuiteGate && Bot1RegimeSuiteSaysRanging();
   bool degraded = killSwitchDegraded || regimeSuiteDegraded;

   g_useRangeModeForThisEntry = false;
   if(signal != 0 && degraded) {
      if(UseRangeModeAdaptation) {
         g_useRangeModeForThisEntry = true;
      } else {
         signal = 0;
      }
   }

   bool exhaustionBlocked = false;
   if(signal != 0 && !g_useRangeModeForThisEntry && g_r2.exhaustionSkip) {
      exhaustionBlocked = true;
      signal = 0;
      if(Bot1R2DiagOn())
         Print("[BOT1-R2-SL] ", _Symbol, " SKIP exhaustion_frac=", DoubleToString(g_r2.exhaustionFrac, 3),
               " >= ", DoubleToString(ADRExhaustionPct, 2));
   }

   // REGIME 2.1: continuous-score entry gate (step 1 of the new-architecture
   // build order, now LIVE not scaffold). Checked after the 2.0 gates so it
   // never masks which OTHER filter would have vetoed the trade anyway --
   // same precedence discipline as every gate above. With
   // UseRegime21Score=false (default) or Regime21MinScoreToTrade=0.0
   // (default), this is a hard no-op: g_r21.compositeScore is always >= 0.0,
   // so behavior is byte-identical to 2.0 until BOTH are deliberately set.
   bool regime21Blocked = false;
   if(signal != 0 && UseRegime21Score && g_r21.compositeScore < Regime21MinScoreToTrade) {
      regime21Blocked = true;
      signal = 0;
   }

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool oneTradeBlocked = (OneTradePerBar && lastTradeBarTime == currentBarTime);

   // 2026-09-02: post-stop cooldown -- block same-direction re-entry for N
   // bars after this MagicNumber was stopped out. Checked here (before the
   // candidate-log write) so blocked bars are visible in diagnostics as
   // "signal fired but blocked", not silently dropped.
   bool cooldownBlocked = (signal != 0 && Bot1CooldownBlocks(signal));
   if(cooldownBlocked) signal = 0;

   // Log the candidate row regardless of whether a trade will actually open
   // (trade_opened_live is filled in after the open attempt below).
   bool willAttemptOpen = (signal != 0 && !oneTradeBlocked);

   // Build a single human-readable block_reason -- first blocker wins, in
   // the same precedence order the gates above were actually checked, so
   // it matches what genuinely stopped the trade rather than a guess.
   string blockReason = "OK_OPENED";
   if(!willAttemptOpen) {
      if(l1st.l1_result == 0)                                    blockReason = "NO_SIGNAL";
      else if(!IsMarketTradable())                                blockReason = "VOL_FILTER";
      else if(g_RequireL2ForLive && !l2st.l2_pass_strict)           blockReason = "L2_FAIL";
      else if(g_RequireL3ForLive && !l3st.l3_pass_strict)           blockReason = "L3_FAIL";
      else if(g_ExcludeWhenL3Fires && !g_RequireL3ForLive && l3st.l3_pass_strict) blockReason = "L3_EXCLUDE_FIRED";
      else if(degraded && !UseRangeModeAdaptation)                blockReason = "REGIME_DEGRADED";
      else if(exhaustionBlocked)                                  blockReason = "ADR_EXHAUSTION";
      else if(regime21Blocked)                                    blockReason = "REGIME21_SCORE_TOO_LOW";
      else if(cooldownBlocked)                                    blockReason = "COOLDOWN";
      else if(oneTradeBlocked)                                    blockReason = "ONE_TRADE_PER_BAR";
      else                                                        blockReason = "UNKNOWN";
   }
   // NOTE: MaxBuyPositions/MaxSellPositions/min-SL-distance-outlier are
   // evaluated further below (after this log write, inside the per-direction
   // BUY/SELL blocks) -- they cannot yet be reflected in blockReason here.
   // sl_dist_would_be_outlier is filled in separately per-direction below
   // via Bot1LastSLDistanceOutlier; left as NO here for the "no signal at
   // all" case where it was never evaluated.
   Bot1WriteCandidateLog(l1st, l2st, l3st, volst, rcst, willAttemptOpen,
      blockReason, false, cooldownBlocked);

   if(signal == 0) return;
   if(oneTradeBlocked) return;

   // 2026-10-13: 1-per-bar PF-priority diversification gate (additive, fail-open) + fleet-wide
   // min re-entry distance gate (additive, fail-open) -- both previously missing from this file.
   if(UseGuardBarGate && !GGate_ShouldOpen(MagicNumber)) {
      if(LogBot1Trades)
         Print("[BOT1-GATE] MN:", MagicNumber, " entry skipped -- Guard picked a different magic for this bar");
      return;
   }
   if(!GGate_PriceDistanceOk()) {
      if(LogBot1Trades)
         Print("[BOT1-GATE] MN:", MagicNumber, " entry skipped -- within min re-entry distance of last fleet entry");
      return;
   }

   // 2026-10-13: per-direction loss-cooldown enforcement gate (additive, fail-open). OFF by
   // default on the Guard (UseLossCooldownGate=false) -- GGate_LossCooldownOk() returns true
   // until enabled.
   {
      ENUM_POSITION_TYPE signalDir = (signal == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      if(!GGate_LossCooldownOk(signalDir)) {
         if(LogBot1Trades)
            Print("[BOT1-GATE] MN:", MagicNumber, " entry skipped -- direction in loss-cooldown after a recent stop-out");
         return;
      }
   }

   // 2026-10-14: fleet-wide same-instant pile-on gate (additive, fail-open). OFF by default
   // on the Guard (UseFleetOpenCooldownGate=false) -- GGate_FleetOpenCooldownOk() returns true
   // until enabled. Catches the race the price-distance gate above can't (multiple EAs
   // reading its once-per-tick snapshot before anyone's open registers).
   if(!GGate_FleetOpenCooldownOk()) {
      if(LogBot1Trades)
         Print("[BOT1-GATE] MN:", MagicNumber, " entry skipped -- within fleet-wide same-instant open cooldown");
      return;
   }

   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
         position.Magic() == MagicNumber) {
         posCount++;
      }
   }

   if(signal == 1) {
      if(posCount >= MaxBuyPositions) return;

      if(CloseOpposite) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
               position.Magic() == MagicNumber && position.PositionType() == POSITION_TYPE_SELL) {
               trade.PositionClose(position.Ticket());
            }
         }
      }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = CalculateStopLoss(POSITION_TYPE_BUY, ask, true);

      // 2026-09-02: reject anomalously tight SL vs this MagicNumber's own
      // recent history -- see UseMinSLDistanceFilter comment.
      if(Bot1SLDistanceIsOutlier(ask, sl)) {
         Print("[BOT1-INFO] ", _Symbol, " MN:", MagicNumber, " BUY skipped: candidate SL distance ",
               DoubleToString(MathAbs(ask - sl) / _Point, 1), "pt is below ",
               DoubleToString(MinSLDistanceFraction * 100, 0), "% of the rolling avg ",
               DoubleToString(Bot1AvgSLDistance(), 1), "pt -- likely a stale/unrepresentative ADR/Kumo read");
         return;
      }

      double tp = CalculateTakeProfit(POSITION_TYPE_BUY, ask, sl);
      double lot = CalculateLotSize(sl, ask, posCount, Bot1Regime21SizeMultiplier(1));
      // 2026-09-29: magic-number-FIRST format -- see comment in CTBUY block for rationale
      // (31-char comment cap was truncating the magic number for longer ConfigLabels, e.g.
      // R21B's 54510 displaying as "5451" on the live chart -- confirmed real this session).
      string comment = StringFormat("%d|B|Stage", MagicNumber);

      if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lot, ask, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         lastTradeBarTime = currentBarTime;
         Bot1RecordSLDistance(MathAbs(ask - sl) / _Point);
         Bot1TrackPositionMagic(trade.ResultOrder(), MagicNumber);   // v2 AGILE: see Bot1TrackPositionMagic comment -- DEAL_MAGIC isn't reliable on server-triggered closes
         Print("BUY OPENED: ", ask, " SL: ", sl, " TP: ", tp, " Lot: ", lot,
               g_useRangeModeForThisEntry ? " [RANGE MODE]" : "");
         double entryComm = 0, entrySwap = 0;
         ulong entryDeal = trade.ResultDeal();
         if(entryDeal != 0 && HistoryDealSelect(entryDeal)) {
            entryComm = HistoryDealGetDouble(entryDeal, DEAL_COMMISSION);
            entrySwap = HistoryDealGetDouble(entryDeal, DEAL_SWAP);
         }
         // Module 14: fillPrice is the ACTUAL executed price -- may differ
         // from the pre-trade reference (ask) due to slippage/requotes.
         // "price" logged is now the true entry, "requested_price" carries
         // the original reference for slippage = fillPrice - requestedPrice.
         double fillPrice = trade.ResultPrice();
         if(fillPrice <= 0) fillPrice = ask; // fallback if broker didn't report a fill price
         Bot1RememberInitialRisk(trade.ResultOrder(), MathAbs(fillPrice - sl));
         Bot1WriteTradeLog(trade.ResultOrder(), "OPEN_BUY", fillPrice, lot, 0, 0,
            StringFormat("l1=%d l2pass=%s l3pass=%s range_mode=%s", l1st.l1_result, l2st.l2_pass_strict ? "Y" : "N", l3st.l3_pass_strict ? "Y" : "N", g_useRangeModeForThisEntry ? "Y" : "N"),
            sl, tp, MathAbs(fillPrice - sl), entryComm, entrySwap,
            0, 0, 0, 0, ask, -1,
            (UseRegime21Classifier ? Bot1Regime21BucketToString(g_r21b.bucket) : ""),
            g_r21b.trendVotes, g_r21b.votersActive, Bot1Regime21CounterFlag(1),
            GetRegimeADXR(), l2st.rsi_value, (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
            adr, (GetSessionVWAP() > 0 ? fillPrice - GetSessionVWAP() : -999999), g_consecLosses,
            Bot1MomentumPts(3), Bot1MomentumPts(10), g_r2.ema200Bias, g_r2.superTrendDir,
            Bot1DayRangePosition(fillPrice), Bot1PriceVsHourOpenPts(fillPrice),
            g_r21b.direction, (Bot1Regime21DirectionAgrees(1) ? "AGREE" : "DISAGREE"),
            g_r21b.barsSinceBucketFlip, g_r21b.barsSinceDirectionFlip,
            Bot1SlopePtsPerBar(10), Bot1SlopePtsPerBar(50), Bot1SlopePtsPerBar(200));
         Bot1WriteExtendedDiagnostics(trade.ResultOrder(), "OPEN_BUY", l1st, l2st, l3st, volst);
      } else {
         Print("[BOT1-ERROR] BUY OPEN REJECTED for ", _Symbol, " ask=", ask, " sl=", sl, " tp=", tp,
               " retcode=", trade.ResultRetcode(), " -- signal fired but no position opened, "
               "this bar's trade is silently lost unless this is investigated.");
      }
   }
   else if(signal == -1) {
      if(posCount >= MaxSellPositions) return;

      if(CloseOpposite) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
               position.Magic() == MagicNumber && position.PositionType() == POSITION_TYPE_BUY) {
               trade.PositionClose(position.Ticket());
            }
         }
      }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalculateStopLoss(POSITION_TYPE_SELL, bid, true);

      // 2026-09-02: reject anomalously tight SL vs this MagicNumber's own
      // recent history -- see UseMinSLDistanceFilter comment.
      if(Bot1SLDistanceIsOutlier(bid, sl)) {
         Print("[BOT1-INFO] ", _Symbol, " MN:", MagicNumber, " SELL skipped: candidate SL distance ",
               DoubleToString(MathAbs(sl - bid) / _Point, 1), "pt is below ",
               DoubleToString(MinSLDistanceFraction * 100, 0), "% of the rolling avg ",
               DoubleToString(Bot1AvgSLDistance(), 1), "pt -- likely a stale/unrepresentative ADR/Kumo read");
         return;
      }

      double tp = CalculateTakeProfit(POSITION_TYPE_SELL, bid, sl);
      double lot = CalculateLotSize(sl, bid, posCount, Bot1Regime21SizeMultiplier(-1));
      // 2026-09-29: magic-number-FIRST format, see matching comment in the BUY block above.
      string comment = StringFormat("%d|S|Stage", MagicNumber);

      if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lot, bid, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         lastTradeBarTime = currentBarTime;
         Bot1RecordSLDistance(MathAbs(sl - bid) / _Point);
         Bot1TrackPositionMagic(trade.ResultOrder(), MagicNumber);   // v2 AGILE: see Bot1TrackPositionMagic comment
         Print("SELL OPENED: ", bid, " SL: ", sl, " TP: ", tp, " Lot: ", lot,
               g_useRangeModeForThisEntry ? " [RANGE MODE]" : "");
         double entryComm = 0, entrySwap = 0;
         ulong entryDeal = trade.ResultDeal();
         if(entryDeal != 0 && HistoryDealSelect(entryDeal)) {
            entryComm = HistoryDealGetDouble(entryDeal, DEAL_COMMISSION);
            entrySwap = HistoryDealGetDouble(entryDeal, DEAL_SWAP);
         }
         double fillPrice = trade.ResultPrice();
         if(fillPrice <= 0) fillPrice = bid;
         Bot1RememberInitialRisk(trade.ResultOrder(), MathAbs(sl - fillPrice));
         Bot1WriteTradeLog(trade.ResultOrder(), "OPEN_SELL", fillPrice, lot, 0, 0,
            StringFormat("l1=%d l2pass=%s l3pass=%s range_mode=%s", l1st.l1_result, l2st.l2_pass_strict ? "Y" : "N", l3st.l3_pass_strict ? "Y" : "N", g_useRangeModeForThisEntry ? "Y" : "N"),
            sl, tp, MathAbs(sl - fillPrice), entryComm, entrySwap,
            0, 0, 0, 0, bid, -1,
            (UseRegime21Classifier ? Bot1Regime21BucketToString(g_r21b.bucket) : ""),
            g_r21b.trendVotes, g_r21b.votersActive, Bot1Regime21CounterFlag(-1),
            GetRegimeADXR(), l2st.rsi_value, (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
            adr, (GetSessionVWAP() > 0 ? fillPrice - GetSessionVWAP() : -999999), g_consecLosses,
            Bot1MomentumPts(3), Bot1MomentumPts(10), g_r2.ema200Bias, g_r2.superTrendDir,
            Bot1DayRangePosition(fillPrice), Bot1PriceVsHourOpenPts(fillPrice),
            g_r21b.direction, (Bot1Regime21DirectionAgrees(-1) ? "AGREE" : "DISAGREE"),
            g_r21b.barsSinceBucketFlip, g_r21b.barsSinceDirectionFlip,
            Bot1SlopePtsPerBar(10), Bot1SlopePtsPerBar(50), Bot1SlopePtsPerBar(200));
         Bot1WriteExtendedDiagnostics(trade.ResultOrder(), "OPEN_SELL", l1st, l2st, l3st, volst);
      } else {
         Print("[BOT1-ERROR] SELL OPEN REJECTED for ", _Symbol, " bid=", bid, " sl=", sl, " tp=", tp,
               " retcode=", trade.ResultRetcode(), " -- signal fired but no position opened, "
               "this bar's trade is silently lost unless this is investigated.");
      }
   }
}

//+------------------------------------------------------------------+
//| LEGEND HELPER FUNCTIONS                                         
//+------------------------------------------------------------------+
string SignalToString(int sig) {
   if(sig == 1) return "BULLISH";
   if(sig == -1) return "BEARISH";
   return "NEUTRAL";
}

color SignalColor(int sig) {
   if(sig == 1) return clrDarkGreen;
   if(sig == -1) return clrDarkRed;
   return clrDarkGray;
}

string BoolToYesNo(bool val) {
   return val ? "YES" : "NO";
}

void CreateLabel(string name, string text, int x, int y, color col, int fontSize = 8, string font = "Arial", int corner = CORNER_LEFT_UPPER) {
   long chart_id = 0;
   if(ObjectFind(chart_id, name) < 0) {
      ObjectCreate(chart_id, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(chart_id, name, OBJPROP_BACK, false);
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(chart_id, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, col);
   ObjectSetString(chart_id, name, OBJPROP_FONT, font);
   ObjectSetInteger(chart_id, name, OBJPROP_FONTSIZE, fontSize);
}

void DeleteLegendObjects() {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
      string name = ObjectName(0, i);
      if(StringFind(name, "Legend_") == 0 || StringFind(name, "MarketCond_") == 0) {
         ObjectDelete(0, name);
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW LEFT LEGEND - Market State & Entry Conditions              
//+------------------------------------------------------------------+
void DrawLeftLegend() {
   if(!ShowLeftLegend) return;

   int x = 10;
   int y = 20;
   int lineHeight = LegendFontSize + 4;
   int fontSize = LegendFontSize;

   // Calculate current values
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double hypo_sl_buy = CalculateStopLoss(POSITION_TYPE_BUY, ask);
   double hypo_sl_sell = CalculateStopLoss(POSITION_TYPE_SELL, bid);
   double next_lot_buy = CalculateLotSize(hypo_sl_buy, ask);
   double next_lot_sell = CalculateLotSize(hypo_sl_sell, bid);

   bool marketTradable = IsMarketTradable();
   bool timeAllowed = IsTradingTimeAllowed();
   int overallSignal = CheckIndicatorFilters();

   // Get layer signals
   int l1Signal = GetLayer1Trend();
   int l2MACDSignal = GetMACDMomentum();
   int l2RSISignal = GetRSIMomentum();
   bool l2ADXOk = GetADXStrength(l1Signal);
   int l3BollSignal = GetBollingerTrigger();
   int l3OBVSignal = GetOBVTrigger();
   int l3DonchianSignal = GetDonchianTrigger();

   // Individual Layer 1 indicators
   int ichiSignal = GetIchimokuTrend();
   int emaSignal = GetEMACrossTrend();
   int psarSignal = GetPSARTrend();

   // Volatility info
   double volRatio = GetVolatilityRatio();
   int volState = GetVolatilityState();
   string volStateStr = (volState == 1) ? "TRENDING" : (volState == 0) ? "RANGING" : "LOW VOL";
   color volStateColor = (volState == 1) ? clrDarkGreen : (volState == 0) ? clrOrange : clrDarkRed;

   // === TITLE ===
   CreateLabel("Legend_Title", "═════ TRADING CONDITIONS ═════", x, y, clrBlack, fontSize+2, "Arial Black");
   y += lineHeight + 5;

   // === OVERALL STATUS ===
   CreateLabel("Legend_Status", "Overall Signal: " + SignalToString(overallSignal), x, y, SignalColor(overallSignal), fontSize+1, "Arial Bold");
   y += lineHeight + 2;

   CreateLabel("Legend_Market", "Market Tradable: " + BoolToYesNo(marketTradable), x, y, marketTradable ? clrDarkGreen : clrDarkRed, fontSize);
   y += lineHeight;

   CreateLabel("Legend_Time", "Time Allowed: " + BoolToYesNo(timeAllowed), x, y, timeAllowed ? clrDarkGreen : clrDarkRed, fontSize);
   y += lineHeight + 3;

   // === LAYER 1: BASELINE TREND ===
   CreateLabel("Legend_L1_Title", "▼ LAYER 1: Baseline Trend (HTF)", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   if(g_UseIchimoku) {
      string statusIchi = SignalToString(ichiSignal);
      CreateLabel("Legend_Ichi", "  Ichimoku: " + statusIchi, x+10, y, SignalColor(ichiSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseEMACross) {
      string statusEMA = SignalToString(emaSignal);
      CreateLabel("Legend_EMA", "  EMA Cross: " + statusEMA, x+10, y, SignalColor(emaSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UsePSAR) {
      string statusPSAR = SignalToString(psarSignal);
      CreateLabel("Legend_PSAR", "  PSAR: " + statusPSAR, x+10, y, SignalColor(psarSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseSuperTrend) {
      int stSig = GetSuperTrendSignal();
      CreateLabel("Legend_ST", "  SuperTrend: " + SignalToString(stSig), x+10, y, SignalColor(stSig), fontSize-1);
      y += lineHeight;
   }

   if(g_UseEMA200Bias) {
      int ema200Sig = GetEMA200Bias();
      CreateLabel("Legend_EMA200", "  EMA200 bias: " + SignalToString(ema200Sig), x+10, y, SignalColor(ema200Sig), fontSize-1);
      y += lineHeight;
   }

   CreateLabel("Legend_L1_Result", "  → Result: " + SignalToString(l1Signal), x+5, y, SignalColor(l1Signal), fontSize, "Arial Bold");
   y += lineHeight + 3;

   // === LAYER 2: MOMENTUM ===
   CreateLabel("Legend_L2_Title", "▼ LAYER 2: Momentum", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   if(g_UseMACD) {
      CreateLabel("Legend_MACD", "  MACD: " + SignalToString(l2MACDSignal), x+10, y, SignalColor(l2MACDSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseRSI) {
      CreateLabel("Legend_RSI", "  RSI: " + SignalToString(l2RSISignal), x+10, y, SignalColor(l2RSISignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseADX) {
      string adxStatus = l2ADXOk ? "STRONG" : "WEAK";
      color adxColor = l2ADXOk ? clrDarkGreen : clrDarkRed;
      CreateLabel("Legend_ADX", "  ADX: " + adxStatus, x+10, y, adxColor, fontSize-1);
      y += lineHeight;
   }

   bool l2Pass = g_RequireL2ForLive && CheckLayer2Momentum(l1Signal);
   string l2Result = !g_RequireL2ForLive ? "not in gate" : (l2Pass ? "PASS" : "FAIL");
   CreateLabel("Legend_L2_Result", "  → Result: " + l2Result, x+5, y,
               !g_RequireL2ForLive ? clrDarkGray : (l2Pass ? clrDarkGreen : clrDarkRed), fontSize, "Arial Bold");
   y += lineHeight + 3;

   // === LAYER 3: ENTRY TRIGGERS ===
   CreateLabel("Legend_L3_Title", "▼ LAYER 3: Entry Triggers", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   if(g_UseBollinger) {
      CreateLabel("Legend_BB", "  Bollinger: " + SignalToString(l3BollSignal), x+10, y, SignalColor(l3BollSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseOBV) {
      CreateLabel("Legend_OBV", "  OBV: " + SignalToString(l3OBVSignal), x+10, y, SignalColor(l3OBVSignal), fontSize-1);
      y += lineHeight;
   }

   if(g_UseDonchian) {
      CreateLabel("Legend_Donchian", "  Donchian: " + SignalToString(l3DonchianSignal), x+10, y, SignalColor(l3DonchianSignal), fontSize-1);
      y += lineHeight;
   }

   int l3Signal = GetLayer3Trigger();
   string l3GateTxt = EnumToString(g_Layer3Gate);
   CreateLabel("Legend_L3_Result", "  → Result: " + SignalToString(l3Signal) + " [" + l3GateTxt + "]", x+5, y, SignalColor(l3Signal), fontSize, "Arial Bold");
   y += lineHeight + 3;

   // === VOLATILITY ===
   CreateLabel("Legend_Vol_Title", "▼ VOLATILITY", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   CreateLabel("Legend_VolRatio", StringFormat("  Ratio: %.3f (%s)", volRatio, volStateStr), x+10, y, volStateColor, fontSize-1);
   y += lineHeight + 3;

// === NEXT TRADE INFO ===
CreateLabel("Legend_Trade_Title", "▼ NEXT TRADE", x, y, clrNavy, fontSize, "Arial Bold");
y += lineHeight;

// Calculate SL distance and risk
double sl_distance = UseADR ? (adr * ADRMultiplierSL / _Point) : StopLoss;
double valuePerPt = ValuePerPoint();

// Get the lot size for next trade (use BUY as reference, both should be same logic)

double hypo_sl = CalculateStopLoss(POSITION_TYPE_BUY, ask);
double next_lot = CalculateLotSize(hypo_sl, ask);

// Calculate USD risk for next trade
double next_trade_risk = sl_distance * valuePerPt * next_lot;

CreateLabel("Legend_NextLot", StringFormat("  Lot Size: %.2f", next_lot), x+10, y, clrDarkBlue, fontSize-1);
y += lineHeight;

CreateLabel("Legend_SL", StringFormat("  SL Distance: %.0f pips", sl_distance), x+10, y, clrDarkOrange, fontSize-1);
y += lineHeight;

CreateLabel("Legend_SL_Risk", StringFormat("  SL Risk: $%.2f", next_trade_risk), x+10, y, clrDarkRed, fontSize, "Arial Bold");
y += lineHeight;


   // Trade readiness indicator
   string readiness = "";
   color readinessColor = clrDarkGray;

   if(overallSignal != 0 && marketTradable && timeAllowed) {
      readiness = "★ READY TO TRADE ★";
      readinessColor = clrGold;
   } else if(l1Signal != 0 && l2Pass) {
      readiness = "◆ WAITING FOR TRIGGER ◆";
      readinessColor = clrOrange;
   } else if(l1Signal != 0) {
      readiness = "○ WAITING FOR MOMENTUM ○";
      readinessColor = clrDarkOrange;
   } else {
      readiness = "✕ NO TREND DETECTED ✕";
      readinessColor = clrDarkRed;
   }

   y += 3;
   CreateLabel("Legend_Readiness", readiness, x, y, readinessColor, fontSize+1, "Arial Black");
}

//+------------------------------------------------------------------+
//| DRAW RIGHT LEGEND - Market Metrics & Parameters                 
//+------------------------------------------------------------------+
void DrawRightLegend() {
   if(!ShowRightLegend) return;

   int x = 250;
   int y = 20;
   int lineHeight = LegendFontSize + 4;
   int fontSize = LegendFontSize;

   // Get ADX values - FIXED: Proper array allocation
   double adxVals[];
   double pdiVals[];
   double mdiVals[];
   ArraySetAsSeries(adxVals, true);
   ArraySetAsSeries(pdiVals, true);
   ArraySetAsSeries(mdiVals, true);

   bool adxOk = false;
   if(adxHandle != INVALID_HANDLE) {
      if(CopyBuffer(adxHandle, 0, 0, 1, adxVals) >= 1 &&
         CopyBuffer(adxHandle, 1, 0, 1, pdiVals) >= 1 &&
         CopyBuffer(adxHandle, 2, 0, 1, mdiVals) >= 1) {
         adxOk = true;
      }
   }

   // Get RSI value - FIXED: Proper array allocation
   double rsiVals[];
   ArraySetAsSeries(rsiVals, true);
   bool rsiOk = false;
   if(rsiHandle != INVALID_HANDLE) {
      if(CopyBuffer(rsiHandle, 0, 0, 1, rsiVals) >= 1) {
         rsiOk = true;
      }
   }

   // Get MACD values - FIXED: Proper array allocation
   double macdVals[];
   double signalVals[];
   ArraySetAsSeries(macdVals, true);
   ArraySetAsSeries(signalVals, true);
   bool macdOk = false;
   if(macdHandle != INVALID_HANDLE) {
      if(CopyBuffer(macdHandle, 0, 0, 1, macdVals) >= 1 &&
         CopyBuffer(macdHandle, 1, 0, 1, signalVals) >= 1) {
         macdOk = true;
      }
   }

   // === TITLE ===
   CreateLabel("MarketCond_Title", "═════ MARKET METRICS ═════", x, y, clrBlack, fontSize+2, "Arial Black", CORNER_RIGHT_UPPER);
   y += lineHeight + 5;

   // === CURRENT PRICE ===
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   CreateLabel("MarketCond_Bid", StringFormat("BID: %.5f", bid), x, y, clrDarkRed, fontSize, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight;
   CreateLabel("MarketCond_Ask", StringFormat("ASK: %.5f", ask), x, y, clrDarkGreen, fontSize, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight + 3;

   // === ADR ===
   CreateLabel("MarketCond_ADR", StringFormat("ADR(14): %.5f", adr), x, y, clrDarkBlue, fontSize, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight + 3;

   // === INDICATORS ===
   if(adxOk && ArraySize(adxVals) > 0) {
      color adxColor = (adxVals[0] > ADXThreshold * 1.5) ? clrDarkGreen : (adxVals[0] > ADXThreshold) ? clrOrange : clrDarkRed;  // v5.94: StrongADXThreshold input removed (cosmetic-only, never affected trading) -- legend color now derives from the real ADXThreshold instead of a second unused input
      CreateLabel("MarketCond_ADXVal", StringFormat("ADX: %.2f", adxVals[0]), x, y, adxColor, fontSize, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;

      if(ArraySize(pdiVals) > 0) {
         CreateLabel("MarketCond_PDI", StringFormat("+DI: %.2f", pdiVals[0]), x, y, clrDarkGreen, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
         y += lineHeight;
      }

      if(ArraySize(mdiVals) > 0) {
         CreateLabel("MarketCond_MDI", StringFormat("-DI: %.2f", mdiVals[0]), x, y, clrDarkRed, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
         y += lineHeight + 2;
      }
   }

   if(rsiOk && ArraySize(rsiVals) > 0) {
      color rsiColor = (rsiVals[0] > 70) ? clrDarkRed : (rsiVals[0] < 30) ? clrDarkGreen : clrDarkGray;
      CreateLabel("MarketCond_RSI", StringFormat("RSI: %.2f", rsiVals[0]), x, y, rsiColor, fontSize, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight + 2;
   }

   if(macdOk && ArraySize(macdVals) > 0 && ArraySize(signalVals) > 0) {
      color macdColor = (macdVals[0] > signalVals[0]) ? clrDarkGreen : clrDarkRed;
      CreateLabel("MarketCond_MACD", StringFormat("MACD: %.5f", macdVals[0]), x, y, macdColor, fontSize, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;
      CreateLabel("MarketCond_Signal", StringFormat("Signal: %.5f", signalVals[0]), x, y, clrDarkGray, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight + 3;
   }

   // === ACCOUNT INFO ===
   CreateLabel("MarketCond_AccTitle", "▼ ACCOUNT", x, y, clrNavy, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
   y += lineHeight;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPL = equity - startDayBalance;
   color plColor = (dailyPL >= 0) ? clrDarkGreen : clrDarkRed;

   CreateLabel("MarketCond_Balance", StringFormat("Balance: %.2f", balance), x, y, clrDarkBlue, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight;

   CreateLabel("MarketCond_Equity", StringFormat("Equity: %.2f", equity), x, y, clrDarkBlue, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight;

   CreateLabel("MarketCond_DailyPL", StringFormat("Daily P/L: %.2f", dailyPL), x, y, plColor, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight + 3;

   // === FTMO STATUS ===
   // v5.97: dailyFloor/overallFloor now %-of-balance based, matching
   // CalculateLotSize() -- see FTMO PROTECTION group comment.
   double dailyLossBudgetDisp = startDayBalance * (MaxDailyLossPct / 100.0);
   double overallLossBudgetDisp = g_eaStartBalance * (MaxOverallLossPct / 100.0);
   double dailyFloor = startDayBalance - dailyLossBudgetDisp;
   double overallFloor = g_eaStartBalance - overallLossBudgetDisp;
   double dailyRemaining = equity - dailyFloor;
   double overallRemaining = equity - overallFloor;

   CreateLabel("MarketCond_FTMO", "▼ FTMO PROTECTION", x, y, clrNavy, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
   y += lineHeight;

   color dailyColor = (dailyRemaining > dailyLossBudgetDisp * 0.5) ? clrDarkGreen : (dailyRemaining > dailyLossBudgetDisp * 0.2) ? clrOrange : clrDarkRed;
   CreateLabel("MarketCond_DailyRem", StringFormat("Daily Remaining: %.2f", dailyRemaining), x, y, dailyColor, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight;

   color overallColor = (overallRemaining > overallLossBudgetDisp * 0.5) ? clrDarkGreen : (overallRemaining > overallLossBudgetDisp * 0.2) ? clrOrange : clrDarkRed;
   CreateLabel("MarketCond_OverallRem", StringFormat("Overall Remaining: %.2f", overallRemaining), x, y, overallColor, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight + 3;

   // === ACTIVE POSITIONS ===
   int posCount = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber) {
         posCount++;
      }
   }

   CreateLabel("MarketCond_Pos", StringFormat("Active Positions: %d", posCount), x, y, posCount > 0 ? clrDarkGreen : clrDarkGray, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
   y += lineHeight;

   // === STAGE TARGETS ===
   if(g_UseStageExits && posCount > 0) {
      y += 2;
      CreateLabel("MarketCond_StageTitle", "▼ STAGE TARGETS", x, y, clrNavy, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_TP1", StringFormat("TP1: %d pips (%.0f%%)", g_TP1_Distance, g_TP1_ClosePercent*100), x, y, clrDarkOrange, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_TP2", StringFormat("TP2: %d pips (%.0f%%)", g_TP2_Distance, g_TP2_ClosePercent*100), x, y, clrDarkOrange, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_Trail", StringFormat("Trail: %d pips @ %d pips", TrailingDistance, TrailingActivation), x, y, clrDarkGreen, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(MagicNumber);
   Bot1ResolveArch();

   // NEWS-BLACKOUT FEASIBILITY PROBE (2026-09-19, temporary, remove once
   // resolved): live-chart CalendarValueHistory() confirmed working (9210
   // events, 2491 USD, real data for the 2026-01-01/08-31 test window) via
   // a standalone Script -- but MQL_TESTER was 0 there (regular chart), not
   // the actual Strategy Tester environment this EA runs in. MT5 Tester's
   // economic-calendar support is broker/build-dependent and has been known
   // to silently return 0 events in some setups even when the live-chart
   // API works fine. This one-time OnInit check answers that directly
   // before any real news-filter logic gets built on top of it.
   {
      MqlCalendarValue calProbeValues[];
      datetime calProbeFrom = D'2026.01.01 00:00:00';
      datetime calProbeTo   = D'2026.08.31 23:59:59';
      int calProbeTotal = CalendarValueHistory(calProbeValues, calProbeFrom, calProbeTo);
      Print("[CALENDAR-PROBE-INSIDE-EA] MQL_TESTER=", MQLInfoInteger(MQL_TESTER),
            " MQL_OPTIMIZATION=", MQLInfoInteger(MQL_OPTIMIZATION),
            " CalendarValueHistory returned ", calProbeTotal, " events for the test window -- ",
            (calProbeTotal > 0 ? "REAL DATA, news filter is viable" : "ZERO EVENTS, news filter would be a NO-OP on this build/broker"));
   }


   // v5.97: capture the REAL starting balance once, replacing the old
   // flat-dollar InitialBalance input -- see FTMO PROTECTION group comment.
   g_eaStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long effectiveMin = (stopsLevel > 0) ? stopsLevel : Bot1FallbackMinStopPoints;
   int legalTrail = Bot1LegalTrailPts();
   Print("[BOT1-INFO] ", _Symbol, " StopsLevel=", stopsLevel, " pts  FreezeLevel=", freezeLevel,
         " pts  EffectiveMinStop=", effectiveMin, " pts",
         (stopsLevel == 0) ? " (broker reported 0 -- using Bot1FallbackMinStopPoints, confirmed necessary 2026-07-15)" : "",
         "  TrailingDistance(input)=", TrailingDistance, " pts  legal_trail=", legalTrail, " pts",
         (TrailingDistance < legalTrail) ? "  [v6.13: input trail tighter than broker min -- will CLAMP up, not skip]" : "");
   Print("[BOT1-LIVE] TICKS: L1=", Bot1Layer1TickTag(),
         " L2=", (g_RequireL2ForLive ? "ON" : "OFF"),
         " L3=", Bot1Layer3TickTag(),
         " regime=", Bot1RegimeTickTag(),
         " exit=", EnumToString(g_ExitMode),
         " trail=", (Bot1TrailAllowed() ? "ON" : "OFF"),
         " kumoSL=", (UseKumoSL ? "ON" : "OFF"),
         " lot=", DoubleToString(LotSize, 2),
         " ct=", EnumToString(g_CTMode),
         " score=", EnumToString(OptScoreMode));
   Print("[BOT1-INFO] ", _Symbol, " LIVE GATE CONFIG: g_RequireL2ForLive=", g_RequireL2ForLive,
         " g_RequireL3ForLive=", g_RequireL3ForLive, " g_ExcludeWhenL3Fires=", g_ExcludeWhenL3Fires,
         " g_TP1_Distance=", g_TP1_Distance, " g_TP2_Distance=", g_TP2_Distance);
   if(g_RequireL3ForLive && g_ExcludeWhenL3Fires)
      Print("[BOT1-ERROR] ", _Symbol, " CONTRADICTORY CONFIG: g_RequireL3ForLive and g_ExcludeWhenL3Fires are BOTH true. "
            "g_RequireL3ForLive wins; g_ExcludeWhenL3Fires is ignored. Fix the .set file.");

   // PERF FIX: atrHandle removed -- it was created here but never read via
   // CopyBuffer anywhere in the file. CalculateADR() computes ADR directly
   // from raw iHigh/iLow on PERIOD_D1, not from this indicator handle, so
   // it was a pure wasted allocation with zero effect on any calculation.

   bool needIchiHTF = g_UseIchimoku;
   bool needIchiCur = UseKumoSL;
   bool needEmaFast = g_UseEMACross;
   bool needEmaSlow = g_UseEMACross || g_UseEMA200Bias;
   bool needPsar    = g_UsePSAR;
   bool needST      = Bot1NeedsSuperTrend();
   bool needAdx     = g_UseADX || g_UseADXSlope || Bot1Lean4Active();
   bool needBoll    = g_UseBollinger || g_UseCounterTrendModule || Bot1Lean4Active();
   bool needCci     = g_UseLayer2CCI;
   bool needStoch   = g_UseCounterTrendModule && g_UseStochasticTrigger;
   bool needAtrStop = (g_StopBasisMode == SL_ATR);

   if(needIchiHTF) {
      ichimokuHandleHTF = iIchimoku(_Symbol, HigherTimeframe, IchimokuTenkan, IchimokuKijun, IchimokuSenkou);
      if(ichimokuHandleHTF == INVALID_HANDLE) return INIT_FAILED;
   }
   if(needIchiCur) {
      ichimokuHandleCur = iIchimoku(_Symbol, _Period, IchimokuTenkan, IchimokuKijun, IchimokuSenkou);
      if(ichimokuHandleCur == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needEmaFast) {
      emaFastHandle = iMA(_Symbol, HigherTimeframe, EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaFastHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   if(needEmaSlow) {
      emaSlowHandle = iMA(_Symbol, HigherTimeframe, EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaSlowHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needPsar) {
      psarHandle = iSAR(_Symbol, HigherTimeframe, PSARStep, PSARMax);
      if(psarHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needST) {
      superTrendAtrHandle = iATR(_Symbol, HigherTimeframe, SuperTrendATRPeriod);
      if(superTrendAtrHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needAtrStop) {
      atrStopHandle = iATR(_Symbol, _Period, ATRStopPeriod);
      if(atrStopHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(g_UseMACD) {
      macdHandle = iMACD(_Symbol, _Period, MACDFast, MACDSlow, MACDSignal, MACDPrice);
      if(macdHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(g_UseRSI || g_UseCounterTrendModule) {
      rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needAdx) {
      adxHandle = iADX(_Symbol, _Period, ADXPeriod);
      if(adxHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needBoll) {
      bollHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDev, PRICE_CLOSE);
      if(bollHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(g_UseOBV) {
      obvHandle = iOBV(_Symbol, _Period, VOLUME_TICK);
      if(obvHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needCci) {
      cciHandle = iCCI(_Symbol, _Period, Layer2CCIPeriod, PRICE_TYPICAL);
      if(cciHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(needStoch) {
      stochHandle = iStochastic(_Symbol, _Period, StochKPeriod, StochDPeriod, StochSlowing, MODE_SMA, STO_LOWHIGH);
      if(stochHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   // FULL10-only handles. LEAN4 ignores these UseRegime* flags so we do not
   // allocate the unused six voters (plan: no wasted handles on the lean preset).
   if(!Bot1Lean4Active()) {
      if(g_UseRegimeADX) {
         regimeAdxHandle = iADX(_Symbol, _Period, RegimeADXPeriod);
         if(regimeAdxHandle == INVALID_HANDLE) return INIT_FAILED;
      }
      if(g_UseATRBandGate) {
         communityAtrBandHandle = iATR(_Symbol, _Period, ATRBandPeriod);
         if(communityAtrBandHandle == INVALID_HANDLE) return INIT_FAILED;
      }
      if(g_UseATRSpikeFilter) {
         communityAtrSpikeShortHandle = iATR(_Symbol, PERIOD_M1, ATRSpikeShortPeriod);
         communityAtrSpikeLongHandle = iATR(_Symbol, PERIOD_M1, ATRSpikeLongPeriod);
         if(communityAtrSpikeShortHandle == INVALID_HANDLE || communityAtrSpikeLongHandle == INVALID_HANDLE) return INIT_FAILED;
      }
      if(g_UseAsianRangeFilter) {
         communityDailyAtrHandle = iATR(_Symbol, PERIOD_D1, AsianRangeDailyATRPeriod);
         if(communityDailyAtrHandle == INVALID_HANDLE) return INIT_FAILED;
         g_asianRangeTrackedDay = 0;
         g_asianRangeHigh = 0.0;
         g_asianRangeLow = 0.0;
         g_asianRangeWindowSeen = false;
         g_asianRangeVerdictComputed = false;
         g_asianRangeDayAllowed = true;
      }
   }
   if((g_UseRegimeATRRatio && !Bot1Lean4Active()) || UseVolatilityRatio) {
      regimeAtrFastHandle = iATR(_Symbol, _Period, RegimeATRFastPeriod);
      regimeAtrSlowHandle = iATR(_Symbol, _Period, RegimeATRSlowPeriod);
      if(regimeAtrFastHandle == INVALID_HANDLE || regimeAtrSlowHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   // ── REGIME 2.1 continuous score (v2) -- no handles to allocate (ER/CHOP
   // computed directly from price arrays), guarded by its own master switch.
   if(UseRegime21Score) {
      ZeroMemory(g_r21);
   }

   startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ArrayResize(stages, 0);
   ZeroMemory(g_r2);
   g_retestPendingDir = 0;
   g_retestLevel = 0.0;
   g_retestBarsLeft = 0;

   Print("═════════════════════════════════════════");
   Print("bot1_regime2_1 v1.00 Initialized -- NEW ARCHITECTURE BRANCH (forked from regime2.0 v6.22). UseRegime21Score=", UseRegime21Score, " (scaffold: computes+logs only, not yet gating)");
   Print("Magic: ", MagicNumber);
   Print("[BOT1-R2] L1 ticks=", Bot1Layer1TickTag(),
         " g_Layer2RSIMode=", EnumToString(g_Layer2RSIMode),
         " g_UseADXSlope=", g_UseADXSlope, " g_UseLayer2CCI=", g_UseLayer2CCI,
         " g_PreferCCIInTrend=", g_PreferCCIInTrend);
   Print("[BOT1-R2] L3 ticks=", Bot1Layer3TickTag(),
         " g_UseOBV=", g_UseOBV, " g_StopBasisMode=", EnumToString(g_StopBasisMode),
         " g_UseADRExhaustionFilter=", g_UseADRExhaustionFilter,
         " ADRExhaustionPct=", DoubleToString(ADRExhaustionPct, 2));
   Print("[BOT1-R2] regime=", Bot1RegimeTickTag(),
         " g_UseRegimeSuiteGate=", g_UseRegimeSuiteGate,
         " VoteMode=", EnumToString(RegimeSuiteVoteMode));
   Print("[BOT1-R2] CT module=", g_UseCounterTrendModule,
         " RSI_OS/OB=", DoubleToString(CounterTrendRSIOversold, 0), "/", DoubleToString(CounterTrendRSIOverbought, 0),
         " close_inside=", g_RequireCloseBackInsideBand,
         " stoch=", g_UseStochasticTrigger, " vwap_dev=", g_UseVWAPDeviationTrigger);
   if(g_PreferCCIInTrend && !g_UseLayer2CCI)
      Print("[BOT1-R2] WARNING: g_PreferCCIInTrend=true but g_UseLayer2CCI=false — prefer is a no-op.");
   if(Bot1Lean4Active() && !g_UseRegimeSuiteGate)
      Print("[BOT1-R2] NOTE: UseRegimeLEAN4=true but suite gate derived OFF — should not happen; check ResolveArch.");
   if(Bot1Lean4Active())
      Print("[BOT1-R2] LEAN4 force-voters: ADX-slope + CHOP + BB-width-percentile + Session. Other UseRegime* flags IGNORED.");
   if(g_UseVWAPReclaim && VwapAnchorHour < 0)
      Print("[BOT1-R2] WARNING: VwapAnchorHour invalid.");
   if(!g_UseIchimoku && !g_UsePSAR && !g_UseEMACross && !g_UseSuperTrend && !g_UseEMA200Bias)
      Print("[BOT1-LIVE] WARNING: no Layer 1 ticks — EA will not open trades.");
   Print("Stage Exits: ", g_UseStageExits, " ExitMode=", EnumToString(g_ExitMode),
         " TrailAllowed=", Bot1TrailAllowed());
   if(g_UseStageExits) {
      Print("TP1: ", g_TP1_Distance, " pips (", (int)(g_TP1_ClosePercent*100), "%)");
      Print("TP2: ", g_TP2_Distance, " pips (", (int)(g_TP2_ClosePercent*100), "%)");
      Print("Trailing: ", TrailingDistance, " pips");
   }
   Print("Entry Mode: ", UseStrictLayers ? "STRICT" : "FLEXIBLE");
   Print("Volatility Filters: ENABLED");
   Print("Legend: LEFT=", ShowLeftLegend, " RIGHT=", ShowRightLegend);
   Print("BOT1 Candidates Log: ", LogBot1Candidates ? "ON" : "OFF", " | BOT1 Trades Log: ", LogBot1Trades ? "ON" : "OFF");
   Print("LIVE GATE: L1", g_RequireL2ForLive ? "+L2" : "", g_RequireL3ForLive ? "+L3" : "",
         (!g_RequireL2ForLive && !g_RequireL3ForLive) ? " ONLY (POC default)" : " (promoted by param_advisor)");
   Print("Regime Kill Switch: ", UseRegimeKillSwitch ? "ON" : "OFF",
         " | Regime Suite Gate: ", g_UseRegimeSuiteGate ? "ON" : "OFF",
         " | Vote Mode: ", EnumToString(RegimeSuiteVoteMode),
         " | Range Mode Adaptation: ", UseRangeModeAdaptation ? "ON" : "OFF");
   if(g_UseRegimeSuiteGate) {
      if(Bot1Lean4Active()) {
         Print("  Regime Suite filters active: LEAN4 force ADX-slope CHOP BB-width-pctile Session (UseRegime* flags ignored)");
      } else {
         Print("  Regime Suite filters active: ",
               g_UseRegimeADX ? "ADX " : "", g_UseRegimeER ? "ER " : "", g_UseRegimeCHOP ? "CHOP " : "",
               g_UseRegimeLinReg ? "LinReg " : "", g_UseRegimeATRRatio ? "ATRRatio " : "",
               g_UseRegimeMMI ? "MMI " : "", g_UseRegimeSession ? "Session " : "",
               g_UseATRBandGate ? "ATRBand " : "", g_UseATRSpikeFilter ? "ATRSpike " : "",
               g_UseAsianRangeFilter ? "AsianRange " : "",
               (!g_UseRegimeADX && !g_UseRegimeER && !g_UseRegimeCHOP && !g_UseRegimeLinReg &&
                !g_UseRegimeATRRatio && !g_UseRegimeMMI && !g_UseRegimeSession &&
                !g_UseATRBandGate && !g_UseATRSpikeFilter && !g_UseAsianRangeFilter) ? "(none -- gate is a no-op)" : "");
      }
   }
   if(g_UseCounterTrendModule) {
      Print("[BOT1-R2-CT] requested SL/TP=", RangeModeSL_Points, "/", RangeModeTP_Points,
            " pts; legal min SL=", (Bot1SpreadPts() + Bot1EffectiveStopsLevelPts() + 5),
            " (spread+", Bot1EffectiveStopsLevelPts(), "+5) TP=", (Bot1EffectiveStopsLevelPts() + 5));
   }
   Print("═════════════════════════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTester — custom "Complex Criterion" for genetic optimization   |
//| Ported from bot4_TREND_FX_v1_2.mq5's OnTester() (2026-06-30       |
//| pattern there). Same four disqualifying gates (min trades, max    |
//| DD%, positive profit, min avg-R/trade) plus a profit-factor cap   |
//| so one fluke trade can't dominate the score, and a sample-size    |
//| confidence weighting so the optimizer doesn't just reward raw     |
//| trade COUNT. Select "Complex Criterion max" in Tester > Settings  |
//| to use this.                                                      |
//|                                                                    |
//| ADAPTATION FROM BOT4, NOT A BLIND COPY: bot4 always sizes by a    |
//| fixed % of equity (RiskPercentL1), so "expected payoff / (balance |
//| x risk%)" is a clean, always-valid R-multiple. bot1 defaults to   |
//| LotType=LOT_FIXED (fixed lot size, not risk-based) -- under fixed |
//| sizing, RiskPercent isn't actually the fraction of equity risked  |
//| per trade, so treating it as one would silently misclassify runs. |
//| The avg-R gate below is therefore only APPLIED when LotType==     |
//| LOT_RISK, where the bot4-style calculation is actually valid; in  |
//| LOT_FIXED mode it's skipped (not faked), and the other four gates |
//| (trades/DD/profit/PF) still apply in either mode.                 |
//+------------------------------------------------------------------+
input group "═══ 2.2 MISC / LEGACY (non-essential for wide sweeps, see header) ═══"
// Relocated to the bottom of the input list per the 2.2 branch directive:
// all Regime21-prefixed inputs are either a prototype scaffold
// (UseRegime21Score/Classifier both default false, confirmed inert at
// those defaults by the PARDO sweep's own dead-parameter detection) or
// narrow per-pattern risk multipliers validated on small samples -- none
// of this is a core L1/L2/L3/Regime-Suite toggle a wide sweep needs easy
// access to. Left fully intact and still independently switchable -- a
// wide sweep CAN still reach these inputs, they are just not cluttering
// the top of the input list where the 37 core Use* booleans now live.
input bool   UseRegime21Score = false;      // master switch for the continuous regime score (inert until wired into entry/exit logic)
input double Regime21MinScoreToTrade = 0.0; // entry gate threshold. Signal is suppressed when composite_score < this. 0.0 = gate is a no-op.
input int    Regime21ERPeriod = 14;          // Kaufman Efficiency Ratio lookback (own copy, independent of the Regime Suite's UseRegimeER toggle)
input int    Regime21CHOPPeriod = 14;        // Choppiness Index lookback (own copy, independent of UseRegimeCHOP)
input int    Regime21SessionStartHour = 7;   // broker/server time, session score peaks inside [Start,End]
input int    Regime21SessionEndHour = 16;
input int    Regime21SessionTaperHours = 4;  // hours either side of the window over which the session score linearly decays to 0
input int    Regime21ADXPeriod = 14;        // trend-strength component (Wilder ADX, raw value not a cutoff)
input int    Regime21ADXSlopeBars = 5;      // bars back for ADX slope (rising ADX = strengthening trend)
input int    Regime21ATRPctileLookback = 200; // bars for ATR percentile-rank component (volatility regime, continuous 0-100)
input int    Regime21ATRPeriod = 14;
input double Regime21WeightER = 0.4;        // blend weights (should sum to ~1.0; kept separate so each can be swept independently). Efficiency Ratio: high = clean directional move
input double Regime21WeightCHOP = 0.3;      // Choppiness Index (inverted -- low CHOP/uncongested = high score contribution)
input double Regime21WeightSession = 0.3;   // session/liquidity timing: high inside the configured active window
input bool   LogRegime21Diagnostics = true; // one line per bar with raw ER/CHOP/session + blended score
input bool   UseRegime21Classifier = false;   // master switch, off by default: zero cost/behavior change unless enabled
input int    Regime21BucketMajority = 4;      // votes (out of up to 6 active voters) needed to call TREND or CHOP; between = MIXED
input bool   LogRegime21BucketCsv = true;     // one line per bar: each voter's raw verdict + the final bucket label
input bool   Regime21ClassifierPassiveOnly = true; // SAFETY: when true, force g_UseRegimeSuiteGate=false even if the underlying voters are turned on for the classifier to read
input double Regime21ChopSizeMultiplier = 1.0; // risk-size multiplier for CHOP-bucket entries. Default 1.0 = no-op. SAMPLE SIZE WARNING: validated on only 27 trades.
input double Regime21DisagreeSizeMultiplier = 1.0; // risk-size multiplier for DISAGREE-direction entries. Default 1.0 = no-op. Validated on 555 trades (p=0.0043), several sub-slices borderline.
input double Regime21SlopeGoodSizeMultiplier = 1.0; // risk-size multiplier for 2 confirmed GOOD multi-timeframe-slope SELL patterns. Default 1.0 = no-op.
input double Regime21SlopeBadSizeMultiplier = 1.0; // risk-size multiplier for 1 confirmed BAD multi-timeframe-slope SELL pattern. Default 1.0 = no-op; values <1.0 intended to REDUCE size.

input group "═══ SCORE_WINRATE: directional-accuracy score (PORTED FROM 2.0, 2026-10-11) ═══"
// User ask (originally 2026-10-09 on 2.0): "biggest issue is if we are in right direction and not in
// the final second of the swing" -- i.e. rank configs by how often the EA calls direction correctly,
// separated from how big the subsequent swing is ridden out for. Pure win-rate alone is a known
// exploit (see SCORE_PARDO's own header comment: SCORE_RF_SOFT once picked a 100%-win-rate/0-loss/
// 42-trade config over configs making 6-10x more real money) -- a config can trivially hit a
// near-100% win rate by setting TP1 a few points from entry, "winning" on noise without the market
// ever really testing the position. WinRateMinAvgR is the anti-exploit floor: a trade only counts
// toward win-rate confidence once the config has demonstrated it captures a MEANINGFUL R-multiple on
// average, not a token one. "Win" = the position's net final P&L (STAT_PROFIT_TRADES/STAT_LOSS_TRADES,
// same stats MT5 already tracks) is positive -- simplest definition, matches what every other score
// mode already measures trade-by-trade, not a staged TP1/TP2-granular rate.
// PORT NOTE (2026-10-11): byte-identical logic/defaults to 2.0's SCORE_WINRATE -- ported so a sweep on
// this EA can use the same win-rate-maximizing criterion that found the 1250/816/667/3257/4099/etc
// candidates on 2.0, now combined with 2.2's own RegimeConfirmBars persistence filter (native to this
// EA, not part of this port) to test whether some 2.0 floor-rejected candidates were partly bar-flip
// noise rather than a real edge ceiling. Zero behavior change for any existing .set file unless
// OptScoreMode is deliberately set to SCORE_WINRATE.
input int    OptWinRateMinTrades  = 30;    // disqualify runs with too few trades (stat noise) -- same
                                            // role as OptMinTrades/OptPardoMinTrades, own input so this
                                            // mode's threshold can be tuned independently
input double OptWinRateMinAvgR    = 0.10;  // min expected R/trade (STAT_EXPECTED_PAYOFF / risked-$-per-
                                            // trade) -- the anti-"token TP" floor described above. Uses
                                            // RiskPercent-implied $ risk regardless of LotType (unlike
                                            // OptMinAvgR above, which only fires under LotType=LOT_RISK)
                                            // so this mode's floor always applies.
input double OptWinRateMaxDDPct   = 3.5;   // hard equity-DD cap, % -- same role/value as OptMaxDDPctAllowed,
                                            // own input so this mode doesn't silently share state with others

input group "═══ OPTIMIZATION CRITERION (Strategy Tester only) ═══"
input ENUM_OPT_SCORE OptScoreMode = SCORE_RF_SOFT;  // RF_SOFT default; LEGACY = old profit×PF formula
input int    OptMinTrades        = 30;    // disqualify runs with too few trades (stat noise)
input double OptMaxDDPctAllowed  = 3.5;   // v5.95 (2026-08-30): tightened 5.0 -> 3.5 after real-tick verification of the best v5.94 MAJORITY candidate (pass 323) showed modeled "Every tick" DD of 4.72% understated real-tick DD by ~1.5pt (actual 6.30%, breached the 5.0 gate and returned OnTester=0). FTMO's actual overall-loss ceiling is 10% -- 3.5% leaves a real margin against both the FTMO limit AND the observed modeled-vs-real gap, instead of gating right at the edge where a genetic search naturally clusters (52% of prior MAJORITY-qualified candidates sat within 0.5% of the old 5.0 ceiling).
input double OptMaxPFCap         = 5.0;   // cap PF contribution so one huge fluke trade can't dominate
input double OptMinAvgR          = 0.05;  // min expected R/trade -- only enforced under LotType=LOT_RISK; v5.97: recalibrated 0.30 -> 0.05, see note above CalculateLotSize's avg-R gate for why 0.30 was both scale-broken and too strict for this EA's staged-exit architecture
input bool   UseUlcerPenalty     = true;  // v5.2: penalize sustained/deep drawdown periods specifically, not just the single worst DD (OptMaxDDPctAllowed) -- targets the "grinds down for months" equity-curve shape directly. See CalculateUlcerIndex() below.
input double OptUlcerFloor       = 1.0;   // floor for the Ulcer Index divisor, avoids divide-by-near-zero on an almost perfectly smooth equity curve

input group "═══ SCORE_PARDO: pessimistic-profit + Sterling cushion + hard DD gate (2026-09-27) ═══"
// Built after finding our SCORE_RF_SOFT/ratio-based scoring picked a config with a
// 100% win rate (0 losses / 42 trades) over configs making 6-10x more real money
// -- confirmed via research that a pure ratio can't distinguish "genuinely low risk"
// from "unverifiable small sample". Pardo's Pessimistic Return solves this directly by
// shrinking the win count and inflating the loss count by their standard errors before
// computing profit, so a small/zero-loss sample gets discounted on the PROFIT term
// itself, not just via the trade-count ramp. See bossafx-performance skill for the
// full research summary and validation against 8 real logged verify runs.
input double OptPardoDDCapPct     = 5.0;    // hard equity-DD cap, % (below this: no DD penalty at all)
input int    OptPardoMinTrades    = 100;    // below this trade count: graded rejection (2026-09-27: Pardo score needs a bigger sample before trusting it at all)
input int    OptPardoFullTrades   = 200;    // trade count for FULL confidence weight (~8mo window means 200 trades = fully validated)
input double OptPardoSterlingCushion = 10.0; // Sterling ratio's original cushion (Deane Sterling Jones, 1981)
input double OptPardoMinImputedLoss  = 1.0;  // minimum imputed loss count when a candidate has ZERO observed losses (prevents PF=inf/undiscounted zero-loss passes)

input group "═══ SPREAD/SLIPPAGE REALISM PENALTY (2026-09-26) ═══"
// Same rationale as bot1_regime2.0 -- see that file's comment for detail.
input bool   UseSpreadSlippagePenalty = true;   // master on/off -- off reproduces the pre-2026-09-26 scoring exactly
input double OptAssumedSpreadPoints   = 60.0;   // CORRECTED 2026-09-26: real observed GOLD_test spread is 57-64pts (median ~60), per spread_pts_at_entry logged on 19 real bot1r21 trades. Previous default of 550 was a unit-confusion error, ~9x too harsh.
input double OptAssumedSlippagePoints = 15.0;   // modest ~25% buffer over the observed spread
input double OptAssumedLotForPenalty  = 0.05;   // typical live lot size -- $ conversion only, does not affect real position sizing

double Bot1EstimateSpreadSlippageCost(double numTrades) {
   if(!UseSpreadSlippagePenalty || numTrades <= 0) return 0.0;
   double pointCostPerLot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                             MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / _Point, 1.0);
   double costPerTrade = (OptAssumedSpreadPoints + OptAssumedSlippagePoints) * pointCostPerLot * OptAssumedLotForPenalty;
   return numTrades * costPerTrade;
}

input group "═══ ANTI-CONCENTRATION SCORING (v2 AGILE, 2026-09-06, ported from bot4) ═══"
// bot4's optimization project found repeatedly that Profit/PF/DD/trade-
// count alone cannot distinguish "genuinely edge-driven" from "a couple of
// lucky tail-event days dominated the whole result" -- one bot4 candidate
// scored a headline-record PF13.18 with 77% of total profit from just 2 of
// 8 active trading days. bot1 has never been checked for this. Soft
// proportional penalty (not a hard gate) -- a config with a couple of
// genuinely large winners should still score SOMETHING, just not full
// marks, so the genetic algorithm keeps a real gradient across the search
// space instead of a wall of hard zeros (bot4 learned this the hard way
// too: an earlier hard-gated version gave the optimizer no signal to climb).
input bool   UseConcentrationPenalty   = true;
input double OptMaxDayConcentrationPct = 40.0;  // soft target: no single calendar day should exceed this % of TOTAL realized profit

// v5.3 (2026-08-28): FTMO-style prop-firm accounts gate on TWO separate DD
// rules -- overall relative DD (OptMaxDDPctAllowed above) AND a per-CALENDAR-
// DAY loss limit, usually the tighter/first-tripped of the two in practice.
// STAT_EQUITY_DDREL_PERCENT only ever reports the single worst peak-to-
// trough across the WHOLE test, so it can silently pass a run that blew a
// daily limit mid-test but recovered later in the same run. This gate
// reconstructs daily P&L from closed-deal history (same technique as
// CalculateUlcerIndex() below) and disqualifies any run where a single
// calendar day's loss (from that day's own starting balance) exceeds
// OptMaxDailyDDPctAllowed. Defaults ON since this directly encodes the
// FTMO-style daily-loss rule the user actually trades under -- set false
// to fall back to overall-DD-only gating (pre-v5.3 behavior).
input bool   UseDailyDDGate           = true;  // gate on worst single-calendar-day loss %, not just overall relative DD
input double OptMaxDailyDDPctAllowed  = 5.0;   // disqualify runs where any single calendar day lost more than this % of that day's starting balance (FTMO daily-loss-limit proxy)

// v5.2: Ulcer Index (Peter Martin, 1987) -- reconstructs the equity curve
// from the test's closed-deal history (OnTester() has no direct access to
// a per-tick/per-bar equity series, so per-deal is the finest granularity
// available post-test, and is standard practice for this kind of metric).
// At each deal, tracks drawdown% from the running peak, squares it, and
// averages across all deals -- squaring means a long, deep decline
// contributes far more than a few brief dips, which is deliberately
// different from OptMaxDDPctAllowed above (that gate only caps the SINGLE
// worst drawdown; this measures how much total TIME the curve spent in
// pain, and by how much). A curve that's allowed to oscillate but trends
// up scores well here; a curve that grinds down for months before
// recovering scores poorly, even if its single worst drawdown never
// breaches OptMaxDDPctAllowed.
double CalculateUlcerIndex() {
   if(!HistorySelect(0, TimeCurrent())) return 0.0;
   int totalDeals = HistoryDealsTotal();
   if(totalDeals <= 1) return 0.0;

   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double peak = balance;
   double sumSqDD = 0.0;
   int sampleCount = 0;

   for(int i = 0; i < totalDeals; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      // Only deals that actually move the account (entry deals carry zero
      // profit and would just add noise samples at DD=0 -- harmless either
      // way since they don't change balance, but skip for a cleaner signal).
      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                         + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                         + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      if(dealProfit == 0.0) continue;

      balance += dealProfit;
      if(balance > peak) peak = balance;
      double ddPct = (peak > 0.0) ? (peak - balance) / peak * 100.0 : 0.0;
      sumSqDD += ddPct * ddPct;
      sampleCount++;
   }
   if(sampleCount == 0) return 0.0;
   return MathSqrt(sumSqDD / sampleCount);
}

// v5.3 (2026-08-28): worst single-calendar-day loss %, reconstructed from
// closed-deal history exactly like CalculateUlcerIndex() above, but bucketed
// by calendar day (broker/server time, via TimeToStruct) instead of tracked
// continuously. Each day's "starting balance" is the running balance as of
// that day's first deal -- this is a same-day, same-account-size proxy for
// a prop-firm daily-loss-limit check, not an official FTMO API value (FTMO
// itself computes off midnight-server-time equity/balance snapshots this
// EA doesn't have from Strategy Tester deal history alone -- close enough
// for optimization-time screening, not a substitute for verifying an actual
// candidate run against the real daily-loss rule before going live with it).
double CalculateWorstDailyDDPct() {
   if(!HistorySelect(0, TimeCurrent())) return 0.0;
   int totalDeals = HistoryDealsTotal();
   if(totalDeals <= 1) return 0.0;

   double balance = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double worstDayPct = 0.0;

   int    curDayKey = -1;
   double dayStartBalance = balance;
   double dayLowBalance   = balance;

   for(int i = 0; i < totalDeals; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                         + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                         + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      if(dealProfit == 0.0) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      MqlDateTime dt;
      TimeToStruct(dealTime, dt);
      int dayKey = dt.year * 10000 + dt.mon * 100 + dt.day;

      if(dayKey != curDayKey) {
         // day rolled -- close out the previous day's worst excursion first
         if(curDayKey != -1 && dayStartBalance > 0.0) {
            double ddPct = (dayStartBalance - dayLowBalance) / dayStartBalance * 100.0;
            if(ddPct > worstDayPct) worstDayPct = ddPct;
         }
         curDayKey = dayKey;
         dayStartBalance = balance;   // balance as of this new day's first deal
         dayLowBalance   = balance;
      }

      balance += dealProfit;
      if(balance < dayLowBalance) dayLowBalance = balance;
   }
   // close out the final day
   if(curDayKey != -1 && dayStartBalance > 0.0) {
      double ddPct = (dayStartBalance - dayLowBalance) / dayStartBalance * 100.0;
      if(ddPct > worstDayPct) worstDayPct = ddPct;
   }
   return worstDayPct;
}

// v2 AGILE (2026-09-06): ported from bot4's anti-concentration OnTester
// penalty (see bot4_EA_Optimization_Knowledge.md §4/§9). bot4's history is
// the direct motivation: a "record" PF13.18 candidate turned out to have
// 77% of its total profit concentrated in just 2 out of 8 active trading
// days -- textbook overfit that Profit/PF/DD/trade-count alone could not
// distinguish from genuine edge. bot1 has never been audited for this
// specific failure mode; adding the guard now, preemptively, rather than
// waiting to discover it the same expensive way bot4 did.
//
// Reuses the exact per-day bucketing technique CalculateWorstDailyDDPct()
// above already established (HistorySelect + HistoryDealsTotal, dayKey via
// TimeToStruct) -- walks the SAME closed-deal history a second time to
// group REALIZED profit (not running balance/DD, profit itself) by
// calendar day, then reports what fraction of TOTAL profit the single
// biggest day represents.
double CalculateMaxDayConcentrationPct() {
   if(!HistorySelect(0, TimeCurrent())) return 0.0;
   int totalDeals = HistoryDealsTotal();
   if(totalDeals <= 1) return 0.0;

   // Map is small (a handful to a few hundred distinct trading days over
   // an 8-month test) -- linear-scan arrays are fine, no need for a hash
   // structure in MQL5 for this size.
   int    dayKeys[];
   double dayProfits[];
   int    dayCount = 0;
   double totalProfit = 0.0;

   for(int i = 0; i < totalDeals; i++) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                         + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                         + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      if(dealProfit == 0.0) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      MqlDateTime dt;
      TimeToStruct(dealTime, dt);
      int dayKey = dt.year * 10000 + dt.mon * 100 + dt.day;

      int idx = -1;
      for(int j = 0; j < dayCount; j++) {
         if(dayKeys[j] == dayKey) { idx = j; break; }
      }
      if(idx == -1) {
         idx = dayCount;
         dayCount++;
         ArrayResize(dayKeys, dayCount);
         ArrayResize(dayProfits, dayCount);
         dayKeys[idx] = dayKey;
         dayProfits[idx] = 0.0;
      }
      dayProfits[idx] += dealProfit;
      totalProfit += dealProfit;
   }

   if(dayCount == 0 || totalProfit <= 0.0) return 0.0;   // no profitable days -- concentration is moot, OnTester's own profit_pct<=0 gate already disqualifies

   double maxDayProfit = 0.0;
   for(int j = 0; j < dayCount; j++) {
      if(dayProfits[j] > maxDayProfit) maxDayProfit = dayProfits[j];
   }
   return (maxDayProfit / totalProfit) * 100.0;
}

double Bot1OnTesterLegacy() {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < OptMinTrades) return 0.0;

   double max_dd_pct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(!MathIsValidNumber(max_dd_pct) || max_dd_pct > OptMaxDDPctAllowed)
      return 0.0;

   if(UseDailyDDGate) {
      double worst_daily_dd_pct = CalculateWorstDailyDDPct();
      if(!MathIsValidNumber(worst_daily_dd_pct) || worst_daily_dd_pct > OptMaxDailyDDPctAllowed)
         return 0.0;
   }

   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   if(!MathIsValidNumber(pf) || pf <= 0) return 0.0;
   pf = MathMin(pf, OptMaxPFCap);

   double init_bal   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double net_profit = TesterStatistics(STAT_PROFIT);
   net_profit -= Bot1EstimateSpreadSlippageCost(trades);  // 2026-09-26: realism penalty
   double profit_pct = (init_bal > 0) ? net_profit / init_bal * 100.0 : 0.0;
   if(profit_pct <= 0) return 0.0;

   if(LotType == LOT_RISK && RiskPercent > 0) {
      double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
      double avg_r = (init_bal > 0) ? expected_payoff / (init_bal * RiskPercent / 100.0) : 0.0;
      if(avg_r < OptMinAvgR) return 0.0;
   }

   double sample_conf = MathSqrt(MathMin(trades, 200.0));
   double dd_penalty   = MathMax(max_dd_pct, 1.0);
   double score = profit_pct * pf * sample_conf / dd_penalty;

   if(UseUlcerPenalty) {
      double ulcer = CalculateUlcerIndex();
      double ulcer_penalty = MathMax(ulcer, OptUlcerFloor);
      score = score / ulcer_penalty;
   }

   if(UseConcentrationPenalty) {
      double max_day_pct = CalculateMaxDayConcentrationPct();
      if(max_day_pct > OptMaxDayConcentrationPct) {
         double excess = max_day_pct - OptMaxDayConcentrationPct;
         double concentration_penalty = 1.0 + (excess / 25.0);
         score = score / concentration_penalty;
      }
   }
   return score;
}

double Bot1SoftRampOverCap(double value, double cap) {
   if(!MathIsValidNumber(value) || cap <= 0.0) return 1.0;
   if(value <= cap) return 1.0;
   double over = (value - cap) / cap;
   return 1.0 / (1.0 + over * over * 8.0);
}

double Bot1ApplyConcentrationSoft(double score) {
   if(!UseConcentrationPenalty) return score;
   double max_day_pct = CalculateMaxDayConcentrationPct();
   if(max_day_pct > OptMaxDayConcentrationPct) {
      double excess = max_day_pct - OptMaxDayConcentrationPct;
      score = score / (1.0 + (excess / 25.0));
   }
   return score;
}

// SCORE_PARDO helper -- 2026-09-27. See bot1_regime2.0.mq5 for full rationale.
double Bot1CalcPardoPessimisticProfitPct(double trades) {
   double deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
   double grossLoss   = MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   double W = TesterStatistics(STAT_PROFIT_TRADES);
   double L = TesterStatistics(STAT_LOSS_TRADES);
   if(deposit <= 0.0) return 0.0;

   double avgWin  = (W > 0.0) ? grossProfit / W : 0.0;
   double avgLoss = (L > 0.0) ? grossLoss / L : avgWin;

   double Wp = MathMax(W - MathSqrt(W), 0.0);
   double Lp = L + MathMax(MathSqrt(L), OptPardoMinImputedLoss);

   double pessimisticProfit = avgWin * Wp - avgLoss * Lp;
   // 2026-09-27 BUGFIX: subtract the same friction estimate applied to
   // net_profit elsewhere -- STAT_GROSS_PROFIT/LOSS never see it.
   pessimisticProfit -= Bot1EstimateSpreadSlippageCost(trades);
   return (pessimisticProfit / deposit) * 100.0;
}

double OnTester() {
   if(OptScoreMode == SCORE_LEGACY)
      return Bot1OnTesterLegacy();

   double trades = TesterStatistics(STAT_TRADES);
   double max_dd_pct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double init_bal   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double net_profit = TesterStatistics(STAT_PROFIT);
   net_profit -= Bot1EstimateSpreadSlippageCost(trades);  // 2026-09-26: realism penalty
   double profit_pct = (init_bal > 0) ? net_profit / init_bal * 100.0 : 0.0;
   if(!MathIsValidNumber(max_dd_pct) || max_dd_pct < 0.0) max_dd_pct = 0.0;

   double tradesRamp = 1.0;
   if(OptMinTrades > 0 && trades < OptMinTrades)
      tradesRamp = 0.01 + 0.99 * (trades / (double)OptMinTrades);

   double ddRamp = Bot1SoftRampOverCap(max_dd_pct, OptMaxDDPctAllowed);
   double dailyRamp = 1.0;
   if(UseDailyDDGate)
      dailyRamp = Bot1SoftRampOverCap(CalculateWorstDailyDDPct(), OptMaxDailyDDPctAllowed);

   double sample_conf = MathSqrt(MathMin(trades, 100.0));
   double score = 0.0;

   if(OptScoreMode == SCORE_PARDO) {
      if(trades < OptPardoMinTrades) {
         return -1000.0 + trades;
      }
      double pessPct = Bot1CalcPardoPessimisticProfitPct(trades);
      if(pessPct <= 0.0) {
         return pessPct;
      }
      double tw      = MathMin(trades / MathMax(OptPardoFullTrades, 1), 1.0);
      double ddGate   = (max_dd_pct <= OptPardoDDCapPct) ? 1.0
                        : MathMax(0.0, 1.0 / (1.0 + 2.0 * (max_dd_pct - OptPardoDDCapPct) / OptPardoDDCapPct));
      double sterling = OptPardoSterlingCushion / (OptPardoSterlingCushion + max_dd_pct);
      score = pessPct * tw * ddGate * sterling;
      score = Bot1ApplyConcentrationSoft(score);
      return score;
   }

   if(OptScoreMode == SCORE_WINRATE) {
      // PORTED FROM 2.0 (2026-10-11), byte-identical logic. Pure directional-accuracy score: % of
      // trades with positive net final P&L, gated by a minimum avg-R/trade floor (anti-"token TP"
      // exploit, see input group comment above) and the standard trade-count/DD safety rails every
      // other mode already uses.
      if(trades < OptWinRateMinTrades)
         return -1000.0 + trades;  // graded rejection, same shape as SCORE_PARDO's min-trades gate

      double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
      double risk_usd = (init_bal > 0 && RiskPercent > 0) ? init_bal * RiskPercent / 100.0 : 0.0;
      double avg_r = (risk_usd > 0) ? expected_payoff / risk_usd : 0.0;
      if(avg_r < OptWinRateMinAvgR)
         return avg_r;  // below the meaningful-R floor -- reject with a gradient the GA can still
                         // climb (less negative avg_r is "closer" to qualifying), not a flat wall

      double W = TesterStatistics(STAT_PROFIT_TRADES);
      double winPct = (trades > 0) ? (W / trades) * 100.0 : 0.0;

      double ddGate = (max_dd_pct <= OptWinRateMaxDDPct) ? 1.0
                      : MathMax(0.0, 1.0 / (1.0 + 2.0 * (max_dd_pct - OptWinRateMaxDDPct) / OptWinRateMaxDDPct));
      score = winPct * tradesRamp * ddGate;
      score = Bot1ApplyConcentrationSoft(score);
      return score;
   }

   if(OptScoreMode == SCORE_UPI) {
      double ulcer = CalculateUlcerIndex();
      double ui = MathMax(ulcer, OptUlcerFloor);
      if(ui < 0.1) ui = 0.1;
      score = profit_pct / ui * sample_conf * tradesRamp * ddRamp * dailyRamp;
   } else {
      // SCORE_RF_SOFT: one profitability term, one DD term, SQN-style sqrt(N) cap 100. No PF.
      double ddTerm = MathMax(max_dd_pct, 0.1);
      score = profit_pct / ddTerm * sample_conf * tradesRamp * ddRamp * dailyRamp;
   }

   score = Bot1ApplyConcentrationSoft(score);
   return score;
}


//+------------------------------------------------------------------+
//| OnDeinit                                                         
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DeleteLegendObjects();

   if(ichimokuHandleHTF != INVALID_HANDLE) IndicatorRelease(ichimokuHandleHTF);
   if(ichimokuHandleCur != INVALID_HANDLE) IndicatorRelease(ichimokuHandleCur);
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(psarHandle != INVALID_HANDLE) IndicatorRelease(psarHandle);
   if(macdHandle != INVALID_HANDLE) IndicatorRelease(macdHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(bollHandle != INVALID_HANDLE) IndicatorRelease(bollHandle);
   if(obvHandle != INVALID_HANDLE) IndicatorRelease(obvHandle);
   if(superTrendAtrHandle != INVALID_HANDLE) IndicatorRelease(superTrendAtrHandle);
   if(atrStopHandle != INVALID_HANDLE) IndicatorRelease(atrStopHandle);
   if(cciHandle != INVALID_HANDLE) IndicatorRelease(cciHandle);
   if(stochHandle != INVALID_HANDLE) IndicatorRelease(stochHandle);
   if(regimeAdxHandle != INVALID_HANDLE) IndicatorRelease(regimeAdxHandle);
   if(regimeAtrFastHandle != INVALID_HANDLE) IndicatorRelease(regimeAtrFastHandle);
   if(regimeAtrSlowHandle != INVALID_HANDLE) IndicatorRelease(regimeAtrSlowHandle);
   if(communityAtrBandHandle != INVALID_HANDLE) IndicatorRelease(communityAtrBandHandle);
   if(communityAtrSpikeShortHandle != INVALID_HANDLE) IndicatorRelease(communityAtrSpikeShortHandle);
   if(communityAtrSpikeLongHandle != INVALID_HANDLE) IndicatorRelease(communityAtrSpikeLongHandle);
   if(communityDailyAtrHandle != INVALID_HANDLE) IndicatorRelease(communityDailyAtrHandle);

   // PERF FIX: close the four persistent log handles opened via
   // Bot1GetLogHandle -- these were previously reopened/closed on every
   // single row write; now held open for the EA's lifetime and closed once
   // here.
   if(g_candidateLogHandle   != INVALID_HANDLE) FileClose(g_candidateLogHandle);
   if(g_tradeLogHandle       != INVALID_HANDLE) FileClose(g_tradeLogHandle);
   if(g_postmortemLogHandle  != INVALID_HANDLE) FileClose(g_postmortemLogHandle);
   if(g_shadowTradeLogHandle != INVALID_HANDLE) FileClose(g_shadowTradeLogHandle);
   if(g_heartbeatLogHandle   != INVALID_HANDLE) FileClose(g_heartbeatLogHandle);
   if(g_regimeEventLogHandle != INVALID_HANDLE) FileClose(g_regimeEventLogHandle);
   if(g_shadowOutcomeLogHandle != INVALID_HANDLE) FileClose(g_shadowOutcomeLogHandle);
   if(g_r2DiagLogHandle        != INVALID_HANDLE) FileClose(g_r2DiagLogHandle);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction -- captures FINAL close reason (SL/manual/    |
//| opposite-close) that ManageStagedProfits cannot see, since by    |
//| the time a position is gone it's too late to read its state.    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result) {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   ulong posTicketEarly = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   long rawDealMagic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   // v2 AGILE BUG FIX (found during smoke test, 2026-09-06): confirmed
   // directly that MT5's DEAL_MAGIC on a broker/server-triggered SL/TP
   // close does NOT reliably carry the original position's magic (a
   // counter-trend position opened under magic 55221 had its SL-hit CLOSE
   // deal reported under magic 54321, the trend side's MagicNumber). Look
   // up the magic WE recorded at open time first (Bot1TrackPositionMagic);
   // only fall back to the deal's own (possibly-wrong) DEAL_MAGIC if this
   // ticket was never tracked (e.g. a pre-v2-AGILE-restart open position).
   long trackedMagic = Bot1LookupTrackedMagic(posTicketEarly);
   long dealMagic = (trackedMagic >= 0) ? trackedMagic : rawDealMagic;
   // also accept the counter-trend module's own magic
   // (MagicNumber+CounterTrendMagicOffset) so ITS closes get logged and
   // (critically) trigger the SAME cooldown-after-SL protection the trend
   // side already has -- previously this filter only matched MagicNumber
   // exactly, which would have silently dropped every counter-trend close
   // from the trade log AND left it with zero cooldown enforcement.
   bool isTrendMagic = (dealMagic == (long)MagicNumber);
   bool isCounterTrendMagic = (g_UseCounterTrendModule && dealMagic == (long)Bot1CounterTrendMagic());
   if(!isTrendMagic && !isCounterTrendMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if(Bot1WasDealLogged(trans.deal)) return;  // already logged manually (TP1/TP2/final-close-target) -- prevents double-counted P&L

   double dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double dealPrice  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double dealComm   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double dealSwap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
   ulong posTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   string reasonStr;
   switch(dealReason) {
      case DEAL_REASON_SL:      reasonStr = "SL_HIT"; break;
      case DEAL_REASON_TP:      reasonStr = "TP_HIT"; break;
      case DEAL_REASON_CLIENT:  reasonStr = "MANUAL_OR_TRAIL"; break;
      case DEAL_REASON_EXPERT:  reasonStr = "EXPERT_CLOSE"; break;
      default:                  reasonStr = "OTHER"; break;
   }
   // NOTE: this only fires for deals we did NOT manually log -- i.e. broker-
   // initiated closes (SL hit, TP hit, external manual close). Deals we
   // closed ourselves (TP1/TP2 partials, final-close-target) are marked via
   // Bot1MarkDealLogged() and skipped above, since DEAL_ENTRY_OUT fires for
   // partial closes too and would otherwise double-count their P&L.
   // NOTE: pnl_usd here is dealProfit ONLY (gross) -- commission/swap now
   // logged in their own columns instead of being silently summed in.
   // v2 AGILE: the counter-trend module has no MFE/MAE/stage tracking of
   // its own (deliberately simple, fixed-bracket exits) -- these calls are
   // harmless no-ops for a ticket they were never told about, same as they
   // already are for any ticket without a tracked slot.
   double mfePx = 0, maePx = 0;
   int barsToMfePx = 0, barsToMaePx = 0;
   Bot1GetMFEMAE(posTicket, mfePx, maePx, barsToMfePx, barsToMaePx);
   // CONSECUTIVE LOSS TRACKER update (2026-09-19): this fires on the FINAL
   // close of the position (SL/TP/manual/expert), same event that already
   // triggers Bot1ReleaseMFESlot() below -- sum ALL deals tied to this
   // position (TP1/TP2 partials + this final leg) via HistorySelectByPosition
   // to get the true net result, not just this last deal's profit (which
   // would misclassify a position that took partial profit then stopped out
   // net-positive as a "loss" just because the LAST leg was a small SL hit).
   double positionNetProfit = 0.0;
   if(HistorySelectByPosition(posTicket)) {
      int dealCount = HistoryDealsTotal();
      for(int di = 0; di < dealCount; di++) {
         ulong dTkt = HistoryDealGetTicket(di);
         if(dTkt == 0) continue;
         positionNetProfit += HistoryDealGetDouble(dTkt, DEAL_PROFIT)
                             + HistoryDealGetDouble(dTkt, DEAL_COMMISSION)
                             + HistoryDealGetDouble(dTkt, DEAL_SWAP);
      }
   } else {
      positionNetProfit = dealProfit;  // fallback: at least this leg's profit
   }
   if(positionNetProfit > 0) g_consecLosses = 0;
   else if(positionNetProfit < 0) g_consecLosses++;
   double earlyPx1BarClose, earlyPx3BarClose, earlyPx5BarClose;
   Bot1GetEarlyPriceAction(posTicket, earlyPx1BarClose, earlyPx3BarClose, earlyPx5BarClose);
   Bot1WriteTradeLog(posTicket, "CLOSE", dealPrice, dealVolume, dealProfit, 0, reasonStr,
      0, 0, 0, dealComm, dealSwap, mfePx, maePx, barsToMfePx, barsToMaePx, 0, dealMagic,
      "", -1, -1, "", -1, -1, -1, -1, -999999, -1,
      -999999, -999999, -99, -99, -1, -999999, -99, "", -1, -1,
      -999999, -999999, -999999,
      earlyPx1BarClose, earlyPx3BarClose, earlyPx5BarClose);
   Bot1ReleaseMFESlot(posTicket);
   Bot1ReleaseStageTracker(posTicket);
   Bot1RecordTradeOutcome(posTicket);
   Bot1ReleaseTrackedMagic(posTicket);   // v2 AGILE: free this slot now that the position is fully closed

   // Closing a BUY position generates a SELL deal and vice versa -- infer
   // the original direction from the closing deal's type.
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   int origDir = (dealType == DEAL_TYPE_SELL) ? 1 : -1;
   Bot1RegisterPostmortemWatch(posTicket, dealPrice, origDir, reasonStr);

   // 2026-09-02: block same-direction re-entry for N bars after a stop-loss
   // hit -- see UseCooldownAfterSL comment. Deliberately NOT triggered by
   // TP_HIT/MANUAL_OR_TRAIL/EXPERT_CLOSE -- only a genuine SL loss.
   // v2 AGILE NOTE: g_cooldownUntilBuyBar/SellBar are process-global, not
   // per-magic -- a trend-side SL will cool down the counter-trend module's
   // same-direction entries too, and vice versa. Accepted as intentional
   // for v1 of this module (both are "I was wrong about this direction on
   // this symbol right now" signals) rather than building fully independent
   // per-magic cooldown state; revisit if live/smoke data shows this
   // cross-suppression is too aggressive.
   if(dealReason == DEAL_REASON_SL) {
      Bot1RegisterCooldown(origDir);
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           
//+------------------------------------------------------------------+
void OnTick() {
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime != lastBarTime);

   // PERF FIX (v5.5): ADR is a D1-period value -- only recompute it when the
   // current D1 bar has actually changed, not on every M5 (or whatever
   // _Period is) bar close. v5.3 already cut this from per-tick to per-bar;
   // this cuts it further from per-bar to per-day (on M5, ~288x fewer calls
   // than v5.3 alone). Value used by CalculateStopLoss/CalculateTakeProfit
   // is identical either way -- ADR genuinely doesn't change intraday.
   if(isNewBar) {
      datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
      if(currentDay != lastADRCalcDay) {
         adr = CalculateADR(ADRPeriod);
         lastADRCalcDay = currentDay;
      }
      lastBarTime = currentBarTime;
      Bot1UpdateAsianRangeTracking();   // v5: must run before CheckForTradingSignals so a same-bar window-close verdict is available to it
      CheckForTradingSignals();
      Bot1CheckCounterTrendSignal();   // v2 AGILE (2026-09-06): independent mean-reversion entry for ranging conditions -- see input group comment
      Bot1UpdatePostmortemTracker();
      Bot1CheckRegimeTransitions();   // 2026-09-04: event-driven regime/gate/cooldown transition log
   }

   Bot1UpdateMFETracker(isNewBar);
   Bot1ShadowPoolUpdate(isNewBar);  // 2026-09-25: multi-trade shadow pool, ticks every tick if ShadowPoolTrackTickMFE
   ManageStagedProfits();
   Bot1WriteHeartbeat();   // 2026-09-04: proof-of-life row, internally rate-limited to HeartbeatIntervalSeconds

   // PERF FIX: legend drawing (and everything it recomputes -- a full
   // duplicate pass over every Layer 1/2/3 + volatility function, plus
   // ObjectCreate/ObjectSetInteger calls) and ChartRedraw() are purely
   // cosmetic. Skip them during non-visual Strategy Tester runs (i.e. every
   // optimization pass) where nothing is watching the chart; keep them for
   // live trading and visual single-runs, where the legend is the point.
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) {
      DrawLeftLegend();
      DrawRightLegend();
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+