//+------------------------------------------------------------------+
//|  bot4_TREND_FX_v1_2.mq5                                         |
//|                                                                  |
//|  Donchian Breakout + Pullback Pyramid EA — forked/adapted        |
//|  from bot3_BASKET_FX_v1_3 architecture                          |
//|  Magic range: 40001–40099                                        |
//|  Chart timeframe: M15 (entry); HTF: D1/H4/H1 for trend          |
//|                                                                  |
//|  STRATEGY (from BOT4_MASTER_SPEC.md v1.0):                      |
//|  Trend-following PYRAMID (anti-martingale / odwrócona drabinka). |
//|  D1 Donchian(55) sets the bias. H4 Donchian(20) confirms break.  |
//|  M15 pullback into Fib 38.2–61.8% zone = entry trigger (L1).    |
//|  Additional units added only when price ADVANCES with trend      |
//|  (pyramid): +PyramidSpacingMult × ATR(H4) per unit.             |
//|  Exit: Chandelier(22,3×) on H1 OR Donchian(10) H1 low, partial  |
//|  close at +2R, time-stop 12h/24h.                               |
//|                                                                  |
//|  LOT LADDER (decreasing — anti-martingale):                      |
//|    L1: 1.0 × BaseLotSize                                         |
//|    L2: 0.7 × BaseLotSize                                         |
//|    L3: 0.5 × BaseLotSize                                         |
//|    L4: 0.3 × BaseLotSize                                         |
//|  Total at full 4 levels = 2.5 × BaseLotSize max exposure        |
//|                                                                  |
//|  SHADOW MODE (data-gather / tuning):                             |
//|  ShadowScoreThreshold=5 logs nearly everything for labeler.      |
//|  LiveScoreThreshold=50 for actual execution.                     |
//|  ShadowModeOnly=true until 100 validated trades/symbol.         |
//|                                                                  |
//|  GUARDS:                                                         |
//|  G1  D1 bias required — no entry against D1 Donchian direction  |
//|  G2  ADX min confirmation (M15 ADX > 18 for entry quality)      |
//|  G3  Max spread/ATR ratio at entry                               |
//|  G4  Global equity circuit-breaker                               |
//|  G5  Max concurrent pyramids (FTMO safety: 3)                   |
//|  G6  Post-SL cooldown per symbol                                 |
//|  G7  Friday force-close                                          |
//|  G8  News filter ±60 min (new entry block)                       |
//|  G9  Daily equity stop (FTMO: 3.5% intraday drop → halt)        |
//|  G10 Correlation group cap                                        |
//|                                                                  |
//|  OUTPUT FILES (MQL5/Files/):                                     |
//|  • trendbaskets_BOT4_{SYM}.csv   — closed basket lifecycle log  |
//|  • trendcandidates_BOT4_{SYM}.csv — all scored signals          |
//|  • trendrejected_BOT4_{SYM}.csv  — blocked signals with reason  |
//|  • trendpyramid_BOT4_{SYM}.csv   — per-unit pyramid events      |
//|  • groqreq_BOT4_{SYM}.json       — Groq open request            |
//|  • groqresp_BOT4_{SYM}.json      — Groq open response           |
//|  • groqreq_BOT4_CONTINUE_{SYM}_L{N}.json — continue request     |
//|                                                                  |
//|  v1.0: Initial build — data-gather + shadow mode                 |
//+------------------------------------------------------------------+
//|  PARAMETER TUNING HISTORY (moved here 2026-07-24 from scattered   |
//|  inline comments — read this before changing any of these). Each |
//|  input below has a short plain-language comment explaining what  |
//|  it does; the WHY-this-value reasoning for ones that were changed |
//|  based on real data lives here instead, so the input list stays  |
//|  readable.                                                        |
//|                                                                  |
//|  DonchianPeriodBias (2026-06-09): was 55, changed to 20. 55 days   |
//|  was too long for the available demo history (61 days) — most    |
//|  symbols never got a bias at all. 20 gives roughly a 1-month      |
//|  trend window and leaves enough history for backfill.             |
//|                                                                  |
//|  LiveRequireStrongBias (2026-06-14): disabled. Two contradictory  |
//|  findings in 5 days on small samples — first said only STRONG    |
//|  bias worked, then a bigger sample (506 trades) said MODERATE     |
//|  outperformed STRONG on every symbol tested. Rather than flip a   |
//|  third time on more thin data, this gate is off until a much      |
//|  bigger sample justifies turning it back on.                      |
//|                                                                  |
//|  LiveMaxExtension (2026-06-14): restored to 0.618 after briefly   |
//|  being relaxed to 2.0. The relaxed value came from a 2-day,       |
//|  1-symbol sample; a 506-trade sample confirmed the original       |
//|  0.618 hypothesis was right — buying/selling far past the         |
//|  breakout level (an "extended" or "chased" entry) performs badly. |
//|                                                                  |
//|  UseSniperMode (2026-07-22): this used to be permanently on with |
//|  no way to turn it off. It turned out to be the main reason live  |
//|  trade counts were far lower than expected even with every other  |
//|  filter loosened — not a bug, just a filter nobody could see or   |
//|  disable. Now has a real on/off switch (see input below).         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.49"
#property description "Bot4 Donchian Trend-Following Pyramid EA — v1.49 (regime-suite branch: ports the multi-filter regime-veto architecture, DEAL-reason-precise SL cooldown, self-calibrating min-SL-distance filter, and 3-tier live-diagnostics logging (heartbeat/regime-events/block_reason) from the bot1-regime research branch (see Documents/EA_Regime_And_Diagnostics_Knowledge.md); v1.48's isolated fast-exit mode carried forward unchanged, off by default)"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <BossafxGuardGate.mqh>  // 2026-10-05: 1-per-bar PF-priority entry gate + closure-reason tagging

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_DONCHIAN_PERIOD_BIAS  { DON_BIAS_5=5, DON_BIAS_10=10, DON_BIAS_15=15, DON_BIAS_20=20, DON_BIAS_34=34, DON_BIAS_55=55 };
enum ENUM_H4_DONCHIAN_PERIOD  { H4_DON_10=10, H4_DON_20=20, H4_DON_30=30 };
enum ENUM_H1_EXIT_PERIOD      { H1_EXIT_8=8,  H1_EXIT_10=10, H1_EXIT_14=14 };
enum ENUM_PARTIAL_CLOSE_MODE  { PC_NONE=0, PC_AT_2R=1, PC_AT_1R5=2 };

//+------------------------------------------------------------------+
//| INPUTS — CORE                                                    |
//+------------------------------------------------------------------+
input group "═══ General ═══"
input string        ConfigSymbol         = "";
input int           MagicNumber          = 40001;
input string  RunProfileTag        = ""; // Short label for which .set/config produced this run — e.g. "AGGR", "STAB", "WORK". Written into every trade's Comment field (replaces the default "Bot4" prefix) so History/Comment column shows which profile opened it. Keep to <=6 chars — comment field is short and already carries basket_id + level.
input group "=== 1-per-bar PF-priority entry gate (2026-10-05, additive) ==="
input bool UseGuardBarGate = true;  // user default ON; fail-open if EA_G_PortfolioGuard_MultiEA
                                     // isn't running or hasn't published a gate decision yet -- see
                                     // BossafxGuardGate.mqh GGate_ShouldOpen()
input bool          LogAllCandidates     = true;  // log all scored signals (data-gather)
input bool          LogRejected          = true;  // log blocked signals
input bool          DiagnosticMode       = true;  // verbose WHY-NO-TRADE logging (set false once validated)
input int           HeartbeatBars        = 16;    // print a state heartbeat every N M15 bars (16=4h)

// FIX (v1.49, regime-suite branch): time-interval-driven CSV heartbeat,
// ported from bot1-regime. Distinct from the bar-count Print() heartbeat
// above (HeartbeatBars) — that one only fires while OnTick is actually being
// called with new bars; THIS one is wall-clock-time-driven, so a gap in the
// CSV itself is the diagnosis when something (terminal restart, history-sync
// failure) stops the EA cold. Two independent proof-of-life signals, kept
// deliberately separate rather than merged into one.
input int           CsvHeartbeatSeconds  = 300;   // Write one row to the heartbeat CSV every N seconds of wall-clock time (not bars/ticks/trades). Set to 0 to disable.

input group "═══ TREND DETECTION ═══"
// D1 layer — primary bias
input bool                  UseD1Bias           = true;
input ENUM_DONCHIAN_PERIOD_BIAS DonchianPeriodBias  = DON_BIAS_10;  // FIX (v1.47, frequency branch): default changed from DON_BIAS_20. Smoke-tested A/B on the same 8-month window: DonchianPeriodBias=20 produced only 12 D1 breakout events / 17 L1 opens / 12 active trading days; =10 produced 21 events / 33 opens / 23 active days (+92% opens) and higher profit ($7,356 vs $3,749). D1 bias frequency was the dominant upstream bottleneck — looser downstream gates (SniperMode, WEAK-bias, score thresholds) can't matter if D1 bias itself barely ever exists. How many bars of BiasTimeframe (below) the EA looks back to decide "is this a real trend". On the default D1 timeframe: 5-15=reacts fast/changes its mind often, 20=roughly a month, 34/55=longer, slower-to-change. Same idea applies if you change BiasTimeframe to H1/H4 instead — the number of bars, not calendar time, is what this controls.
input int                   D1EMAFastPeriod     = 50;
input int                   D1EMASlowPeriod     = 200;
input bool                  D1RequireEMAAlign   = true;   // require EMA50>EMA200 (D1) for bias
// v1.1: D1 breakout persistence — tracks last D1 breakout for up to N D1 bars
// After a D1 close above the previous Donchian upper, the bullish bias remains
// valid for D1TrendValidBars days (even when next bars are inside the channel).
// Bias cancels early if D1 close drops back below the breakout level.
input int                   D1TrendValidBars    = 30;     // Once the EA decides "today is a bull/bear trend day", how many days it keeps believing that even if price goes quiet. Lower = gives up on the trend sooner (fewer trades taken on an aging trend). Higher = keeps trading the same trend idea for longer, even if it's gone stale.
// H4 layer — breakout confirmation
input bool                  UseH4Confirm        = true;
input ENUM_H4_DONCHIAN_PERIOD H4DonchianPeriod  = H4_DON_20;  // Same idea as the daily one above, but on the 4-hour chart — a second check that the shorter-term price action agrees with the daily trend. Lower = confirms faster (more trades), higher = wants stronger agreement first (fewer, more confident trades).
// H1 layer — swing structure / pullback reference
input bool                  UseH1Structure      = true;
input int                   H1SwingLookback     = 20;     // bars to define last H1 swing
// ADX gate
input bool                  UseADXGate          = true;
input int                   ADXPeriod           = 14;
input double                ADXMinEntry         = 18.0;   // Below this, the market is considered "too flat/choppy" to trust a trend trade. Raise it to be more selective (fewer trades, only strong trends); lower it to let the EA trade calmer/quieter markets too (more trades, more risk of trading sideways chop).
input double                ADXMaxEntry         = 50.0;   // Above this, the trend is considered "too far along / exhausted" to safely join. Lower it to avoid jumping in late on a move that might be about to reverse; raise it to let the EA join even very strong, fast-moving trends.

input group "═══ EXPERIMENTAL FEATURES (2026-07-25, all default OFF) ═══"
// These implement the anti-whipsaw research findings from the 2026-07-25
// deep dive. Every one defaults to false/current-behavior so existing
// symbols/configs are completely unaffected until you deliberately turn
// one on and re-validate that symbol. Turn on ONE at a time when testing —
// turning on several together at first makes it hard to tell which one is
// responsible for a result.

// (1) ATR confirmation buffer — price must close past the D1 breakout
// level by an extra volatility-scaled margin before the EA believes it,
// and must close back past that same margin (not just the bare level) to
// cancel it. Directly targets the "poke past the line and snap back"
// whipsaw pattern. Bigger BufferATRMult = fewer, more convincing
// breakouts; 0 = same as off.
input bool                  UseD1BreakoutBuffer     = true;   // FIX (v1.46): was false, which made D1BreakoutBufferATRMult a dead sweep parameter (122/122 pairs, zero effect) — the buffer computation only ever runs when this flag is on.
input double                D1BreakoutBufferATRMult = 0.5;

// (2) Regime gate — on top of everything else, require the market to
// actually be "trending enough" (by ADX or by Efficiency Ratio, your
// choice) before the EA will act on a D1 breakout at all. This is the
// filter research suggests helps GOLD the most, since GOLD's daily chop
// is what causes most of its false signals.
input bool                  UseRegimeGate           = true;   // FIX (v1.46): was false, which made RegimeGateMethod a dead sweep parameter (89/89 pairs, zero effect) — the ADX-vs-EfficiencyRatio branch only ever gets reached when this flag is on.
enum ENUM_REGIME_METHOD { REGIME_ADX=0, REGIME_EFFICIENCY_RATIO=1 };
input ENUM_REGIME_METHOD    RegimeGateMethod        = REGIME_ADX;
input double                RegimeMinADX            = 20.0;  // only used if RegimeGateMethod=ADX
input double                RegimeMinER             = 0.30;  // only used if RegimeGateMethod=EFFICIENCY_RATIO, range 0(pure noise)-1(pure trend)
input int                   EfficiencyRatioPeriod   = 14;

// (5) Renko/D1 agreement — require the most recent Renko brick's own
// direction to agree with the D1 bias direction before treating a signal
// as valid. A second, independent vote from the faster layer.
input bool                  UseRenkoD1Agreement     = false;

// (6) Higher-timeframe trend alignment — an extra check, on a slower
// timeframe than your bias layer, that price is on the correct side of a
// long moving average. Meant to keep trades aligned with the dominant
// multi-week/multi-month trend and cut down on range-bound churn.
input bool                  UseHigherTFTrendFilter  = false;
input ENUM_TIMEFRAMES       HigherTFTrendTimeframe  = PERIOD_W1;
input int                   HigherTFMAPeriod        = 200;

// (4) Bias detection timeframe — DEFAULT IS PERIOD_D1, i.e. unchanged
// behavior. Changing this moves the ENTIRE bias layer (Donchian channel +
// EMA alignment + breakout persistence) onto a different timeframe. The
// 2026-07-25 research leaned toward NOT speeding this up (shorter
// timeframes tend to import more noise) and toward using a shorter
// DonchianPeriodBias on the SAME timeframe instead — but that's a general
// finding, not a rule for every instrument, and it's worth testing H1/H4
// directly rather than assuming. Brick sizing (Renko) stays anchored to
// D1 ATR regardless of this setting, by design — see the 2026-07-25 note
// in ScanHistoricalD1Breakout() for why.
input ENUM_TIMEFRAMES       BiasTimeframe           = PERIOD_D1;
// Bias persistence, expressed in HOURS instead of "N bars of whatever
// timeframe" — this stays meaningful no matter what BiasTimeframe is set
// to. Default 1008h ≈ 42 calendar days, matching the old default's real
// trading-day duration for a 5-day-week instrument (see fix note below).
// FIX found during 2026-07-25 validation pass: the old cutoff was
// iTime(D1, 30) — 30 TRADING days back, which for a 5-day FX week is
// ~42 calendar days, not 30. A naive 720h (=30 calendar days) default
// here would have silently shortened bias persistence for every FX
// symbol. 1008h = 42 calendar days matches the old real-world duration.
// This is an approximation (indices/commodities trade slightly different
// weekly schedules) — re-validate per asset class, don't assume exact.
input int                   TrendValidHours         = 1008;

input group "═══ RENKO M15 ENTRY TRIGGER (v1.2) ═══"
// v1.2: In-memory Renko built from M15 closes.  iCustom() removed entirely.
// Signal: last confirmed brick UP + brick.close > RenkoDonchianUpper(RenkoDonPeriod)
//         + RenkoEMAFast > RenkoEMASlow (when RenkoRequireEMAAlign=true)
// BrickSizeATRMult is the key parameter — tune per-symbol via param_advisor.
// SniperMode: after a BUY signal, no new BUY until a DOWN brick resets the state.
// Reversal2x: a reversal brick requires 2× brick_size (classic Renko — anti-whipsaw).
input double  RenkoBrickSizeATRMult = 0.25;    // How big a price move counts as "one step" before the EA looks for a trade. Bigger number = fewer, bigger steps = fewer but more significant signals. Smaller number = more, smaller steps = many more signals but noisier/lower quality ones.
input bool    RenkoReversal2x       = true;    // If true, price has to reverse TWICE as far to count as "turning around" as it did to go forward — filters out small back-and-forth wobbles. Turn off to let the EA react to smaller reversals (more signals, but more false alarms too).
input bool    UseSniperMode         = true;    // If true, once the EA fires a BUY it won't fire another BUY until price genuinely reverses first — stops it from repeatedly re-entering the same move. Turn off if you want MANY more trades for testing purposes; this is the single biggest lever on how often the EA trades.
// FIX (v1.47, frequency branch): a second, faster re-arm path alongside the
// reversal-brick reset above. Once SniperReArmBars M15 bars have elapsed since
// the last same-direction fire, that direction re-opens even without a reversal
// brick. 0 = disabled (pure reversal-only reset, same as v1.46 behavior).
input int     SniperReArmBars       = 20;      // M15 bars before the SAME direction can fire again, even without a reversal brick. 0=off (old reversal-only behavior). Lower = more trades, more re-entries into the same move.
input int     RenkoDonPeriod        = 20;      // How many recent "steps" (bricks) price has to break above/below to count as a real trend, not just noise. Lower number = the EA calls a trend sooner (more trades, easier to be wrong). Higher number = waits for a more convincing move (fewer trades, more likely to be right).

// FIX (v1.47, Task 7): TRACK B — adaptive brick sizing, ISOLATED research
// feature, OFF by default. When enabled, RenkoBrickSizeATRMult is no longer
// a single fixed value for the whole run — instead, every AdaptiveBrickReevalBars
// M15 bars, the EA replays a TRAILING (never future) window of
// AdaptiveBrickLookbackBars M15 closes through a lightweight, scratch-buffer
// (not the live ring buffer) Renko simulation for each candidate multiplier
// in AdaptiveBrickCandidates, scores each candidate, and adopts the best-
// scoring one going forward. Deliberately: (1) small, fixed candidate set —
// NOT a continuous search — to avoid becoming its own overfit surface; (2)
// coarse re-evaluation cadence — avoids chasing noise on a short cycle; (3)
// only ever looks at bars strictly in the past relative to "now" in the
// backtest, so there is no look-ahead. When a new best multiplier differs
// from the current one, the LIVE g_renko_bricks ring buffer is rebuilt via
// the existing RenkoInitHistory() path (not patched in place) for
// correctness. Kept fully separate from the Track A frequency changes above
// — this must be validated as an isolated A/B against a static-brick
// baseline (see bot4_v147_track_b_adaptive_isolated.set) before ever being
// combined with a Track A sweep.
input bool    UseAdaptiveBrickSize      = false;  // Master switch for Track B. OFF = identical behavior to a fixed RenkoBrickSizeATRMult (Track A only). ON = brick size re-picked periodically from AdaptiveBrickCandidates based on trailing-window performance.
input int     AdaptiveBrickLookbackBars = 500;    // M15 bars (~5 trading days) of PAST-ONLY history replayed to score each candidate brick multiplier. Only used when UseAdaptiveBrickSize=true.
input int     AdaptiveBrickReevalBars   = 480;    // M15 bars (~weekly) between re-evaluations. Coarse on purpose — a short cycle would chase noise instead of regime. Only used when UseAdaptiveBrickSize=true.
input string  AdaptiveBrickCandidates   = "0.15,0.20,0.25,0.30,0.35"; // Comma-separated fixed candidate multipliers to evaluate each re-eval cycle. Deliberately narrow/centered on values already shown to work in steadier (non-tail-chasing) sweeps — NOT the wide 0.08-0.90 range that produced the day-concentrated overfit found auditing v1.46 sweep8. Only used when UseAdaptiveBrickSize=true.
input int     RenkoEMAFastPeriod    = 20;      // EMA fast on brick closes
input int     RenkoEMASlowPeriod    = 50;      // EMA slow on brick closes
input bool    RenkoRequireEMAAlign  = true;    // require EMAFast > EMASlow for BUY (EMASlow > EMAFast for SELL)
input int     MaxRenkoBricks        = 500;     // ring buffer size (500 = enough for EMA50 warmup + Donchian20)
// Note: D1 ATR handle already exists. No new indicator handles needed.

input group "═══ PULLBACK ENTRY (M15) ═══"
// v1.1: Fib zone is now a SCORE BONUS (not a hard gate).
// ps.valid is set by the Donchian M15 signal. Fib/candle/EMA add score points.
input bool                  UseFibZone           = true;   // (Option A) reward fresh breakouts, not chased ones
input double                FibRetraceLow        = 0.382;  // retained for CSV/compat (unused as gate)
input double                FibRetraceHigh       = 0.618;  // retained for CSV/compat (unused as gate)
input double                MaxBreakoutExtension = 1.0;    // (Option A) max breakout extension (range units) before "over-extended/chased"
input bool                  UseCandleConfirm     = true;   // candle pattern adds score points (not hard gate)
input int                   PullbackLookbackBars = 40;     // M15 bars to look back for impulse measurement
input double                MaxEntryDistATRMult  = 1.5;    // max distance from EMA20 M15 at entry (ATR multiples)
input int                   EMAEntryPeriod       = 20;     // M15 EMA for pullback proximity context
// Volatility filter
input bool                  UseVolFilter         = true;  // A safety check on how "normal" current volatility is (see VolRatioMin/Max just above). Turn off to remove this check entirely — more trades allowed through, including in unusually quiet or unusually wild conditions.
input bool                  UseImpulseRangeFilter = true; // A check that the recent price swing was big enough, relative to normal volatility, to be worth trading. Turn off to allow smaller/quieter price swings to qualify too (more trades, but weaker ones).
input int                   ATRShortPeriod       = 5;
input int                   ATRLongPeriod        = 20;
input double                VolRatioMin          = 0.70;   // Below this, the market is considered "too quiet/dead right now" to bother trading. Lower it to let the EA trade in quieter conditions too; raise it to only trade when there's already some real movement happening.
input double                VolRatioMax          = 2.50;   // Above this, the market is considered "moving too wildly/erratically right now" — a possible news spike or panic move, not a clean trend. Raise it to let the EA trade through more chaotic conditions; lower it to sit out the wildest moments.

input group "═══ PYRAMID ENGINE ═══"
input int                   MaxPyramidLevels  = 4;       // The most "add-on" positions the EA can stack onto one trending trade (1=never add, just one entry; 4=up to 3 add-ons on top of the first). More levels = bigger position and bigger profit if the trend keeps going, but bigger loss if it reverses after adding.
input double                PyramidSpacingMult= 0.70;    // How far price has to move in your favor before the EA adds another position to a winning trade. Bigger number = waits for a stronger move before adding (fewer add-ons, each more confident). Smaller number = adds sooner and more often (bigger position built faster, but on less confirmation).
input bool                  PyramidRequiresSetup = true; // require new pullback/signal for L2+
// Lot ladder (decreasing — anti-martingale)
input double                LotMultL1         = 1.00;    // L1 multiplier
input double                LotMultL2         = 0.70;    // L2 multiplier
input double                LotMultL3         = 0.50;    // L3 multiplier
input double                LotMultL4         = 0.30;    // L4 multiplier
// Basket SL — single hard stop for all units, per-unit trailing
input double                BasketSLATRMult   = 2.0;     // How far below (for a buy) or above (for a sell) the entry price the initial stop-loss sits, in "how volatile is this instrument right now" units. Bigger number = wider stop, trade survives more wobble before being closed for a loss, but each loss costs more. Smaller number = tighter stop, smaller losses but more trades stopped out by normal noise.
input double                BETrailATRMult    = 0.5;     // after next unit opens, trail SL to avg_entry − N×ATR

input group "═══ EXIT MANAGEMENT ═══"
// Partial close
input ENUM_PARTIAL_CLOSE_MODE PartialCloseMode = PC_AT_2R;
input double                  PartialClosePct  = 0.40;   // % of total units to close at partial trigger
// Chandelier trail (H1)
input bool                  UseChandelierTrail   = true;
input int                   ChandelierPeriod     = 22;   // lookback bars on H1
input double                ChandelierATRMult    = 3.0;  // Controls how far behind the price the trailing stop follows once a trade is winning. Bigger number = stop trails further back, giving the trade more room to breathe (lets bigger wins run, but gives back more profit before exiting). Smaller number = stop follows tighter (locks in profit sooner, but can cut winners short).
// Donchian-10 exit (H1) — backup exit when Chandelier doesn't fire
input bool                  UseDonchianExit      = true;
input ENUM_H1_EXIT_PERIOD   DonchianExitPeriod   = H1_EXIT_10;
// Time-stops
input int                   TimestopSoftBars     = 48;   // If a trade has been open this many 15-minute bars (48 = about 12 hours) and still isn't doing well, the EA closes half of it to reduce risk. Lower it to give up on slow trades sooner; raise it to give trades more time to develop before trimming.
input int                   TimestopHardBars     = 96;   // If a trade has been open this many 15-minute bars (96 = about 24 hours) and still isn't performing, the EA closes the whole thing regardless. Lower it to force trades to prove themselves faster; raise it to let trades run longer before being forced shut.
input double                TimestopSoftMinR     = 1.5;  // if basket below this R at soft stop, close 50%
input double                TimestopHardMinR     = 3.0;  // if basket below this R at hard stop, close all
// D1 reversal exit
input bool                  UseD1ReversalExit    = true; // close all if D1 bias flips against position

// FIX (v1.48, intraday fast-exit branch): ISOLATED, opt-in research feature,
// OFF by default. v1.47's day-concentration audit (4 verified candidates)
// showed EVERY candidate — regardless of entry-frequency tuning — still had
// ~28-30% of total profit land on the same single day (2026.03.23), meaning
// the trend-following exit architecture (Chandelier trail + basket SL +
// 12-24h timestops) is fundamentally built to ride rare multi-day trend runs,
// not to bank smaller intraday moves. This mode tests the opposite bet:
// lock in profit sooner and give up on stagnant trades faster, to see if
// that redistributes the profit curve toward more, smaller, steadier gains
// instead of a few big-move days per month. Entry logic is UNCHANGED from
// v1.47 — this only touches exit management, and only when the switch below
// is true, so v1.47 behavior is fully preserved when UseFastExitMode=false.
input group "═══ FAST-EXIT MODE (v1.48, isolated research toggle) ═══"
input bool    UseFastExitMode          = false; // Master switch. false = identical behavior to v1.47 (this whole block is inert). true = apply the R-based Chandelier tightening and intraday timestops below.
input double  FastExitLockRMult        = 1.0;   // Once the basket reaches this R-multiple of profit, start tightening the Chandelier trail multiplier (see FastExitTightenedATRMult) instead of using the normal wide ChandelierATRMult. Lower = starts locking in profit sooner (after a smaller win); higher = waits for a bigger win before tightening.
input double  FastExitTightenedATRMult = 1.2;   // The tighter Chandelier ATR multiplier used once FastExitLockRMult is reached (replaces ChandelierATRMult for that basket only). Smaller number = stop follows much closer once in profit, locking in gains fast but risking an early exit on normal pullback noise.
input int     FastExitTimestopSoftBars = 8;     // Intraday soft time-stop when UseFastExitMode=true (in M15 bars; 8 = ~2 hours). Replaces TimestopSoftBars for this mode. Much shorter than the v1.47 default of 48 (~12h) — tests whether stagnant trades should be de-risked within the same session instead of over 12+ hours.
input int     FastExitTimestopHardBars = 16;    // Intraday hard time-stop when UseFastExitMode=true (in M15 bars; 16 = ~4 hours). Replaces TimestopHardBars for this mode. Much shorter than the v1.47 default of 96 (~24h) — forces trades to prove themselves within a single trading session or close out.

// FIX (v1.49, regime-suite branch): ported from the bot1-regime research
// branch (Documents/EA_Regime_And_Diagnostics_Knowledge.md) — a pluggable
// multi-filter veto layer on top of the existing single-method RegimeGateMethod
// above, NOT a replacement for it. Master switch below defaults to false so
// v1.48 behavior (single ADX-or-ER check) is exactly preserved until this is
// deliberately turned on. Each filter is independently toggleable and
// defaults to a NEUTRAL/PASS verdict when its own toggle is off, so enabling
// only 1 of 5 filters still produces a coherent combined verdict — the same
// structural rule the source branch used to keep A/B testing clean.
// All underlying calculations reuse EXISTING functions (GetADXValue(),
// GetEfficiencyRatio(), GetVolatilityRatio() for the ATR-ratio filter) —
// no duplicate indicator plumbing.
input group "═══ REGIME SUITE (v1.49, pluggable multi-filter veto) ═══"
input bool    UseRegimeSuite            = false; // Master switch. false = v1.48 behavior unchanged (single RegimeGateMethod check above still applies on its own). true = this suite REPLACES that single check with a combined multi-filter vote (see RegimeSuiteVoteMode).
enum ENUM_REGIME_SUITE_VOTE { RS_VOTE_AND=0, RS_VOTE_OR=1, RS_VOTE_MAJORITY=2 };
input ENUM_REGIME_SUITE_VOTE RegimeSuiteVoteMode = RS_VOTE_MAJORITY; // AND = every enabled filter must agree "trending" (strictest, fewest trades). OR = any ONE enabled filter saying "trending" is enough (loosest, most trades). MAJORITY = more than half of the ENABLED filters must agree.
input bool    RSUseADX                  = true;  // Reuses existing ADX reading (GetADXValue() >= RegimeMinADX from the TREND DETECTION group above) as one vote in the suite.
input bool    RSUseER                   = true;  // Reuses existing Efficiency Ratio reading (GetEfficiencyRatio(EfficiencyRatioPeriod) >= RegimeMinER from the TREND DETECTION group above) as one vote in the suite.
input bool    RSUseCHOP                 = true;  // Choppiness Index vote — high value (near 100) = choppy/ranging, low value (near 0) = trending. New calculation, ported concept from bot1-regime.
input int     RSChopPeriod              = 14;    // Lookback bars for the Choppiness Index calculation.
input double  RSChopMaxForTrending      = 55.0;  // CHOP value must be BELOW this to count as "trending" for this filter's vote. Lower = stricter (only very clean trends pass); higher = looser.
input bool    RSUseATRRatio             = true;  // ATR-ratio vote — reuses existing GetVolatilityRatio() (short-ATR/long-ATR). A ratio well above 1.0 means volatility is currently expanding (more likely a real move, not just chop).
input double  RSATRRatioMinForTrending  = 1.05;  // GetVolatilityRatio() must be AT OR ABOVE this to count as "trending" for this filter's vote.
input bool    RSUseSession               = false; // Session-window vote — restricts the suite's "trending" vote to a specific UTC hour range (e.g. London/NY overlap), independent of any other time filter elsewhere in the EA. Off by default since UseTimeFilter already exists separately — this is an additional, regime-suite-specific option, not a duplicate gate forced on.
input int     RSSessionStartHour         = 7;     // UTC hour the session-window vote starts counting as "trending" (inclusive). Only used if RSUseSession=true.
input int     RSSessionEndHour         = 17;    // UTC hour the session-window vote stops counting as "trending" (exclusive). Only used if RSUseSession=true.

// FIX (v1.49, regime-suite branch): self-calibrating min-SL-distance filter,
// ported from bot1-regime. Rejects an L1 open whose CANDIDATE SL distance
// (BasketSLATRMult * current ATR — see CalculateInitialSL()) is an outlier
// vs this config's own recent REAL trade history. An anomalously tight SL
// usually means the ATR read is stale/unrepresentative for the current bar,
// not a genuinely tighter opportunity — and since lot sizing can scale UP to
// hold $ risk constant, a too-tight SL means a much LARGER position built on
// a low-confidence volatility read. No fixed point threshold: what counts as
// "normal" varies by symbol/timeframe/BasketSLATRMult, so this always
// compares against THIS config's own rolling average, never a hardcoded
// number. Warm-up guarded — does nothing until enough real trade history
// exists, so it never falsely rejects on a fresh EA restart.
input group "═══ MIN-SL-DISTANCE SANITY FILTER (v1.49) ═══"
input bool    UseMinSLDistanceFilter   = false; // Master switch. false = no effect (v1.48 behavior unchanged).
input double  MinSLDistanceFraction    = 0.4;   // Reject the L1 open if candidate SL distance < this fraction of the rolling average of the last SLDistanceHistoryLen real trades' SL distances.
input int     SLDistanceHistoryLen     = 20;    // Rolling window size (real trades) used to compute the average SL distance.
input int     SLDistanceMinSamples     = 5;     // Filter does nothing until at least this many real trades have been recorded — avoids false rejects right after an EA restart with no history yet.

input group "═══ SCORING ═══"
input int                   ShadowScoreThreshold = 5;    // The minimum "quality score" (0-100) for the EA to even write a setup down for later study — kept very low on purpose so almost nothing is missed for data-gathering. This is NOT the trade-taking threshold, just the note-taking one.
input int                   LiveScoreThreshold   = 15;   // FIX (v1.47, frequency branch): lowered from 50. With SniperMode re-arm (Task 2) and WEAK_TRADEABLE now scoreable (Task 3), more raw candidates reach this gate — the old default of 50 risked becoming the new bottleneck that silently capped frequency right back down. Still swept in the full sweep (Task 6); this is just a sane default for the Task 5 smoke test. Raise to be pickier (fewer, hopefully better trades). Lower to trade more often.
input bool                  ShadowModeOnly       = true; // The master safety switch. TRUE = the EA only watches and writes down what it WOULD have done, no real money moves. FALSE = it actually places real orders. Always double-check this is what you intend before running on a live or funded account.
// ── Live-quality gates (data-driven, 2026-06-05) ──
// These restrict LIVE entries only; shadow logging is unaffected so we keep
// collecting the filtered-out signals to validate these gates over time.
input bool                  LiveRequireStrongBias = false; // If true, only trades where D1 daily AND H4 AND EMA trend all fully agree ("STRONG") are allowed live — stricter, fewer trades. Currently off; see the tuning-history note near the top of this file for why. Don't flip this back on without a large enough sample to justify it.
input double                LiveMaxExtension      = 0.618; // How far past the breakout point price is allowed to have already moved before the EA still calls it a fresh, tradeable entry (rather than "too late, price already ran"). Lower number = only takes very fresh entries (fewer trades, avoids chasing). Higher number = still enters even after price has moved a lot already (more trades, more risk of buying near a top / selling near a bottom). See tuning-history note near the top of this file.
input bool                  LiveRequireFreshBreakout = false; // (NEW) live only when Renko fires a FRESH breakout brick (renko_signal=±1), not mid-trend continuation. Reduces autocorrelation. Keep false during gathering; flip true to test independent-signal mode.
// Score weights (tunable by param_advisor)
input int                   ScoreD1BiasMax        = 30;  // max points for D1 Donchian + EMA alignment
input int                   ScoreH4ConfirmMax     = 20;  // max points for H4 Donchian confirmation
input int                   ScorePullbackQualMax  = 30;  // max points for pullback depth + candle
input int                   ScoreADXVolMax        = 20;  // max points for ADX strength + vol ratio

input group "═══ FTMO PROTECTION ═══"
input double                InitialBalance        = 100000.0;
input double                MaxDailyLossAmount    = 5000.0;    // 5% of 100k
input double                MaxOverallLossAmount  = 10000.0;   // 10% of 100k
input double                DailyEquityStopPct    = 3.5;       // intraday hard halt (3.5% < FTMO 5%)
input double                GlobalEquityStopPct   = 4.0;       // overall floating circuit-breaker
input double                SafetyBuffer          = 100.0;

input group "═══ RISK & SIZING ═══"
input double                BaseLotSize                = 0.01;  // The trade size (in lots) used for the first position, when UseRiskSizing (below) is turned OFF. Bigger number = bigger trades = bigger wins AND bigger losses. Only used when UseRiskSizing=false.
input double                RiskPercentL1              = 0.50;  // % equity risk per L1 (used if UseRiskSizing=true)
input bool                  UseRiskSizing              = false; // Controls how trade size is decided. FALSE (recommended, and what almost everything in this system has been tuned around) = always use the fixed BaseLotSize above. TRUE = calculate size from a % of your account balance and the stop-loss distance — this can produce MUCH bigger trades than BaseLotSize when equity is high or the stop is tight, so treat this like a separate setting from everything else, not a minor tweak.
input int                   MaxOpenPyramids            = 3;     // global max concurrent pyramids (FTMO: max 3)
// Fix #2 — Correlated direction cap: at most N pyramids in the same direction
// simultaneously across ALL symbols (prevents correlated USD/EUR/AUD all-BUY
// being wiped by single FOMC event). Set 2 = max 2 BUY or 2 SELL at a time.
input int                   MaxSameDirectionPyramids   = 2;     // The most trades the EA will have open in the SAME direction (all buys, or all sells) at once, across every symbol combined. This exists because if EURUSD, GBPUSD, and USDJPY are all "buy the dollar" at the same time, one surprise USD news event can hit all of them together. Raise it to allow more simultaneous same-direction trades (more potential profit, more correlated risk); lower it to spread risk out more.
input int                   CooldownBarsSL             = 48;    // After a stop-loss hit, how many 15-minute bars (48 = 12 hours) the EA waits before it's allowed to open a new trade on that same symbol again — stops it from immediately re-entering a setup that just failed. Lower it to allow faster re-entry; raise it to wait longer after a loss.
input int                   CooldownBarsTP             = 4;     // M15 bars after TP/trail before new entry

input group "═══ CORRELATION ═══"
input string                CorrelationGroup      = "EUR_BLOCK";
input int                   MaxPyramidsPerGroup   = 1;     // max simultaneous pyramids per group

input group "═══ GROQ AI ═══"
input bool                  UseGroqFilter         = true;
input bool                  GroqShadowModeOnly    = true;
input double                GroqMinConfidence     = 0.55;
input int                   GroqTimeoutSeconds    = 8;
input int                   GroqDailyCallLimit    = 300;
input int                   GroqCooldownBars      = 3;
input string                AIRequestPath         = "groqreq_BOT4_";
input string                AIResponsePath        = "groqresp_BOT4_";

input group "═══ QUALITY FILTERS ═══"
input double                MaxSpreadATR          = 0.50;   // max spread/ATR ratio
input double                MaxSpreadAbsolutePips = 4.0;    // absolute max spread pips
input double                MinATRPips            = 3.0;    // min ATR M15 (avoid dead symbols)
input double                MaxATRPips            = 200.0;  // max ATR M15 (avoids blow-off chaos)

input group "═══ NEWS FILTER ═══"
input bool                  UseNewsFilter         = true;
input int                   NewsMinutesBefore     = 60;     // no new L1 entry 60 min before high-impact
input int                   NewsMinutesAfter      = 30;     // wait 30 min after high-impact

input group "═══ TIME FILTER ═══"
input bool                  UseTimeFilter         = false;
input string                StartTime             = "00:00";
input string                EndTime               = "23:59";
input bool                  AvoidFriday           = true;
input int                   FridayCloseHour       = 20;

input group "═══ DISPLAY ═══"
input bool                  ShowLeftLegend        = true;
input bool                  ShowRightLegend       = true;
// FIX (bot4 audit, 2026-08): ShowEntryLevels was a dead duplicate of
// ShowEntryLevels2 (declared further down, in the RENKO/ENTRY VISUALS
// group) -- this one was never read anywhere (see DrawEntryCriteriaLevels,
// which checks ShowEntryLevels2 only). Removed rather than wired-in,
// because wiring it in would have silently flipped ShowEntryLevels2's
// default (false) to true for every existing .set file that had
// ShowEntryLevels at its own default of true -- a behavior change nobody
// asked for. Use ShowEntryLevels2 to draw the D1/H4 Donchian lines.
input bool                  ShowPyramidLines      = true;
input int                   LegendFontSize        = 8;
// NEW (2026-07-22): separate from the always-on legend above. This is a
// deeper diagnostic overlay meant for understanding WHY/WHEN a trade fires
// — an arrow marker on every bar where a candidate scored above
// ShadowScoreThreshold (colored by direction, tooltip shows score/reason),
// plus a live status panel showing the current D1/H4/Renko/score state and
// the specific reason blocking a trade right now, if any. Default OFF —
// meant to be switched on deliberately while studying a chart, not left
// running during normal shadow/live operation (extra chart objects add
// overhead over a long test/session).
input bool                  ShowSignalVisuals     = false;

//+------------------------------------------------------------------+
//| STRUCTS                                                          |
//+------------------------------------------------------------------+
struct TrendState {
   // D1 layer
   int    d1_bias;          // 1=bull, -1=bear, 0=neutral
   bool   d1_don_bullish;   // price > D1 Donchian upper (recent breakout)
   bool   d1_ema_aligned;   // EMA50 > EMA200 on D1
   double d1_don_upper;
   double d1_don_lower;
   double d1_don_mid;
   // H4 layer
   int    h4_confirm;       // 1=bull confirmed, -1=bear confirmed, 0=none
   bool   h4_breakout_fresh;// price crossed H4 upper/lower recently
   double h4_don_upper;
   double h4_don_lower;
   // H1 layer
   double h1_swing_high;    // last swing high on H1
   double h1_swing_low;     // last swing low on H1
   // Composite
   int    overall_bias;     // final direction: 1=long, -1=short, 0=no trade
   string bias_strength;    // STRONG / MODERATE / WEAK
};

struct PullbackState {
   bool   valid;            // signal fired in trade direction (Renko breakout)
   int    direction;        // intended trade direction (1=long, -1=short)
   double impulse_high;     // high of impulse move (Donchian channel high for breakout ref)
   double impulse_low;      // low of impulse move (Donchian channel low)
   double fib_38;           // retained for CSV; now = breakout reference levels
   double fib_50;
   double fib_62;
   // OPTION A — breakout strategy semantics:
   // pullback_depth REPURPOSED as breakout_extension. For a trend-following
   // breakout, price is ABOVE the channel high (long) when the signal fires.
   // We measure how far PAST the breakout level price has extended, in units
   // of the channel range. 0.0 = right at the breakout level; >0 = extended
   // beyond it (deeper breakout); <0 would mean still inside the channel.
   // The CSV column keeps the name "pullback_depth" for backward compatibility,
   // but the value now means extension, not retracement.
   double pullback_depth;   // = breakout_extension (range-normalized, >0 = extended past breakout)
   bool   in_golden_zone;   // = "healthy breakout zone": extension within sane bounds (not over-extended)
   string candle_pattern;   // ENGULFING / PIN_BULL / PIN_BEAR / STRONG_BODY / NONE
   double ema20_value;      // M15 EMA20 at time of entry
   double dist_to_ema_atr;  // distance to EMA20 in ATR multiples
   double atr_m15;          // M15 ATR14 value
   double atr_h4;           // H4 ATR14 value (for pyramid spacing)
   double vol_ratio;        // ATR short/long ratio
   string session;
   string day_of_week;
   int    hour_utc;
};

struct PyramidLevel {
   ulong    ticket;
   double   entry_price;
   double   lot_size;
   datetime open_time;
   double   sl_price;          // individual unit SL (basket-level overrides)
   bool     partial_closed;    // has partial close been done on this unit
   int      level_idx;         // 0=L1, 1=L2, etc.
};

struct PyramidBasket {
   string      basket_id;
   int         direction;          // 1=BUY, -1=SELL
   PyramidLevel level[4];          // max 4 units (L1–L4)
   int          active_levels;     // 0 = no active basket
   double       basket_open_equity;
   double       basket_sl_price;   // current basket-wide SL (trailing up)
   double       initial_sl_price;  // SL at L1 open (for R calculation)
   double       initial_risk_r;    // equity at risk for 1R (account currency)
   bool         partial_done;      // has global partial close fired
   bool         trail_activated;   // Chandelier/Don-10 trail armed
   double       chandelier_stop;   // current Chandelier stop price
   double       don10_stop;        // current Donchian-10 H1 stop price
   datetime     open_time;
   int          bars_open;
   // Signal context at L1 (for CSV logging)
   int          mech_score;
   string       d1_bias_str;
   string       h4_confirm_str;
   string       pullback_depth_str;
   string       candle_pattern_str;
   double       atr_at_open;
   double       atr_h4_at_open;
   string       session_str;
   string       day_of_week_str;
   int          hour_utc;
   string       correlation_group;
   // Groq context
   bool         groq_called;
   string       groq_action;
   double       groq_confidence;
   string       groq_reason;
   bool         continue_called[4];
};

struct VolState {
   string vol_state;  // HIGH / NORMAL / LOW
   double atr_ratio;
   double atr_abs_pips;
};

struct RiskContext {
   int     recent_win_loss_streak;
   bool    max_daily_loss_reached;
   double  daily_loss_pct;
   int     daily_trades_done;
   string  recent_results;
   string  day_of_week;
   int     hour_utc;
   string  symbol_class;
   int     open_pyramids_total;
   int     open_pyramids_same_group;
};

struct GroqResponse {
   string trade_action;    // OPEN / SKIP
   string direction;
   string trend_quality;
   double confidence;
   string reason;
   bool   valid;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo position;

// Indicator handles — M15 (chart TF)
int atrM15Handle     = INVALID_HANDLE;  // ATR14 M15
int atrShortHandle   = INVALID_HANDLE;  // ATR short (vol ratio)
int atrLongHandle    = INVALID_HANDLE;  // ATR long (vol ratio)
int adxM15Handle     = INVALID_HANDLE;  // ADX M15
int ema20M15Handle   = INVALID_HANDLE;  // EMA20 M15 (pullback proximity)
// v1.2: In-memory Renko state — no external indicator handles needed for entry
// Ring buffer: index = g_renko_count % MaxRenkoBricks
// Accessing last confirmed brick: (g_renko_count-1) % MaxRenkoBricks
struct RenkoBrick {
   double   open;          // brick open price
   double   close;         // brick close = open ± brick_size
   int      direction;     // +1 = up-brick, -1 = down-brick
   datetime time_formed;   // time of M15 bar that completed this brick
};
RenkoBrick g_renko_bricks[];    // ring buffer, resized to MaxRenkoBricks in OnInit
int        g_renko_count   = 0; // total bricks ever formed (modulo for ring index)
double     g_renko_forming = 0; // price level of partially-forming next brick
int        g_renko_form_dir= 0; // direction of forming brick (+1/-1/0)
double     g_renko_brick_size = 0; // current brick size in price (ATR×mult)
// Renko computed signals (updated by RenkoComputeSignal() on each new bar)
int        g_renko_signal  = 0; // +1=BUY, -1=SELL, 0=none (SniperMode aware)
datetime   g_last_candidate_time = 0; // per-symbol: updated on each WriteCandidateLog call
datetime   g_last_live_candidate_time      = 0; // FIX (2026-07-20 follow-up): dedicated throttle anchor, separate from g_last_candidate_time (which feeds the CSV bars_since_last_signal column and must keep updating on every logged row, throttled or not)
int        g_last_live_candidate_direction = 0;
input int  MinM15BarsBetweenSameDirSignal = 4; // throttle: min M15 bars before re-attempting LIVE on same symbol+direction (0=off). Does NOT suppress shadow CSV logging.
double     g_effective_initial_balance = 0; // set in OnInit — see InitialBalance sanity check
double     g_renko_don_upper = 0;
double     g_renko_don_lower = 0;
double     g_renko_ema_fast  = 0;
double     g_renko_ema_slow  = 0;
// Sniper state (reset when direction flips, like DonchianBreakoutSystem SniperMode)
bool       g_renko_sniper_buy_fired  = false;
bool       g_renko_sniper_sell_fired = false;
datetime   g_renko_sniper_reset_day  = 0; // daily reset reference
// FIX (v1.47, frequency branch): SniperMode used to be a hard one-shot-per-swing
// block — "the single biggest lever on how often the EA trades" per the original
// comment above the input, and confirmed the dominant frequency bottleneck across
// every sweep so far (UseSniperMode=true always won on PF/profit, at the direct
// cost of trade count). These timestamps let SniperReArmBars re-open the same
// direction after N M15 bars WITHOUT waiting for a full reversal brick — a second,
// faster re-arm path alongside (not replacing) the existing reversal-brick reset.
datetime   g_renko_sniper_buy_fired_time  = 0;
datetime   g_renko_sniper_sell_fired_time = 0;
// D1 ATR handle (shared with brick size calculation)
int        g_atr_d1_handle = INVALID_HANDLE;
// H4
int atrH4Handle      = INVALID_HANDLE;  // ATR14 H4 (pyramid spacing)
int atrH4Chan        = INVALID_HANDLE;  // ATR22 H4 (Chandelier — unused, H1 used)
// H1
int atrH1Handle      = INVALID_HANDLE;  // ATR22 H1 (Chandelier trail)
// D1
int emaD1FastHandle  = INVALID_HANDLE;  // EMA50 on BiasTimeframe
int emaD1SlowHandle  = INVALID_HANDLE;  // EMA200 on BiasTimeframe
int biasATRHandle    = INVALID_HANDLE;  // FEATURE (1) 2026-07-25: ATR on BiasTimeframe, for breakout buffer
int higherTFMAHandle = INVALID_HANDLE;  // FEATURE (6) 2026-07-25: higher-timeframe trend-alignment MA

// v1.1: D1 breakout persistence state
// Tracks the LAST D1 Donchian breakout time and level per direction.
// Bias remains valid for D1TrendValidBars D1 bars after the breakout.
// Cancelled early if price closes back below/above the breakout level.
datetime g_d1_bull_breakout_time  = 0;   // time of last D1 bullish breakout bar
datetime g_d1_bear_breakout_time  = 0;   // time of last D1 bearish breakout bar
double   g_d1_bull_breakout_level = 0;   // Donchian upper at time of bull breakout
double   g_d1_bear_breakout_level = 0;   // Donchian lower at time of bear breakout
// v1.1 Fix #3: D1 midline soft-cancel state — persists across bars
// true = price closed below midline after bull breakout → block new L1 entries
// (bias intact for existing pyramids; recovers automatically if price > midline)
bool     g_d1_bull_soft_cancel    = false;
bool     g_d1_bear_soft_cancel    = false;
// DEBUG (2026-07-20): whipsaw tracking — records the D1 bar time of the most
// recent hard-cancel per direction, so a re-breakout in the same direction
// soon after can be flagged explicitly. Added to make the USDCHF-style
// breakout->cancel->re-breakout cycle visible in the log instead of only
// inferable after the fact from CSV data.
datetime g_d1_bull_last_cancel_time = 0;
datetime g_d1_bear_last_cancel_time = 0;
input int WhipsawWarnD1Bars = 3;  // flag re-breakout within this many D1 bars of its own cancel

// Pyramid state (one basket per chart instance)
PyramidBasket g_pyr;

// Cooldown tracking
datetime g_cooldown_sl_time  = 0;
datetime g_cooldown_tp_time  = 0;

// FIX (v1.49, regime-suite branch): rolling window of REAL L1-open SL
// distances, for the self-calibrating min-SL-distance filter (ported concept
// from bot1-regime). No fixed point threshold — "normal" SL distance depends
// on symbol/timeframe/BasketSLATRMult, so this calibrates itself per running
// config from its own recent trade history.
double g_sl_dist_history[];
int    g_sl_dist_history_count = 0;   // total ever recorded (for warm-up gate)

// FIX (v1.49, regime-suite branch): state for the time-driven CSV heartbeat
// and the transition-driven regime-event CSV.
datetime g_csv_last_heartbeat_time = 0;
bool     g_last_regime_verdict     = true;   // last computed RegimeSuiteVerdict(), for transition detection
bool     g_last_regime_adx_vote    = false;  // per-filter last vote, for GATE_FLIP detection
bool     g_last_regime_er_vote     = false;
bool     g_last_regime_chop_vote   = false;
bool     g_last_regime_atr_vote    = false;
bool     g_last_regime_session_vote= false;
bool     g_regime_state_initialized= false;  // first evaluation just seeds state, doesn't log a "flip"
datetime g_regime_last_checked_bar = 0;      // bar-gate for the regime-event check — see perf note above CheckAndWriteRegimeEvents()

// Daily stats
double   startDayBalance     = 0.0;
datetime lastDayStart        = 0;
int      dailyTradeCount     = 0;
int      recentStreak        = 0;
string   recentResults       = "";
datetime dailyStatsReset     = 0;
double   dailyStartEquity    = 0.0;
bool     g_daily_stop_hit    = false;
// ── Diagnostic counters (reset daily, reported in heartbeat) ──────
int      g_diag_ticks_total      = 0;   // bar-gate passes today
int      g_diag_no_trend         = 0;   // exits: no D1 bias
int      g_diag_weak_bias        = 0;   // exits: WEAK bias
int      g_diag_adx_block        = 0;   // exits: ADX gate
int      g_diag_spread_block     = 0;   // exits: spread too wide
int      g_diag_atr_block        = 0;   // exits: ATR out of range
int      g_diag_renko_no_signal  = 0;   // Renko gave no signal
int      g_diag_renko_warmup     = 0;   // Renko still warming up (too few bricks)
int      g_diag_below_shadow     = 0;   // score < ShadowScoreThreshold
int      g_diag_shadow_logged    = 0;   // candidate logged (shadow)
int      g_diag_cooldown_block   = 0;   // SL/TP cooldown active
int      g_diag_cap_block        = 0;   // max concurrent pyramids
int      g_diag_news_block       = 0;   // news filter
int      g_diag_time_block       = 0;   // outside trading hours
int      g_diag_live_attempts    = 0;   // reached live OpenPyramidLevel
int      g_diag_renko_channel_break_no_signal = 0; // Renko channel broke but EMA/Sniper blocked the signal (see RenkoComputeSignal diag)
int      g_diag_last_hb_bar      = 0;   // last heartbeat bar count
datetime g_diag_day              = 0;   // day of current counters
bool     g_overall_stop_hit  = false;  // persisted via GlobalVariable across restarts

// Bar tracking
datetime lastBarTime         = 0;

// Groq tracking
int      groqDailyCallCount  = 0;
datetime groqDayReset        = 0;
datetime groqLastCallBar     = 0;

// Lot ladder (decreasing — anti-martingale)
double LOT_LADDER[4];  // filled in OnInit from inputs
// Effective (clamped 1..4) MaxPyramidLevels — see OnInit clamp comment.
// Fixed-size level[4]/LOT_LADDER[4] arrays make >4 unsafe; using this
// instead of the raw input everywhere prevents an out-of-bounds write.
int    g_max_pyramid_levels_effective = 4;

//+------------------------------------------------------------------+
//| OVERALL LOSS PERSISTENCE (GlobalVariable key, survives restart)  |
//+------------------------------------------------------------------+
string B4_OVERALL_HIT_VAR() {
   return "B4_OVERALL_HIT_" + _Symbol + "_" + IntegerToString(MagicNumber);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS (adapted from Bot3)                             |
//+------------------------------------------------------------------+
double PipSize() {
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (d==5 || d==3) ? _Point*10.0 : _Point;
}
double ValuePerPoint() {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0) ? tv * (_Point / ts) : tv;
}
double NormalizeVolume(double lots) {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(mn, MathMin(mx, lots));
   if(st > 0) lots = MathFloor(lots/st) * st;   // MathFloor not MathRound (safety)
   return NormalizeDouble(lots, 2);
}
double GetMinStopDistance() {
   long   sl = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double fl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double bm = MathMax((double)sl, fl) * _Point;
   double pf = 3.0 * PipSize();
   return MathMax(bm, pf) + 2.0 * _Point;
}
string GetCurrentSession() {
   MqlDateTime t; TimeToStruct(TimeGMT(), t); int h = t.hour;
   bool isLon = (h>=8 && h<17), isNY = (h>=13 && h<22), isAsia = (h>=0 && h<8);
   if(isLon && isNY) return "LONDON_NY_OVERLAP";
   if(isLon)         return "LONDON";
   if(isNY)          return "NY";
   if(isAsia)        return "ASIA";
   return "OFF_HOURS";
}
string GetDayOfWeek() {
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   string d[] = {"SUN","MON","TUE","WED","THU","FRI","SAT"};
   return d[t.day_of_week];
}
int GetHourUTC() { MqlDateTime t; TimeToStruct(TimeGMT(), t); return t.hour; }
string GetSymbolClass() {
   string s = _Symbol;
   if(StringFind(s,"GOLD")>=0 || StringFind(s,"XAU")>=0) return "COMMODITY_GOLD";
   if(StringFind(s,"US30")>=0 || StringFind(s,"NAS")>=0 || StringFind(s,"SPX")>=0) return "INDEX";
   if(StringFind(s,"JPY")>=0) return (StringFind(s,"USD")>=0)?"MAJOR_JPY":"CROSS_JPY";
   return "MAJOR_FX";
}
string SanitizeCSVField(string text) {
   StringReplace(text, ",", ""); StringReplace(text, "\n", " ");
   StringReplace(text, "\r", " "); StringReplace(text, "\"", "'");
   return text;
}
string FmtAmt(double val) {
   return StringFormat("%.2f %s", val, AccountInfoString(ACCOUNT_CURRENCY));
}
bool IsFridayClose() {
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   return (t.day_of_week == 5 && t.hour >= FridayCloseHour);
}
int TimeStringToMinutes(const string ts) {
   string p[]; if(StringSplit(ts, ':', p) != 2) return -1;
   int h = (int)StringToInteger(p[0]), m = (int)StringToInteger(p[1]);
   if(h<0||h>23||m<0||m>59) return -1; return h*60+m;
}
bool IsTradingTimeAllowed() {
   if(!UseTimeFilter) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   int cur = t.hour*60 + t.min;
   int st  = TimeStringToMinutes(StartTime), en = TimeStringToMinutes(EndTime);
   if(st<0 || en<0) return false;
   bool ok = (st<=en) ? (cur>=st && cur<=en) : (cur>=st || cur<=en);
   if(!ok) return false;
   if(AvoidFriday && t.day_of_week==5 && t.hour>=FridayCloseHour) return false;
   return true;
}

//+------------------------------------------------------------------+
//| ATR HELPERS                                                       |
//+------------------------------------------------------------------+
double GetATRPips_M15() {
   if(atrM15Handle == INVALID_HANDLE) return 10.0 * PipSize();
   double buf[];
   if(CopyBuffer(atrM15Handle, 0, 1, 1, buf) < 1) return 10.0 * PipSize();
   return NormalizeDouble(buf[0] / PipSize(), 2);
}
double GetATRValue_M15() {
   if(atrM15Handle == INVALID_HANDLE) return 10.0 * PipSize();
   double buf[];
   if(CopyBuffer(atrM15Handle, 0, 1, 1, buf) < 1) return 10.0 * PipSize();
   return buf[0];
}
double GetATRValue_H4() {
   if(atrH4Handle == INVALID_HANDLE) return 30.0 * PipSize();
   double buf[];
   if(CopyBuffer(atrH4Handle, 0, 1, 1, buf) < 1) return 30.0 * PipSize();
   return buf[0];
}
double GetATRValue_H1() {
   if(atrH1Handle == INVALID_HANDLE) return 15.0 * PipSize();
   double buf[];
   if(CopyBuffer(atrH1Handle, 0, 1, 1, buf) < 1) return 15.0 * PipSize();
   return buf[0];
}
double GetVolatilityRatio() {
   if(atrShortHandle==INVALID_HANDLE || atrLongHandle==INVALID_HANDLE) return 1.0;
   double s[], l[];
   if(CopyBuffer(atrShortHandle, 0, 1, 1, s) < 1) return 1.0;
   if(CopyBuffer(atrLongHandle,  0, 1, 1, l) < 1) return 1.0;
   if(l[0] <= 0) return 1.0;
   return NormalizeDouble(s[0] / l[0], 3);
}
VolState GetVolStateExport() {
   VolState vs;
   vs.atr_ratio    = GetVolatilityRatio();
   vs.atr_abs_pips = GetATRPips_M15();
   vs.vol_state    = (vs.atr_ratio > 1.5) ? "HIGH" : (vs.atr_ratio > 0.8) ? "NORMAL" : "LOW";
   return vs;
}

//+------------------------------------------------------------------+
//| SYMBOL APPROVAL LIST (same as Bot3 — strip broker suffixes)      |
//+------------------------------------------------------------------+
string NormaliseSymbol(string raw) {
   string s = raw; StringToUpper(s);
   StringReplace(s,".M",""); StringReplace(s,".R","");
   StringReplace(s,"#","");  StringReplace(s,".CASH","");
   StringReplace(s,".PRO","");
   // Alias map
   if(s=="GOLD") s="XAUUSD";
   if(s=="BTCUSD") s="BTCUSD";
   return s;
}
bool IsSymbolApproved(string sym) {
   string approved[] = {
      "EURUSD","GBPUSD","USDJPY","AUDUSD","USDCAD","NZDUSD","USDCHF",
      "EURGBP","EURJPY","GBPJPY","AUDJPY","EURAUD","EURCHF","GBPAUD",
      "GBPCAD","EURCAD","CADCHF","AUDCAD","NZDCAD","AUDNZD",
      "CADJPY","CHFJPY","NZDJPY",                          // were missing
      "XAUUSD","XAGUSD","GOLD",                            // metals + alias
      // Indices — generic + FTMO .cash names
      "US30","NAS100","SPX500","DE40","UK100","JP225","US500","US100",
      "US30.cash","US500.cash","US100.cash","GER40.cash","UK100.cash","JP225.cash"
   };
   for(int i = 0; i < ArraySize(approved); i++)
      if(approved[i] == sym) return true;
   return false;
}

//+------------------------------------------------------------------+
//| CORRELATION GROUP LOGIC (adapted from Bot3)                      |
//+------------------------------------------------------------------+
// DEAD CODE REMOVED (bot4 audit, 2026-08): GroupCooldownVarName() and
// GetGroupPyramidCount(grp, dir) were both unreferenced everywhere except
// their own declarations -- GetGroupPyramidCount's own comment even says
// "Cross-chart group enforcement handled by MaxOpenPyramids cap in OnTick",
// i.e. it documents itself as never having been wired in. The real,
// actually-enforced group-cap mechanism is GroupCountVarName() +
// GetGroupPyramidCountForGroup() + Increment/DecrementGroupPyramidCount()
// further below, added by the 2026-08 MaxPyramidsPerGroup fix. Kept only
// the live implementation to avoid two parallel, similarly-named
// "count pyramids for a group" mechanisms with different (and in the old
// one's case, never-executed) semantics.

// Count total open UNITS (positions) with Bot4 magic range
int GetTotalOpenUnits() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      long magic = position.Magic();
      if(magic >= 60001 && magic <= 60099) cnt++;
   }
   return cnt;
}

// BUG C FIX: Count distinct PYRAMIDS (baskets), not units.
// A pyramid = all positions sharing the same symbol+magic (one basket per chart).
// We count distinct (symbol) combos in the Bot4 magic range.
int GetTotalOpenPyramids() {
   string seen_symbols[];
   int    pyramid_count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      long magic = position.Magic();
      if(magic < 60001 || magic > 60099) continue;
      string sym = position.Symbol();
      // Check if this symbol already counted
      bool found = false;
      for(int j = 0; j < ArraySize(seen_symbols); j++)
         if(seen_symbols[j] == sym) { found = true; break; }
      if(!found) {
         int sz = ArraySize(seen_symbols);
         ArrayResize(seen_symbols, sz + 1);
         seen_symbols[sz] = sym;
         pyramid_count++;
      }
   }
   return pyramid_count;
}

int GetPyramidsForSymbol() {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Magic() == MagicNumber && position.Symbol() == _Symbol) cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| COUNT SAME-DIRECTION PYRAMIDS (Fix #2)                           |
//| Counts all Bot4 pyramids (magic 60001-60099) across ALL symbols  |
//| in the same direction as 'dir'. Used to enforce the correlated-   |
//| direction cap (MaxSameDirectionPyramids).                         |
//+------------------------------------------------------------------+
int GetSameDirectionPyramidCount(int dir) {
   int cnt = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      long magic = position.Magic();
      if(magic < 60001 || magic > 60099) continue;
      int pos_dir = (position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      if(pos_dir == dir) cnt++;
   }
   return cnt;
}

// Store group in GlobalVariable for cross-chart correlation
void RegisterGroupVar() {
   string gv = "B4_GRP_" + _Symbol;
   GlobalVariableSet(gv, 1.0);
   // Store direction
   string dv = "B4_DIR_" + _Symbol;
   if(g_pyr.active_levels > 0)
      GlobalVariableSet(dv, (double)g_pyr.direction);
}

// FIX (2026-08 dead-parameter audit): MaxPyramidsPerGroup was declared,
// commented as "max simultaneous pyramids per group", but nothing ever
// counted open pyramids per CorrelationGroup or compared against it — the
// "G10: CORRELATION GROUP CAP" block further down actually just re-checks
// the unrelated global MaxOpenPyramids cap. GlobalVariables can only hold
// numbers, not strings, and the existing RegisterGroupVar() never stored
// which group a symbol belongs to — so there was no way to answer "how
// many open baskets share my group" across charts. This adds that.
// KNOWN LIMITATION: increments on open, decrements on close (both via
// CloseBasket(), the single choke point for all basket closes regardless
// of reason) — this survives normal EA restarts (ReconstructBasketFromPositions
// still leads to a real CloseBasket() call eventually), but a terminal
// crash between an open and its close could leave the counter stuck high
// until manually reset. Not bulletproof; flagged, not silently assumed safe.
string GroupCountVarName(string grp) { return "B4_GROUPCOUNT_" + grp; }
int GetGroupPyramidCountForGroup(string grp) {
   string gv = GroupCountVarName(grp);
   return GlobalVariableCheck(gv) ? (int)GlobalVariableGet(gv) : 0;
}
void IncrementGroupPyramidCount(string grp) {
   string gv = GroupCountVarName(grp);
   double cur = GlobalVariableCheck(gv) ? GlobalVariableGet(gv) : 0;
   GlobalVariableSet(gv, cur + 1);
}
void DecrementGroupPyramidCount(string grp) {
   string gv = GroupCountVarName(grp);
   double cur = GlobalVariableCheck(gv) ? GlobalVariableGet(gv) : 0;
   GlobalVariableSet(gv, MathMax(0, cur - 1));
}

//+------------------------------------------------------------------+
//| DONCHIAN CHANNEL CALCULATION                                     |
//+------------------------------------------------------------------+
// Returns highest high over 'period' confirmed bars on given TF
double DonchianUpper(ENUM_TIMEFRAMES tf, int period, int shift = 1) {
   double highs[];
   if(CopyHigh(_Symbol, tf, shift, period, highs) < period) return 0;
   double hh = highs[0];
   for(int i = 1; i < period; i++) if(highs[i] > hh) hh = highs[i];
   return hh;
}
double DonchianLower(ENUM_TIMEFRAMES tf, int period, int shift = 1) {
   double lows[];
   if(CopyLow(_Symbol, tf, shift, period, lows) < period) return 0;
   double ll = lows[0];
   for(int i = 1; i < period; i++) if(lows[i] < ll) ll = lows[i];
   return ll;
}

//+------------------------------------------------------------------+
//| TREND STATE — multi-TF Donchian bias                             |
//+------------------------------------------------------------------+
TrendState GetTrendState() {
   TrendState ts;
   ZeroMemory(ts);

   // ── D1 Layer (v1.1 — persistence-based breakout tracking) ──────────
   // Instead of checking if the LAST D1 bar broke out (only true for 1 bar),
   // we track when the MOST RECENT breakout occurred and keep the bias valid
   // for D1TrendValidBars days. Cancel early if price closes back below breakout level.
   if(UseD1Bias) {
      double d1_upper = DonchianUpper(BiasTimeframe, (int)DonchianPeriodBias, 1);
      double d1_lower = DonchianLower(BiasTimeframe, (int)DonchianPeriodBias, 1);
      double d1_close = iClose(_Symbol, BiasTimeframe, 1);  // last confirmed bias-TF bar
      double d1_prev_upper = DonchianUpper(BiasTimeframe, (int)DonchianPeriodBias, 2);
      double d1_prev_lower = DonchianLower(BiasTimeframe, (int)DonchianPeriodBias, 2);

      ts.d1_don_upper = d1_upper;
      ts.d1_don_lower = d1_lower;
      ts.d1_don_mid   = (d1_upper + d1_lower) / 2.0;

      // FEATURE (1) 2026-07-25: ATR confirmation buffer. When on, price has
      // to close PAST the band by an extra volatility-scaled margin to
      // count as a breakout, and has to close back past that SAME margin
      // (not just the bare level) to cancel — real hysteresis against the
      // "poke past the line and snap back" whipsaw. Buffer is computed on
      // BiasTimeframe's own ATR (biasATRHandle), so it scales correctly
      // whatever timeframe bias is being detected on — this is
      // deliberately separate from the D1-anchored Renko brick-size ATR.
      double buf = 0;
      if(UseD1BreakoutBuffer && biasATRHandle != INVALID_HANDLE) {
         double atrbuf[];
         if(CopyBuffer(biasATRHandle, 0, 1, 1, atrbuf) >= 1)
            buf = atrbuf[0] * D1BreakoutBufferATRMult;
      }

      // ── RECORD new breakout if last confirmed bias-TF bar just broke out ──
      // BUG FIX: only RECORD + LOG when the breakout bar is genuinely NEW
      // (different bar time). Previously this fired on every M15 tick,
      // re-recording the same breakout and spamming logs 88×/day.
      datetime d1_bar_time = iTime(_Symbol, BiasTimeframe, 1);
      // Bullish: close > previous upper band (+ buffer if enabled)
      if(d1_close > d1_prev_upper + buf && d1_prev_upper > 0) {
         if(g_d1_bull_breakout_time != d1_bar_time) {  // NEW breakout bar
            g_d1_bull_breakout_time  = d1_bar_time;
            g_d1_bull_breakout_level = d1_prev_upper;
            Print(StringFormat("[D1] New BULL breakout: close=%.5f prev_upper=%.5f%s",
                  d1_close, d1_prev_upper, UseD1BreakoutBuffer ? StringFormat(" (buffer=%.5f)", buf) : ""));
            // DEBUG: whipsaw check — did this direction just get hard-cancelled recently?
            if(g_d1_bull_last_cancel_time > 0) {
               int bars_since_cancel = (int)((d1_bar_time - g_d1_bull_last_cancel_time) / PeriodSeconds(BiasTimeframe));
               if(bars_since_cancel <= WhipsawWarnD1Bars) {
                  Print(StringFormat("[D1] WHIPSAW WARNING: %s BULL re-breakout only %d bias-bar(s) "
                        "after its own hard-cancel — breakout level may be too close to noise "
                        "for current volatility, or D1TrendValidBars=%d is re-arming too fast",
                        _Symbol, bars_since_cancel, D1TrendValidBars));
               }
            }
         }
      }
      // Bearish: close < previous lower band (- buffer if enabled)
      if(d1_close < d1_prev_lower - buf && d1_prev_lower > 0) {
         if(g_d1_bear_breakout_time != d1_bar_time) {  // NEW breakout bar
            g_d1_bear_breakout_time  = d1_bar_time;
            g_d1_bear_breakout_level = d1_prev_lower;
            Print(StringFormat("[D1] New BEAR breakout: close=%.5f prev_lower=%.5f%s",
                  d1_close, d1_prev_lower, UseD1BreakoutBuffer ? StringFormat(" (buffer=%.5f)", buf) : ""));
            if(g_d1_bear_last_cancel_time > 0) {
               int bars_since_cancel = (int)((d1_bar_time - g_d1_bear_last_cancel_time) / PeriodSeconds(BiasTimeframe));
               if(bars_since_cancel <= WhipsawWarnD1Bars) {
                  Print(StringFormat("[D1] WHIPSAW WARNING: %s BEAR re-breakout only %d bias-bar(s) "
                        "after its own hard-cancel", _Symbol, bars_since_cancel));
               }
            }
         }
      }

      // ── HARD CANCEL: price closes back through original breakout level
      //    (+ buffer if enabled — same hysteresis distance as the entry) ──
      if(g_d1_bull_breakout_time > 0 && d1_close < g_d1_bull_breakout_level - buf) {
         Print(StringFormat("[D1] BULL breakout HARD CANCEL: close=%.5f < breakout_level=%.5f%s",
               d1_close, g_d1_bull_breakout_level, UseD1BreakoutBuffer ? StringFormat(" (buffer=%.5f)", buf) : ""));
         g_d1_bull_last_cancel_time = d1_bar_time;
         g_d1_bull_breakout_time = 0;
      }
      if(g_d1_bear_breakout_time > 0 && d1_close > g_d1_bear_breakout_level + buf) {
         Print(StringFormat("[D1] BEAR breakout HARD CANCEL: close=%.5f > breakout_level=%.5f%s",
               d1_close, g_d1_bear_breakout_level, UseD1BreakoutBuffer ? StringFormat(" (buffer=%.5f)", buf) : ""));
         g_d1_bear_last_cancel_time = d1_bar_time;
         g_d1_bear_breakout_time = 0;
      }

      // ── SOFT CANCEL (Fix #3): price returns below D1 midline ──────
      // Midline breach = trend is weakening but not fully reversed.
      // Action: mark as WEAK (block NEW L1 entries) but don't erase
      // the breakout timestamp (allows recovery if price re-crosses midline).
      // Implemented via ts.bias_strength = "WEAK" which OnTick checks
      // before allowing new pyramid opens.
      // g_d1_bull/bear_soft_cancel tracks the soft state across bars.
      bool bull_midline_breach = (g_d1_bull_breakout_time > 0 &&
                                   d1_close < ts.d1_don_mid && ts.d1_don_mid > 0);
      bool bear_midline_breach = (g_d1_bear_breakout_time > 0 &&
                                   d1_close > ts.d1_don_mid && ts.d1_don_mid > 0);
      // Store midline breach state in globals (persists across bars)
      if(bull_midline_breach && !g_d1_bull_soft_cancel) {
         g_d1_bull_soft_cancel = true;
         Print(StringFormat("[D1] BULL soft-cancel: close=%.5f < midline=%.5f — no new L1 entries",
               d1_close, ts.d1_don_mid));
      }
      if(!bull_midline_breach && g_d1_bull_soft_cancel && g_d1_bull_breakout_time > 0) {
         g_d1_bull_soft_cancel = false;  // recovered above midline
         Print(StringFormat("[D1] BULL soft-cancel LIFTED: close=%.5f > midline=%.5f",
               d1_close, ts.d1_don_mid));
      }
      if(bear_midline_breach && !g_d1_bear_soft_cancel) {
         g_d1_bear_soft_cancel = true;
         Print(StringFormat("[D1] BEAR soft-cancel: close=%.5f > midline=%.5f — no new L1 entries",
               d1_close, ts.d1_don_mid));
      }
      if(!bear_midline_breach && g_d1_bear_soft_cancel && g_d1_bear_breakout_time > 0) {
         g_d1_bear_soft_cancel = false;  // recovered below midline
         Print(StringFormat("[D1] BEAR soft-cancel LIFTED: close=%.5f < midline=%.5f",
               d1_close, ts.d1_don_mid));
      }

      // ── DETERMINE ACTIVE BIAS ──────────────────────────────────────
      // FEATURE (4) 2026-07-25: cutoff now computed from TrendValidHours
      // (a real duration) instead of "N bars of whatever timeframe" — this
      // stays meaningful regardless of BiasTimeframe. D1TrendValidBars is
      // no longer used for this calculation; kept as an input only for the
      // whipsaw-warning log message above (bar-count is more readable there).
      datetime cutoff = TimeCurrent() - TrendValidHours * 3600;
      bool bull_active = (g_d1_bull_breakout_time > 0 && g_d1_bull_breakout_time >= cutoff);
      bool bear_active = (g_d1_bear_breakout_time > 0 && g_d1_bear_breakout_time >= cutoff);

      if(bull_active && !bear_active) {
         ts.d1_bias        = 1;
         ts.d1_don_bullish = true;
         // Fix #3: demote to WEAK if soft-cancelled (midline breach)
         if(g_d1_bull_soft_cancel) ts.bias_strength = "WEAK";
      } else if(bear_active && !bull_active) {
         ts.d1_bias        = -1;
         ts.d1_don_bullish = false;
         if(g_d1_bear_soft_cancel) ts.bias_strength = "WEAK";
      } else if(bull_active && bear_active) {
         // Both active (unusual) — take the more recent one
         bool bull_newer   = (g_d1_bull_breakout_time >= g_d1_bear_breakout_time);
         ts.d1_bias        = bull_newer ? 1 : -1;
         ts.d1_don_bullish = bull_newer;
         bool soft_cancelled = bull_newer ? g_d1_bull_soft_cancel : g_d1_bear_soft_cancel;
         if(soft_cancelled) ts.bias_strength = "WEAK";
      } else {
         // No active breakout — neutral (no tradeable trend)
         ts.d1_bias        = 0;
         ts.d1_don_bullish = false;
      }

      // ── D1 EMA alignment (unchanged) ──────────────────────────────
      if(D1RequireEMAAlign && emaD1FastHandle!=INVALID_HANDLE && emaD1SlowHandle!=INVALID_HANDLE) {
         double ef[], es[];
         if(CopyBuffer(emaD1FastHandle,0,1,1,ef)>=1 && CopyBuffer(emaD1SlowHandle,0,1,1,es)>=1) {
            ts.d1_ema_aligned = (ts.d1_bias == 1) ? (ef[0] > es[0]) : (ef[0] < es[0]);
         } else ts.d1_ema_aligned = true;
      } else ts.d1_ema_aligned = true;
   } else {
      // FIX (2026-07-22): was hardcoded ts.d1_bias=1 (always bullish) —
      // meaning "disabling" D1 bias for exploration silently locked out
      // every SELL setup for the whole test. Now direction-neutral: follow
      // whatever the Renko engine is currently signaling, or stay neutral
      // (0) if Renko has no signal either. This lets a genetic/exploratory
      // run actually see both directions when this filter is off.
      ts.d1_bias = g_renko_signal;
      ts.d1_ema_aligned = true;
   }

   // ── H4 Layer ─────────────────────────────────────────────────────
   if(UseH4Confirm) {
      double h4_upper = DonchianUpper(PERIOD_H4, (int)H4DonchianPeriod, 1);
      double h4_lower = DonchianLower(PERIOD_H4, (int)H4DonchianPeriod, 1);
      double h4_close = iClose(_Symbol, PERIOD_H4, 1);  // confirmed H4 bar

      ts.h4_don_upper = h4_upper;
      ts.h4_don_lower = h4_lower;

      // H4 must confirm same direction as D1.
      // FIX (v1.46, dead-parameter repair): the old midline fallback
      // ("close above upper OR just above midline = confirmed") meant
      // that during any sustained trend, price sits above the H4
      // midline almost the whole time regardless of H4DonchianPeriod —
      // making the swept period value a no-op (0/208 sweep pairs ever
      // changed the outcome). Confirmation now requires an actual
      // breakout of the H4 band itself, so widening/narrowing the H4
      // Donchian period genuinely changes how often this fires.
      if(ts.d1_bias == 1) {
         ts.h4_confirm = (h4_close > h4_upper) ? 1 : 0;
         ts.h4_breakout_fresh = (h4_close > h4_upper);
      } else if(ts.d1_bias == -1) {
         ts.h4_confirm = (h4_close < h4_lower) ? -1 : 0;
         ts.h4_breakout_fresh = (h4_close < h4_lower);
      }
   } else {
      ts.h4_confirm = ts.d1_bias; ts.h4_breakout_fresh = false;
   }

   // ── H1 Swing Structure ────────────────────────────────────────────
   if(UseH1Structure) {
      double h1_highs[], h1_lows[];
      int lb = H1SwingLookback;
      if(CopyHigh(_Symbol, PERIOD_H1, 1, lb, h1_highs) >= lb &&
         CopyLow (_Symbol, PERIOD_H1, 1, lb, h1_lows)  >= lb) {
         ts.h1_swing_high = h1_highs[0];
         ts.h1_swing_low  = h1_lows[0];
         for(int i=1; i<lb; i++) {
            if(h1_highs[i] > ts.h1_swing_high) ts.h1_swing_high = h1_highs[i];
            if(h1_lows[i]  < ts.h1_swing_low)  ts.h1_swing_low  = h1_lows[i];
         }
      }
   }

   // ── Overall bias ─────────────────────────────────────────────────
   // All layers must agree for STRONG; D1 alone = WEAK; D1+H4 = MODERATE
   int agree = 0;
   if(ts.d1_bias != 0) agree++;
   if(UseH4Confirm && ts.h4_confirm == ts.d1_bias) agree++;
   if(D1RequireEMAAlign && ts.d1_ema_aligned) agree++;

   if(ts.d1_bias == 0) {
      ts.overall_bias = 0;
      ts.bias_strength = "NONE";
   } else if(agree >= 3) {
      ts.overall_bias = ts.d1_bias;
      ts.bias_strength = "STRONG";
   } else if(agree == 2) {
      ts.overall_bias = ts.d1_bias;
      ts.bias_strength = "MODERATE";
   } else {
      // FIX (v1.47, frequency branch): D1-only, no H4 confirmation. Was a hard
      // reject (overall_bias forced to 0, discarding every early/moderate-
      // conviction setup outright — one more contributor to the low trade
      // count). Now passed through as a scoreable "WEAK_TRADEABLE" tier instead
      // of a binary block: CalculateSignalScore() applies a reduced D1-bias
      // base score for this tier (see there), so it still competes fairly
      // against ShadowScoreThreshold/LiveScoreThreshold rather than being
      // thrown away before scoring ever runs.
      ts.overall_bias = ts.d1_bias;
      ts.bias_strength = "WEAK_TRADEABLE";
   }

   return ts;
}

//+------------------------------------------------------------------+
//| PULLBACK DETECTION (M15)                                         |
//+------------------------------------------------------------------+
// Detect the most recent impulse (swing move) on M15 and measure retracement
PullbackState GetPullbackState(int direction) {
   PullbackState ps;
   ZeroMemory(ps);
   ps.direction = direction;
   ps.valid     = false;

   int lb = PullbackLookbackBars;
   double highs[], lows[], closes[];
   if(CopyHigh (_Symbol, _Period, 1, lb, highs) < lb) return ps;
   if(CopyLow  (_Symbol, _Period, 1, lb, lows)  < lb) return ps;
   if(CopyClose(_Symbol, _Period, 1, lb, closes) < lb) return ps;

   // ATR values (confirmed bar offset 1)
   ps.atr_m15 = GetATRValue_M15();
   ps.atr_h4  = GetATRValue_H4();
   ps.vol_ratio = GetVolatilityRatio();

   // EMA20 on M15
   if(ema20M15Handle != INVALID_HANDLE) {
      double ema[];
      if(CopyBuffer(ema20M15Handle, 0, 1, 1, ema) >= 1)
         ps.ema20_value = ema[0];
   }

   // ── OPTION A: BREAKOUT EXTENSION (not Fib pullback) ──────────────
   // The strategy is trend-following breakout: Renko fires when price breaks
   // the Donchian channel. We measure how far price extended PAST the breakout
   // level, normalized by the channel range. This replaces the old (broken)
   // Fib-pullback measure that always produced negative depth on a breakout.
   if(direction == 1) {
      // Long breakout. FIX (Problem #1): scan the FULL lookback for both
      // extremes (old code searched a wrong/narrow window). bar[0]=newest.
      double min_low  = lows[0];
      double max_high = highs[0];
      for(int i=1; i<lb; i++) {
         if(lows[i]  < min_low)  min_low  = lows[i];
         if(highs[i] > max_high) max_high = highs[i];
      }

      ps.impulse_low  = min_low;
      ps.impulse_high = max_high;

      double range = max_high - min_low;
      // FIX (2026-07-22): this had NO toggle at all — it silently killed
      // every candidate below the threshold regardless of any other input.
      // Now gated so exploratory/genetic runs can actually disable it.
      if(UseImpulseRangeFilter && range < ps.atr_m15 * 1.0) return ps; // range too small → not tradable

      // Breakout reference = the channel high price broke through.
      // Prefer the Renko Donchian upper (the actual breakout level); else
      // fall back to the bar-based channel high.
      double breakout_level = (g_renko_don_upper > 0) ? g_renko_don_upper : max_high;

      // Reference levels (kept in fib_* fields for CSV continuity):
      // fib_38 = breakout level; fib_50 = +0.5 range; fib_62 = +1.0 range
      ps.fib_38 = breakout_level;
      ps.fib_50 = breakout_level + range * 0.5;
      ps.fib_62 = breakout_level + range * 1.0;

      double current_close = iClose(_Symbol, _Period, 1); // confirmed M15 bar

      // breakout_extension: how far ABOVE the breakout level, in range units.
      // >0 = extended past breakout (normal); ~0 = fresh at breakout (ideal);
      // <0 = still inside channel (no breakout yet).
      ps.pullback_depth = (range > 0) ? (current_close - breakout_level) / range : 0;

      // "Healthy breakout zone": entered near the breakout, not over-extended.
      ps.in_golden_zone = (ps.pullback_depth >= 0.0 &&
                           ps.pullback_depth <= MaxBreakoutExtension);

      if(ps.atr_m15 > 0 && ps.ema20_value > 0)
         ps.dist_to_ema_atr = MathAbs(current_close - ps.ema20_value) / ps.atr_m15;
      else ps.dist_to_ema_atr = 0;

   } else {
      // Short breakout: price broke BELOW the channel low.
      double min_low  = lows[0];
      double max_high = highs[0];
      for(int i=1; i<lb; i++) {
         if(lows[i]  < min_low)  min_low  = lows[i];
         if(highs[i] > max_high) max_high = highs[i];
      }

      ps.impulse_high = max_high;
      ps.impulse_low  = min_low;

      double range = max_high - min_low;
      if(UseImpulseRangeFilter && range < ps.atr_m15 * 1.0) return ps;

      double breakout_level = (g_renko_don_lower > 0) ? g_renko_don_lower : min_low;

      ps.fib_38 = breakout_level;
      ps.fib_50 = breakout_level - range * 0.5;
      ps.fib_62 = breakout_level - range * 1.0;

      double current_close = iClose(_Symbol, _Period, 1);

      // Short extension: how far BELOW the breakout level (positive = extended down)
      ps.pullback_depth = (range > 0) ? (breakout_level - current_close) / range : 0;

      ps.in_golden_zone = (ps.pullback_depth >= 0.0 &&
                           ps.pullback_depth <= MaxBreakoutExtension);

      if(ps.atr_m15 > 0 && ps.ema20_value > 0)
         ps.dist_to_ema_atr = MathAbs(current_close - ps.ema20_value) / ps.atr_m15;
      else ps.dist_to_ema_atr = 0;
   }

   // Session / time context
   ps.session     = GetCurrentSession();
   ps.day_of_week = GetDayOfWeek();
   ps.hour_utc    = GetHourUTC();

   // Vol filter (hard gate — stays as blocker even in v1.1)
   if(UseVolFilter && (ps.vol_ratio < VolRatioMin || ps.vol_ratio > VolRatioMax)) return ps;

   // Distance from EMA filter (soft — warns in log, doesn't block signal)
   // MaxEntryDistATRMult kept for logging; only blocks if > 1.5× (wide margin)
   // This allows indicator signals slightly outside the EMA zone (data-gather mode)

   // ── PRIMARY VALIDITY = Renko breakout signal in trade direction ──
   // ps.valid = true when Renko fires a breakout signal in the trade direction.
   // OPTION A: this IS a breakout strategy. "in_golden_zone" now means the
   // breakout is fresh (not over-extended), used as a score bonus, not a gate.
   int don_signal = GetDonchianEntrySignal();
   ps.valid = (don_signal == direction);

   // Log signal context (Renko engine already prints its own signal line)
   if(ps.valid) {
      Print(StringFormat("[ENTRY] %s | breakout_ext=%.3f fresh=%s atr=%.1fp "
                         "don_u=%.5f don_l=%.5f ema_align=%s bricks=%d",
            (direction==1)?"BUY":"SELL",
            ps.pullback_depth, ps.in_golden_zone?"YES":"NO(chased)",
            ps.atr_m15/PipSize(),
            g_renko_don_upper, g_renko_don_lower,
            (g_renko_ema_fast>g_renko_ema_slow)?"bull":"bear",
            g_renko_count));
   }
   return ps;
}

//+------------------------------------------------------------------+
//| CANDLE CONFIRMATION PATTERN (M15 — confirmed bar)                |
//+------------------------------------------------------------------+
string GetCandlePattern(int direction) {
   double open[], high[], low[], close[];
   const int need = 3;
   ArraySetAsSeries(open,  true); ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true); ArraySetAsSeries(close, true);
   if(CopyOpen (_Symbol,_Period,1,need,open) <need) return "NONE";
   if(CopyHigh (_Symbol,_Period,1,need,high) <need) return "NONE";
   if(CopyLow  (_Symbol,_Period,1,need,low)  <need) return "NONE";
   if(CopyClose(_Symbol,_Period,1,need,close)<need) return "NONE";

   double body  = MathAbs(close[0] - open[0]);
   double range = high[0] - low[0];
   if(range < _Point*3) return "NONE";

   double prev_body = MathAbs(close[1] - open[1]);
   if(body > prev_body * 1.8 && range > 0) {
      bool bullEngulf = (close[0] > open[0]) && (close[1] < open[1]);
      bool bearEngulf = (close[0] < open[0]) && (close[1] > open[1]);
      if(direction == 1 && bullEngulf) return "ENGULFING";
      if(direction == -1 && bearEngulf) return "ENGULFING";
   }

   double upper_shadow = high[0] - MathMax(close[0], open[0]);
   double lower_shadow = MathMin(close[0], open[0]) - low[0];
   if(direction == 1  && lower_shadow > body * 2.0 && lower_shadow > upper_shadow) return "PIN_BULL";
   if(direction == -1 && upper_shadow > body * 2.0 && upper_shadow > lower_shadow) return "PIN_BEAR";
   if(body > range * 0.65) {
      bool bullBody = (close[0] > open[0]);
      if(direction == 1  && bullBody) return "STRONG_BODY";
      if(direction == -1 && !bullBody) return "STRONG_BODY";
   }
   return "NONE";
}

//+------------------------------------------------------------------+
//| ADX READ (M15)                                                   |
//+------------------------------------------------------------------+
double GetADXValue() {
   if(adxM15Handle == INVALID_HANDLE) return 20.0;
   double buf[];
   if(CopyBuffer(adxM15Handle, 0, 1, 1, buf) < 1) return 20.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| RENKO ENGINE (v1.2)                                              |
//| In-memory ring buffer built from M15 confirmed bar closes.       |
//| Replaces DonchianBreakoutSystem_v2.1 iCustom() entirely.         |
//+------------------------------------------------------------------+

// ── Brick size from D1 ATR ─────────────────────────────────────────
double RenkoGetBrickSize() {
   if(g_atr_d1_handle != INVALID_HANDLE) {
      double atr[];
      if(CopyBuffer(g_atr_d1_handle, 0, 1, 1, atr) >= 1 && atr[0] > 0)
         return NormalizeDouble(atr[0] * RenkoBrickSizeATRMult,
                                (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   }
   // Fallback: M15 ATR × 8 ≈ D1 ATR
   double atr_m15 = GetATRValue_M15();
   if(atr_m15 > 0)
      return NormalizeDouble(atr_m15 * 8.0 * RenkoBrickSizeATRMult,
                             (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   return 10.0 * PipSize();
}

// ── Ring buffer access ─────────────────────────────────────────────
// rev_idx=0 = last confirmed brick, rev_idx=1 = brick before that, etc.
bool RenkoGetBrick(int rev_idx, RenkoBrick &b) {
   if(g_renko_count == 0) return false;
   int max_b = ArraySize(g_renko_bricks);
   if(max_b == 0) return false;
   int avail = MathMin(g_renko_count, max_b);
   if(rev_idx >= avail) return false;
   // Most recent brick is at index (g_renko_count-1) % max_b
   int idx = ((g_renko_count - 1 - rev_idx) % max_b + max_b) % max_b;
   b = g_renko_bricks[idx];
   return true;
}

// ── Process one confirmed M15 bar close → append bricks ────────────
void RenkoProcessClose(double price, datetime bar_time) {
   double bs = g_renko_brick_size;
   if(bs <= 0) return;

   if(g_renko_forming == 0) {
      g_renko_forming  = price;
      g_renko_form_dir = 0;
      return;
   }

   double reversal = RenkoReversal2x ? bs * 2.0 : bs;
   int    max_b    = ArraySize(g_renko_bricks);
   if(max_b == 0) return;

   // UP bricks
   while(price >= g_renko_forming + bs) {
      if(g_renko_form_dir == -1 && RenkoReversal2x) {
         if(price < g_renko_forming + reversal) break;
         g_renko_forming += bs; // consume extra
      }
      int idx = g_renko_count % max_b;
      g_renko_bricks[idx].open       = g_renko_forming;
      g_renko_bricks[idx].close      = g_renko_forming + bs;
      g_renko_bricks[idx].direction  = 1;
      g_renko_bricks[idx].time_formed= bar_time;
      g_renko_count++;
      g_renko_forming += bs;
      g_renko_form_dir = 1;
   }
   // DOWN bricks
   while(price <= g_renko_forming - bs) {
      if(g_renko_form_dir == 1 && RenkoReversal2x) {
         if(price > g_renko_forming - reversal) break;
         g_renko_forming -= bs;
      }
      int idx = g_renko_count % max_b;
      g_renko_bricks[idx].open       = g_renko_forming;
      g_renko_bricks[idx].close      = g_renko_forming - bs;
      g_renko_bricks[idx].direction  = -1;
      g_renko_bricks[idx].time_formed= bar_time;
      g_renko_count++;
      g_renko_forming -= bs;
      g_renko_form_dir = -1;
   }
}

// ── Build history from CopyClose on OnInit ─────────────────────────
void RenkoInitHistory() {
   g_renko_count    = 0;
   g_renko_forming  = 0;
   g_renko_form_dir = 0;
   g_renko_brick_size = RenkoGetBrickSize();
   if(g_renko_brick_size <= 0) {
      Print("[RENKO] ERROR: brick_size=0 at init — check D1 ATR handle");
      return;
   }

   // Fetch enough M15 bars to build a healthy brick history.
   // CRITICAL: at brick_size=13p and avg M15 move ~4p, you need MANY bars
   // per brick. Empirically ~30-40 M15 bars per brick in ranging markets.
   // To guarantee MaxRenkoBricks bricks: fetch generously and cap by what's available.
   // 1500 bars gave only ~40 bricks (warmup fail). Need ~10000+ for 300 bricks.
   int need_bars = MathMax(MaxRenkoBricks * 40, 12000);  // ~40 M15 bars per brick estimate
   int avail     = Bars(_Symbol, _Period);
   need_bars     = MathMin(need_bars, avail - 2);
   if(need_bars < 500) need_bars = MathMin(500, avail - 2);

   double closes[]; datetime times[];
   int got = CopyClose(_Symbol, _Period, 1, need_bars, closes); // shift=1: confirmed bars
   if(got <= 0) { Print("[RENKO] CopyClose failed on init"); return; }
   CopyTime(_Symbol, _Period, 1, got, times);

   // CopyClose returns index 0=newest; process oldest→newest
   for(int i = got-1; i >= 0; i--)
      RenkoProcessClose(closes[i], times[i]);

   Print(StringFormat("[RENKO] Init: %d bricks from %d M15 bars | brick_size=%.5f (%.1fp) | mult=%.2f",
         g_renko_count, got, g_renko_brick_size,
         g_renko_brick_size/PipSize(), RenkoBrickSizeATRMult));
}

// ── Donchian on bricks (by confirmed-brick count) ──────────────────
// BUG J FIX: Donchian must exclude the LAST (current) brick, otherwise
// last.close is always part of don_upper and the strict > comparison can
// never be satisfied for a breakout brick. We scan bricks i=1..period
// (the `period` bricks BEFORE the current one) — standard Donchian breakout:
// "does the current brick close beyond the prior N-brick high/low?"
double RenkoDonUpper(int period) {
   if(g_renko_count < period + 1) return 0;
   double hh = -DBL_MAX;
   for(int i = 1; i <= period; i++) {        // skip i=0 (current brick)
      RenkoBrick b; if(!RenkoGetBrick(i, b)) break;
      double hi = MathMax(b.open, b.close);
      if(hi > hh) hh = hi;
   }
   return (hh > -DBL_MAX) ? hh : 0;
}
double RenkoDonLower(int period) {
   if(g_renko_count < period + 1) return 0;
   double ll = DBL_MAX;
   for(int i = 1; i <= period; i++) {        // skip i=0 (current brick)
      RenkoBrick b; if(!RenkoGetBrick(i, b)) break;
      double lo = MathMin(b.open, b.close);
      if(lo < ll) ll = lo;
   }
   return (ll < DBL_MAX) ? ll : 0;
}

// ── EMA on brick closes ────────────────────────────────────────────
double RenkoEMABricks(int period) {
   int max_b = ArraySize(g_renko_bricks);
   if(max_b == 0 || g_renko_count < period) return 0;
   int avail = MathMin(g_renko_count, max_b);
   // Warm-up: use 3× period starting from oldest available brick
   int warmup_start = MathMax(0, avail - period * 3);
   double k   = 2.0 / (period + 1.0);
   // Get oldest warmup brick
   RenkoBrick b0;
   if(!RenkoGetBrick(avail - 1 - warmup_start, b0)) return 0;
   double ema = b0.close;
   for(int i = avail - 2 - warmup_start; i >= 0; i--) {
      RenkoBrick b; if(!RenkoGetBrick(i, b)) break;
      ema = b.close * k + ema * (1.0 - k);
   }
   return ema;
}

// ── Update Renko on each new confirmed M15 bar ─────────────────────
void RenkoUpdateOnNewBar() {
   double price = iClose(_Symbol, _Period, 1); // last confirmed bar
   datetime bt  = iTime(_Symbol,  _Period, 1);
   RenkoProcessClose(price, bt);
}

// ── Daily sniper reset ─────────────────────────────────────────────
void RenkoResetSniperIfNewDay() {
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   datetime today_start = TimeCurrent() -
      (mdt.hour * 3600 + mdt.min * 60 + mdt.sec);
   if(today_start != g_renko_sniper_reset_day) {
      g_renko_sniper_buy_fired  = false;
      g_renko_sniper_sell_fired = false;
      g_renko_sniper_reset_day  = today_start;
   }
}

// ── Main signal computation (called at bar gate) ───────────────────
void RenkoComputeSignal() {
   g_renko_signal    = 0;
   g_renko_don_upper = 0;
   g_renko_don_lower = 0;
   g_renko_ema_fast  = 0;
   g_renko_ema_slow  = 0;

   // Donchian now needs period+1 bricks (excludes current), so +1 margin
   int min_bricks = MathMax(RenkoDonPeriod + 1, RenkoEMASlowPeriod) + 5;
   if(g_renko_count < min_bricks) return;

   // Compute indicators on last confirmed bricks
   g_renko_don_upper = RenkoDonUpper(RenkoDonPeriod);
   g_renko_don_lower = RenkoDonLower(RenkoDonPeriod);
   g_renko_ema_fast  = RenkoEMABricks(RenkoEMAFastPeriod);
   g_renko_ema_slow  = RenkoEMABricks(RenkoEMASlowPeriod);

   if(g_renko_don_upper <= 0 || g_renko_don_lower <= 0) return;

   RenkoBrick last;
   if(!RenkoGetBrick(0, last)) return;  // last confirmed brick

   // Daily sniper reset
   RenkoResetSniperIfNewDay();

   // SniperMode: reset state when direction flips
   if(last.direction == -1) g_renko_sniper_buy_fired  = false;
   if(last.direction ==  1) g_renko_sniper_sell_fired = false;

   // FIX (v1.47, frequency branch): second, faster re-arm path — re-open a
   // direction after SniperReArmBars M15 bars have elapsed since it last fired,
   // even without a reversal brick. Whichever re-arm condition is met first
   // (reversal brick, above, or bar-count timeout, here) wins; this does not
   // remove the reversal-brick reset, it just adds a second way back in.
   if(SniperReArmBars > 0) {
      if(g_renko_sniper_buy_fired && g_renko_sniper_buy_fired_time > 0) {
         int bars_since_buy = (int)((TimeCurrent() - g_renko_sniper_buy_fired_time) / 900);
         if(bars_since_buy >= SniperReArmBars) g_renko_sniper_buy_fired = false;
      }
      if(g_renko_sniper_sell_fired && g_renko_sniper_sell_fired_time > 0) {
         int bars_since_sell = (int)((TimeCurrent() - g_renko_sniper_sell_fired_time) / 900);
         if(bars_since_sell >= SniperReArmBars) g_renko_sniper_sell_fired = false;
      }
   }

   bool ema_bull = (!RenkoRequireEMAAlign) ||
                   (g_renko_ema_fast > g_renko_ema_slow);
   bool ema_bear = (!RenkoRequireEMAAlign) ||
                   (g_renko_ema_fast < g_renko_ema_slow);

   // Raw breakout condition (brick direction + Donchian break), BEFORE the
   // EMA-align and SniperMode filters are applied. Used only for the
   // diagnostic below, so a "channel broke but signal=0" case can be
   // attributed to the correct filter instead of just showing signal=0 and
   // leaving the operator to guess which of the three AND-conditions ate it.
   bool raw_up_break   = (last.direction == 1  && last.close > g_renko_don_upper);
   bool raw_down_break = (last.direction == -1 && last.close < g_renko_don_lower);

   // BUY: last confirmed brick UP + close > Donchian upper
   if(last.direction == 1 &&
      last.close > g_renko_don_upper &&
      ema_bull &&
      (!UseSniperMode || !g_renko_sniper_buy_fired)) {
      g_renko_signal = 1;
      g_renko_sniper_buy_fired = true;
      g_renko_sniper_buy_fired_time = TimeCurrent();
   }
   // SELL: last confirmed brick DOWN + close < Donchian lower
   else if(last.direction == -1 &&
           last.close < g_renko_don_lower &&
           ema_bear &&
           (!UseSniperMode || !g_renko_sniper_sell_fired)) {
      g_renko_signal = -1;
      g_renko_sniper_sell_fired = true;
      g_renko_sniper_sell_fired_time = TimeCurrent();
   }

   // DIAGNOSTIC (bot4 audit, 2026-08): the channel legitimately broke out
   // (raw_up_break/raw_down_break) but no signal fired — attribute WHY, so
   // "Renko looks broken" reports can be distinguished from "Renko is
   // working exactly as configured, EMA/Sniper is the reason it's quiet".
   // Throttled (once per ~20 evaluations) to avoid log spam on M15.
   if(g_renko_signal == 0 && (raw_up_break || raw_down_break) && DiagnosticMode) {
      g_diag_renko_channel_break_no_signal++;
      if(g_diag_renko_channel_break_no_signal % 20 == 1) {
         string blocked_by = "";
         if(raw_up_break) {
            if(!ema_bull) blocked_by = "EMA_MISALIGN(fast<=slow)";
            else if(UseSniperMode && g_renko_sniper_buy_fired) blocked_by = "SNIPER_ALREADY_FIRED_BUY";
         } else {
            if(!ema_bear) blocked_by = "EMA_MISALIGN(fast>=slow)";
            else if(UseSniperMode && g_renko_sniper_sell_fired) blocked_by = "SNIPER_ALREADY_FIRED_SELL";
         }
         Print(StringFormat("[RENKO-DIAG] Channel broke (%s) but signal=0 | blocked_by=%s | "
                            "close=%.5f don_u=%.5f don_l=%.5f ema_fast=%.5f ema_slow=%.5f "
                            "RequireEMAAlign=%s SniperMode=%s",
               raw_up_break?"UP":"DOWN", (blocked_by!="")?blocked_by:"UNKNOWN",
               last.close, g_renko_don_upper, g_renko_don_lower,
               g_renko_ema_fast, g_renko_ema_slow,
               RenkoRequireEMAAlign?"true":"false", UseSniperMode?"true":"false"));
      }
   }

   if(g_renko_signal != 0) {
      Print(StringFormat("[RENKO] Signal %s | brick=%s close=%.5f don_u=%.5f don_l=%.5f "
                         "ema20=%.5f ema50=%.5f bricks=%d brick_size=%.1fp",
            (g_renko_signal==1)?"BUY":"SELL",
            (last.direction==1)?"UP":"DOWN", last.close,
            g_renko_don_upper, g_renko_don_lower,
            g_renko_ema_fast, g_renko_ema_slow,
            g_renko_count, g_renko_brick_size/PipSize()));
   }
}

// ── Compatibility wrappers (keep same call sites as v1.1) ──────────
int GetDonchianEntrySignal()           { return g_renko_signal; }
double GetDonchianSignalLevel(int dir) {
   // Returns the Renko brick close that generated the signal (price level for CSV)
   if(g_renko_signal != dir) return 0;
   RenkoBrick b;
   if(RenkoGetBrick(0, b)) return b.close;
   return 0;
}

//+------------------------------------------------------------------+
//| SCORE CALCULATION                                                |
//+------------------------------------------------------------------+
// Returns: 0–100 score (weighted sum of trend quality + pullback quality)
// Also populates TrendState and PullbackState
int CalculateSignalScore(int direction, TrendState &ts, PullbackState &ps) {
   int score = 0;

   // ── D1 Bias score (max ScoreD1BiasMax = 30) ──────────────────────
   if(ts.d1_bias == direction) {
      int d1pts = ScoreD1BiasMax / 2;         // base for correct direction
      if(ts.d1_ema_aligned) d1pts += ScoreD1BiasMax / 4;
      if(ts.d1_don_bullish == (direction==1)) d1pts += ScoreD1BiasMax / 4;
      // FIX (v1.47, frequency branch): WEAK_TRADEABLE (D1-only, no H4 confirm)
      // now reaches scoring instead of being hard-rejected in GetTrendState().
      // Apply an explicit penalty here so it still competes honestly against
      // ShadowScoreThreshold/LiveScoreThreshold rather than scoring identically
      // to a fully-confirmed STRONG/MODERATE setup.
      if(ts.bias_strength == "WEAK_TRADEABLE") d1pts = d1pts / 2;
      score += d1pts;
   }

   // ── H4 Confirmation score (max ScoreH4ConfirmMax = 20) ───────────
   if(ts.h4_confirm == direction) {
      int h4pts = ScoreH4ConfirmMax / 2;
      if(ts.h4_breakout_fresh) h4pts += ScoreH4ConfirmMax / 2;
      score += h4pts;
   } else if(ts.h4_confirm == 0) {
      score += ScoreH4ConfirmMax / 4; // neutral = partial credit
   }

   // ── Pullback Quality score (max ScorePullbackQualMax = 30) — v1.1 ─
   // v1.1: Donchian M15 signal = primary trigger (already in ps.valid).
   // Scoring here rewards QUALITY CONTEXT: Fib zone, candle, EMA proximity.
   // All points are additive bonuses — none are blockers.
   // ps.valid=false (no Donchian signal) still allowed at shadow-score level:
   // it logs the bar context even without a signal firing (for noise analysis).

   // Candle pattern — always compute for CSV logging
   string cand = GetCandlePattern(direction);
   ps.candle_pattern = cand;

   if(ps.valid) {
      int pbpts = 0;

      // Renko breakout signal fired in trend direction = base quality (+15)
      pbpts += 15;

      // OPTION A — breakout quality: reward FRESH entries (near breakout level),
      // penalize chasing (price already extended far past the breakout).
      // ps.in_golden_zone == healthy (extension within [0, MaxBreakoutExtension]).
      if(UseFibZone && ps.in_golden_zone) pbpts += 8;
      // Freshest breakouts (extension < 0.25 range past the level) = best entry (+4)
      if(ps.in_golden_zone) {
         double ext = ps.pullback_depth;     // breakout extension (range units)
         if(ext >= 0.0 && ext < 0.25) pbpts += 4;       // fresh, not chased
         else if(ext >= 0.25 && ext < 0.50) pbpts += 2; // still acceptable
      }

      // Candle confirmation bonus (+3/+2/+1)
      if(!UseCandleConfirm || cand == "ENGULFING")  pbpts += 3;
      else if(cand == "PIN_BULL" || cand == "PIN_BEAR") pbpts += 2;
      else if(cand == "STRONG_BODY")                    pbpts += 1;

      // EMA20 proximity bonus (+2): price close to EMA at entry
      if(ps.atr_m15 > 0 && ps.dist_to_ema_atr < 0.5) pbpts += 2;

      score += MathMin(pbpts, ScorePullbackQualMax);
   } else {
      // No Renko signal — partial score only for shadow logging
      if(UseFibZone && ps.in_golden_zone) score += 4;
   }

   // ── ADX + Volatility score (max ScoreADXVolMax = 20) ─────────────
   // FIX (v1.46, dead-parameter repair): was a flat pass/fail bonus, so
   // CalculateSignalScore only ever landed on a handful of discrete totals
   // — which is why LiveScoreThreshold sweeps (20..50) showed zero effect
   // in 305/305 sweep pairs: most real signals either cleared every
   // threshold in the range or none of them, with nothing in between.
   // Now scored proportionally to how far ADX sits inside its ideal band
   // and how close vol_ratio is to 1.0, so the total score actually varies
   // continuously trade-to-trade and the threshold sweep has real bite.
   double adx = GetADXValue();
   if(UseADXGate && adx >= ADXMinEntry && adx <= ADXMaxEntry) {
      int adxpts = ScoreADXVolMax / 2; // base for clearing the gate at all
      // Continuous bonus for proximity to the 25-40 "ideal" ADX zone.
      double adx_mid = 32.5, adx_half_width = 7.5;
      double adx_prox = 1.0 - MathMin(1.0, MathAbs(adx - adx_mid) / (adx_half_width * 3.0));
      adxpts += (int)MathRound((ScoreADXVolMax / 4.0) * adx_prox);
      // Continuous bonus for vol_ratio proximity to 1.0 (normal volatility).
      double vol_prox = 1.0 - MathMin(1.0, MathAbs(ps.vol_ratio - 1.0) / 0.6);
      adxpts += (int)MathRound((ScoreADXVolMax / 4.0) * MathMax(0.0, vol_prox));
      score += adxpts;
   } else if(!UseADXGate) {
      score += ScoreADXVolMax / 2;
   }

   return MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| LOT SIZING                                                       |
//+------------------------------------------------------------------+
double CalculateLotForLevel(int level_idx) {
   double mult = LOT_LADDER[MathMin(level_idx, 3)];
   double base_lot;
   if(UseRiskSizing && level_idx == 0) {
      // Risk-based sizing for L1 only
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_amt = equity * RiskPercentL1 / 100.0;
      double sl_dist  = BasketSLATRMult * GetATRValue_M15();
      double vpip     = ValuePerPoint();
      if(sl_dist > 0 && vpip > 0)
         base_lot = risk_amt / (sl_dist / _Point * vpip);
      else
         base_lot = BaseLotSize;
      base_lot = NormalizeVolume(base_lot);
   } else {
      base_lot = BaseLotSize;
   }
   return NormalizeVolume(base_lot * mult);
}

//+------------------------------------------------------------------+
//| BASKET P&L HELPERS                                               |
//+------------------------------------------------------------------+
double GetBasketPnL() {
   double total = 0;
   for(int i = 0; i < g_pyr.active_levels; i++) {
      if(g_pyr.level[i].ticket == 0) continue;
      if(position.SelectByTicket(g_pyr.level[i].ticket)) {
         total += position.Profit() + position.Swap() + position.Commission();
         continue;
      }
      // FIX (2026-07-22): the position wasn't found among OPEN positions.
      // This happens when the broker's own native SL/TP order (attached at
      // open — see broker_sl in OpenPyramidLevel) fires before the EA's own
      // tick-based price check gets to it: the position closes at the
      // broker level, and by the time this function runs, it's gone from
      // the live list entirely. The old code silently treated that as
      // "contributes 0" — which is how two real closed trades
      // (2026-07-21 03:29, 2026-07-22 00:03, the second one at 1.02 lots
      // under risk-sizing) logged R=0.00/pnl=0.00 despite a real fill and a
      // real close. Look up the actual closed deal from history instead of
      // assuming zero.
      if(HistorySelectByPosition(g_pyr.level[i].ticket)) {
         int deals = HistoryDealsTotal();
         for(int d = 0; d < deals; d++) {
            ulong deal_ticket = HistoryDealGetTicket(d);
            if(deal_ticket == 0) continue;
            if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
               total += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            }
         }
      } else {
         Print(StringFormat("[PNL_LOOKUP] WARNING: ticket=%d not found in open "
               "positions or history — P&L for this leg is genuinely unknown, "
               "not zero. Investigate manually.", g_pyr.level[i].ticket));
      }
   }
   return total;
}
double GetBasketPnLPct() {
   if(g_pyr.basket_open_equity <= 0) return 0;
   return GetBasketPnL() / g_pyr.basket_open_equity * 100.0;
}
double GetBasketRMultiple() {
   if(g_pyr.initial_risk_r <= 0) return 0;
   return GetBasketPnL() / g_pyr.initial_risk_r;
}
double GetTotalFloatingPnL() {
   double total = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      long magic = position.Magic();
      if(magic >= 60001 && magic <= 60099)
         total += position.Profit() + position.Swap();
   }
   return total;
}

//+------------------------------------------------------------------+
//| CHANDELIER STOP CALCULATION (H1)                                 |
//+------------------------------------------------------------------+
double CalculateChandelierStop(int direction) {
   // Chandelier: highest_high(period) - ATR(period) * mult  [for long]
   //             lowest_low(period)  + ATR(period) * mult   [for short]
   int period = ChandelierPeriod;
   double atrH1 = GetATRValue_H1();
   double raw_stop;

   // FIX (v1.48, fast-exit branch): once a basket has locked in FastExitLockRMult
   // profit, swap the wide ChandelierATRMult for the tighter FastExitTightenedATRMult
   // so the trail follows price much closer and banks gains sooner. Only active
   // when UseFastExitMode=true; v1.47 behavior (always ChandelierATRMult) is
   // unchanged otherwise. Uses GetBasketRMultiple() — safe to call here since
   // this is only invoked from ManageActiveBasket() while a basket is open.
   double effective_mult = ChandelierATRMult;
   if(UseFastExitMode && GetBasketRMultiple() >= FastExitLockRMult)
      effective_mult = FastExitTightenedATRMult;

   if(direction == 1) {
      double h1highs[];
      if(CopyHigh(_Symbol, PERIOD_H1, 1, period, h1highs) < period) return 0;
      double hh = h1highs[0];
      for(int i=1; i<period; i++) if(h1highs[i] > hh) hh = h1highs[i];
      raw_stop = hh - atrH1 * effective_mult;
   } else {
      double h1lows[];
      if(CopyLow(_Symbol, PERIOD_H1, 1, period, h1lows) < period) return 0;
      double ll = h1lows[0];
      for(int i=1; i<period; i++) if(h1lows[i] < ll) ll = h1lows[i];
      raw_stop = ll + atrH1 * effective_mult;
   }

   // FIX (2026-07-26): root cause of Chandelier exits firing at hold=0min/
   // 1min, 45/55 of them losses, mean R=-0.24 across a whole GOLD test.
   // "highest_high(last 22 H1 bars)" can be an OLD spike unrelated to the
   // current breakout — GOLD is spiky/news-driven, so this is common, not
   // rare. When that happens, raw_stop can land at or above current price
   // for a fresh long, guaranteeing an instant exit instead of genuine
   // trailing protection. Sanity-check against current price: if the
   // computed level isn't at least a minimum distance on the correct side
   // of price right now, treat it as not-yet-meaningful (return 0 — the
   // caller already treats 0 as "inactive", relying on the hard SL until
   // a later bar produces a genuinely valid trailing level).
   double ref_price = (direction==1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double min_dist = GetMinStopDistance();
   if(direction == 1  && raw_stop > ref_price - min_dist) return 0;
   if(direction == -1 && raw_stop < ref_price + min_dist) return 0;
   return raw_stop;
}

//+------------------------------------------------------------------+
//| DONCHIAN-10 H1 EXIT STOP                                         |
//+------------------------------------------------------------------+
double CalculateDonchian10Exit(int direction) {
   int period = (int)DonchianExitPeriod;
   if(direction == 1) {
      // Long exit when H1 close drops below Donchian(10) H1 low
      return DonchianLower(PERIOD_H1, period, 1);
   } else {
      return DonchianUpper(PERIOD_H1, period, 1);
   }
}

//+------------------------------------------------------------------+
//| BASKET SL PRICE (initial and trailing)                           |
//+------------------------------------------------------------------+
double CalculateInitialSL(int direction, double entry_price) {
   double atr = GetATRValue_M15();
   double sl_dist = BasketSLATRMult * atr;
   double min_dist = GetMinStopDistance();
   sl_dist = MathMax(sl_dist, min_dist);
   if(direction == 1)  return NormalizeDouble(entry_price - sl_dist, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   else                return NormalizeDouble(entry_price + sl_dist, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

// After pyramid advance, trail basket SL to average_entry − 0.5×ATR
double CalculateTrailedSL(int direction) {
   if(g_pyr.active_levels == 0) return 0;
   // Weighted average entry
   double total_lots = 0, weighted_price = 0;
   for(int i = 0; i < g_pyr.active_levels; i++) {
      total_lots     += g_pyr.level[i].lot_size;
      weighted_price += g_pyr.level[i].entry_price * g_pyr.level[i].lot_size;
   }
   if(total_lots <= 0) return 0;
   double avg_entry = weighted_price / total_lots;
   double trail_dist = BETrailATRMult * GetATRValue_M15();
   double min_dist = GetMinStopDistance();
   trail_dist = MathMax(trail_dist, min_dist);
   if(direction == 1)  return NormalizeDouble(avg_entry - trail_dist, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   else                return NormalizeDouble(avg_entry + trail_dist, (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| SYNC BROKER-SIDE SL ON ALL OPEN UNITS (Fix #1)                  |
//| Called after every basket_sl_price change (pyramid add, trail).  |
//| Ensures VPS crash leaves positions with up-to-date broker SL.   |
//+------------------------------------------------------------------+
void UpdateAllBrokerSLs() {
   if(g_pyr.active_levels == 0 || g_pyr.basket_sl_price <= 0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl  = NormalizeDouble(g_pyr.basket_sl_price, digits);
   double min_dist = GetMinStopDistance();

   for(int i = 0; i < g_pyr.active_levels; i++) {
      if(g_pyr.level[i].ticket == 0) continue;
      if(!position.SelectByTicket(g_pyr.level[i].ticket)) continue;

      double current_pos_sl = position.StopLoss();
      // Only modify if SL changed meaningfully (avoid unnecessary server calls)
      bool needs_update;
      if(g_pyr.direction == 1)
         needs_update = (sl > current_pos_sl + _Point * 2);  // trail up for longs
      else
         needs_update = (sl < current_pos_sl - _Point * 2);  // trail down for shorts

      if(!needs_update) continue;

      // Validate SL distance from current price
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double ref = (g_pyr.direction == 1) ? bid : ask;
      double dist = MathAbs(ref - sl);
      if(dist < min_dist) {
         // Too close — use minimum distance
         sl = (g_pyr.direction == 1) ?
              NormalizeDouble(ref - min_dist, digits) :
              NormalizeDouble(ref + min_dist, digits);
      }

      bool mod_ok = trade.PositionModify(g_pyr.level[i].ticket, sl, 0);
      if(mod_ok) {
         g_pyr.level[i].sl_price = sl;
      } else {
         Print(StringFormat("[SL_SYNC] L%d ticket=%d FAILED rc=%d: %s",
               i+1, g_pyr.level[i].ticket,
               trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN PYRAMID LEVEL                                               |
//+------------------------------------------------------------------+
bool OpenPyramidLevel(int level_idx, int direction, string basket_id) {
   double lot = CalculateLotForLevel(level_idx);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (direction == 1) ? ask : bid;

   // ── Determine broker-side SL ──────────────────────────────────
   // L1: calculate from scratch (basket_sl_price not yet set)
   // L2+: use current basket_sl_price (already trailed from previous levels)
   double sl;
   if(g_pyr.basket_sl_price > 0 && level_idx > 0)
      sl = g_pyr.basket_sl_price;
   else
      sl = CalculateInitialSL(direction, price);

   // Safety: never send SL=0 or SL on wrong side
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   if(sl <= 0) {
      Print(StringFormat("[OPEN_L%d] ABORT: computed SL=0, cannot open safely", level_idx+1));
      return false;
   }
   double min_dist = GetMinStopDistance();
   double dist_check = MathAbs(price - sl);
   if(dist_check < min_dist) {
      // Expand SL to minimum required distance
      sl = (direction == 1) ?
           NormalizeDouble(price - min_dist, digits) :
           NormalizeDouble(price + min_dist, digits);
      Print(StringFormat("[OPEN_L%d] SL adjusted to min_dist: sl=%.5f", level_idx+1, sl));
   }
   // Sanity: SL must be on the correct side
   if(direction == 1 && sl >= price) {
      Print(StringFormat("[OPEN_L%d] ABORT: BUY but SL=%.5f >= price=%.5f", level_idx+1, sl, price));
      return false;
   }
   if(direction == -1 && sl <= price) {
      Print(StringFormat("[OPEN_L%d] ABORT: SELL but SL=%.5f <= price=%.5f", level_idx+1, sl, price));
      return false;
   }

   // ── BUG D FIX: Margin check before sending order ──────────────
   // FTMO uses dynamic leverage (XAU 1:20, FX 1:30, indices 1:10) and can
   // change it. Verify we have enough free margin for this lot before opening.
   double margin_required = 0;
   ENUM_ORDER_TYPE ord_type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ord_type, _Symbol, lot, price, margin_required)) {
      Print(StringFormat("[OPEN_L%d] ABORT: OrderCalcMargin failed (err=%d)",
            level_idx+1, GetLastError()));
      return false;
   }
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   // Require a safety multiple: free margin must cover this order + 50% buffer
   // (protects against simultaneous opens on other symbols + leverage changes)
   double margin_buffer = 1.5;
   if(free_margin < margin_required * margin_buffer) {
      Print(StringFormat("[OPEN_L%d] ABORT: insufficient margin. "
            "required=%.2f (×%.1f buffer=%.2f) free=%.2f",
            level_idx+1, margin_required, margin_buffer,
            margin_required * margin_buffer, free_margin));
      return false;
   }
   // Also check projected margin level stays healthy (> 200%)
   double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
   double projected_margin = margin_used + margin_required;
   if(projected_margin > 0) {
      double projected_level = equity_now / projected_margin * 100.0;
      if(projected_level < 200.0) {
         Print(StringFormat("[OPEN_L%d] ABORT: projected margin level %.0f%% < 200%% "
               "(equity=%.0f used=%.0f +req=%.0f)",
               level_idx+1, projected_level, equity_now, margin_used, margin_required));
         return false;
      }
   }

   // ── Send order with broker-side SL ───────────────────────────
   bool ok = false;
   int  max_retries = 3;
   uint last_retcode = 0;
   // Tag every order's comment with which config produced it (RunProfileTag),
   // so History/Comment shows e.g. "AGGR_B4_20260726_1435_BUY_L1" instead of
   // a generic "Bot4_..." — lets you tell which .set file actually opened a
   // given trade when running the same symbol/window under multiple profiles.
   string profile_tag = (StringLen(RunProfileTag) > 0) ? RunProfileTag : "Bot4";
   for(int attempt = 1; attempt <= max_retries; attempt++) {
      if(direction == 1)
         ok = trade.Buy(lot, _Symbol, 0, sl, 0,
                        StringFormat("%s_%s_L%d", profile_tag, basket_id, level_idx+1));
      else
         ok = trade.Sell(lot, _Symbol, 0, sl, 0,
                         StringFormat("%s_%s_L%d", profile_tag, basket_id, level_idx+1));

      last_retcode = trade.ResultRetcode();
      if(ok) break;

      // Fix #5: ORDER_FILLING_RETURN fallback on FOK failure
      // TRADE_RETCODE_INVALID_FILL (10016) or TRADE_RETCODE_REQUOTE (10004)
      if(last_retcode == 10016 || last_retcode == 10004) {
         if(attempt == 1) {
            // Retry with IOC filling
            trade.SetTypeFilling(ORDER_FILLING_IOC);
            Print(StringFormat("[OPEN_L%d] FOK failed rc=%d, retrying with IOC (attempt %d)",
                  level_idx+1, last_retcode, attempt+1));
            continue;
         } else if(attempt == 2) {
            // Final retry with RETURN filling
            trade.SetTypeFilling(ORDER_FILLING_RETURN);
            Print(StringFormat("[OPEN_L%d] IOC failed, retrying with RETURN (attempt %d)",
                  level_idx+1, attempt+1));
            continue;
         }
      }
      // Other errors: no retry
      break;
   }
   // Restore preferred filling mode after retries
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   if(!ok) {
      Print(StringFormat("[OPEN_L%d] FAILED after %d attempts. Last rc=%d: %s",
            level_idx+1, max_retries, last_retcode, trade.ResultRetcodeDescription()));
      return false;
   }

   ulong ticket = trade.ResultOrder();
   GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
   g_pyr.level[level_idx].ticket         = ticket;
   g_pyr.level[level_idx].entry_price    = price;
   g_pyr.level[level_idx].lot_size       = lot;
   g_pyr.level[level_idx].open_time      = TimeCurrent();
   g_pyr.level[level_idx].sl_price       = sl;
   g_pyr.level[level_idx].level_idx      = level_idx;
   g_pyr.level[level_idx].partial_closed = false;

   Print(StringFormat("[OPEN_L%d] %s %s lot=%.2f price=%.5f broker_sl=%.5f ticket=%d",
         level_idx+1, (direction==1)?"BUY":"SELL",
         _Symbol, lot, price, sl, ticket));
   return true;
}

//+------------------------------------------------------------------+
//| 2026-10-05: map bot4's free-text CloseBasket reason strings to    |
//| the shared short closure-reason codes used in position comments   |
//| (GGATE_REASON_*, see BossafxGuardGate.mqh — 31-char comment cap). |
//+------------------------------------------------------------------+
string Bot4GateReasonFromCloseReason(const string reason) {
   string r = reason;
   StringToUpper(r);
   if(StringFind(r, "TRAIL") >= 0 || StringFind(r, "TSL") >= 0) return GGATE_REASON_TSL;
   if(StringFind(r, "SL") >= 0 || StringFind(r, "STOP") >= 0)   return GGATE_REASON_SL;
   if(StringFind(r, "TP1") >= 0)                                 return GGATE_REASON_TP1;
   if(StringFind(r, "TP2") >= 0 || StringFind(r, "TARGET") >= 0 || StringFind(r, "TP") >= 0) return GGATE_REASON_FCT;
   return GGATE_REASON_MAN;
}

//+------------------------------------------------------------------+
//| CLOSE ENTIRE BASKET                                              |
//+------------------------------------------------------------------+
void CloseBasket(string reason) {
   if(g_pyr.active_levels == 0) return;

   double pnl     = GetBasketPnL();
   double pnlPct  = GetBasketPnLPct();
   double rMult   = GetBasketRMultiple();
   int    holdMin = (int)((TimeCurrent() - g_pyr.open_time) / 60);

   Print(StringFormat("[CLOSE_BASKET] reason=%s pnl=%.2f (%.3f%%) R=%.2f hold=%dmin depth=L%d",
         reason, pnl, pnlPct, rMult, holdMin, g_pyr.active_levels));

   // BUG G FIX: verify each close succeeds. If any fail (requote, market
   // closed, no connection), do NOT wipe tracking — retry next tick so the
   // position keeps its broker SL and stays managed instead of orphaned.
   int close_failures = 0;
   for(int i = g_pyr.active_levels-1; i >= 0; i--) {
      if(g_pyr.level[i].ticket == 0) continue;
      if(!position.SelectByTicket(g_pyr.level[i].ticket)) {
         // Position already gone (closed by broker SL) — clear the slot
         g_pyr.level[i].ticket = 0;
         continue;
      }
      bool closed = GGate_CloseTagged(trade, g_pyr.level[i].ticket, Bot4GateReasonFromCloseReason(reason));
      if(closed) {
         g_pyr.level[i].ticket = 0;
      } else {
         close_failures++;
         Print(StringFormat("[CLOSE_BASKET] L%d close FAILED rc=%d (%s) — keeping tracking",
               i+1, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      }
   }
   if(close_failures > 0) {
      // Some positions still open — keep g_pyr intact, retry next tick.
      // Re-sync broker SLs so the survivors stay protected.
      Print(StringFormat("[CLOSE_BASKET] %d close(s) failed — basket NOT zeroed, "
            "will retry. Broker SLs remain active.", close_failures));
      // Compact active_levels: drop closed slots, keep open ones
      int still_open = 0;
      for(int i = 0; i < g_pyr.active_levels; i++)
         if(g_pyr.level[i].ticket != 0) still_open++;
      if(still_open == 0) {
         // All actually closed despite reported failures — safe to zero
         DecrementGroupPyramidCount(CorrelationGroup);
         ZeroMemory(g_pyr);
         g_pyr.active_levels = 0;
      }
      return;  // keep tracking the survivors; do not run cooldown/log yet
   }

   // Update cooldown timers
   // FIX (2026-07-21): g_cooldown_sl_time/g_cooldown_tp_time were plain
   // in-memory globals, never persisted — unlike g_overall_stop_hit, which
   // already uses GlobalVariableSet/Check for exactly this reason. Confirmed
   // via CSV: a basket opened 2026-07-20 21:02:39, only 1h35m after a
   // 19:27:33 SL close, deep inside what should have been a 12h/48-bar
   // cooldown. A restart between those two times would silently zero this
   // variable and let the entry through with no gate ever blocking it.
   // FIX (v1.49, regime-suite branch): the old substring match
   // (StringFind(reason,"SL")>=0 || StringFind(reason,"STOP")>=0) silently
   // missed v1.48's "TIMEOUT_HARD" reason — a hard time-stop closing a
   // stagnant/losing trade is exactly the "I was wrong, don't immediately
   // re-enter" case the cooldown exists for, but it matched NEITHER branch
   // (no "SL" or "STOP" substring, no "TP"/"TRAIL"/"CHANDELIER"/
   // "DONCHIAN_EXIT" substring either) so it registered zero cooldown at
   // all. Replaced with an explicit, exhaustive classification of every
   // reason string CloseBasket() is actually called with (grepped: BASKET_SL,
   // D1_REVERSAL_EXIT, TIMEOUT_HARD, GLOBAL_EQUITY_STOP, DAILY_EQUITY_STOP,
   // CHANDELIER_EXIT, DONCHIAN10_EXIT, GROQ_EARLY_CLOSE, FRIDAY_CLOSE) so a
   // new reason string added later fails LOUD (falls into the "unclassified"
   // else with a Print warning) instead of silently getting no cooldown.
   bool is_loss_like_close =
      (reason == "BASKET_SL" || reason == "D1_REVERSAL_EXIT" ||
       reason == "TIMEOUT_HARD" || reason == "GLOBAL_EQUITY_STOP" ||
       reason == "DAILY_EQUITY_STOP");
   bool is_win_like_close =
      (reason == "CHANDELIER_EXIT" || reason == "DONCHIAN10_EXIT" ||
       reason == "GROQ_EARLY_CLOSE");
   // FRIDAY_CLOSE is deliberately neutral — a housekeeping close, not evidence
   // the trade was right or wrong, so it registers no cooldown either way.

   if(is_loss_like_close) {
      g_cooldown_sl_time = TimeCurrent();
      GlobalVariableSet("B4_COOL_SL_" + _Symbol, (double)g_cooldown_sl_time);
      recentStreak = (recentStreak > 0) ? -1 : recentStreak - 1;
      recentResults = StringSubstr(recentResults+"L", 0, 8);
   } else if(is_win_like_close) {
      g_cooldown_tp_time = TimeCurrent();
      GlobalVariableSet("B4_COOL_TP_" + _Symbol, (double)g_cooldown_tp_time);
      recentStreak = (recentStreak < 0) ? 1 : recentStreak + 1;
      recentResults = StringSubstr(recentResults+"W", 0, 8);
   } else if(reason != "FRIDAY_CLOSE") {
      Print(StringFormat("[COOLDOWN-WARN] Unclassified CloseBasket reason '%s' — "
            "no cooldown registered. If this is a new exit path, add it to the "
            "is_loss_like_close/is_win_like_close classification in CloseBasket().",
            reason));
   }
   dailyTradeCount++;

   WriteBasketCloseLog(reason, pnl, pnlPct, rMult, holdMin);
   DecrementGroupPyramidCount(CorrelationGroup);
   ZeroMemory(g_pyr);
   g_pyr.active_levels = 0;
}

//+------------------------------------------------------------------+
//| PARTIAL CLOSE (one unit or % of total)                          |
//+------------------------------------------------------------------+
void PartialCloseBasket(double pct) {
   if(g_pyr.partial_done) return;
   if(g_pyr.active_levels == 0) return;

   // Close a percentage of the OLDEST (L1) unit lot first
   for(int i = 0; i < g_pyr.active_levels; i++) {
      if(g_pyr.level[i].ticket == 0 || g_pyr.level[i].partial_closed) continue;
      if(!position.SelectByTicket(g_pyr.level[i].ticket)) continue;

      // BUG E FIX: capture volume BEFORE the partial close (log was reading
      // the post-close volume, reporting the wrong percentage)
      double vol_before = position.Volume();
      double close_lot  = NormalizeVolume(vol_before * pct);
      double min_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(close_lot < min_lot) close_lot = min_lot;
      if(close_lot >= vol_before) close_lot = NormalizeVolume(vol_before * 0.5);
      if(close_lot < min_lot) {
         Print(StringFormat("[PARTIAL_CLOSE] L%d skip: lot too small (vol=%.2f)",
               i+1, vol_before));
         break;
      }

      bool pc_ok = GGate_ClosePartialTagged(trade, g_pyr.level[i].ticket, close_lot, GGATE_REASON_TP1);
      if(pc_ok) {
         g_pyr.level[i].partial_closed = true;
         Print(StringFormat("[PARTIAL_CLOSE] L%d ticket=%d closed=%.2f (%.0f%% of %.2f)",
               i+1, g_pyr.level[i].ticket, close_lot, pct*100, vol_before));
      } else {
         Print(StringFormat("[PARTIAL_CLOSE] L%d FAILED rc=%d — will retry next trigger",
               i+1, trade.ResultRetcode()));
         return;  // don't set partial_done if the close failed
      }
      break; // close only L1 first
   }

   g_pyr.partial_done = true;
}

//+------------------------------------------------------------------+
//| MANAGE ACTIVE BASKET (per-tick + per-bar logic)                 |
//+------------------------------------------------------------------+
void ManageActiveBasket() {
   if(g_pyr.active_levels == 0) return;
   // bars_open is incremented at the bar gate in OnTick, not here
   // to prevent double-counting when ManageActiveBasket is called from multiple paths

   // ── Update trailing stops ──────────────────────────────────────
   if(UseChandelierTrail) {
      double new_chan = CalculateChandelierStop(g_pyr.direction);
      if(new_chan > 0) {
         // Trail only in favorable direction
         if(g_pyr.direction == 1 && (g_pyr.chandelier_stop == 0 || new_chan > g_pyr.chandelier_stop))
            g_pyr.chandelier_stop = new_chan;
         if(g_pyr.direction == -1 && (g_pyr.chandelier_stop == 0 || new_chan < g_pyr.chandelier_stop))
            g_pyr.chandelier_stop = new_chan;
      }
   }
   if(UseDonchianExit) {
      double new_d10 = CalculateDonchian10Exit(g_pyr.direction);
      if(new_d10 > 0) {
         if(g_pyr.direction == 1 && (g_pyr.don10_stop == 0 || new_d10 > g_pyr.don10_stop))
            g_pyr.don10_stop = new_d10;
         if(g_pyr.direction == -1 && (g_pyr.don10_stop == 0 || new_d10 < g_pyr.don10_stop))
            g_pyr.don10_stop = new_d10;
      }
   }

   // ── Pyramid advance check ─────────────────────────────────────
   // Add next unit if price advances PyramidSpacingMult × ATR(H4) from last entry
   // FIX (bot4 audit, 2026-08): was `< MaxPyramidLevels` (the raw, unclamped
   // input) — now uses the OnInit-clamped effective value so a stray
   // MaxPyramidLevels>4 in a .set/sweep can never index level[4]+.
   if(g_pyr.active_levels < g_max_pyramid_levels_effective) {
      int last_idx = g_pyr.active_levels - 1;
      double last_entry = g_pyr.level[last_idx].entry_price;
      double spacing    = PyramidSpacingMult * GetATRValue_H4();
      double current    = (g_pyr.direction==1) ?
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool advance = (g_pyr.direction == 1) ?
                     (current >= last_entry + spacing) :
                     (current <= last_entry - spacing);

      if(advance) {
         // FIX: ShadowModeOnly previously only gated the L1 open (see OnTick,
         // near the bottom). This pyramid-add path had NO such check — an
         // already-open live basket kept adding real L2/L3/L4 units even
         // after ShadowModeOnly was flipped to true. Confirmed live cause of
         // US30 trading while inputs showed ShadowModeOnly=true.
         if(ShadowModeOnly) return;

         // Check trend still valid
         TrendState ts = GetTrendState();
         bool trend_ok = (ts.overall_bias == g_pyr.direction);

         // Optionally check new setup (Option A: Renko still signals AND
         // breakout still fresh / not over-extended — avoids chasing on adds)
         bool setup_ok = true;
         if(PyramidRequiresSetup) {
            PullbackState ps2 = GetPullbackState(g_pyr.direction);
            setup_ok = (ps2.valid && ps2.in_golden_zone);
         }

         if(trend_ok && (!PyramidRequiresSetup || setup_ok)) {
            int new_idx = g_pyr.active_levels;
            if(OpenPyramidLevel(new_idx, g_pyr.direction, g_pyr.basket_id)) {
               g_pyr.active_levels++;
               // Trail basket SL up to avg_entry − BETrailATRMult
               double new_sl = CalculateTrailedSL(g_pyr.direction);
               bool sl_improved = (g_pyr.direction == 1 && new_sl > g_pyr.basket_sl_price) ||
                                  (g_pyr.direction == -1 && new_sl < g_pyr.basket_sl_price);
               if(sl_improved) {
                  g_pyr.basket_sl_price = new_sl;
                  // Fix #1: sync new trailed SL to broker on ALL open units
                  UpdateAllBrokerSLs();
               }

               WritePyramidLog(new_idx + 1, "PYRAMID_ADD", current);
               Print(StringFormat("[PYRAMID] Added L%d | advance=%.5f spacing=%.5f new_sl=%.5f",
                     new_idx+1, current, spacing, g_pyr.basket_sl_price));
               WriteGroqContinueRequest(g_pyr.active_levels);
               // FIX (2026-07-24): distinct visual marker for a REAL pyramid
               // add — separate from the scored-candidate arrows, which fire
               // on every evaluated signal regardless of outcome and made it
               // impossible to see actual pyramiding on the chart.
               if(ShowSignalVisuals) {
                  datetime bt = iTime(_Symbol, _Period, 0);
                  string mname = StringFormat("B4_PYRADD_%s_L%d_%d", _Symbol, new_idx+1, (long)bt);
                  long oid = 0;
                  if(ObjectFind(oid, mname) < 0)
                     ObjectCreate(oid, mname, OBJ_ARROW, 0, bt, current);
                  ObjectSetInteger(oid, mname, OBJPROP_ARROWCODE, 217); // filled circle
                  ObjectSetInteger(oid, mname, OBJPROP_COLOR, (g_pyr.direction==1)?clrDodgerBlue:clrMagenta);
                  ObjectSetInteger(oid, mname, OBJPROP_WIDTH, 4);
                  ObjectSetString(oid, mname, OBJPROP_TOOLTIP,
                     StringFormat("PYRAMID ADD L%d | price=%.5f new_sl=%.5f", new_idx+1, current, g_pyr.basket_sl_price));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DAILY STATS                                                      |
//+------------------------------------------------------------------+
void UpdateDailyStats() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);

   // BUG F FIX: portfolio-wide daily anchor via shared GlobalVariable.
   // FTMO measures daily loss against the BALANCE at broker midnight, across
   // the WHOLE account — not per-symbol, not from EA-start equity.
   // The first chart to see the new broker day sets the shared anchor;
   // all other charts read the same value.
   string gv_day    = "B4_DAY_START";       // datetime of current broker day
   string gv_balava = "B4_DAY_BALANCE";     // account balance at day start

   double stored_day = GlobalVariableCheck(gv_day) ? GlobalVariableGet(gv_day) : 0;
   if((datetime)stored_day != today) {
      // New broker day — first chart to notice sets the shared anchor
      GlobalVariableSet(gv_day, (double)today);
      GlobalVariableSet(gv_balava, AccountInfoDouble(ACCOUNT_BALANCE));
      // Reset the shared daily-stop flag for the new day
      GlobalVariableSet("B4_DAILY_STOP", 0.0);
      Print("[DAY] New broker day. Account balance anchor=",
            AccountInfoDouble(ACCOUNT_BALANCE));
   }

   // Local per-chart bookkeeping (used for display + trade count)
   if(today != lastDayStart) {
      lastDayStart     = today;
      startDayBalance  = GlobalVariableGet(gv_balava);
      dailyStartEquity = startDayBalance;   // anchor to balance, not equity
      dailyTradeCount  = 0;
      g_daily_stop_hit = false;
   }
}

bool IsDailyLossLimitReached() {
   if(MaxDailyLossAmount <= 0) return false;

   // BUG F FIX: portfolio-wide. Check shared flag first (set by any chart).
   if(GlobalVariableCheck("B4_DAILY_STOP") && GlobalVariableGet("B4_DAILY_STOP") > 0.5)
      return true;

   // Day-start balance is the shared anchor (broker midnight, whole account)
   double day_start_bal = GlobalVariableCheck("B4_DAY_BALANCE") ?
                          GlobalVariableGet("B4_DAY_BALANCE") :
                          AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // BUG FOUND (bot4 audit, 2026-08): matches Lessons-Learned class 2.1 from
   // the HYBRID bot1 audit. MaxDailyLossAmount/MaxOverallLossAmount are
   // FLAT-DOLLAR constants documented as "5% of 100k" / "10% of 100k" —
   // i.e. calibrated for one specific reference account size (InitialBalance
   // input, default 100000). If the ACTUAL account (Tester Deposit or live
   // balance) is smaller/larger than InitialBalance, these limits silently
   // stop meaning 5%/10% of the real account — e.g. on a 10k account,
   // MaxDailyLossAmount=5000 is actually a 50% daily-loss ceiling, wildly
   // outside the FTMO 5% rule this is supposed to enforce, and it never
   // shows up as a RiskPercent-insensitivity symptom because this EA uses
   // fixed BaseLotSize by default, not equity-scaled sizing. Fix: derive the
   // EFFECTIVE dollar limit by rescaling MaxDailyLossAmount by the same
   // ratio g_effective_initial_balance/InitialBalance already computed in
   // OnInit for the overall-loss reference point — preserves the intended
   // percentage regardless of what account size this actually runs against.
   // When InitialBalance matches the real account (the normal case), this
   // ratio is 1.0 and behavior is unchanged.
   double scale = (InitialBalance > 0) ? (g_effective_initial_balance / InitialBalance) : 1.0;
   double effective_daily_limit = MaxDailyLossAmount * scale;

   // FTMO daily loss = (day_start_balance - current_equity) across whole account
   bool hit = (day_start_bal - eq) >= (effective_daily_limit - SafetyBuffer);
   if(hit) {
      GlobalVariableSet("B4_DAILY_STOP", 1.0);  // broadcast to all charts
      Print("[FTMO-DAILY] Portfolio daily loss limit hit: day_start_bal=",
            day_start_bal, " equity=", eq,
            " loss=", day_start_bal - eq, " limit=", effective_daily_limit,
            " (input=", MaxDailyLossAmount, " scale=", scale, ")");
   }
   return hit;
}

bool IsOverallLossLimitReached() {
   if(MaxOverallLossAmount <= 0) return false;
   // Check in-memory flag (fast path)
   if(g_overall_stop_hit) return true;
   // Check persisted GlobalVariable (survives EA restart / MT5 crash)
   string gv = B4_OVERALL_HIT_VAR();
   if(GlobalVariableCheck(gv) && GlobalVariableGet(gv) > 0.5) {
      g_overall_stop_hit = true;  // restore to RAM
      return true;
   }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   // Same flat-$-vs-reference-account fix as IsDailyLossLimitReached() above
   // (bot4 audit, 2026-08) — MaxOverallLossAmount is calibrated for
   // InitialBalance; rescale by the same ratio so it means what it says
   // regardless of the account size actually running.
   double scale_overall = (InitialBalance > 0) ? (g_effective_initial_balance / InitialBalance) : 1.0;
   double effective_overall_limit = MaxOverallLossAmount * scale_overall;
   bool hit = (g_effective_initial_balance - eq) >= (effective_overall_limit - SafetyBuffer);
   if(hit) {
      g_overall_stop_hit = true;
      GlobalVariableSet(gv, 1.0);  // persist across restarts
      Print("[OVERALL-LOSS] Limit hit. Persisted to GlobalVariable: ", gv,
            " limit=", effective_overall_limit, " (input=", MaxOverallLossAmount,
            " scale=", scale_overall, ")");
   }
   return hit;
}

//+------------------------------------------------------------------+
//| NEWS FILTER (stub — extend with MQL5 Calendar)                  |
//+------------------------------------------------------------------+
bool IsNewsBlocked() {
   if(!UseNewsFilter) return false;
   // MQL5 Calendar integration
   MqlCalendarValue events[];
   datetime from = TimeCurrent() - NewsMinutesBefore*60;
   // FIX (2026-08 dead-parameter audit): this used NewsMinutesBefore for
   // BOTH bounds — NewsMinutesAfter was declared, documented ("wait 30 min
   // after high-impact"), but never actually referenced anywhere. The
   // block window was silently symmetric on NewsMinutesBefore alone.
   datetime to   = TimeCurrent() + NewsMinutesAfter*60;
   int cnt = (int)CalendarValueHistory(events, from, to, NULL, NULL);
   for(int i = 0; i < cnt; i++) {
      MqlCalendarEvent ev;
      if(!CalendarEventById(events[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH) {
         // Check if this currency is in our symbol
         MqlCalendarCountry country;
         if(!CalendarCountryById(ev.country_id, country)) continue;
         string cur = country.currency;
         if(StringFind(_Symbol, cur) >= 0) {
            Print(StringFormat("[NEWS] High-impact event blocked: %s %s", cur, ev.name));
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| GROQ INTEGRATION (adapted from Bot3)                             |
//+------------------------------------------------------------------+
bool WriteGroqOpenRequest(int direction, int score, TrendState &ts, PullbackState &ps, RiskContext &rc) {
   if(!UseGroqFilter) return false;

   // FIX (2026-08 dead-parameter audit): groqDailyCallCount was incremented
   // on every call and groqDayReset was declared for resetting it daily,
   // but nothing ever checked the count against GroqDailyCallLimit, and
   // groqDayReset was never actually used to reset anything — the counter
   // just grew forever, uncompared, for the life of the chart. Same for
   // GroqCooldownBars: groqLastCallBar was recorded but never checked
   // against it. Both now actually gate calls, matching what the inputs
   // already claimed to do.
   MqlDateTime dt_now; TimeToStruct(TimeCurrent(), dt_now);
   datetime today_start = TimeCurrent() - (dt_now.hour*3600 + dt_now.min*60 + dt_now.sec);
   if(today_start != groqDayReset) {
      groqDayReset = today_start;
      groqDailyCallCount = 0;
   }
   if(GroqDailyCallLimit > 0 && groqDailyCallCount >= GroqDailyCallLimit) {
      if(DiagnosticMode) Print(StringFormat("[GROQ] %s call skipped: daily limit %d reached",
            _Symbol, GroqDailyCallLimit));
      return false;
   }
   if(GroqCooldownBars > 0 && groqLastCallBar > 0) {
      datetime cur_bar = iTime(_Symbol, _Period, 0);
      int bars_since = (int)((cur_bar - groqLastCallBar) / PeriodSeconds(_Period));
      if(bars_since < GroqCooldownBars) {
         if(DiagnosticMode) Print(StringFormat("[GROQ] %s call skipped: cooldown %d/%d bars",
               _Symbol, bars_since, GroqCooldownBars));
         return false;
      }
   }

   string filename = AIRequestPath + _Symbol + ".json";
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE) return false;

   string dirStr = (direction == 1) ? "BUY" : "SELL";
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   string json = StringFormat(
      "{\"symbol\":\"%s\",\"timeframe\":\"M15\",\"direction\":\"%s\","
      "\"score\":%d,\"call_type\":\"PYRAMID_OPEN\",\"bot_id\":\"bot4\","
      "\"strategy\":\"TREND_FOLLOWING_PYRAMID\","
      "\"d1_bias\":\"%s\",\"d1_ema_aligned\":%s,"
      "\"h4_confirm\":\"%s\",\"h4_breakout_fresh\":%s,"
      "\"pullback_depth\":%.3f,\"in_golden_zone\":%s,"
      "\"fib_38\":%.5f,\"fib_62\":%.5f,"
      "\"candle_pattern\":\"%s\","
      "\"atr_m15_pips\":%.1f,\"atr_h4_pips\":%.1f,"
      "\"vol_ratio\":%.2f,\"adx_value\":%.1f,"
      "\"session\":\"%s\",\"day_of_week\":\"%s\",\"hour_utc\":%d,"
      "\"daily_loss_pct\":%.2f,\"open_pyramids\":%d,"
      "\"shadow_mode\":%s,\"live_score_threshold\":%d,"
      "\"account_equity\":%.2f}",
      _Symbol, dirStr,
      score,
      (ts.d1_bias==1)?"BULL":(ts.d1_bias==-1)?"BEAR":"NEUTRAL",
      ts.d1_ema_aligned?"true":"false",
      (ts.h4_confirm==1)?"BULL":(ts.h4_confirm==-1)?"BEAR":"NEUTRAL",
      ts.h4_breakout_fresh?"true":"false",
      ps.pullback_depth, ps.in_golden_zone?"true":"false",
      ps.fib_38, ps.fib_62,
      ps.candle_pattern,
      ps.atr_m15/PipSize(), ps.atr_h4/PipSize(),
      ps.vol_ratio, GetADXValue(),
      ps.session, ps.day_of_week, ps.hour_utc,
      rc.daily_loss_pct, rc.open_pyramids_total,
      ShadowModeOnly?"true":"false", LiveScoreThreshold,
      equity);

   FileWriteString(handle, json);
   FileClose(handle);
   groqLastCallBar = iTime(_Symbol, _Period, 0);
   groqDailyCallCount++;
   return true;
}

GroqResponse ReadGroqOpenResponse() {
   GroqResponse resp;
   resp.valid = false; resp.trade_action = "OPEN";
   resp.confidence = 0.5; resp.reason = ""; resp.trend_quality = "B";

   string filename = AIResponsePath + _Symbol + ".json";
   datetime deadline = TimeCurrent() + GroqTimeoutSeconds;
   while(TimeCurrent() < deadline) {
      if(!FileIsExist(filename)) { Sleep(200); continue; }
      int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle == INVALID_HANDLE) { Sleep(200); continue; }
      string content = "";
      while(!FileIsLineEnding(handle) && !FileIsEnding(handle))
         content += FileReadString(handle);
      FileClose(handle);
      FileDelete(filename);
      if(StringLen(content) < 5) break;
      resp.trade_action   = ExtractJsonString(content, "trade_action");
      resp.trend_quality  = ExtractJsonString(content, "trend_quality");
      resp.confidence     = ExtractJsonDouble(content, "confidence");
      resp.reason         = ExtractJsonString(content, "reason");
      resp.valid = true;
      if(resp.trade_action == "") resp.trade_action = "OPEN";
      break;
   }
   return resp;
}

void WriteGroqContinueRequest(int levelReached) {
   if(!UseGroqFilter) return;
   string filename = StringFormat("groqreq_BOT4_CONTINUE_%s_L%d.json", _Symbol, levelReached);
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE) return;

   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnlPct   = GetBasketPnLPct();
   double rMult    = GetBasketRMultiple();
   int    holdBars = g_pyr.bars_open;
   double holdHrs  = holdBars * PeriodSeconds(_Period) / 3600.0;
   string dirStr   = (g_pyr.direction==1) ? "BUY" : "SELL";
   TrendState ts   = GetTrendState();
   bool still_with = (ts.overall_bias == g_pyr.direction);

   string json = StringFormat(
      "{\"symbol\":\"%s\",\"call_type\":\"PYRAMID_CONTINUE\",\"bot_id\":\"bot4\","
      "\"basket_id\":\"%s\",\"level_reached\":%d,\"active_levels\":%d,"
      "\"direction\":\"%s\",\"basket_pnl_pct\":%.4f,\"r_multiple\":%.2f,"
      "\"hold_bars\":%d,\"hold_hours\":%.1f,"
      "\"d1_bias_still_valid\":%s,\"chandelier_stop\":%.5f,\"don10_stop\":%.5f,"
      "\"account_equity\":%.2f}",
      _Symbol, g_pyr.basket_id,
      levelReached, g_pyr.active_levels,
      dirStr, pnlPct, rMult,
      holdBars, holdHrs,
      still_with?"true":"false",
      g_pyr.chandelier_stop, g_pyr.don10_stop,
      eq);

   FileWriteString(handle, json);
   FileClose(handle);
   if(levelReached-1 < 4) g_pyr.continue_called[levelReached-1] = true;
}

bool CheckGroqContinueResponse(int levelReached) {
   // Hard rules first (no Groq needed)
   double pnlPct  = GetBasketPnLPct();
   double rMult   = GetBasketRMultiple();
   double holdHrs = g_pyr.bars_open * PeriodSeconds(_Period) / 3600.0;

   // For trend-following: close if trend reverses AND we're losing
   TrendState ts = GetTrendState();
   bool trend_flipped = (ts.overall_bias == -g_pyr.direction);
   if(UseD1ReversalExit && trend_flipped && pnlPct < 0) {
      Print(StringFormat("[CONTINUE] HARD CLOSE: D1 trend flipped against position pnl=%.3f%%", pnlPct));
      CloseBasket("D1_REVERSAL_EXIT");
      return true;
   }

   // Hard time-stop
   // FIX (v1.48, fast-exit branch): when UseFastExitMode=true, use the much
   // shorter FastExitTimestopHardBars instead of the v1.47 default (96 bars
   // / ~24h). v1.47 behavior unchanged when the mode is off.
   int effective_hard_bars = UseFastExitMode ? FastExitTimestopHardBars : TimestopHardBars;
   if(g_pyr.bars_open >= effective_hard_bars && rMult < TimestopHardMinR) {
      Print(StringFormat("[CONTINUE] HARD CLOSE: time-stop %dh R=%.2f < %.1f",
            (int)holdHrs, rMult, TimestopHardMinR));
      CloseBasket("TIMEOUT_HARD");
      return true;
   }

   // Soft time-stop — partial de-risk if stagnant.
   // NOTE: shares partial_done flag with the 2R partial by design — whichever
   // fires first does the de-risk; we don't want to partial twice on one basket.
   // FIX (v1.48, fast-exit branch): same override for the soft time-stop.
   int effective_soft_bars = UseFastExitMode ? FastExitTimestopSoftBars : TimestopSoftBars;
   if(g_pyr.bars_open >= effective_soft_bars && rMult < TimestopSoftMinR && !g_pyr.partial_done) {
      Print(StringFormat("[CONTINUE] SOFT: time-stop %dh R=%.2f < %.1f — partial de-risk %.0f%%",
            (int)holdHrs, rMult, TimestopSoftMinR, PartialClosePct*100));
      PartialCloseBasket(PartialClosePct);  // use configured pct, not hardcoded 0.50
   }

   // Read Groq response if available (continue checks)
   if(!UseGroqFilter) return false;
   string filename = StringFormat("groqresp_BOT4_CONTINUE_%s_L%d.json", _Symbol, levelReached);
   if(!FileIsExist(filename)) return false;
   int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle == INVALID_HANDLE) return false;
   string content = "";
   while(!FileIsLineEnding(handle) && !FileIsEnding(handle)) content += FileReadString(handle);
   FileClose(handle);
   FileDelete(filename);
   if(StringLen(content) < 5) return false;

   string assessment = ExtractJsonString(content, "continue_assessment");
   double confidence = ExtractJsonDouble(content, "confidence");
   string reason     = ExtractJsonString(content, "reason");
   Print(StringFormat("[CONTINUE-RESP] L%d assessment=%s conf=%.2f reason=%s",
         levelReached, assessment, confidence, reason));
   if(assessment == "CLOSE_EARLY" && confidence >= GroqMinConfidence) {
      CloseBasket("GROQ_EARLY_CLOSE");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| JSON PARSERS (carried from Bot3)                                 |
//+------------------------------------------------------------------+
string ExtractJsonString(const string &json, const string &key) {
   string search = "\"" + key + "\":\"";
   int pos = StringFind(json, search);
   if(pos < 0) return "";
   pos += StringLen(search);
   int end = StringFind(json, "\"", pos);
   if(end < 0) return "";
   return StringSubstr(json, pos, end - pos);
}
double ExtractJsonDouble(const string &json, const string &key) {
   string search = "\"" + key + "\":";
   int pos = StringFind(json, search);
   if(pos < 0) return 0;
   pos += StringLen(search);
   string val = "";
   for(int i = pos; i < StringLen(json); i++) {
      ushort c = StringGetCharacter(json, i);
      if(c=='"' || c==',' || c=='}' || c==']') break;
      val += StringSubstr(json, i, 1);
   }
   return StringToDouble(val);
}

//+------------------------------------------------------------------+
//| RISK CONTEXT EXPORT (for Groq logging)                          |
//+------------------------------------------------------------------+
RiskContext GetRiskContext() {
   RiskContext rc;
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   rc.daily_loss_pct       = (dailyStartEquity>0) ? (dailyStartEquity-eq)/dailyStartEquity*100.0 : 0;
   rc.max_daily_loss_reached = IsDailyLossLimitReached();
   rc.recent_win_loss_streak = recentStreak;
   rc.recent_results         = recentResults;
   rc.daily_trades_done      = dailyTradeCount;
   rc.day_of_week            = GetDayOfWeek();
   rc.hour_utc               = GetHourUTC();
   rc.symbol_class           = GetSymbolClass();
   rc.open_pyramids_total    = GetTotalOpenPyramids();
   rc.open_pyramids_same_group = 0; // simplified
   return rc;
}

//+------------------------------------------------------------------+
//| CSV SCHEMA GUARD (fix, applies to all 4 writers below)          |
//| Checks the existing file's header against the current expected  |
//| header. If they don't match (older build, fewer/different       |
//| columns), archives the old file instead of appending mismatched-  |
//| width rows under a stale header — the exact bug that silently    |
//| dropped ~2 weeks of candidate rows (labeler's on_bad_lines=skip   |
//| discards every row wider than the header, with no warning).      |
//| Returns true if a fresh header needs to be written.               |
//+------------------------------------------------------------------+
bool EnsureCsvSchema(string filename, string expected_header) {
   if(!FileIsExist(filename)) return true;   // no file yet — write fresh header

   int check_handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
   if(check_handle == INVALID_HANDLE) return true;
   string existing_header = FileReadString(check_handle);
   FileClose(check_handle);

   if(existing_header == expected_header) return false;  // schema matches, append normally

   // Mismatch — archive the old file under a dated name rather than corrupt it.
   string archive_name = filename;
   StringReplace(archive_name, ".csv", "");
   MqlDateTime mdt_arch; TimeToStruct(TimeCurrent(), mdt_arch);
   archive_name = archive_name + "_pre" +
      StringFormat("%04d%02d%02d", mdt_arch.year, mdt_arch.mon, mdt_arch.day) +
      ".csv";
   bool moved = FileMove(filename, 0, archive_name, FILE_REWRITE);
   Print(StringFormat("[SCHEMA] %s header mismatch (old width vs current) — %s: archived to %s",
         filename, moved ? "OK" : "FileMove FAILED, check permissions/build", archive_name));
   return true;  // write fresh header regardless — if archive failed, we still don't want to append wrong-width rows
}

void WriteCandidateLog(int direction, int score, bool is_shadow, bool is_live,
                       TrendState &ts, PullbackState &ps, string reject_reason) {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps, matches bot1_regime2.x pattern
   if(!LogAllCandidates && score < ShadowScoreThreshold) return;
   string filename = "trendcandidates_BOT4_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "event_time,symbol,direction,score,shadow_mode,live_mode,reject_reason,"
      "d1_bias,d1_bias_days_active,d1_ema_aligned,h4_confirm,h4_breakout_fresh,"
      "renko_signal,renko_brick_dir,renko_brick_close,"
      "renko_don_upper,renko_don_lower,renko_ema_fast,renko_ema_slow,"
      "renko_brick_count,brick_size_pips,brick_atr_mult,"
      "pullback_depth,in_golden_zone,fib_38,fib_50,fib_62,"
      "candle_pattern,dist_to_ema_atr,"
      "atr_m15_pips,atr_h4_pips,vol_ratio,adx_val,"
      "session,day_of_week,hour_utc,"
      "overall_bias_strength,impulse_high,impulse_low,"
      "renko_consec_bricks,d1_don_midline_pct,bars_since_last_signal,"
      "h4_don_upper,h4_don_lower";
   bool need_header = EnsureCsvSchema(filename, EXPECTED_HEADER);
   // FIX (v1.49, regime-suite branch): FILE_SHARE_READ lets external tools
   // (Python analysis scripts, the weekly-report aggregator, etc.) read this
   // CSV while the EA has it open live, instead of getting a
   // PermissionError/"used by another process" — ported directly from
   // bot1-regime's day-one lesson. Zero downside, should be default for any
   // EA log meant for later offline analysis.
   int handle  = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, EXPECTED_HEADER + "\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   // ── NEW COLUMN VALUES ─────────────────────────────────────────────────────
   // renko_consec_bricks: how many consecutive bricks in signal direction
   int consec = 0;
   for(int bi = 0; bi < g_renko_count && bi < 50; bi++) {
      RenkoBrick bk; if(!RenkoGetBrick(bi, bk)) break;
      if(bk.direction == direction) consec++;
      else break;
   }
   // d1_don_midline_pct: where is current price in the bias-TF Donchian channel (0-1)
   double d1_upper = DonchianUpper(BiasTimeframe,(int)DonchianPeriodBias,1);
   double d1_lower = DonchianLower(BiasTimeframe,(int)DonchianPeriodBias,1);
   double d1_range = d1_upper - d1_lower;
   double d1_close = iClose(_Symbol,BiasTimeframe,1);
   double d1_mid_pct = (d1_range > 0) ? (d1_close - d1_lower) / d1_range : 0.5;
   // bars_since_last_signal: M15 bars since the last WriteCandidateLog on this symbol
   // stored in a global updated each time we write
   int bars_since = (int)((TimeCurrent() - g_last_candidate_time) / 900);
   g_last_candidate_time = TimeCurrent();
   // H4 Donchian upper/lower
   double h4_upper = DonchianUpper(PERIOD_H4,(int)H4DonchianPeriod,1);
   double h4_lower = DonchianLower(PERIOD_H4,(int)H4DonchianPeriod,1);
   // v1.2: Renko signal columns replacing don15_signal/level
   int d1_days_active = 0;
   if(ts.d1_bias == 1 && g_d1_bull_breakout_time > 0)
      d1_days_active = (int)((iTime(_Symbol,BiasTimeframe,0) - g_d1_bull_breakout_time) / 86400);
   else if(ts.d1_bias == -1 && g_d1_bear_breakout_time > 0)
      d1_days_active = (int)((iTime(_Symbol,BiasTimeframe,0) - g_d1_bear_breakout_time) / 86400);
   RenkoBrick last_brick; bool has_last = RenkoGetBrick(0, last_brick);
   double renko_brick_close_log = has_last ? last_brick.close  : 0;
   int    renko_brick_dir_log   = has_last ? last_brick.direction : 0;
   FileWriteString(handle,
      ts_str + "," + _Symbol + "," +
      ((direction==1)?"BUY":"SELL") + "," +
      IntegerToString(score) + "," +
      (is_shadow?"1":"0") + "," +
      (is_live?"1":"0") + "," +
      SanitizeCSVField(reject_reason) + "," +
      ((ts.d1_bias==1)?"BULL":(ts.d1_bias==-1)?"BEAR":"NEUTRAL") + "," +
      IntegerToString(d1_days_active) + "," +
      (ts.d1_ema_aligned?"1":"0") + "," +
      ((ts.h4_confirm==1)?"BULL":(ts.h4_confirm==-1)?"BEAR":"NEUTRAL") + "," +
      (ts.h4_breakout_fresh?"1":"0") + "," +
      IntegerToString(g_renko_signal) + "," +
      IntegerToString(renko_brick_dir_log) + "," +
      DoubleToString(renko_brick_close_log,5) + "," +
      DoubleToString(g_renko_don_upper,5) + "," +
      DoubleToString(g_renko_don_lower,5) + "," +
      DoubleToString(g_renko_ema_fast,5) + "," +
      DoubleToString(g_renko_ema_slow,5) + "," +
      IntegerToString(g_renko_count) + "," +
      DoubleToString(g_renko_brick_size/PipSize(),1) + "," +
      DoubleToString(RenkoBrickSizeATRMult,3) + "," +
      DoubleToString(ps.pullback_depth,3) + "," +
      (ps.in_golden_zone?"1":"0") + "," +
      DoubleToString(ps.fib_38,5) + "," +
      DoubleToString(ps.fib_50,5) + "," +
      DoubleToString(ps.fib_62,5) + "," +
      ps.candle_pattern + "," +
      DoubleToString(ps.dist_to_ema_atr,2) + "," +
      DoubleToString(ps.atr_m15/PipSize(),1) + "," +
      DoubleToString(ps.atr_h4/PipSize(),1) + "," +
      DoubleToString(ps.vol_ratio,3) + "," +
      DoubleToString(GetADXValue(),1) + "," +
      ps.session + "," +
      ps.day_of_week + "," +
      IntegerToString(ps.hour_utc) + "," +
      ts.bias_strength + "," +
      DoubleToString(ps.impulse_high,5) + "," +
      DoubleToString(ps.impulse_low,5) + "," +
      IntegerToString(consec) + "," +
      DoubleToString(d1_mid_pct,3) + "," +
      IntegerToString(bars_since) + "," +
      DoubleToString(h4_upper,5) + "," +
      DoubleToString(h4_lower,5) + "\n");
   FileClose(handle);
}

void WriteRejectionLog(int direction, int score, string reason, TrendState &ts, PullbackState &ps) {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;  // 2026-09-23: skip disk I/O during optimization/sweeps, matches bot1_regime2.x pattern
   if(!LogRejected) return;
   string filename = "trendrejected_BOT4_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "event_time,symbol,direction,score,reason,"
      "d1_bias,h4_confirm,pullback_valid,candle_pattern,"
      "adx_val,vol_ratio,session,hour_utc,"
      "atr_m15_pips,atr_h4_pips,renko_signal,renko_brick_count,"
      "brick_size_pips,pullback_depth,impulse_high,impulse_low";
   bool need_header = EnsureCsvSchema(filename, EXPECTED_HEADER);
   // FIX (v1.49, regime-suite branch): FILE_SHARE_READ lets external tools
   // (Python analysis scripts, the weekly-report aggregator, etc.) read this
   // CSV while the EA has it open live, instead of getting a
   // PermissionError/"used by another process" — ported directly from
   // bot1-regime's day-one lesson. Zero downside, should be default for any
   // EA log meant for later offline analysis.
   int handle  = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, EXPECTED_HEADER + "\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   FileWriteString(handle,
      ts_str + "," + _Symbol + "," +
      ((direction==1)?"BUY":"SELL") + "," +
      IntegerToString(score) + "," +
      SanitizeCSVField(reason) + "," +
      ((ts.d1_bias==1)?"BULL":(ts.d1_bias==-1)?"BEAR":"NEUTRAL") + "," +
      ((ts.h4_confirm==1)?"BULL":(ts.h4_confirm==-1)?"BEAR":"NEUTRAL") + "," +
      (ps.valid?"1":"0") + "," +
      ps.candle_pattern + "," +
      DoubleToString(GetADXValue(),1) + "," +
      DoubleToString(ps.vol_ratio,3) + "," +
      ps.session + "," +
      IntegerToString(ps.hour_utc) + "," +
      // FIX (v1.3): 6 fields were missing entirely — REJECTED rows had no
      // ATR/Renko/impulse data, making ~100% of rejected weeks unresolvable
      // downstream. g_renko_* are globals (always valid); atr_m15/atr_h4
      // are populated by every caller. impulse_high/impulse_low/
      // pullback_depth are ONLY meaningful when the caller ran pullback
      // detection on the real ps object — the two stub-struct callers
      // (d1_weak_midline_breach, adx_gate_*) reject BEFORE pullback
      // detection runs, so those three fields legitimately read 0 for those
      // two specific reasons. That's correct, not a bug: there is no
      // pullback to report at that gate stage.
      DoubleToString(ps.atr_m15/PipSize(),1) + "," +
      DoubleToString(ps.atr_h4/PipSize(),1) + "," +
      IntegerToString(g_renko_signal) + "," +
      IntegerToString(g_renko_count) + "," +
      DoubleToString(g_renko_brick_size/PipSize(),1) + "," +
      DoubleToString(ps.pullback_depth,3) + "," +
      DoubleToString(ps.impulse_high,5) + "," +
      DoubleToString(ps.impulse_low,5) + "\n");
   FileClose(handle);
}

void WriteBasketCloseLog(string reason, double pnl, double pnl_pct, double r_mult, int hold_min) {
   string filename = "trendbaskets_BOT4_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "close_time,basket_id,symbol,direction,close_reason,"
      "pnl_account_ccy,pnl_pct,r_multiple,hold_min,max_levels,"
      "score,d1_bias,h4_confirm,candle_pattern,"
      "atr_m15_open,atr_h4_open,session,day_of_week,hour_utc";
   bool need_header = EnsureCsvSchema(filename, EXPECTED_HEADER);
   // FIX (v1.49, regime-suite branch): FILE_SHARE_READ lets external tools
   // (Python analysis scripts, the weekly-report aggregator, etc.) read this
   // CSV while the EA has it open live, instead of getting a
   // PermissionError/"used by another process" — ported directly from
   // bot1-regime's day-one lesson. Zero downside, should be default for any
   // EA log meant for later offline analysis.
   int handle  = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, EXPECTED_HEADER + "\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   FileWriteString(handle,
      ts_str + "," +
      g_pyr.basket_id + "," +
      _Symbol + "," +
      ((g_pyr.direction==1)?"BUY":"SELL") + "," +
      reason + "," +
      DoubleToString(pnl,2) + "," +
      DoubleToString(pnl_pct,4) + "," +
      DoubleToString(r_mult,2) + "," +
      IntegerToString(hold_min) + "," +
      IntegerToString(g_pyr.active_levels) + "," +
      IntegerToString(g_pyr.mech_score) + "," +
      g_pyr.d1_bias_str + "," +
      g_pyr.h4_confirm_str + "," +
      g_pyr.candle_pattern_str + "," +
      DoubleToString(g_pyr.atr_at_open/PipSize(),1) + "," +
      DoubleToString(g_pyr.atr_h4_at_open/PipSize(),1) + "," +
      g_pyr.session_str + "," +
      g_pyr.day_of_week_str + "," +
      IntegerToString(g_pyr.hour_utc) + "\n");
   FileClose(handle);
}

void WritePyramidLog(int level, string event_type, double price) {
   string filename = "trendpyramid_BOT4_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "event_time,basket_id,symbol,direction,event_type,level,"
      "price,lot,basket_sl_price,r_multiple,active_levels,hold_bars";
   bool need_header = EnsureCsvSchema(filename, EXPECTED_HEADER);
   // FIX (v1.49, regime-suite branch): FILE_SHARE_READ lets external tools
   // (Python analysis scripts, the weekly-report aggregator, etc.) read this
   // CSV while the EA has it open live, instead of getting a
   // PermissionError/"used by another process" — ported directly from
   // bot1-regime's day-one lesson. Zero downside, should be default for any
   // EA log meant for later offline analysis.
   int handle  = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, EXPECTED_HEADER + "\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   double lot = (level >= 1 && level <= 4) ? g_pyr.level[level-1].lot_size : 0;
   FileWriteString(handle,
      ts_str + "," +
      g_pyr.basket_id + "," +
      _Symbol + "," +
      ((g_pyr.direction==1)?"BUY":"SELL") + "," +
      event_type + "," +
      IntegerToString(level) + "," +
      DoubleToString(price,5) + "," +
      DoubleToString(lot,2) + "," +
      DoubleToString(g_pyr.basket_sl_price,5) + "," +
      DoubleToString(GetBasketRMultiple(),2) + "," +
      IntegerToString(g_pyr.active_levels) + "," +
      IntegerToString(g_pyr.bars_open) + "\n");
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| BASKET RECONSTRUCTION ON RESTART                                 |
//+------------------------------------------------------------------+
void ReconstructBasketFromPositions() {
   g_pyr.active_levels = 0;
   ulong tickets[4]; int cnt = 0; int dir = 0;
   for(int i = PositionsTotal()-1; i >= 0 && cnt < 4; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
      tickets[cnt] = position.Ticket();
      if(dir == 0) dir = (position.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      cnt++;
   }
   if(cnt == 0) return;
   // Sort by open time ascending
   for(int a = 0; a < cnt-1; a++)
      for(int b = a+1; b < cnt; b++) {
         datetime ta=0,tb=0;
         if(position.SelectByTicket(tickets[a])) ta=(datetime)position.Time();
         if(position.SelectByTicket(tickets[b])) tb=(datetime)position.Time();
         if(tb < ta) { ulong tmp=tickets[a]; tickets[a]=tickets[b]; tickets[b]=tmp; }
      }
   for(int i = 0; i < cnt; i++) {
      if(!position.SelectByTicket(tickets[i])) continue;
      g_pyr.level[i].ticket      = tickets[i];
      g_pyr.level[i].entry_price = position.PriceOpen();
      g_pyr.level[i].lot_size    = position.Volume();
      g_pyr.level[i].open_time   = (datetime)position.Time();
      g_pyr.active_levels        = i + 1;
   }
   if(g_pyr.active_levels > 0) {
      g_pyr.direction          = dir;
      g_pyr.basket_open_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_pyr.basket_id          = "RECOVERED_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
      g_pyr.open_time          = g_pyr.level[0].open_time;
      g_pyr.basket_sl_price    = CalculateInitialSL(dir, g_pyr.level[0].entry_price);
      // FIX (2026-06-24): RECOVERED basket used RiskPercentL1 × equity for initial_risk_r
      // even when UseRiskSizing=false (fixed lot mode). This caused the lot ladder to
      // compute L2 as (equity × risk%) / SL_dist rather than BaseLotSize × LotMultL2,
      // giving 0.06 instead of 0.07. Now mirrors the normal L1 lot calculation.
      if(UseRiskSizing)
         g_pyr.initial_risk_r  = g_pyr.basket_open_equity * RiskPercentL1 / 100.0;
      else
         g_pyr.initial_risk_r  = BaseLotSize * LotMultL1 *
                                  GetATRValue_M15() * BasketSLATRMult / PipSize();
      // BUG I FIX: read the actual broker SL from the recovered positions if
      // present (more accurate than recomputing), else push our computed SL.
      double existing_sl = 0;
      if(position.SelectByTicket(g_pyr.level[0].ticket))
         existing_sl = position.StopLoss();
      if(existing_sl > 0) {
         g_pyr.basket_sl_price = existing_sl;  // trust the live broker SL
      } else {
         // No broker SL on recovered positions — push our computed one immediately
         UpdateAllBrokerSLs();
         Print("[BASKET] Recovered positions had no broker SL — pushed computed SL");
      }
      // Mark partial as done if any recovered unit has reduced volume (best effort)
      g_pyr.partial_done = false;
      Print("[BASKET] Reconstructed from ", cnt, " positions dir=", dir,
            " sl=", g_pyr.basket_sl_price);
   }
}

//+------------------------------------------------------------------+
//| DISPLAY LEGEND                                                   |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color col,
                 int fs=8, string font="Arial", int corner=CORNER_LEFT_UPPER) {
   long id = 0;
   if(ObjectFind(id,name)<0) {
      ObjectCreate(id,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(id,name,OBJPROP_CORNER,corner);
      ObjectSetInteger(id,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(id,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(id,name,OBJPROP_BACK,false);
      ObjectSetInteger(id,name,OBJPROP_SELECTABLE,false);
   }
   ObjectSetString(id,name,OBJPROP_TEXT,text);
   ObjectSetInteger(id,name,OBJPROP_COLOR,col);
   ObjectSetString(id,name,OBJPROP_FONT,font);
   ObjectSetInteger(id,name,OBJPROP_FONTSIZE,fs);
}

void DrawLeftLegend() {
   if(!ShowLeftLegend) return;
   int x=10, y=20, lh=LegendFontSize+4, fs=LegendFontSize;

   CreateLabel("B4_Title", "══ BOT4 TREND PYRAMID v1.1 ══", x,y, clrDarkBlue, fs+2, "Arial Black"); y+=lh+2;

   if(StringLen(ConfigSymbol)>0) {
      bool m = (ConfigSymbol==_Symbol);
      CreateLabel("B4_Cfg", (m?"Config: "+ConfigSymbol+" ✓":"⚠ MISMATCH: "+ConfigSymbol+" ≠ "+_Symbol),
                  x,y, m?clrDarkGreen:clrRed, fs); y+=lh;
   }

   // Trend state
   TrendState ts = GetTrendState();
   // Fix #3: WEAK shown in orange in legend
   string biasStr = (ts.overall_bias==1)?"LONG":(ts.overall_bias==-1)?"SHORT":"RANGE";
   if(ts.bias_strength == "WEAK_TRADEABLE") biasStr = biasStr + " [WEAK-tradeable]";
   color biasCol  = (ts.overall_bias==1)?clrDarkGreen:(ts.overall_bias==-1)?clrDarkRed:clrDarkGray;
   if(ts.bias_strength == "WEAK_TRADEABLE") biasCol = clrDarkOrange;
   CreateLabel("B4_Trend",
      StringFormat("Trend: %s (%s) | D1: %s EMA: %s | H4: %s",
         biasStr, ts.bias_strength,
         (ts.d1_bias==1)?"BULL":(ts.d1_bias==-1)?"BEAR":"N",
         ts.d1_ema_aligned?"OK":"FAIL",
         (ts.h4_confirm==1)?"BULL":(ts.h4_confirm==-1)?"BEAR":"N"),
      x,y, biasCol, fs); y+=lh;

   // Bias-TF Donchian + breakout persistence status
   int d1_bull_bars_ago = (g_d1_bull_breakout_time > 0) ?
      (int)((iTime(_Symbol,BiasTimeframe,0) - g_d1_bull_breakout_time) / 86400) : -1;
   int d1_bear_bars_ago = (g_d1_bear_breakout_time > 0) ?
      (int)((iTime(_Symbol,BiasTimeframe,0) - g_d1_bear_breakout_time) / 86400) : -1;
   string d1_persist_str = (d1_bull_bars_ago >= 0) ?
      StringFormat("BULL break %dd ago", d1_bull_bars_ago) :
      (d1_bear_bars_ago >= 0) ?
      StringFormat("BEAR break %dd ago", d1_bear_bars_ago) : "no active breakout";
   CreateLabel("B4_Don",
      StringFormat("D1 Don[%d]: U=%.5f L=%.5f | %s | H4[%d]: U=%.5f L=%.5f",
         DonchianPeriodBias, ts.d1_don_upper, ts.d1_don_lower,
         d1_persist_str,
         H4DonchianPeriod, ts.h4_don_upper, ts.h4_don_lower),
      x,y, (ts.d1_bias!=0)?clrDarkBlue:clrDarkGray, fs); y+=lh;
   // v1.2: Renko signal status
   RenkoBrick rleg_b; bool rleg_ok = RenkoGetBrick(0, rleg_b);
   string renko_state = StringFormat("[RENKO] %s | brick=%s %.5f | Don U=%.5f L=%.5f | "
                                     "EMA20%sEMA50 | n=%d bs=%.1fp",
      (g_renko_signal== 1) ? "BUY ✓" :
      (g_renko_signal==-1) ? "SELL ✓" : "no signal",
      rleg_ok ? ((rleg_b.direction==1)?"UP":"DN") : "?",
      rleg_ok ? rleg_b.close : 0,
      g_renko_don_upper, g_renko_don_lower,
      (g_renko_ema_fast > g_renko_ema_slow) ? ">" : "<",
      g_renko_count, g_renko_brick_size/PipSize());
   color renko_col = (g_renko_signal!=0) ? clrDarkGreen :
                     (g_renko_count < MathMax(RenkoDonPeriod,RenkoEMASlowPeriod)+5) ?
                     clrOrange : clrDarkGray;
   CreateLabel("B4_Renko", renko_state, x,y, renko_col, fs); y+=lh;

   // Pyramid state
   if(g_pyr.active_levels > 0) {
      double pnl    = GetBasketPnL();
      double pnlPct = GetBasketPnLPct();
      double rMult  = GetBasketRMultiple();
      string dirStr = (g_pyr.direction==1)?"BUY":"SELL";

      CreateLabel("B4_Basket",
         StringFormat("PYRAMID ACTIVE: %s L%d/%d | P&L: %+.2f (%+.3f%%) R=%.2f",
            dirStr, g_pyr.active_levels, MaxPyramidLevels,
            pnl, pnlPct, rMult),
         x,y, clrDarkBlue, fs); y+=lh;

      CreateLabel("B4_BSL",
         StringFormat("BasketSL: %.5f | InitialSL: %.5f | Risk 1R: %s",
            g_pyr.basket_sl_price, g_pyr.initial_sl_price,
            FmtAmt(g_pyr.initial_risk_r)),
         x,y, clrDarkRed, fs); y+=lh;

      if(g_pyr.chandelier_stop > 0) {
         CreateLabel("B4_Chan",
            StringFormat("Chandelier: %.5f | Don10-H1: %.5f",
               g_pyr.chandelier_stop, g_pyr.don10_stop),
            x,y, clrOrange, fs); y+=lh;
      }

      int holdMin = (int)((TimeCurrent() - g_pyr.open_time) / 60);
      CreateLabel("B4_Hold",
         StringFormat("Hold: %d bars / %dh%02dm | soft=%dh hard=%dh",
            g_pyr.bars_open, holdMin/60, holdMin%60,
            TimestopSoftBars*15/60, TimestopHardBars*15/60),
         x,y, (g_pyr.bars_open > TimestopSoftBars*8/10)?clrOrange:clrDarkGray, fs); y+=lh;

   } else {
      CreateLabel("B4_Basket","NO ACTIVE PYRAMID",x,y,clrDarkGray,fs); y+=lh;
      ObjectDelete(0,"B4_BSL"); ObjectDelete(0,"B4_Chan"); ObjectDelete(0,"B4_Hold");
   }

   // ADX / vol
   double adv = GetADXValue(); double vr = GetVolatilityRatio();
   CreateLabel("B4_ADX",
      StringFormat("ADX: %.1f (gate: %.0f–%.0f) | VolRatio: %.2f (%.1f–%.1f)",
         adv, ADXMinEntry, ADXMaxEntry, vr, VolRatioMin, VolRatioMax),
      x,y, (adv>=ADXMinEntry&&adv<=ADXMaxEntry)?clrDarkGreen:clrOrange, fs); y+=lh;

   // Mode
   string modeStr = ShadowModeOnly ? "SHADOW (no orders)" : "LIVE";
   CreateLabel("B4_Mode",
      StringFormat("Mode: %s | ShadowGate=%d | LiveGate=%d | MagicN=%d",
         modeStr, ShadowScoreThreshold, LiveScoreThreshold, MagicNumber),
      x,y, ShadowModeOnly?clrSlateGray:clrDarkGreen, fs); y+=lh;
}

void DrawRightLegend() {
   if(!ShowRightLegend) return;
   int fs=LegendFontSize, lh=LegendFontSize+4, corner=1, x=10, y=20;

   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnL = eq - dailyStartEquity;
   double dailyPct = (dailyStartEquity>0) ? dailyPnL/dailyStartEquity*100 : 0;

   CreateLabel("B4_R_Title","══ ACCOUNT ══",x,y,clrBlack,fs+1,"Arial Black",corner); y+=lh+2;
   CreateLabel("B4_R_Eq",
      StringFormat("Eq: %s | Day: %+.3f%% (%+s)",
         FmtAmt(eq), dailyPct, FmtAmt(dailyPnL)),
      x,y, (dailyPnL>=0)?clrDarkGreen:clrDarkRed, fs,"Arial",corner); y+=lh;

   double dailyUsed = (dailyStartEquity>0) ? (dailyStartEquity-eq) : 0;
   // FIX (bot4 audit, 2026-08): legend must show the same SCALED limit the
   // gate functions actually enforce (see IsDailyLossLimitReached), not the
   // raw MaxDailyLossAmount input — otherwise the on-chart number silently
   // disagrees with reality whenever InitialBalance != real account size.
   double scale_disp = (InitialBalance > 0) ? (g_effective_initial_balance / InitialBalance) : 1.0;
   double dailyLim  = MaxDailyLossAmount * scale_disp;
   CreateLabel("B4_R_Daily",
      StringFormat("Daily DD: %.3f%% / limit -%s",
         -dailyPct, FmtAmt(dailyLim)),
      x,y, (dailyUsed>dailyLim*0.7)?clrOrange:clrDarkGray, fs,"Arial",corner); y+=lh;

   double overallLim = MaxOverallLossAmount * scale_disp;
   double overallUsed = (g_effective_initial_balance>0) ? (g_effective_initial_balance-eq)/g_effective_initial_balance*100 : 0;
   CreateLabel("B4_R_Overall",
      StringFormat("Overall DD: %.3f%% / limit -%s",
         overallUsed, FmtAmt(overallLim)),
      x,y, (overallUsed>(overallLim/g_effective_initial_balance*100)*0.7)?clrOrange:clrDarkGray,
      fs,"Arial",corner); y+=lh;

   int openNow = GetTotalOpenPyramids();
   CreateLabel("B4_R_Pyr",
      StringFormat("Pyramids today: %d | open: %d/%d | ccy: %s",
         dailyTradeCount, openNow, MaxOpenPyramids, GetSymbolClass()),
      x,y, clrDarkGray, fs,"Arial",corner); y+=lh;

   // Daily stop status
   if(DailyEquityStopPct > 0) {
      double drop = (dailyStartEquity>0) ? (dailyStartEquity-eq)/dailyStartEquity*100 : 0;
      string dss = g_daily_stop_hit ?
         "⛔ DAILY STOP HIT — halted" :
         StringFormat("Daily halt: %.2f%% / %.1f%%", drop, DailyEquityStopPct);
      CreateLabel("B4_R_DStop", dss, x,y,
         g_daily_stop_hit?clrRed:(drop>DailyEquityStopPct*0.7?clrOrange:clrDarkGray),
         fs,"Arial",corner); y+=lh;
   }

   // Cooldown
   int barsSinceSL = (g_cooldown_sl_time>0) ?
      (int)((TimeCurrent()-g_cooldown_sl_time)/PeriodSeconds(_Period)) : 9999;
   bool inCool = (g_cooldown_sl_time>0 && barsSinceSL < CooldownBarsSL);
   CreateLabel("B4_R_Cool",
      inCool ?
         StringFormat("SL COOLDOWN: %d/%d bars", barsSinceSL, CooldownBarsSL) : "Ready",
      x,y, inCool?clrOrange:clrDarkGreen, fs,"Arial",corner); y+=lh;

   // FTMO progress
   double challengeTarget = g_effective_initial_balance * 0.10;
   double progress = (eq > g_effective_initial_balance) ? (eq - g_effective_initial_balance) / challengeTarget * 100 : 0;
   CreateLabel("B4_R_FTMO",
      StringFormat("FTMO: +%.2f%% / 10%% target | prog: %.1f%%",
         (eq-g_effective_initial_balance)/g_effective_initial_balance*100, progress),
      x,y, (progress>=100)?clrDarkGreen:(progress>50?clrDarkOrange:clrDarkGray),
      fs,"Arial",corner); y+=lh;

   CreateLabel("B4_R_Group",
      StringFormat("Group: %s | GroqMode: %s",
         CorrelationGroup, GroqShadowModeOnly?"shadow":"live"),
      x,y, clrSlateGray, fs,"Arial",corner);
}

//+------------------------------------------------------------------+
//| DRAW BASKET LINES ON CHART                                       |
//+------------------------------------------------------------------+
void CreateHLine(string name, double price, color col, ENUM_LINE_STYLE style, int width, string tooltip) {
   long id = 0;
   if(ObjectFind(id,name)<0)
      ObjectCreate(id,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(id,name,OBJPROP_PRICE,price);
   ObjectSetInteger(id,name,OBJPROP_COLOR,col);
   ObjectSetInteger(id,name,OBJPROP_STYLE,style);
   ObjectSetInteger(id,name,OBJPROP_WIDTH,width);
   ObjectSetString(id,name,OBJPROP_TOOLTIP,tooltip);
}
void DeleteBasketLines() {
   long id = 0; int total = ObjectsTotal(0,0,-1);
   for(int i=total-1; i>=0; i--) {
      string n = ObjectName(0,i);
      if(StringFind(n,"B4_LINE_")>=0) ObjectDelete(id,n);
   }
}
void DrawBasketLines() {
   if(!ShowPyramidLines || g_pyr.active_levels == 0) { DeleteBasketLines(); return; }
   if(g_pyr.basket_sl_price > 0)
      CreateHLine("B4_LINE_SL", g_pyr.basket_sl_price, clrRed, STYLE_SOLID, 2,
                  StringFormat("Bot4 Basket SL (%.5f)", g_pyr.basket_sl_price));
   if(g_pyr.chandelier_stop > 0)
      CreateHLine("B4_LINE_CHAN", g_pyr.chandelier_stop, clrOrangeRed, STYLE_DASHDOT, 1,
                  StringFormat("Chandelier Stop (%.5f)", g_pyr.chandelier_stop));
   if(g_pyr.don10_stop > 0)
      CreateHLine("B4_LINE_D10", g_pyr.don10_stop, clrOrange, STYLE_DOT, 1,
                  StringFormat("Don10 H1 Exit (%.5f)", g_pyr.don10_stop));
   // Fib entry zones (when no basket open)
}

//+------------------------------------------------------------------+
//| SIGNAL VISUALS (2026-07-22) — exploratory/teaching overlay        |
//| Gated entirely by ShowSignalVisuals (default false). Draws a      |
//| persistent arrow at every bar where a candidate was scored, and a |
//| live status panel explaining the current gate state — for         |
//| understanding WHEN/WHY a trade would fire, not for normal ops.    |
//+------------------------------------------------------------------+
void DrawSignalMarker(int direction, int score, bool is_live, bool is_shadow, string reject_reason) {
   if(!ShowSignalVisuals) return;
   datetime bar_time = iTime(_Symbol, _Period, 0);
   double   price     = (direction == 1) ?
                        iLow(_Symbol, _Period, 0)  - GetATRValue_M15() * 0.3 :
                        iHigh(_Symbol, _Period, 0) + GetATRValue_M15() * 0.3;
   string   name = StringFormat("B4_SIG_%s_%d", _Symbol, (long)bar_time);
   long id = 0;
   if(ObjectFind(id, name) < 0)
      ObjectCreate(id, name, (direction==1) ? OBJ_ARROW_UP : OBJ_ARROW_DOWN, 0, bar_time, price);
   color col;
   if(is_live)          col = (direction==1) ? clrLime      : clrRed;
   else if(is_shadow)   col = (direction==1) ? clrDarkGreen : clrMaroon;
   else                 col = clrGray;
   ObjectSetInteger(id, name, OBJPROP_COLOR, col);
   ObjectSetInteger(id, name, OBJPROP_WIDTH, is_live ? 3 : 1);
   string tip = StringFormat("%s score=%d %s%s",
         (direction==1)?"BUY":"SELL", score,
         is_live?"[LIVE ATTEMPT]":is_shadow?"[shadow]":"[below live gate]",
         (reject_reason!="") ? (" reason=" + reject_reason) : "");
   ObjectSetString(id, name, OBJPROP_TOOLTIP, tip);
}

void DrawDiagnosticPanel(TrendState &ts, PullbackState &ps, int score, string block_reason) {
   if(!ShowSignalVisuals) return;
   int x = 10, y = 300, lh = LegendFontSize + 4, fs = LegendFontSize;
   CreateLabel("B4_VIZ_Title", "══ SIGNAL DIAGNOSTIC (exploratory) ══", x, y, clrBlack, fs+1, "Arial Black"); y+=lh+2;
   CreateLabel("B4_VIZ_D1", StringFormat("D1 bias: %s (%s) | EMA align: %s",
      (ts.d1_bias==1)?"BULL":(ts.d1_bias==-1)?"BEAR":"NEUTRAL", ts.bias_strength,
      ts.d1_ema_aligned?"OK":"FAIL"), x, y,
      (ts.d1_bias!=0)?clrDarkBlue:clrGray, fs); y+=lh;
   CreateLabel("B4_VIZ_H4", StringFormat("H4 confirm: %s | fresh breakout: %s",
      (ts.h4_confirm==1)?"BULL":(ts.h4_confirm==-1)?"BEAR":"NEUTRAL",
      ts.h4_breakout_fresh?"YES":"no"), x, y, clrDarkSlateGray, fs); y+=lh;
   CreateLabel("B4_VIZ_Renko", StringFormat("Renko signal: %s | bricks=%d | ema_fast%sema_slow",
      (g_renko_signal==1)?"BUY":(g_renko_signal==-1)?"SELL":"none", g_renko_count,
      (g_renko_ema_fast>g_renko_ema_slow)?">":"<"), x, y,
      (g_renko_signal!=0)?clrDarkGreen:clrGray, fs); y+=lh;
   CreateLabel("B4_VIZ_PB", StringFormat("Pullback valid: %s | extension=%.3f | golden_zone: %s",
      ps.valid?"YES":"no", ps.pullback_depth, ps.in_golden_zone?"YES":"no"),
      x, y, ps.valid?clrDarkGreen:clrGray, fs); y+=lh;
   CreateLabel("B4_VIZ_Score", StringFormat("Score: %d (shadow>=%d, live>=%d)",
      score, ShadowScoreThreshold, LiveScoreThreshold), x, y,
      (score>=LiveScoreThreshold)?clrDarkGreen:(score>=ShadowScoreThreshold)?clrDarkOrange:clrGray, fs); y+=lh;
   CreateLabel("B4_VIZ_Block", StringFormat("Current block: %s", (block_reason!="")?block_reason:"none — would attempt entry"),
      x, y, (block_reason!="")?clrDarkRed:clrDarkGreen, fs); y+=lh;
}

//+------------------------------------------------------------------+
//| RENKO BRICK VISUALS (2026-07-24)                                 |
//| The Renko engine is entirely in-memory — it has never been        |
//| visible on the chart. This draws the most recent bricks as small  |
//| rectangles at the M15 bar where each one formed, so you can watch |
//| bricks build up in real time and see exactly which one crosses    |
//| the Donchian-on-bricks line that fires a signal.                  |
//+------------------------------------------------------------------+
input group "═══ RENKO / ENTRY VISUALS (exploratory) ═══"
input bool ShowRenkoBricks   = false; // draws the last N Renko bricks as boxes on the chart, and the price lines a brick close has to cross to fire a signal
input bool ShowEntryLevels2  = false; // draws the D1 and H4 Donchian channel lines (the bigger-picture trend levels) directly on this chart, so you can see price approaching them
input int  MaxBricksToDraw   = 80;    // how many recent bricks to draw — more bricks is more history but more chart clutter/lag

void DrawRenkoBricks() {
   static bool cleared_once = false;
   if(!ShowRenkoBricks) {
      if(!cleared_once) {
         long id = 0; int total = ObjectsTotal(0,0,-1);
         for(int i = total-1; i >= 0; i--) {
            string n = ObjectName(0,i);
            if(StringFind(n,"B4_BRICK_")>=0) ObjectDelete(id,n);
         }
         cleared_once = true;
      }
      return;
   }
   cleared_once = false;

   int max_b = ArraySize(g_renko_bricks);
   int avail = MathMin(g_renko_count, max_b);
   int to_draw = MathMin(avail, MaxBricksToDraw);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = 0; i < to_draw; i++) {
      RenkoBrick b;
      if(!RenkoGetBrick(i, b)) break;
      // Each brick spans its own time_formed to the next M15 bar (bricks are
      // price-events, not time-events, so this is an approximation for
      // display purposes only — the brick's real boundary is price, not time).
      string name = StringFormat("B4_BRICK_%s_%d", _Symbol, (long)b.time_formed);
      long id = 0;
      double price1 = MathMin(b.open, b.close);
      double price2 = MathMax(b.open, b.close);
      datetime t2 = b.time_formed + PeriodSeconds(_Period);
      if(ObjectFind(id, name) < 0)
         ObjectCreate(id, name, OBJ_RECTANGLE, 0, b.time_formed, price1, t2, price2);
      else {
         ObjectSetInteger(id, name, OBJPROP_TIME, 0, b.time_formed);
         ObjectSetInteger(id, name, OBJPROP_TIME, 1, t2);
         ObjectSetDouble(id, name, OBJPROP_PRICE, 0, price1);
         ObjectSetDouble(id, name, OBJPROP_PRICE, 1, price2);
      }
      color brick_col = (b.direction==1) ? clrLimeGreen : clrTomato;
      ObjectSetInteger(id, name, OBJPROP_COLOR, brick_col);
      ObjectSetInteger(id, name, OBJPROP_FILL, true);
      ObjectSetInteger(id, name, OBJPROP_BACK, true);
      ObjectSetString(id, name, OBJPROP_TOOLTIP,
         StringFormat("Renko brick %s %.5f -> %.5f", (b.direction==1)?"UP":"DOWN", b.open, b.close));
   }

   // The actual line a fresh brick close has to cross to fire a signal —
   // this is the single most useful line for understanding "when does a
   // trade fire": g_renko_don_upper / g_renko_don_lower.
   if(g_renko_don_upper > 0)
      CreateHLine("B4_BRICKDON_UPPER", g_renko_don_upper, clrDeepSkyBlue, STYLE_DASH, 1,
         StringFormat("Renko brick must CLOSE above this (%.5f) to fire a BUY", g_renko_don_upper));
   if(g_renko_don_lower > 0)
      CreateHLine("B4_BRICKDON_LOWER", g_renko_don_lower, clrDeepSkyBlue, STYLE_DASH, 1,
         StringFormat("Renko brick must CLOSE below this (%.5f) to fire a SELL", g_renko_don_lower));
}

//+------------------------------------------------------------------+
//| ENTRY CRITERIA LEVELS (2026-07-24)                                |
//| The D1 and H4 Donchian channels that set bias/confirmation live on|
//| higher timeframes and are invisible on an M15 chart. This puts    |
//| the actual price levels on the chart you're looking at.           |
//+------------------------------------------------------------------+
void DrawEntryCriteriaLevels(TrendState &ts) {
   if(!ShowEntryLevels2) {
      long id = 0;
      ObjectDelete(id, "B4_D1_UPPER"); ObjectDelete(id, "B4_D1_LOWER");
      ObjectDelete(id, "B4_H4_UPPER"); ObjectDelete(id, "B4_H4_LOWER");
      return;
   }
   if(ts.d1_don_upper > 0)
      CreateHLine("B4_D1_UPPER", ts.d1_don_upper, clrGold, STYLE_SOLID, 1,
         StringFormat("D1 Donchian(%d) upper — daily close above this = bullish breakout (%.5f)", DonchianPeriodBias, ts.d1_don_upper));
   if(ts.d1_don_lower > 0)
      CreateHLine("B4_D1_LOWER", ts.d1_don_lower, clrGold, STYLE_SOLID, 1,
         StringFormat("D1 Donchian(%d) lower — daily close below this = bearish breakout (%.5f)", DonchianPeriodBias, ts.d1_don_lower));
   if(ts.h4_don_upper > 0)
      CreateHLine("B4_H4_UPPER", ts.h4_don_upper, clrSilver, STYLE_DOT, 1,
         StringFormat("H4 Donchian(%d) upper — needs to confirm the D1 direction (%.5f)", H4DonchianPeriod, ts.h4_don_upper));
   if(ts.h4_don_lower > 0)
      CreateHLine("B4_H4_LOWER", ts.h4_don_lower, clrSilver, STYLE_DOT, 1,
         StringFormat("H4 Donchian(%d) lower — needs to confirm the D1 direction (%.5f)", H4DonchianPeriod, ts.h4_don_lower));
}


//+------------------------------------------------------------------+
//| SIGNAL DIRECTION SCAN                                            |
//| Determines which direction (if any) has a valid setup           |
//+------------------------------------------------------------------+
// FEATURE (2) 2026-07-25: Kaufman Efficiency Ratio — |net move| / sum(|bar
// moves|) over EfficiencyRatioPeriod M15 bars. 0 = pure noise/chop,
// 1 = pure directional move. Used as an alternative to ADX for the regime
// gate below.
double GetEfficiencyRatio(int period) {
   double closes[];
   if(CopyClose(_Symbol, _Period, 1, period + 1, closes) < period + 1) return 0;
   double net_move = MathAbs(closes[0] - closes[period]);
   double sum_moves = 0;
   for(int i = 0; i < period; i++)
      sum_moves += MathAbs(closes[i] - closes[i+1]);
   return (sum_moves > 0) ? net_move / sum_moves : 0;
}

// FIX (v1.49, regime-suite branch): Choppiness Index — ported concept from
// bot1-regime. CHOP = 100 * log10( sum(TrueRange, period) / (max_high(period)
// - min_low(period)) ) / log10(period). Near 100 = choppy/ranging (price
// traveled a lot but net range is small); near 0 = trending (price traveled
// efficiently toward the range extremes). Uses CopyHigh/CopyLow/CopyClose on
// the chart timeframe — no new indicator handle needed, matches the style of
// GetEfficiencyRatio() above.
double GetChoppinessIndex(int period) {
   if(period < 2) return 50.0;  // neutral fallback, avoid log10(1)=0 div/0
   double highs[], lows[], closes[];
   if(CopyHigh(_Symbol, _Period, 1, period + 1, highs) < period + 1) return 50.0;
   if(CopyLow(_Symbol, _Period, 1, period + 1, lows)  < period + 1) return 50.0;
   if(CopyClose(_Symbol, _Period, 1, period + 1, closes) < period + 1) return 50.0;

   double sum_tr = 0;
   double hh = highs[0], ll = lows[0];
   for(int i = 0; i < period; i++) {
      double tr = MathMax(highs[i], closes[i+1]) - MathMin(lows[i], closes[i+1]);
      sum_tr += tr;
      if(highs[i] > hh) hh = highs[i];
      if(lows[i]  < ll) ll = lows[i];
   }
   double range = hh - ll;
   if(range <= 0 || sum_tr <= 0) return 50.0;  // degenerate/flat data — neutral
   double chop = 100.0 * MathLog10(sum_tr / range) / MathLog10((double)period);
   return chop;
}

// FIX (v1.49, regime-suite branch): combines up to 5 independently-toggleable
// regime filters into ONE verdict via RegimeSuiteVoteMode (AND/OR/MAJORITY).
// Structural rule (matches bot1-regime source): a filter whose own UseX toggle
// is false is simply NOT counted — it contributes neither a "trending" nor a
// "not trending" vote, so disabling filters never silently biases the result
// either direction. If ALL filters are disabled, returns true (neutral pass —
// matches UseRegimeSuite=false having zero effect, so a config that turns the
// suite on but forgets to enable any filter doesn't silently block everything).
// FIX (v1.49, regime-suite branch): computes each filter's individual vote
// (only meaningful if that filter's own toggle is on — callers must check
// the corresponding RSUseX before trusting the value) plus the totals needed
// for the combined verdict. Factored out from RegimeSuiteVerdict() so the
// regime-event logger can detect a GATE_FLIP on any INDIVIDUAL filter even
// when the combined verdict doesn't change (e.g. under OR/MAJORITY vote
// modes) — computing votes only once per bar, not duplicated between the
// entry gate and the logger.
void ComputeRegimeSuiteVotes(bool &adx_vote, bool &er_vote, bool &chop_vote,
                              bool &atr_vote, bool &session_vote,
                              int &votes_trending, int &votes_total) {
   adx_vote = false; er_vote = false; chop_vote = false;
   atr_vote = false; session_vote = false;
   votes_trending = 0; votes_total = 0;

   if(RSUseADX) {
      votes_total++;
      adx_vote = (GetADXValue() >= RegimeMinADX);
      if(adx_vote) votes_trending++;
   }
   if(RSUseER) {
      votes_total++;
      er_vote = (GetEfficiencyRatio(EfficiencyRatioPeriod) >= RegimeMinER);
      if(er_vote) votes_trending++;
   }
   if(RSUseCHOP) {
      votes_total++;
      chop_vote = (GetChoppinessIndex(RSChopPeriod) < RSChopMaxForTrending);
      if(chop_vote) votes_trending++;
   }
   if(RSUseATRRatio) {
      votes_total++;
      atr_vote = (GetVolatilityRatio() >= RSATRRatioMinForTrending);
      if(atr_vote) votes_trending++;
   }
   if(RSUseSession) {
      votes_total++;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      session_vote = (RSSessionStartHour <= RSSessionEndHour) ?
                     (dt.hour >= RSSessionStartHour && dt.hour < RSSessionEndHour) :
                     (dt.hour >= RSSessionStartHour || dt.hour < RSSessionEndHour); // wraps midnight
      if(session_vote) votes_trending++;
   }
}

bool RegimeSuiteVerdict() {
   bool adx_v, er_v, chop_v, atr_v, sess_v;
   int votes_trending, votes_total;
   ComputeRegimeSuiteVotes(adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);

   if(votes_total == 0) return true;  // no filters enabled — neutral pass, see comment above

   switch(RegimeSuiteVoteMode) {
      case RS_VOTE_AND:      return votes_trending == votes_total;
      case RS_VOTE_OR:       return votes_trending > 0;
      case RS_VOTE_MAJORITY: return votes_trending * 2 > votes_total;
      default:               return votes_trending * 2 > votes_total;
   }
}

// FIX (v1.49, regime-suite branch): records a REAL trade's SL distance into
// the rolling window used by the min-SL-distance sanity filter. Called once
// per L1 open with the ACTUAL broker SL distance that was sent (post any
// min_dist expansion in OpenPyramidLevel()), not the raw ATR-derived
// candidate — so the rolling average reflects real sent orders.
void RecordSLDistanceSample(double dist) {
   if(dist <= 0) return;
   int cap = MathMax(1, SLDistanceHistoryLen);
   int cur_len = ArraySize(g_sl_dist_history);
   if(cur_len < cap) {
      ArrayResize(g_sl_dist_history, cur_len + 1);
      g_sl_dist_history[cur_len] = dist;
   } else {
      // Ring-buffer shift — cap is small (SLDistanceHistoryLen, typically
      // 10-30) so this O(n) shift is negligible cost, once per real trade
      // open (not per tick/bar).
      for(int i = 0; i < cap - 1; i++) g_sl_dist_history[i] = g_sl_dist_history[i+1];
      g_sl_dist_history[cap - 1] = dist;
   }
   g_sl_dist_history_count++;
}

// Returns true if `candidate_dist` is an outlier (too tight) vs the rolling
// average — i.e. the L1 open SHOULD be rejected. Always returns false
// (never rejects) until SLDistanceMinSamples real trades exist, and always
// returns false if the filter is disabled — both are checked by the caller,
// this function only does the math once those gates already passed.
bool IsSLDistanceOutlier(double candidate_dist) {
   int n = ArraySize(g_sl_dist_history);
   if(n == 0) return false;
   double sum = 0;
   for(int i = 0; i < n; i++) sum += g_sl_dist_history[i];
   double avg = sum / n;
   if(avg <= 0) return false;
   return candidate_dist < (avg * MinSLDistanceFraction);
}

int ScanForSignal(TrendState &ts) {
   if(ts.overall_bias == 0) return 0;
   // FIX (v1.47, frequency branch): the old "WEAK" tier used to be forced to
   // overall_bias=0 upstream in GetTrendState(), so this check was reachable
   // and hard-blocked every D1-only setup. WEAK_TRADEABLE now carries a real
   // non-zero overall_bias and is scored (with a penalty) in
   // CalculateSignalScore() instead of being rejected here — no gate needed at
   // this point anymore. Left as a comment for history; nothing to block on.

   // FEATURE (2) 2026-07-25: regime gate — only act on a bias if the market
   // is actually trending enough right now, by whichever method you picked.
   // FIX (v1.49, regime-suite branch): when UseRegimeSuite=true, the combined
   // multi-filter vote REPLACES this single-method check entirely (not both
   // applied — that would double-gate and make sweep results hard to
   // attribute to either mechanism). When UseRegimeSuite=false, behavior is
   // byte-for-byte identical to v1.48.
   if(UseRegimeSuite) {
      if(!RegimeSuiteVerdict()) return 0;
   } else if(UseRegimeGate) {
      if(RegimeGateMethod == REGIME_ADX) {
         if(GetADXValue() < RegimeMinADX) return 0;
      } else { // REGIME_EFFICIENCY_RATIO
         if(GetEfficiencyRatio(EfficiencyRatioPeriod) < RegimeMinER) return 0;
      }
   }

   // FEATURE (5) 2026-07-25: Renko/D1 agreement — require the most recent
   // confirmed Renko brick's own direction to agree with the bias direction.
   // A second, independent vote from the faster layer before trusting the
   // slower one.
   // FIX (v1.46, dead-parameter repair): a single-brick check was a no-op
   // in this dataset — 92/92 sweep pairs showed zero effect from toggling
   // it, because in a sustained trend nearly every M15 brick already points
   // the same way as the D1/H4 composite bias, so the gate almost never had
   // anything to veto. Requiring the last TWO confirmed bricks to BOTH agree
   // (not just the latest one) makes this an actual independent filter: a
   // single pullback/consolidation brick against the trend now blocks entry
   // until the faster layer re-confirms, instead of being invisible whenever
   // the very latest brick happens to still align.
   if(UseRenkoD1Agreement) {
      RenkoBrick last_b, prev_b;
      if(!RenkoGetBrick(0, last_b)) return 0;   // no brick history yet — can't confirm
      if(last_b.direction != ts.overall_bias) return 0;
      if(RenkoGetBrick(1, prev_b) && prev_b.direction != ts.overall_bias) return 0;
   }

   // FEATURE (6) 2026-07-25: higher-timeframe trend alignment — price has
   // to be on the correct side of a slow MA on a higher timeframe than the
   // bias layer, independent confirmation of the dominant trend direction.
   if(UseHigherTFTrendFilter && higherTFMAHandle != INVALID_HANDLE) {
      double ma[];
      if(CopyBuffer(higherTFMAHandle, 0, 1, 1, ma) >= 1) {
         double htf_close = iClose(_Symbol, HigherTFTrendTimeframe, 1);
         bool aligned = (ts.overall_bias == 1) ? (htf_close > ma[0]) : (htf_close < ma[0]);
         if(!aligned) return 0;
      }
   }

   return ts.overall_bias;
}

//+------------------------------------------------------------------+
//| Scan historical D1 bars for most recent breakout (init backfill) |
//| Fixes: bias never activating when EA starts after the breakout   |
//+------------------------------------------------------------------+
void ScanHistoricalD1Breakout() {
   if(!UseD1Bias) return;

   int period = (int)DonchianPeriodBias;

   // Clamp scan range to available bias-timeframe history. Backfill needs
   // (scan_bars + period + 1) bars; demo servers often have limited history,
   // which made DonchianUpper return 0 for every bar → "No active breakout"
   // everywhere.
   int avail = Bars(_Symbol, BiasTimeframe);
   if(avail < period + 5) {
      Print(StringFormat("[D1 INIT] Only %d bias-TF bars (<%d needed) — skipping backfill, "
            "bias will build live", avail, period + 5));
      return;
   }
   // FEATURE (4) 2026-07-25: scan window now derived from TrendValidHours
   // (a real duration) converted to a bar-count for whichever BiasTimeframe
   // is active, instead of raw D1TrendValidBars.
   int scan_bars = (int)MathMax(1, (TrendValidHours * 3600) / PeriodSeconds(BiasTimeframe));
   int max_scan  = avail - period - 1;     // furthest shift we can compute a channel for
   if(scan_bars > max_scan) scan_bars = max_scan;
   if(scan_bars < 1) { return; }

   datetime newest_bull = 0, newest_bear = 0;
   double   bull_level = 0, bear_level = 0;
   int      bars_checked = 0;

   for(int shift = scan_bars; shift >= 1; shift--) {
      double close_i = iClose(_Symbol, BiasTimeframe, shift);
      double prev_upper = DonchianUpper(BiasTimeframe, period, shift + 1);
      double prev_lower = DonchianLower(BiasTimeframe, period, shift + 1);
      if(close_i <= 0 || prev_upper <= 0 || prev_lower <= 0) continue;
      bars_checked++;

      datetime bar_time = iTime(_Symbol, BiasTimeframe, shift);

      if(close_i > prev_upper) {        // bullish breakout on this bar
         newest_bull = bar_time;
         bull_level  = prev_upper;
      }
      if(close_i < prev_lower) {        // bearish breakout on this bar
         newest_bear = bar_time;
         bear_level  = prev_lower;
      }
   }

   // Apply HARD CANCEL: if price has since closed back through the level, void it
   double d1_close_now = iClose(_Symbol, BiasTimeframe, 1);
   if(newest_bull > 0 && d1_close_now < bull_level) newest_bull = 0;
   if(newest_bear > 0 && d1_close_now > bear_level) newest_bear = 0;

   // Keep only the more recent of the two (a fresh bear cancels an old bull)
   if(newest_bull > 0 && newest_bull >= newest_bear) {
      g_d1_bull_breakout_time  = newest_bull;
      g_d1_bull_breakout_level = bull_level;
      g_d1_bear_breakout_time  = 0;
      Print(StringFormat("[D1 INIT] Backfilled BULL breakout from history: "
            "level=%.5f (%d bars ago)", bull_level,
            iBarShift(_Symbol, BiasTimeframe, newest_bull)));
   } else if(newest_bear > 0 && newest_bear > newest_bull) {
      g_d1_bear_breakout_time  = newest_bear;
      g_d1_bear_breakout_level = bear_level;
      g_d1_bull_breakout_time  = 0;
      Print(StringFormat("[D1 INIT] Backfilled BEAR breakout from history: "
            "level=%.5f (%d bars ago)", bear_level,
            iBarShift(_Symbol, BiasTimeframe, newest_bear)));
   } else {
      Print(StringFormat("[D1 INIT] No active D1 breakout in %d D1 bars checked "
            "(scan=%d, period=%d) — bias starts neutral",
            bars_checked, scan_bars, period));
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   // ── InitialBalance sanity check (2026-06-30) ─────────────────────────
   // BUG FOUND: InitialBalance is the reference point for the overall-loss
   // circuit breaker (IsOverallLossLimitReached: hit when
   // InitialBalance - equity >= MaxOverallLossAmount - SafetyBuffer).
   // If the .set file's InitialBalance doesn't match the account's actual
   // starting balance (e.g. a .set built for a 1,000,000 account loaded on
   // a 100,000 account), the EA computes a fake "loss" of 900,000 and
   // halts permanently on the FIRST tick, before any signal is evaluated —
   // with no trades ever opening. This silently looked like "the strategy
   // doesn't trade" when it was actually a config/account size mismatch.
   //
   // Fix: auto-correct to the real account balance unless the mismatch is
   // small (<5%, i.e. normal drift from a prior session's P&L) — large
   // mismatches almost always mean a wrong .set was loaded, not a deliberate
   // custom baseline, so we warn loudly and use the REAL balance instead of
   // silently halting on a typo.
   double real_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_effective_initial_balance = InitialBalance;
   if(InitialBalance > 0 && real_balance > 0) {
      double mismatch_pct = MathAbs(InitialBalance - real_balance) / real_balance * 100.0;
      if(mismatch_pct > 5.0) {
         Print(StringFormat(
            "[WARN] InitialBalance input (%.2f) differs from actual account "
            "balance (%.2f) by %.1f%% — this looks like a stale/wrong .set "
            "file (the overall-loss circuit breaker would otherwise compute "
            "a fake %.2f 'loss' and halt before any trade). "
            "Using actual account balance (%.2f) as the reference instead. "
            "If this account intentionally tracks a custom baseline, set "
            "InitialBalance explicitly close to the real balance to silence this.",
            InitialBalance, real_balance, mismatch_pct,
            InitialBalance - real_balance, real_balance));
         g_effective_initial_balance = real_balance;
      }
   }

   // Fill lot ladder
   LOT_LADDER[0] = LotMultL1;
   LOT_LADDER[1] = LotMultL2;
   LOT_LADDER[2] = LotMultL3;
   LOT_LADDER[3] = LotMultL4;

   // BUG FOUND (bot4 audit, 2026-08): MaxPyramidLevels was a plain int input
   // with NO clamp anywhere. PyramidBasket.level[] is a FIXED 4-slot array
   // (L1..L4) and LOT_LADDER[] is also fixed to 4 — CalculateLotForLevel()
   // already clamps its own LOT_LADDER read via MathMin(level_idx,3), but
   // ManageActiveBasket()'s pyramid-add path calls
   // OpenPyramidLevel(g_pyr.active_levels, ...) directly and writes to
   // g_pyr.level[new_idx] with NO clamp. Any run/optimizer sweep/.set file
   // with MaxPyramidLevels>4 (or <=0) would eventually index level[4]+ —
   // an out-of-bounds write on a fixed-size array (#property strict makes
   // this a fatal "array out of range" runtime error, silently invalidating
   // that whole Tester pass, or crashing a live/demo chart). Clamp here so
   // a bad input value fails loud in the log instead of failing silently
   // mid-run — this is exactly the parameter most likely to get pushed
   // beyond 4 while exploring "much bigger position / deeper pyramiding"
   // variants.
   int clamped_max_pyr = MaxPyramidLevels;
   if(clamped_max_pyr > 4) clamped_max_pyr = 4;
   if(clamped_max_pyr < 1) clamped_max_pyr = 1;
   if(clamped_max_pyr != MaxPyramidLevels) {
      Print(StringFormat(
         "[INIT WARN] MaxPyramidLevels=%d is out of the supported range [1,4] "
         "(level[] array and LOT_LADDER[] are both fixed at 4 slots — L1..L4). "
         "Clamped to %d for this run to avoid an out-of-bounds pyramid-level "
         "write. To go deeper than L4, PyramidBasket.level[4] and LOT_LADDER[4] "
         "must be resized in source first, plus LotMultL5+ inputs added.",
         MaxPyramidLevels, clamped_max_pyr));
      g_max_pyramid_levels_effective = clamped_max_pyr;
   } else {
      g_max_pyramid_levels_effective = MaxPyramidLevels;
   }

   // Symbol validation
   string sym = NormaliseSymbol(_Symbol);
   if(!IsSymbolApproved(sym)) {
      Print("[WARN] Symbol '",_Symbol,"' → '",sym,"' not in approved list — proceeding but verify");
   }

   if(StringLen(ConfigSymbol)>0 && ConfigSymbol!=_Symbol)
      Print("[WARN] ConfigSymbol='",ConfigSymbol,"' ≠ chart symbol '",_Symbol,"'");

   // Indicator handles — M15 (chart TF)
   atrM15Handle   = iATR(_Symbol, _Period, 14);
   atrShortHandle = iATR(_Symbol, _Period, ATRShortPeriod);
   atrLongHandle  = iATR(_Symbol, _Period, ATRLongPeriod);
   adxM15Handle   = iADX(_Symbol, _Period, ADXPeriod);
   ema20M15Handle = iMA(_Symbol, _Period, EMAEntryPeriod, 0, MODE_EMA, PRICE_CLOSE);
   // H4
   atrH4Handle    = iATR(_Symbol, PERIOD_H4, 14);
   // H1
   atrH1Handle    = iATR(_Symbol, PERIOD_H1, ChandelierPeriod);
   // Bias-timeframe EMA (FEATURE 4: now follows BiasTimeframe, default D1 = unchanged)
   emaD1FastHandle = iMA(_Symbol, BiasTimeframe, D1EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   emaD1SlowHandle = iMA(_Symbol, BiasTimeframe, D1EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   // FEATURE (1) 2026-07-25: ATR on BiasTimeframe itself, for the breakout
   // confirmation buffer. Deliberately separate from g_atr_d1_handle below,
   // which stays anchored to D1 for Renko brick sizing regardless of what
   // BiasTimeframe is set to.
   biasATRHandle = iATR(_Symbol, BiasTimeframe, 14);
   // FEATURE (6) 2026-07-25: higher-timeframe trend-alignment MA, only used
   // when UseHigherTFTrendFilter=true.
   higherTFMAHandle = iMA(_Symbol, HigherTFTrendTimeframe, HigherTFMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(UseD1BreakoutBuffer && biasATRHandle == INVALID_HANDLE)
      Print("[INIT WARN] biasATRHandle failed — breakout buffer will be treated as 0 (off) until this resolves");
   if(UseHigherTFTrendFilter && higherTFMAHandle == INVALID_HANDLE)
      Print("[INIT WARN] higherTFMAHandle failed — higher-TF trend filter will be skipped (treated as always-pass) until this resolves");

   // Diagnostic mode banner
   if(DiagnosticMode)
      Print("[DIAG] DiagnosticMode ON — verbose no-trade logging active. "
            "Heartbeat every ", HeartbeatBars, " bars. Set DiagnosticMode=false once validated.");

   // v1.2: In-memory Renko — no iCustom() needed
   // D1 ATR handle for brick size calculation
   g_atr_d1_handle = iATR(_Symbol, PERIOD_D1, 14);
   if(g_atr_d1_handle == INVALID_HANDLE) {
      Print("[INIT WARN] D1 ATR handle failed — Renko will use M15 ATR fallback");
   }

   // Resize Renko ring buffer
   ArrayResize(g_renko_bricks, MaxRenkoBricks);
   // Zero-initialize all bricks
   for(int _bi = 0; _bi < MaxRenkoBricks; _bi++) {
      g_renko_bricks[_bi].open       = 0;
      g_renko_bricks[_bi].close      = 0;
      g_renko_bricks[_bi].direction  = 0;
      g_renko_bricks[_bi].time_formed= 0;
   }

   // Build Renko history from M15 confirmed bars
   RenkoInitHistory();
   if(g_renko_count < MathMax(RenkoDonPeriod, RenkoEMASlowPeriod) + 5) {
      Print(StringFormat("[INIT WARN] Only %d Renko bricks on init (need %d) — "
                         "signals will activate after warmup",
            g_renko_count, MathMax(RenkoDonPeriod, RenkoEMASlowPeriod)+5));
   }
   // Compute initial signal state
   RenkoComputeSignal();

   // ── CRITICAL FIX: scan historical D1 bars for the most recent breakout ──
   // Previously, D1 bias only activated if the EA was RUNNING on the exact bar
   // that broke out. If the breakout happened before the EA started (or a restart
   // wiped the globals), bias stayed 0 forever even in a strong trend — which is
   // why FX symbols showed no_trend=15/16 despite being in clear trends.
   // This backfills g_d1_*_breakout_time by scanning the last D1TrendValidBars.
   ScanHistoricalD1Breakout();

   bool ok = (atrM15Handle    != INVALID_HANDLE &&
              atrShortHandle  != INVALID_HANDLE &&
              atrLongHandle   != INVALID_HANDLE &&
              adxM15Handle    != INVALID_HANDLE &&
              ema20M15Handle  != INVALID_HANDLE &&
              atrH4Handle     != INVALID_HANDLE &&
              atrH1Handle     != INVALID_HANDLE &&
              emaD1FastHandle != INVALID_HANDLE &&
              emaD1SlowHandle != INVALID_HANDLE);
   if(!ok) { Print("[INIT FAIL] Core indicator handles invalid"); return INIT_FAILED; }

   // Init pyramid state
   ZeroMemory(g_pyr);
   for(int i=0; i<4; i++) g_pyr.continue_called[i] = false;

   // Restore persistent overall-loss flag (survives MT5 restart — Bot3 audit lesson)
   string ovGV = B4_OVERALL_HIT_VAR();
   if(GlobalVariableCheck(ovGV) && GlobalVariableGet(ovGV) > 0.5) {
      g_overall_stop_hit = true;
      Print("[INIT] WARNING: OverallLossHit flag restored from GlobalVariable. EA halted for trading.");
   }

   // FIX (2026-07-21): restore SL/TP cooldown timers — see CloseBasket() for
   // why this exists. Without this, a restart during an active cooldown
   // silently let a new L1 open with no gate ever blocking it (confirmed
   // via CSV: 2026-07-20 21:02:39 open, only 1h35m after a 19:27:33 SL,
   // inside what should have been a 12h window).
   string coolSlGV = "B4_COOL_SL_" + _Symbol;
   string coolTpGV = "B4_COOL_TP_" + _Symbol;
   if(GlobalVariableCheck(coolSlGV)) {
      g_cooldown_sl_time = (datetime)GlobalVariableGet(coolSlGV);
      int barsSinceRestore = (int)((TimeCurrent() - g_cooldown_sl_time) / PeriodSeconds(_Period));
      if(barsSinceRestore < CooldownBarsSL)
         Print(StringFormat("[INIT] SL cooldown restored from GlobalVariable: %d/%d bars remaining",
               barsSinceRestore, CooldownBarsSL));
   }
   if(GlobalVariableCheck(coolTpGV))
      g_cooldown_tp_time = (datetime)GlobalVariableGet(coolTpGV);

   // Recover from existing positions
   ReconstructBasketFromPositions();

   // Daily stats
   UpdateDailyStats();

   // Trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   // FIX/CHECK (2026-07-25): SL and the pyramid-add trigger are sized off
   // different ATR timeframes (SL = BasketSLATRMult × M15 ATR, pyramid-add
   // = PyramidSpacingMult × H4 ATR) — nothing enforces they're on a
   // consistent scale. If the SL distance (in M15-ATR terms) is smaller
   // than the pyramid trigger distance, the SL will on average fire before
   // a trade ever earns a pyramid add, even in a straight-line trend with
   // zero pullback. This does NOT change behavior — it just makes the
   // mismatch visible instead of silently limiting pyramiding.
   {
      double m15atr_now = GetATRValue_M15();
      double h4atr_now  = GetATRValue_H4();
      if(m15atr_now > 0) {
         double sl_in_m15atr = BasketSLATRMult;
         double pyramid_trigger_in_m15atr = (h4atr_now > 0) ?
            PyramidSpacingMult * (h4atr_now / m15atr_now) : 0;
         if(pyramid_trigger_in_m15atr > 0 && sl_in_m15atr < pyramid_trigger_in_m15atr) {
            double shortfall_pct = (1.0 - sl_in_m15atr / pyramid_trigger_in_m15atr) * 100.0;
            Print(StringFormat("[INIT WARN] %s: SL (BasketSLATRMult=%.2f x M15 ATR) is %.0f%% TIGHTER "
                  "than the pyramid-add trigger (PyramidSpacingMult=%.2f x H4 ATR, currently ~%.2fx M15 ATR "
                  "at today's volatility) — trades are likely to hit SL before ever earning a pyramid add, "
                  "even with zero pullback. Consider raising BasketSLATRMult or lowering PyramidSpacingMult "
                  "so SL >= pyramid trigger distance.",
                  _Symbol, sl_in_m15atr, shortfall_pct, PyramidSpacingMult, pyramid_trigger_in_m15atr));
         }
      }
   }

   Print(StringFormat("[INIT] Bot4 v1.45 | %s | Magic=%d | Mode=%s | ShadowGate=%d | LiveGate=%d",
         _Symbol, MagicNumber,
         ShadowModeOnly?"SHADOW":"LIVE",
         ShadowScoreThreshold, LiveScoreThreshold));
   return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//| REGIME 2.3 OnTester PORT -- shared scoring module                |
//| Ported verbatim (logic unchanged) from bot1_regime2.3.mq5's       |
//| current OnTester(), 2026-09-22, per user request to confront      |
//| every EA on this account against ONE common selection criterion.  |
//| All new inputs/functions are prefixed R23_ to guarantee zero name |
//| collisions with this file's own pre-existing inputs/functions.    |
//| REPLACES this file's own previous OnTester() -- see diff for the  |
//| removed version, kept in project history / git if tracked.        |
//+------------------------------------------------------------------+
input group "═══ REGIME 2.3 SHARED ONTESTER (ported score, 2026-09-22) ═══"
enum ENUM_R23_OPT_SCORE {
   R23_SCORE_RF_SOFT = 0,  // Recovery Factor backbone, no PF multiply, soft ramps (default, matches current bot1_regime2.3 production scoring)
   R23_SCORE_UPI     = 1,  // profit% / Ulcer Index as the whole score
   R23_SCORE_PARDO   = 2   // 2026-09-27: Pardo pessimistic-profit + Sterling cushion + hard DD gate (see OnTester())
};
input ENUM_R23_OPT_SCORE R23_OptScoreMode          = R23_SCORE_RF_SOFT;
input int    R23_OptMinTrades                      = 30;    // soft ramp below this trade count, not a hard gate
input double R23_OptMaxDDPctAllowed                = 3.5;   // soft ramp above this equity DD%, matches current 3.5% production ceiling
input bool   R23_UseDailyDDGate                    = true;
input double R23_OptMaxDailyDDPctAllowed           = 5.0;
input bool   R23_UseUlcerPenalty                   = true;  // only used when R23_OptScoreMode=R23_SCORE_UPI
input double R23_OptUlcerFloor                     = 1.0;
input bool   R23_UseConcentrationPenalty           = true;
input double R23_OptMaxDayConcentrationPct         = 40.0;

input group "═══ SCORE_PARDO: pessimistic-profit + Sterling cushion + hard DD gate (2026-09-27) ═══"
// See bot1_regime2.0.mq5 / bossafx-performance skill for full rationale.
input double R23_OptPardoDDCapPct     = 5.0;    // hard equity-DD cap, % (below this: no DD penalty at all)
input int    R23_OptPardoMinTrades    = 100;    // below this trade count: graded rejection
input int    R23_OptPardoFullTrades   = 200;    // trade count for FULL confidence weight
input double R23_OptPardoSterlingCushion = 10.0; // Sterling ratio's original cushion (Deane Sterling Jones, 1981)
input double R23_OptPardoMinImputedLoss  = 1.0;  // minimum imputed loss count when a candidate has ZERO observed losses

input group "═══ SPREAD/SLIPPAGE REALISM PENALTY (2026-09-26) ═══"
// PROBLEM THIS FIXES: MT5's backtester fills orders at the exact requested
// price by default, ignoring real broker spread/slippage. A sweep can
// therefore reward TP1/TP2/TrailingDistance values only reachable in the
// frictionless backtest, not on demo/live. Does NOT change how real trades
// execute -- only makes the OPTIMIZER'S SCORE reflect the cost honestly.
input bool   R23_UseSpreadSlippagePenalty = true;   // master on/off -- off reproduces the pre-2026-09-26 scoring exactly
input double R23_OptAssumedSpreadPoints   = 60.0;   // CORRECTED 2026-09-26: real observed GOLD_test spread is 57-64pts (median ~60), per spread_pts_at_entry logged on 19 real bot1r21 trades. Previous default of 550 was a unit-confusion error, ~9x too harsh.
input double R23_OptAssumedSlippagePoints = 15.0;   // modest ~25% buffer over the observed spread
input double R23_OptAssumedLotForPenalty  = 0.05;   // typical live lot size -- $ conversion only, does not affect real position sizing

double R23_EstimateSpreadSlippageCost(double numTrades) {
   if(!R23_UseSpreadSlippagePenalty || numTrades <= 0) return 0.0;
   double pointCostPerLot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                             MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / _Point, 1.0);
   double costPerTrade = (R23_OptAssumedSpreadPoints + R23_OptAssumedSlippagePoints) * pointCostPerLot * R23_OptAssumedLotForPenalty;
   return numTrades * costPerTrade;
}

double R23_CalculateUlcerIndex() {
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

double R23_CalculateWorstDailyDDPct() {
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
         if(curDayKey != -1 && dayStartBalance > 0.0) {
            double ddPct = (dayStartBalance - dayLowBalance) / dayStartBalance * 100.0;
            if(ddPct > worstDayPct) worstDayPct = ddPct;
         }
         curDayKey = dayKey;
         dayStartBalance = balance;
         dayLowBalance   = balance;
      }
      balance += dealProfit;
      if(balance < dayLowBalance) dayLowBalance = balance;
   }
   if(curDayKey != -1 && dayStartBalance > 0.0) {
      double ddPct = (dayStartBalance - dayLowBalance) / dayStartBalance * 100.0;
      if(ddPct > worstDayPct) worstDayPct = ddPct;
   }
   return worstDayPct;
}

double R23_CalculateMaxDayConcentrationPct() {
   if(!HistorySelect(0, TimeCurrent())) return 0.0;
   int totalDeals = HistoryDealsTotal();
   if(totalDeals <= 1) return 0.0;
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
   if(dayCount == 0 || totalProfit <= 0.0) return 0.0;
   double maxDayProfit = 0.0;
   for(int j = 0; j < dayCount; j++) {
      if(dayProfits[j] > maxDayProfit) maxDayProfit = dayProfits[j];
   }
   return (maxDayProfit / totalProfit) * 100.0;
}

double R23_SoftRampOverCap(double value, double cap) {
   if(!MathIsValidNumber(value) || cap <= 0.0) return 1.0;
   if(value <= cap) return 1.0;
   double over = (value - cap) / cap;
   return 1.0 / (1.0 + over * over * 8.0);
}

double R23_ApplyConcentrationSoft(double score) {
   if(!R23_UseConcentrationPenalty) return score;
   double max_day_pct = R23_CalculateMaxDayConcentrationPct();
   if(max_day_pct > R23_OptMaxDayConcentrationPct) {
      double excess = max_day_pct - R23_OptMaxDayConcentrationPct;
      score = score / (1.0 + (excess / 25.0));
   }
   return score;
}

// SCORE_PARDO helper -- 2026-09-27. See bot1_regime2.0.mq5 for full rationale.
double R23_CalcPardoPessimisticProfitPct(double trades) {
   double deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
   double grossLoss   = MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   double W = TesterStatistics(STAT_PROFIT_TRADES);
   double L = TesterStatistics(STAT_LOSS_TRADES);
   if(deposit <= 0.0) return 0.0;

   double avgWin  = (W > 0.0) ? grossProfit / W : 0.0;
   double avgLoss = (L > 0.0) ? grossLoss / L : avgWin;

   double Wp = MathMax(W - MathSqrt(W), 0.0);
   double Lp = L + MathMax(MathSqrt(L), R23_OptPardoMinImputedLoss);

   double pessimisticProfit = avgWin * Wp - avgLoss * Lp;
   // 2026-09-27 BUGFIX: subtract the same friction estimate applied to
   // net_profit elsewhere -- STAT_GROSS_PROFIT/LOSS never see it.
   pessimisticProfit -= R23_EstimateSpreadSlippageCost(trades);
   return (pessimisticProfit / deposit) * 100.0;
}

double OnTester() {
   double trades = TesterStatistics(STAT_TRADES);
   double max_dd_pct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double init_bal   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double net_profit = TesterStatistics(STAT_PROFIT);
   net_profit -= R23_EstimateSpreadSlippageCost(trades);  // 2026-09-26: realism penalty, see input group comment
   double profit_pct = (init_bal > 0) ? net_profit / init_bal * 100.0 : 0.0;
   if(!MathIsValidNumber(max_dd_pct) || max_dd_pct < 0.0) max_dd_pct = 0.0;

   double tradesRamp = 1.0;
   if(R23_OptMinTrades > 0 && trades < R23_OptMinTrades)
      tradesRamp = 0.01 + 0.99 * (trades / (double)R23_OptMinTrades);

   double ddRamp = R23_SoftRampOverCap(max_dd_pct, R23_OptMaxDDPctAllowed);
   double dailyRamp = 1.0;
   if(R23_UseDailyDDGate)
      dailyRamp = R23_SoftRampOverCap(R23_CalculateWorstDailyDDPct(), R23_OptMaxDailyDDPctAllowed);

   double sample_conf = MathSqrt(MathMin(trades, 100.0));
   double score = 0.0;

   if(R23_OptScoreMode == R23_SCORE_PARDO) {
      if(trades < R23_OptPardoMinTrades) {
         return -1000.0 + trades;
      }
      double pessPct = R23_CalcPardoPessimisticProfitPct(trades);
      if(pessPct <= 0.0) {
         return pessPct;
      }
      double tw      = MathMin(trades / MathMax(R23_OptPardoFullTrades, 1), 1.0);
      double ddGate   = (max_dd_pct <= R23_OptPardoDDCapPct) ? 1.0
                        : MathMax(0.0, 1.0 / (1.0 + 2.0 * (max_dd_pct - R23_OptPardoDDCapPct) / R23_OptPardoDDCapPct));
      double sterling = R23_OptPardoSterlingCushion / (R23_OptPardoSterlingCushion + max_dd_pct);
      score = pessPct * tw * ddGate * sterling;
      score = R23_ApplyConcentrationSoft(score);
      return score;
   }

   if(R23_OptScoreMode == R23_SCORE_UPI) {
      double ulcer = R23_CalculateUlcerIndex();
      double ui = MathMax(ulcer, R23_OptUlcerFloor);
      if(ui < 0.1) ui = 0.1;
      score = profit_pct / ui * sample_conf * tradesRamp * ddRamp * dailyRamp;
   } else {
      double ddTerm = MathMax(max_dd_pct, 0.1);
      score = profit_pct / ddTerm * sample_conf * tradesRamp * ddRamp * dailyRamp;
   }

   score = R23_ApplyConcentrationSoft(score);
   return score;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(atrM15Handle);
   IndicatorRelease(atrShortHandle); IndicatorRelease(atrLongHandle);
   IndicatorRelease(adxM15Handle);   IndicatorRelease(ema20M15Handle);
   IndicatorRelease(atrH4Handle);    IndicatorRelease(atrH1Handle);
   IndicatorRelease(emaD1FastHandle);IndicatorRelease(emaD1SlowHandle);
   if(biasATRHandle != INVALID_HANDLE) IndicatorRelease(biasATRHandle);
   if(higherTFMAHandle != INVALID_HANDLE) IndicatorRelease(higherTFMAHandle);
   if(g_atr_d1_handle != INVALID_HANDLE) IndicatorRelease(g_atr_d1_handle);
   ArrayFree(g_renko_bricks);
   Comment("");
   long id=0; int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--) { string n=ObjectName(0,i); if(StringFind(n,"B4_")>=0)ObjectDelete(id,n); }
   DeleteBasketLines();
   Print("[DEINIT] Bot4 EA removed. Reason=",reason);
}

//+------------------------------------------------------------------+
//| OnTick — main logic                                              |
//+------------------------------------------------------------------+
// ── DIAGNOSTIC: reset daily counters + emit heartbeat ──────────────
void DiagResetIfNewDay() {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
   if(today != g_diag_day) {
      g_diag_day = today;
      g_diag_ticks_total = 0; g_diag_no_trend = 0; g_diag_weak_bias = 0;
      g_diag_adx_block = 0; g_diag_spread_block = 0; g_diag_atr_block = 0;
      g_diag_renko_no_signal = 0; g_diag_renko_warmup = 0; g_diag_below_shadow = 0;
      g_diag_shadow_logged = 0; g_diag_cooldown_block = 0; g_diag_cap_block = 0;
      g_diag_news_block = 0; g_diag_time_block = 0; g_diag_live_attempts = 0;
      g_diag_renko_channel_break_no_signal = 0;
      g_diag_last_hb_bar = 0;
   }
}

void DiagHeartbeat() {
   if(!DiagnosticMode) return;
   if(HeartbeatBars <= 0) return;
   if(g_diag_ticks_total - g_diag_last_hb_bar < HeartbeatBars) return;
   g_diag_last_hb_bar = g_diag_ticks_total;

   int min_bricks = MathMax(RenkoDonPeriod, RenkoEMASlowPeriod) + 5;
   string renko_state = (g_renko_count < min_bricks) ?
      StringFormat("WARMUP %d/%d bricks", g_renko_count, min_bricks) :
      StringFormat("ready %d bricks sig=%d", g_renko_count, g_renko_signal);

   Print(StringFormat(
      "[HEARTBEAT] %s | bars=%d | Renko: %s | "
      "no_trend=%d weak=%d adx=%d spread=%d atr=%d "
      "renko_nosig=%d warmup=%d renko_blocked=%d below_shadow=%d | "
      "shadow_logged=%d cooldown=%d cap=%d news=%d time=%d | live_attempts=%d",
      _Symbol, g_diag_ticks_total, renko_state,
      g_diag_no_trend, g_diag_weak_bias, g_diag_adx_block,
      g_diag_spread_block, g_diag_atr_block,
      g_diag_renko_no_signal, g_diag_renko_warmup, g_diag_renko_channel_break_no_signal, g_diag_below_shadow,
      g_diag_shadow_logged, g_diag_cooldown_block, g_diag_cap_block,
      g_diag_news_block, g_diag_time_block, g_diag_live_attempts));
}

// FIX (v1.49, regime-suite branch): time-interval-driven CSV heartbeat log
// (bot4_heartbeat_{SYMBOL}.csv), ported from bot1-regime. Cheap by design —
// only fires once every CsvHeartbeatSeconds of WALL-CLOCK time (checked via
// TimeCurrent(), not bar/tick count), and does no indicator/history reads at
// all, just cheap AccountInfo/PositionsTotal calls. Deliberately independent
// of whether any bars/trades/signals are happening — a gap in THIS log is
// itself the diagnosis (EA/chart died) as opposed to "EA alive but gated".
void WriteCsvHeartbeatIfDue() {
   if(CsvHeartbeatSeconds <= 0) return;
   // FIX (v1.49 perf fix): NEVER write the heartbeat CSV during an
   // OPTIMIZATION run (many passes). TimeCurrent() in the Tester is
   // SIMULATED time, not wall-clock — over an 8-month backtest that's
   // ~70,000 heartbeat writes PER PASS (each 2-3 file opens), and ALL passes
   // share the same output filename, so a 2000-pass sweep would mean ~140
   // million file-write operations accumulating into one CSV. Measured
   // impact: sweep throughput dropped to ~32 passes/hour (down from
   // thousands/hour on prior sweeps with no heartbeat). This log only has
   // meaning for live/demo monitoring or a single manual verify run (where
   // MQL5_OPTIMIZATION is false) — deliberately NOT guarded on MQL5_TESTER
   // alone, so a single-run backtest verify (Optimization=Disabled) still
   // gets heartbeat rows, same as the v1.49 smoke test that validated this
   // feature.
   // FIX (v1.49 perf fix v2): guard widened from MQL_OPTIMIZATION to
   // MQL5_TESTER — heartbeat has ZERO value in ANY backtest, not just
   // optimization. Confirmed directly: the v1.49 smoke test was a SINGLE
   // run (not optimization) and still produced 40,805 heartbeat rows.
   // Heartbeat answers "is a human-facing live chart still alive right now"
   // — that question doesn't exist in a deterministic, non-realtime
   // backtest, single-run or not. Live/demo only from here on.
   if(MQLInfoInteger(MQL_TESTER)) return;
   datetime now = TimeCurrent();
   if(g_csv_last_heartbeat_time > 0 && (now - g_csv_last_heartbeat_time) < CsvHeartbeatSeconds) return;
   g_csv_last_heartbeat_time = now;

   string filename = "bot4_heartbeat_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "event_time,symbol,magic,run_profile,balance,equity,"
      "open_positions_this_magic,last_bar_time,seconds_since_last_bar,"
      "cooldown_sl_active,cooldown_tp_active";
   bool need_header = EnsureCsvSchema(filename, EXPECTED_HEADER);
   int handle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, EXPECTED_HEADER + "\n");
   FileSeek(handle, 0, SEEK_END);

   int open_count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Magic() == MagicNumber) open_count++;
   }
   datetime last_bar = iTime(_Symbol, _Period, 0);
   int secs_since_bar = (last_bar > 0) ? (int)(now - last_bar) : -1;
   int barsSinceSLnow = (g_cooldown_sl_time>0) ? (int)((now-g_cooldown_sl_time)/PeriodSeconds(_Period)) : 9999;
   int barsSinceTPnow = (g_cooldown_tp_time>0) ? (int)((now-g_cooldown_tp_time)/PeriodSeconds(_Period)) : 9999;
   bool cool_sl = (g_cooldown_sl_time>0 && barsSinceSLnow < CooldownBarsSL);
   bool cool_tp = (g_cooldown_tp_time>0 && barsSinceTPnow < CooldownBarsTP);

   MqlDateTime mdt; TimeToStruct(now, mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                 mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   FileWriteString(handle,
      ts_str + "," + _Symbol + "," + IntegerToString(MagicNumber) + "," + RunProfileTag + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) + "," +
      IntegerToString(open_count) + "," +
      TimeToString(last_bar, TIME_DATE|TIME_SECONDS) + "," +
      IntegerToString(secs_since_bar) + "," +
      (cool_sl?"1":"0") + "," + (cool_tp?"1":"0") + "\n");
   FileClose(handle);
}

// FIX (v1.49, regime-suite branch): transition-driven regime-event log
// (bot4_regime_events_{SYMBOL}.csv), ported from bot1-regime. PERFORMANCE
// NOTE: RegimeSuiteVerdict()/ComputeRegimeSuiteVotes() call CopyClose/
// CopyHigh/CopyLow — real history reads, not free. This function is
// therefore explicitly BAR-GATED (via g_regime_last_checked_bar), not
// tick-gated, even though it's called from OnTick() every tick — it does
// nothing until a new bar has actually formed, so it costs one indicator
// read per bar (same cost class as the rest of the EA's per-bar logic), not
// per tick. Writes a row ONLY on an actual transition (near-zero row volume
// in production), and captures a GATE_FLIP on any INDIVIDUAL filter even
// when the combined verdict doesn't change under OR/MAJORITY modes.
void CheckAndWriteRegimeEvents() {
   if(!UseRegimeSuite) return;   // suite off — nothing to track transitions on
   // FIX (v1.49 perf fix): same reasoning as WriteCsvHeartbeatIfDue() —
   // during optimization ALL passes share the same output filename, so a
   // 2000-pass sweep would mean thousands of passes' worth of transitions
   // (~8,350 rows/pass observed in the smoke test) all appending to one CSV.
   // Lower per-pass volume than the heartbeat, but still meaningfully adds
   // up across a large sweep, and this log has no analytical value for
   // comparing sweep passes anyway (it's for understanding ONE run's regime
   // behavior in detail, not for cross-pass comparison). Skipped during
   // optimization; still active for single-run verify/live/demo.
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == g_regime_last_checked_bar) return;   // bar-gate — see perf note above
   g_regime_last_checked_bar = curBar;

   bool adx_v, er_v, chop_v, atr_v, sess_v;
   int votes_trending, votes_total;
   ComputeRegimeSuiteVotes(adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   bool combined = (votes_total == 0) ? true :
      (RegimeSuiteVoteMode == RS_VOTE_AND      ? (votes_trending == votes_total) :
       RegimeSuiteVoteMode == RS_VOTE_OR       ? (votes_trending > 0) :
                                                  (votes_trending * 2 > votes_total));

   if(!g_regime_state_initialized) {
      // First evaluation this run — seed state, do not log a spurious "flip"
      // from the arbitrary bool defaults above.
      g_last_regime_verdict = combined;
      g_last_regime_adx_vote = adx_v; g_last_regime_er_vote = er_v;
      g_last_regime_chop_vote = chop_v; g_last_regime_atr_vote = atr_v;
      g_last_regime_session_vote = sess_v;
      g_regime_state_initialized = true;
      return;
   }

   string filename = "bot4_regime_events_" + _Symbol + ".csv";
   const string EXPECTED_HEADER =
      "event_time,symbol,event_type,combined_verdict,vote_mode,"
      "adx_vote,er_vote,chop_vote,atr_vote,session_vote,votes_trending,votes_total";

   // Combined-verdict transition (REGIME_DEGRADED = became non-trending,
   // REGIME_CLEARED = became trending again).
   if(combined != g_last_regime_verdict) {
      string event_type = combined ? "REGIME_CLEARED" : "REGIME_DEGRADED";
      WriteRegimeEventRow(filename, EXPECTED_HEADER, event_type, combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   }
   // Individual filter flips (GATE_FLIP) — logged even if the combined
   // verdict above didn't change, so a filter's own behavior stays visible
   // under OR/MAJORITY vote modes where it can flip without moving the
   // combined result.
   if(RSUseADX     && adx_v     != g_last_regime_adx_vote)
      WriteRegimeEventRow(filename, EXPECTED_HEADER, "GATE_FLIP_ADX", combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   if(RSUseER      && er_v      != g_last_regime_er_vote)
      WriteRegimeEventRow(filename, EXPECTED_HEADER, "GATE_FLIP_ER", combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   if(RSUseCHOP    && chop_v    != g_last_regime_chop_vote)
      WriteRegimeEventRow(filename, EXPECTED_HEADER, "GATE_FLIP_CHOP", combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   if(RSUseATRRatio&& atr_v     != g_last_regime_atr_vote)
      WriteRegimeEventRow(filename, EXPECTED_HEADER, "GATE_FLIP_ATRRATIO", combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);
   if(RSUseSession && sess_v    != g_last_regime_session_vote)
      WriteRegimeEventRow(filename, EXPECTED_HEADER, "GATE_FLIP_SESSION", combined,
                           adx_v, er_v, chop_v, atr_v, sess_v, votes_trending, votes_total);

   g_last_regime_verdict = combined;
   g_last_regime_adx_vote = adx_v; g_last_regime_er_vote = er_v;
   g_last_regime_chop_vote = chop_v; g_last_regime_atr_vote = atr_v;
   g_last_regime_session_vote = sess_v;
}

// Shared row-writer for CheckAndWriteRegimeEvents() — avoids duplicating the
// FileOpen/EnsureCsvSchema/FileWriteString boilerplate across 6 call sites.
void WriteRegimeEventRow(string filename, string header, string event_type, bool combined,
                          bool adx_v, bool er_v, bool chop_v, bool atr_v, bool sess_v,
                          int votes_trending, int votes_total) {
   bool need_header = EnsureCsvSchema(filename, header);
   int handle = FileOpen(filename, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle == INVALID_HANDLE) return;
   if(need_header) FileWriteString(handle, header + "\n");
   FileSeek(handle, 0, SEEK_END);

   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string ts_str = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                                 mdt.year,mdt.mon,mdt.day,mdt.hour,mdt.min,mdt.sec);
   string vote_mode_str = (RegimeSuiteVoteMode==RS_VOTE_AND)?"AND":
                           (RegimeSuiteVoteMode==RS_VOTE_OR)?"OR":"MAJORITY";
   FileWriteString(handle,
      ts_str + "," + _Symbol + "," + event_type + "," + (combined?"1":"0") + "," + vote_mode_str + "," +
      (adx_v?"1":"0") + "," + (er_v?"1":"0") + "," + (chop_v?"1":"0") + "," +
      (atr_v?"1":"0") + "," + (sess_v?"1":"0") + "," +
      IntegerToString(votes_trending) + "," + IntegerToString(votes_total) + "\n");
   FileClose(handle);
}

void OnTick() {

   // FIX (v1.49, regime-suite branch): wall-clock time-driven CSV heartbeat +
   // transition-driven regime-event log. Both checked once per tick (cheap —
   // early-return unless enough wall-clock time or a real transition
   // happened), independent of the bar-gate below so they keep working even
   // during a long bar (heartbeat) or fire immediately on a mid-bar tick
   // that changes the regime read (regime-event).
   WriteCsvHeartbeatIfDue();
   CheckAndWriteRegimeEvents();

   // ── INTRABAR EXIT CHECKS (every tick) ────────────────────────────
   if(g_pyr.active_levels > 0) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // ── Basket SL check ──────────────────────────────────────────
      if(g_pyr.basket_sl_price > 0) {
         bool sl_hit = (g_pyr.direction==1) ?
                       (bid <= g_pyr.basket_sl_price) :
                       (ask >= g_pyr.basket_sl_price);
         if(sl_hit) {
            Print("[TICK-SL] Basket SL hit: price=",
                  ((g_pyr.direction==1)?bid:ask), " sl=", g_pyr.basket_sl_price);
            CloseBasket("BASKET_SL"); return;
         }
      }

      // ── Chandelier exit check ─────────────────────────────────────
      if(UseChandelierTrail && g_pyr.chandelier_stop > 0) {
         bool chan_hit = (g_pyr.direction==1) ?
                        (bid < g_pyr.chandelier_stop) :
                        (ask > g_pyr.chandelier_stop);
         if(chan_hit) {
            Print("[TICK-CHAN] Chandelier stop hit: price=",
                  ((g_pyr.direction==1)?bid:ask)," stop=",g_pyr.chandelier_stop);
            CloseBasket("CHANDELIER_EXIT"); return;
         }
      }

      // ── Donchian-10 H1 exit check ────────────────────────────────
      if(UseDonchianExit && g_pyr.don10_stop > 0) {
         // Fire only on bar close (checked per-bar below), not intrabar
         // (don't close on intrabar spike through Donchian — use bar close)
      }

      // ── Partial close trigger ────────────────────────────────────
      if(PartialCloseMode != PC_NONE && !g_pyr.partial_done && g_pyr.initial_risk_r > 0) {
         double r_trigger = (PartialCloseMode == PC_AT_2R) ? 2.0 : 1.5;
         if(GetBasketRMultiple() >= r_trigger) {
            Print("[TICK-PARTIAL] R=", DoubleToString(GetBasketRMultiple(),2),
                  " >= ",r_trigger," → partial close ",DoubleToString(PartialClosePct*100,0),"%");
            PartialCloseBasket(PartialClosePct);
         }
      }
   }

   // ── NEW BAR GATE ──────────────────────────────────────────────────
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastBarTime) return;
   lastBarTime = curBar;

   // ── v1.2: Renko bricks + signal (first thing on new bar) ─────────
   RenkoUpdateOnNewBar();
   RenkoComputeSignal();

   // ── Diagnostics: count this bar, reset counters daily, heartbeat ──
   DiagResetIfNewDay();
   g_diag_ticks_total++;

   UpdateDailyStats();
   DrawLeftLegend();
   DrawRightLegend();
   DrawBasketLines();

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   // ── G4: GLOBAL EQUITY CIRCUIT-BREAKER ───────────────────────────
   double totalFloat = GetTotalFloatingPnL();
   if(equity > 0 && (totalFloat/equity*100 <= -GlobalEquityStopPct)) {
      Print("[CIRCUIT-BREAKER] Global float=",
            NormalizeDouble(totalFloat/equity*100,2),"% <= -",GlobalEquityStopPct,"%");
      if(g_pyr.active_levels > 0) CloseBasket("GLOBAL_EQUITY_STOP");
      return;
   }

   // ── G9: DAILY EQUITY STOP (portfolio-wide, BUG F) ────────────────
   // Two checks: (a) the FTMO absolute daily loss (shared), and
   // (b) the per-chart soft % stop as an early warning.
   bool portfolio_daily_hit = IsDailyLossLimitReached();  // sets shared flag if breached
   if(portfolio_daily_hit) {
      if(!g_daily_stop_hit) {
         g_daily_stop_hit = true;
         Print("[G9] PORTFOLIO DAILY STOP — flattening this chart's basket");
      }
      if(g_pyr.active_levels > 0) { CloseBasket("DAILY_EQUITY_STOP"); return; }
      return;  // no new entries while daily stop active
   }
   // Per-chart soft % stop (uses shared day-start balance as anchor)
   double day_start_bal = GlobalVariableCheck("B4_DAY_BALANCE") ?
                          GlobalVariableGet("B4_DAY_BALANCE") :
                          dailyStartEquity;
   if(DailyEquityStopPct > 0 && day_start_bal > 0) {
      double drop = (day_start_bal - equity) / day_start_bal * 100.0;
      if(drop >= DailyEquityStopPct && !g_daily_stop_hit) {
         g_daily_stop_hit = true;
         Print("[G9] DAILY EQUITY STOP (soft %): drop=",NormalizeDouble(drop,2),
               "% >= ",DailyEquityStopPct,"%");
         if(g_pyr.active_levels > 0) CloseBasket("DAILY_EQUITY_STOP");
         return;
      }
      if(g_daily_stop_hit) {
         if(g_pyr.active_levels > 0) ManageActiveBasket();
         return;
      }
   }

   // ── G7: FRIDAY FORCE-CLOSE ───────────────────────────────────────
   if(IsFridayClose()) {
      if(g_pyr.active_levels > 0) { CloseBasket("FRIDAY_CLOSE"); }
      return;
   }

   // ── MANAGE EXISTING PYRAMID ──────────────────────────────────────
   if(g_pyr.active_levels > 0) {
      g_pyr.bars_open++;   // increment once per bar at the bar-gate (safe location)
      ManageActiveBasket();

      // Per-bar exit checks that shouldn't be on every tick:
      // Donchian-10 H1 exit (bar close)
      if(UseDonchianExit && g_pyr.don10_stop > 0) {
         double h1_close = iClose(_Symbol, PERIOD_H1, 1); // confirmed H1 bar
         bool don_exit = (g_pyr.direction==1) ? (h1_close < g_pyr.don10_stop) :
                                                (h1_close > g_pyr.don10_stop);
         if(don_exit) {
            Print("[BAR-DON10] Donchian-10 H1 exit: h1_close=",h1_close," stop=",g_pyr.don10_stop);
            CloseBasket("DONCHIAN10_EXIT"); return;
         }
      }

      // Groq continue check
      if(g_pyr.active_levels >= 2) {
         if(CheckGroqContinueResponse(g_pyr.active_levels)) return;
      }

      return; // do NOT open new pyramid while one active
   }

   // ── SIGNAL DETECTION (no active pyramid) ─────────────────────────
   // Heartbeat fires here (after gates that always run, before signal gates)
   DiagHeartbeat();

   if(!IsTradingTimeAllowed()) {
      g_diag_time_block++;
      return;
   }
   if(IsNewsBlocked()) {
      g_diag_news_block++;
      if(DiagnosticMode) Print("[DIAG] ", _Symbol, " no-trade: news filter active");
      return;
   }

   RiskContext rc = GetRiskContext();

   // Daily / Overall loss guards
   if(rc.max_daily_loss_reached) {
      Print("[FTMO] Daily loss limit reached — no new entries");
      return;
   }
   if(IsOverallLossLimitReached()) {
      Print("[FTMO] Overall loss limit reached — EA halted");
      return;
   }

   // ── G5: MAX CONCURRENT PYRAMIDS (total) ─────────────────────────
   // BUG C FIX: count distinct baskets, not units. MaxOpenPyramids=3 means
   // at most 3 symbols can have an open basket simultaneously.
   if(GetTotalOpenPyramids() >= MaxOpenPyramids) {
      g_diag_cap_block++;
      if(DiagnosticMode) Print("[DIAG] ", _Symbol, " no-trade: max concurrent pyramids (",
            GetTotalOpenPyramids(), "/", MaxOpenPyramids, ")");
      return; // global cap on concurrent baskets
   }

   // ── G10 (Fix #2): MAX SAME-DIRECTION PYRAMIDS — correlated risk cap ──
   // Prevents 3× BUY (EURUSD+GBPUSD+AUDUSD) being wiped by a single USD event.
   // Checked here (before signal evaluation) for efficiency — direction is
   // determined later, but we check lazily: if BOTH directions are capped, block.
   // The direction-specific check is done again just before OpenPyramidLevel.

   // ── Spread gate (G3) ─────────────────────────────────────────────
   double spreadPips = (SymbolInfoDouble(_Symbol,SYMBOL_ASK) - SymbolInfoDouble(_Symbol,SYMBOL_BID)) / PipSize();
   double atrPipsM15 = GetATRPips_M15();
   // FIX: PipSize()'s digit-count heuristic is forex-only. For indices and
   // metals it produces nonsensical "pip" magnitudes (e.g. US100 ~18000p,
   // XAGUSD ~6000p brick sizes seen in reports) which silently corrupts every
   // absolute-pip threshold below for those classes. The ratio gate just
   // above (MaxSpreadATR) is scale-invariant — PipSize() cancels out of the
   // numerator/denominator — so it stays valid for all classes and is left
   // as the only spread gate for non-FX symbols.
   string symClassForGate = GetSymbolClass();
   bool isFxClassForGate = (symClassForGate == "MAJOR_FX" || symClassForGate == "MAJOR_JPY" || symClassForGate == "CROSS_JPY");
   if(MaxSpreadATR>0 && atrPipsM15>0 && spreadPips/atrPipsM15 > MaxSpreadATR) {
      g_diag_spread_block++;
      if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: spread %.1fp / ATR %.1fp = %.2f > %.2f",
            _Symbol, spreadPips, atrPipsM15, spreadPips/atrPipsM15, MaxSpreadATR));
      return;
   }
   if(isFxClassForGate && MaxSpreadAbsolutePips>0 && spreadPips > MaxSpreadAbsolutePips) {
      g_diag_spread_block++;
      if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: spread %.1fp > max %.1fp",
            _Symbol, spreadPips, MaxSpreadAbsolutePips));
      return;
   }

   // ── ATR range gate ───────────────────────────────────────────────
   if(isFxClassForGate && (atrPipsM15 < MinATRPips || atrPipsM15 > MaxATRPips)) {
      g_diag_atr_block++;
      if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: ATR %.1fp outside [%.1f, %.1f]",
            _Symbol, atrPipsM15, MinATRPips, MaxATRPips));
      return;
   }

   // ── TREND STATE ──────────────────────────────────────────────────
   TrendState ts = GetTrendState();
   int direction  = ScanForSignal(ts);
   DrawRenkoBricks();
   DrawEntryCriteriaLevels(ts);

   // ── DIAGNOSTIC: Renko warmup / signal state (most common no-trade cause) ──
   int min_bricks = MathMax(RenkoDonPeriod, RenkoEMASlowPeriod) + 5;
   if(g_renko_count < min_bricks) {
      g_diag_renko_warmup++;
      if(DiagnosticMode && (g_diag_renko_warmup % 8 == 1))  // throttle: every 8th
         Print(StringFormat("[DIAG] %s no-trade: Renko WARMUP %d/%d bricks "
               "(need more M15 history — this is EXPECTED early)",
               _Symbol, g_renko_count, min_bricks));
   } else if(g_renko_signal == 0) {
      g_diag_renko_no_signal++;
      // Throttled: Renko ready but no signal is the NORMAL state most bars
      if(DiagnosticMode && (g_diag_renko_no_signal % 16 == 1)) {
         RenkoBrick lb; bool ok = RenkoGetBrick(0, lb);
         Print(StringFormat("[DIAG] %s no-signal: Renko ready (%d bricks) but no setup. "
               "last_brick=%s close=%.5f don_u=%.5f don_l=%.5f ema20%sema50",
               _Symbol, g_renko_count,
               ok ? ((lb.direction==1)?"UP":"DN") : "?",
               ok ? lb.close : 0,
               g_renko_don_upper, g_renko_don_lower,
               (g_renko_ema_fast > g_renko_ema_slow) ? ">" : "<"));
      }
   }

   if(direction == 0) {
      // Distinguish: no D1 bias at all vs WEAK bias
      if(ts.overall_bias == 0) g_diag_no_trend++;
      else                     g_diag_weak_bias++;
      if(ShowSignalVisuals) {
         PullbackState ps_empty; ZeroMemory(ps_empty);
         DrawDiagnosticPanel(ts, ps_empty, 0,
            (ts.overall_bias==0) ? "no_d1_trend" : "weak_bias_" + ts.bias_strength);
      }
      return; // no trend bias → no trade
   }

   // ── G1: D1 BIAS REQUIRED ─────────────────────────────────────────
   if(direction == 0) {
      // Log WEAK rejection for data gathering (helps tune D1TrendValidBars / midline thresholds)
      if(ts.overall_bias != 0 && ts.bias_strength == "WEAK" && LogRejected) {
         PullbackState ps_weak; ZeroMemory(ps_weak);
         ps_weak.session = GetCurrentSession(); ps_weak.day_of_week = GetDayOfWeek();
         ps_weak.hour_utc = GetHourUTC(); ps_weak.atr_m15 = GetATRValue_M15();
         ps_weak.atr_h4 = GetATRValue_H4(); ps_weak.vol_ratio = GetVolatilityRatio();
         ps_weak.candle_pattern = GetCandlePattern(ts.overall_bias);
         WriteRejectionLog(ts.overall_bias, 0, "d1_weak_midline_breach", ts, ps_weak);
      }
      return;
   }
   if(!UseD1Bias && ts.d1_bias == 0) return;

   // ── ADX gate (G2) ────────────────────────────────────────────────
   double adxVal = GetADXValue();
   if(UseADXGate && (adxVal < ADXMinEntry || adxVal > ADXMaxEntry)) {
      g_diag_adx_block++;
      if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: ADX %.1f outside [%.0f, %.0f]",
            _Symbol, adxVal, ADXMinEntry, ADXMaxEntry));
      // Still log for data-gather if score passes shadow threshold
      PullbackState ps_adx; ZeroMemory(ps_adx);
      ps_adx.session = GetCurrentSession(); ps_adx.day_of_week = GetDayOfWeek(); ps_adx.hour_utc = GetHourUTC();
      ps_adx.atr_m15 = GetATRValue_M15(); ps_adx.atr_h4 = GetATRValue_H4();
      ps_adx.vol_ratio = GetVolatilityRatio();
      ps_adx.candle_pattern = GetCandlePattern(direction);
      WriteRejectionLog(direction, 0, StringFormat("adx_gate_%.1f", adxVal), ts, ps_adx);
      return;
   }

   // ── PULLBACK DETECTION ────────────────────────────────────────────
   PullbackState ps = GetPullbackState(direction);

   // ── SCORE ─────────────────────────────────────────────────────────
   int score = CalculateSignalScore(direction, ts, ps);

   Print(StringFormat("[SIGNAL] %s %s score=%d bias=%s h4=%s signal=%s breakout=%s adr=%.1f pips",
         _Symbol,
         (direction==1)?"BUY":"SELL",
         score,
         ts.bias_strength,
         (ts.h4_confirm==direction)?"OK":"WEAK",
         ps.valid?"valid":"invalid",
         ps.in_golden_zone?"fresh":"chased",
         atrPipsM15));

   // Below shadow threshold — fully ignore (no log)
   if(score < ShadowScoreThreshold) {
      g_diag_below_shadow++;
      if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: score %d < ShadowThreshold %d",
            _Symbol, score, ShadowScoreThreshold));
      return;
   }

   // FIX (2026-07-20, signal frequency) + FIX (2026-07-20 follow-up):
   // originally this threw away the WHOLE candidate (including the CSV log)
   // when throttled — which meant shadow data collection stopped getting
   // suppressed too, exactly when you want it flowing (e.g. during a
   // post-SL cooldown window). Corrected: throttle now only affects whether
   // this candidate proceeds to a LIVE attempt. It is ALWAYS logged to CSV
   // for shadow analysis, using its own tracking variable so the general
   // bars_since_last_signal CSV column (used for autocorrelation analysis,
   // updated on every logged row) is untouched by this decision.
   bool throttled_from_live = false;
   int bars_since_same_dir = (int)((TimeCurrent() - g_last_live_candidate_time) / 900);
   if(MinM15BarsBetweenSameDirSignal > 0 &&
      direction == g_last_live_candidate_direction &&
      bars_since_same_dir < MinM15BarsBetweenSameDirSignal) {
      throttled_from_live = true;
      if(DiagnosticMode) Print(StringFormat(
            "[DIAG] %s live-throttled (still logged to shadow) — same direction %s "
            "last considered %d bars ago (min=%d)",
            _Symbol, (direction==1)?"BUY":"SELL", bars_since_same_dir, MinM15BarsBetweenSameDirSignal));
   }
   g_last_live_candidate_time      = TimeCurrent();
   g_last_live_candidate_direction = direction;
   g_diag_shadow_logged++;

   bool is_shadow = (score >= ShadowScoreThreshold && score < LiveScoreThreshold);
   bool is_live   = (!ShadowModeOnly && score >= LiveScoreThreshold && !throttled_from_live);

   // ── LIVE-QUALITY GATES (2026-06-05, data-driven) ──────────────────
   // Applied to LIVE entries only. Shadow logging below is untouched, so
   // these filtered signals are still recorded for ongoing validation.
   //   Gate 1: STRONG bias only — MODERATE bias had 0% WR (0/28).
   //   Gate 2: breakout extension <= LiveMaxExtension — deep extension
   //           (>0.618 = chasing) had 4.5% WR (1/22).
   string live_block = "";
   if(throttled_from_live)
      live_block = StringFormat("live_throttled_%dbars", bars_since_same_dir);
   else if(is_live && LiveRequireStrongBias && ts.bias_strength != "STRONG")
      live_block = StringFormat("live_blocked_bias_%s", ts.bias_strength);
   else if(is_live && ps.pullback_depth > LiveMaxExtension)
      live_block = StringFormat("live_blocked_extension_%.3f", ps.pullback_depth);
   else if(is_live && LiveRequireFreshBreakout && g_renko_signal != direction)
      live_block = "live_blocked_not_fresh_breakout";

   if(live_block != "") {
      is_live   = false;          // demote to shadow — do NOT open a real order
      is_shadow = (score >= ShadowScoreThreshold);
      if(DiagnosticMode)
         Print(StringFormat("[DIAG] %s live demoted to shadow: %s (score=%d)",
               _Symbol, live_block, score));
   }

   // FIX: always-on disposition line (not gated by DiagnosticMode) for any
   // signal that scored above LiveScoreThreshold — this is exactly the
   // "why isn't it trading live" question that couldn't be answered from
   // the Groq daemon log alone (Groq isn't the blocker; GroqShadowModeOnly
   // keeps it out of the live-blocking path entirely). One line per
   // qualifying candidate, low volume, always visible in the terminal log.
   if(score >= LiveScoreThreshold) {
      Print(StringFormat("[LIVE_DISPOSITION] %s %s score=%d ShadowModeOnly=%s live_block=%s -> %s",
            _Symbol, (direction==1)?"BUY":"SELL", score,
            ShadowModeOnly?"true":"false",
            (live_block!="")?live_block:"none",
            is_live ? "PROCEEDING_TO_LIVE_GATES" :
            (ShadowModeOnly ? "BLOCKED_BY_SHADOW_MODE_ONLY" : "BLOCKED_BY_LIVE_QUALITY_GATE")));
   }

   // Log candidate (all shadow + live above ShadowScoreThreshold)
   string reject_reason = "";
   if(live_block != "") reject_reason = live_block;
   else if(score < LiveScoreThreshold) reject_reason = StringFormat("score_%d_below_live_gate_%d", score, LiveScoreThreshold);
   else if(ShadowModeOnly) reject_reason = "shadow_mode_only";
   else if(!ps.valid) reject_reason = "pullback_invalid";
   else if(!ps.in_golden_zone) reject_reason = "outside_fib_zone";

   WriteCandidateLog(direction, score, is_shadow, is_live, ts, ps, reject_reason);
   DrawSignalMarker(direction, score, is_live, is_shadow, reject_reason);
   DrawDiagnosticPanel(ts, ps, score, reject_reason);

   // ── G10: CORRELATION GROUP CAP ────────────────────────────────────
   // BUG C follow-up: GetTotalOpenPyramids now counts distinct baskets.
   // The hard cap is already enforced by G5 (>= MaxOpenPyramids). This is a
   // belt-and-suspenders check at the same threshold for the rejection log.
   if(GetTotalOpenPyramids() >= MaxOpenPyramids) {
      WriteRejectionLog(direction, score, "max_concurrent_reached", ts, ps);
      return;
   }

   // ── POST-SL COOLDOWN ──────────────────────────────────────────────
   if(g_cooldown_sl_time > 0) {
      int barsSinceSL = (int)((TimeCurrent()-g_cooldown_sl_time)/PeriodSeconds(_Period));
      if(barsSinceSL < CooldownBarsSL) {
         g_diag_cooldown_block++;
         if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: post-SL cooldown %d/%d bars",
               _Symbol, barsSinceSL, CooldownBarsSL));
         WriteRejectionLog(direction, score, StringFormat("sl_cooldown_%d_bars", barsSinceSL), ts, ps);
         return;
      }
   }
   if(g_cooldown_tp_time > 0) {
      int barsSinceTP = (int)((TimeCurrent()-g_cooldown_tp_time)/PeriodSeconds(_Period));
      if(barsSinceTP < CooldownBarsTP) {
         g_diag_cooldown_block++;
         if(DiagnosticMode) Print(StringFormat("[DIAG] %s no-trade: post-TP cooldown %d/%d bars",
               _Symbol, barsSinceTP, CooldownBarsTP));
         WriteRejectionLog(direction, score, "tp_cooldown", ts, ps);
         return;
      }
   }

   // ── GROQ SHADOW LOG (always write request for all scored signals) ─
   // Even in shadow mode, write Groq request for later analysis
   // (Python server can process these to generate CONTINUE decisions)
   if(UseGroqFilter && score >= ShadowScoreThreshold) {
      WriteGroqOpenRequest(direction, score, ts, ps, rc);
   }

   // ── SHADOW-ONLY MODE: log and stop ───────────────────────────────
   if(ShadowModeOnly) return;

   // ── Below live score threshold: log and stop ─────────────────────
   if(score < LiveScoreThreshold) return;

   // ── Pullback must be valid for live entry ─────────────────────────
   if(!ps.valid || !ps.in_golden_zone) {
      WriteRejectionLog(direction, score, "pullback_not_in_zone", ts, ps);
      return;
   }

   // ── LIVE-QUALITY GATES (hard stop before order) ───────────────────
   // Mirrors the demotion above; ensures no real order opens on MODERATE
   // bias or an over-extended (chased) breakout.
   if(LiveRequireStrongBias && ts.bias_strength != "STRONG") {
      WriteRejectionLog(direction, score,
         StringFormat("live_blocked_bias_%s", ts.bias_strength), ts, ps);
      return;
   }
   if(ps.pullback_depth > LiveMaxExtension) {
      WriteRejectionLog(direction, score,
         StringFormat("live_blocked_extension_%.3f", ps.pullback_depth), ts, ps);
      return;
   }
   if(LiveRequireFreshBreakout && g_renko_signal != direction) {
      WriteRejectionLog(direction, score, "live_blocked_not_fresh_breakout", ts, ps);
      return;
   }

   // ── GROQ FILTER (live mode only — blocks entry based on Groq response) ──
   bool groq_block = false;
   if(UseGroqFilter && !GroqShadowModeOnly) {
      // Groq request already written above (shadow section) — just read response
      GroqResponse gr = ReadGroqOpenResponse();
      if(gr.valid && gr.trade_action == "SKIP" && gr.confidence >= GroqMinConfidence) {
         groq_block = true;
         WriteRejectionLog(direction, score,
            StringFormat("groq_skip_conf%.2f_%s", gr.confidence, gr.reason), ts, ps);
      }
   }
   if(groq_block) return;

   // ── OPEN L1 ──────────────────────────────────────────────────────
   g_diag_live_attempts++;
   if(DiagnosticMode) Print(StringFormat("[DIAG] %s LIVE ENTRY ATTEMPT: %s score=%d "
         "— all gates passed, opening L1", _Symbol, (direction==1)?"BUY":"SELL", score));
   double open_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime mdt; TimeToStruct(TimeCurrent(), mdt);
   string basket_id = StringFormat("B4_%04d%02d%02d_%02d%02d_%s",
                                    mdt.year,mdt.mon,mdt.day,
                                    mdt.hour,mdt.min,_Symbol);

   ZeroMemory(g_pyr);
   g_pyr.basket_id          = basket_id;
   g_pyr.direction          = direction;
   g_pyr.basket_open_equity = open_equity;
   g_pyr.open_time          = TimeCurrent();
   g_pyr.bars_open          = 0;
   g_pyr.mech_score         = score;
   g_pyr.d1_bias_str        = (ts.d1_bias==1)?"BULL":"BEAR";
   g_pyr.h4_confirm_str     = (ts.h4_confirm==direction)?"CONFIRMED":"WEAK";
   g_pyr.candle_pattern_str = ps.candle_pattern;
   g_pyr.atr_at_open        = ps.atr_m15;
   g_pyr.atr_h4_at_open     = ps.atr_h4;
   g_pyr.session_str        = ps.session;
   g_pyr.day_of_week_str    = ps.day_of_week;
   g_pyr.hour_utc           = ps.hour_utc;
   g_pyr.correlation_group  = CorrelationGroup;

   // ── G10 (Fix #2): direction-specific correlated cap ─────────────
   if(MaxSameDirectionPyramids > 0) {
      int same_dir = GetSameDirectionPyramidCount(direction);
      if(same_dir >= MaxSameDirectionPyramids) {
         WriteRejectionLog(direction, score,
            StringFormat("g10_corr_dir_cap_%d_of_%d", same_dir, MaxSameDirectionPyramids),
            ts, ps);
         Print(StringFormat("[G10] Correlated direction cap: %d active %s pyramids >= limit %d",
               same_dir, (direction==1)?"BUY":"SELL", MaxSameDirectionPyramids));
         ZeroMemory(g_pyr);
         return;
      }
   }

   // FIX (2026-08 dead-parameter audit): MaxPyramidsPerGroup now actually
   // enforced — see GetGroupPyramidCountForGroup() for the mechanism and
   // its known limitation.
   if(MaxPyramidsPerGroup > 0) {
      int same_group = GetGroupPyramidCountForGroup(CorrelationGroup);
      if(same_group >= MaxPyramidsPerGroup) {
         WriteRejectionLog(direction, score,
            StringFormat("g10_corr_group_cap_%d_of_%d_%s", same_group, MaxPyramidsPerGroup, CorrelationGroup),
            ts, ps);
         Print(StringFormat("[G10] Correlation group cap: %d active pyramids in group %s >= limit %d",
               same_group, CorrelationGroup, MaxPyramidsPerGroup));
         ZeroMemory(g_pyr);
         return;
      }
   }

   // FIX (v1.49, regime-suite branch): self-calibrating min-SL-distance
   // sanity check, right before the real order is sent. Uses the SAME
   // candidate SL distance CalculateInitialSL()/OpenPyramidLevel() will use
   // (BasketSLATRMult * current ATR) so the rejected/accepted decision
   // matches exactly what would have been sent — computed here rather than
   // inside OpenPyramidLevel() so a rejection can be written to the
   // rejection log with full ts/ps context, same as every other gate above.
   if(UseMinSLDistanceFilter && g_sl_dist_history_count >= SLDistanceMinSamples) {
      double candidate_price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double candidate_sl    = CalculateInitialSL(direction, candidate_price);
      double candidate_dist  = MathAbs(candidate_price - candidate_sl);
      if(IsSLDistanceOutlier(candidate_dist)) {
         WriteRejectionLog(direction, score,
            StringFormat("sl_dist_outlier_%.5f_vs_hist", candidate_dist), ts, ps);
         Print(StringFormat("[MIN-SL-FILTER] Rejected: candidate SL dist=%.5f is an outlier "
               "vs recent %d-trade history (fraction=%.2f)",
               candidate_dist, ArraySize(g_sl_dist_history), MinSLDistanceFraction));
         ZeroMemory(g_pyr);
         return;
      }
   }

   // 2026-10-05: 1-per-bar PF-priority diversification gate (additive, fail-open).
   // Only gates fresh basket opens (level 0), never pyramid adds to an existing basket.
   if(UseGuardBarGate && !GGate_ShouldOpen(MagicNumber)) {
      Print("[GATE] MN:", MagicNumber, " new basket skipped -- Guard picked a different magic for this bar");
      ZeroMemory(g_pyr);
      return;
   }

   // 2026-10-13: fleet-wide min re-entry distance gate (additive, fail-open). OFF by default on
   // the Guard (UsePriceDistanceGate=false) -- GGate_PriceDistanceOk() returns true until enabled.
   if(!GGate_PriceDistanceOk()) {
      Print("[GATE] MN:", MagicNumber, " new basket skipped -- within min re-entry distance of last fleet entry");
      ZeroMemory(g_pyr);
      return;
   }

   // 2026-10-13: per-direction loss-cooldown enforcement gate (additive, fail-open). OFF by
   // default on the Guard (UseLossCooldownGate=false) -- GGate_LossCooldownOk() returns true
   // until enabled.
   {
      ENUM_POSITION_TYPE signalDir = (direction == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      if(!GGate_LossCooldownOk(signalDir)) {
         Print("[GATE] MN:", MagicNumber, " new basket skipped -- direction in loss-cooldown after a recent stop-out");
         ZeroMemory(g_pyr);
         return;
      }
   }

   // 2026-10-14: fleet-wide same-instant pile-on gate (additive, fail-open). OFF by default
   // on the Guard (UseFleetOpenCooldownGate=false) -- GGate_FleetOpenCooldownOk() returns true
   // until enabled. Catches the race the price-distance gate above can't (multiple EAs
   // reading its once-per-tick snapshot before anyone's open registers).
   if(!GGate_FleetOpenCooldownOk()) {
      Print("[GATE] MN:", MagicNumber, " new basket skipped -- within fleet-wide same-instant open cooldown");
      ZeroMemory(g_pyr);
      return;
   }

   if(!OpenPyramidLevel(0, direction, basket_id)) {
      ZeroMemory(g_pyr);
      return;
   }

   g_pyr.active_levels = 1;
   IncrementGroupPyramidCount(CorrelationGroup);

   // Set initial SL and 1R risk
   double entry_price      = g_pyr.level[0].entry_price;
   g_pyr.initial_sl_price  = CalculateInitialSL(direction, entry_price);
   // FIX (v1.49, regime-suite branch): record this real open's SL distance
   // into the rolling window for future opens' outlier checks.
   RecordSLDistanceSample(MathAbs(entry_price - g_pyr.initial_sl_price));
   g_pyr.basket_sl_price   = g_pyr.initial_sl_price;
   double sl_dist          = MathAbs(entry_price - g_pyr.initial_sl_price);
   double vpip             = ValuePerPoint();
   // FIX (2026-07-21): ValuePerPoint() reads live broker symbol info
   // (SYMBOL_TRADE_TICK_VALUE/SIZE) — right after a restart this can
   // transiently return 0 before the connection fully syncs. If it does,
   // initial_risk_r silently computes to 0, and GetBasketRMultiple()'s own
   // safety fallback (initial_risk_r<=0 -> return 0) then reports R=0.00 at
   // close regardless of the real P&L — confirmed in a live trade
   // (2026-07-20 21:02, closed 2026-07-21 03:29 at pnl=0.00/R=0.00 despite
   // hitting the SL, same pattern as a real -1R loss). A basket with unknown
   // risk basis shouldn't be trading at all; closing the position we just
   // opened is safer than running it with broken R-tracking.
   if(vpip <= 0 || sl_dist <= 0) {
      Print(StringFormat("[OPEN_L1] ABORT-AFTER-FILL: invalid risk basis (vpip=%.6f sl_dist=%.5f) "
            "— closing ticket=%d immediately, will not track a basket with unknown risk",
            vpip, sl_dist, g_pyr.level[0].ticket));
      GGate_CloseTagged(trade, g_pyr.level[0].ticket, GGATE_REASON_MAN, "RiskAbort");
      ZeroMemory(g_pyr);
      g_pyr.active_levels = 0;
      return;
   }
   g_pyr.initial_risk_r    = sl_dist / _Point * vpip * g_pyr.level[0].lot_size;

   // Fix #1: Sync broker-side SL immediately after basket_sl_price is computed.
   // L1 was opened with CalculateInitialSL() — same value, so this is a no-op
   // in normal conditions, but ensures consistency if SL was adjusted for min_dist.
   UpdateAllBrokerSLs();

   // Initialize trail stops
   g_pyr.chandelier_stop = CalculateChandelierStop(direction);
   g_pyr.don10_stop      = CalculateDonchian10Exit(direction);

   // Groq open request was already written above (before shadow/live gate)
   WritePyramidLog(1, "PYRAMID_L1_OPEN", entry_price);

   if(ShowSignalVisuals) {
      datetime bt0 = iTime(_Symbol, _Period, 0);
      string mname0 = StringFormat("B4_L1OPEN_%s_%d", _Symbol, (long)bt0);
      long oid0 = 0;
      if(ObjectFind(oid0, mname0) < 0)
         ObjectCreate(oid0, mname0, OBJ_ARROW, 0, bt0, entry_price);
      ObjectSetInteger(oid0, mname0, OBJPROP_ARROWCODE, 174); // large arrow
      ObjectSetInteger(oid0, mname0, OBJPROP_COLOR, (direction==1)?clrBlue:clrPurple);
      ObjectSetInteger(oid0, mname0, OBJPROP_WIDTH, 5);
      ObjectSetString(oid0, mname0, OBJPROP_TOOLTIP,
         StringFormat("REAL L1 OPEN | %s entry=%.5f sl=%.5f", (direction==1)?"BUY":"SELL", entry_price, g_pyr.initial_sl_price));
   }

   Print(StringFormat("[OPEN L1] %s %s score=%d sl=%.5f 1R=%s entry=%.5f",
         basket_id,
         (direction==1)?"BUY":"SELL",
         score,
         g_pyr.initial_sl_price,
         FmtAmt(g_pyr.initial_risk_r),
         entry_price));

   RegisterGroupVar();
}
//+------------------------------------------------------------------+
