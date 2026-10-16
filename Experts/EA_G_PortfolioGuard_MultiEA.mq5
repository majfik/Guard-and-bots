#property copyright "Gold Multi-EA"
#property version   "1.00"
#property strict
#property description "Portfolio FTMO risk guard for the bot1 fleet (5 magics)."
#property description "Phase 1: watches account equity + schedule/loss-cooldown rules, publishes"
#property description "state via GlobalVariables, and can flatten the fleet ONLY on a hard/daily"
#property description "DD-floor breach (both OFF by default -- enable after a watch-only dry run)."
#property description "Schedule/cooldown brakes (loss-cooldown, weekend-gap, Friday) NEVER flatten --"
#property description "they only publish a block-new-entries flag; consuming that flag on the EA side"
#property description "is Phase 2, not yet wired (see PORTFOLIO_GUARD_PLAN_v2_20260929.md)."
#property description "2026-10-02: fleet profit-target flatten (off) + MFE/MAE logging."
#property description "2026-10-05: 1-per-bar PF-priority entry gate via GlobalVariable."

#include <PortfolioGuard.mqh>   // PgCountPositions/PgCloseMagic/PgCancelPendings/PgIsTester -- PgCloseMagic
                                 // gained an additive optional reasonTag param 2026-10-06 (used here as
                                 // "GRD" below); every other caller (archived single-EA, EA_S_GoldSleeve)
                                 // omits it and is unaffected -- see PortfolioGuard.mqh's own comment.
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <BossafxGuardGate.mqh>  // 2026-10-05: 1-per-bar PF-priority entry gate + closure-reason tagging

CPositionInfo position;

//+------------------------------------------------------------------+
//| Local veto codes -- deliberately >=100 so they can never collide  |
//| with PortfolioGuard.mqh's PG_VETO_* constants (0-9) if this EA    |
//| and the original EA_G_PortfolioGuard (bot4/GoldSleeve) ever run   |
//| on the same terminal at once. This EA also uses its OWN           |
//| GlobalVariable namespace ("MEG_" not "PG_") for the same reason.  |
//+------------------------------------------------------------------+
#define MEG_VETO_OK             0
#define MEG_VETO_HARD_FLOOR   101
#define MEG_VETO_DAILY_FLOOR  102
#define MEG_VETO_LOSS_COOLDOWN 103
#define MEG_VETO_GAP_BLOCK     104
#define MEG_VETO_FRIDAY        105
#define MEG_VETO_PROFIT_TARGET 106

input group "=== Protected magics (bot1_regime2.0/2.1 fleet -- KEEP/WATCH configs only) ==="
input int    MagicSwingM5     = 54321;  // SWING_M5_v2       -- KEEP
input int    MagicSwingM15    = 54322;  // SWING_M15 (bot1_regime2.0)  -- added to gate-priority pool 2026-10-05
input int    MagicScalp1x1    = 54323;  // SCALP_M15_1x1     -- WATCH
input int    MagicScalp3x1    = 54324;  // SCALP_M15_3x1     -- KEEP
input int    MagicR21A        = 54510;  // R21A_BEONLY       -- KEEP
input int    MagicR21B        = 54511;  // R21B_LIVEGATE_RR6.5 -- KEEP (declared magic; comment-truncation
                                         // bug that made this display as "5451" on-chart was fixed
                                         // 2026-09-29 in bot1_regime2.1.mq5 -- POSITION_MAGIC was always
                                         // correctly 54511/54510, only the human-readable comment truncated)
input int    MagicBot4_v49    = 40001;  // bot4_TREND_FX_v1_49 -- added to gate-priority pool 2026-10-05
input int    MagicBot4_v50    = 60001;  // bot4_TREND_FX_v1_50 -- added to gate-priority pool 2026-10-05
input int    MagicR22Pass6060 = 220001; // bot1_regime2.2 Move1-edgewiden Pass6060 -- DEMO deployment
                                         // 2026-10-09, NOT yet live-verified. Added to gate-priority +
                                         // protected pool from day one of deployment (see
                                         // VALIDATED_LIVE_CONFIGS/MANIFEST.txt entry #10 for full context).
input int    MagicGuard       = 61998;  // this EA's own magic -- distinct from EA_G_PortfolioGuard's 61999
                                         // so both could coexist on the same terminal without collision
input int    MagicWinrate1250 = 54325;  // bot1_regime2.0 WINRATE_1250_PF250_M5 -- NEW production 2026-10-11,
                                         // fixed lot 0.10. Declared magic range expanded 54320-54326 ->
                                         // 54320-54329 to fit this + 54326/54327 (user-approved).
input int    MagicWinrate667  = 54326;  // bot1_regime2.0 WINRATE_667_PF212_M5  -- NEW production 2026-10-11,
                                         // fixed lot 0.10. 91% win rate but win/loss size asymmetry flagged
                                         // ($31 avg win vs -$148 avg loss) -- WATCH, not KEEP, until live data.
input int    MagicWinrate3257 = 54327;  // bot1_regime2.0 WINRATE_3257_PF196_M15 -- NEW production 2026-10-11,
                                         // fixed lot 0.10.
input int    MagicR22CDHV7794 = 220201; // bot1_regime2.2 CDHV_D_7794_PF227 -- NEW production 2026-10-13,
                                         // fixed lot 0.10 (verified at risk-based ~0.0294 lot). D-family
                                         // (EntryPreset=4), RegimePreset=5. Best-D pick from the C/D
                                         // high-volume follow-up sweep (magic 220150), real single-run
                                         // verified (magic 220151): 345 positions, 88.7% win, PF 2.27,
                                         // DD 0.25%, net $2,433.
input int    MagicR22CDHV2098 = 220202; // bot1_regime2.2 CDHV_C_2098_PF247 -- NEW production 2026-10-13,
                                         // fixed lot 0.10 (verified at risk-based ~0.0352 lot). C-family
                                         // (EntryPreset=3), RegimePreset=0. Best-C pick from the same
                                         // sweep, real single-run verified (magic 220153): 370 positions,
                                         // 83.5% win, PF 2.47 (best PF of the batch), DD 0.25%, net $2,577
                                         // (best net of the batch).

input group "=== FTMO account facts (2-Step Challenge, confirmed STATIC 10% Max Loss) ==="
input double FtmoInitialBalance   = 10000.0;  // Initial Simulated Capital -- CHECK before reusing on a
                                               // different-sized FTMO account
input double FtmoMaxLossPct       = 10.0;     // static for 2-Step, never moves for the life of the phase
input double HardFloorBufferUsd   = 50.0;     // extra cushion above FTMO's real $9,000 breach line, so
                                               // slippage on the closing trade itself can't push through it

input group "=== Daily soft floor (tighter than FTMO's real 5% 2-Step daily limit, by design) ==="
input double DailySoftLossPct        = 3.5;
input int    ServerToCetOffsetHours  = 0;     // MT5 SERVER time minus CET/CEST, in hours. MUST be set
                                               // correctly per broker before the daily reset is trusted --
                                               // wrong by default (0), verify against your broker's stated
                                               // server-time offset before relying on this for anything.

input group "=== Loss cooldown (fleet-wide, published only -- see Phase-1/2 note above) ==="
input bool   UseLossCooldown      = true;
input int    LossCooldownMinutes  = 120;

input group "=== Weekend/gap blackout (published only) ==="
// Detected generically as "no ticks for N hours", not a hardcoded Sunday calendar time -- broker
// weekly-reopen instants vary by DST/session config, so a fixed clock time would be fragile. This
// also incidentally catches any other multi-hour feed outage, which is a reasonable bonus, not a bug.
input bool   UseGapBlock          = true;
input int    GapDetectHours       = 6;    // treat a tick gap of >= this many hours as a weekend/outage gap
input int    GapBlockHours        = 2;    // block new entries for this long after ticks resume

input group "=== Friday close backstop (published only -- redundant safety net) ==="
// bot1_regime2.1.mq5 already has its own AvoidFriday/FridayCloseHour (confirmed live, input default
// true/16). This is a portfolio-wide backstop in case any single EA's own flag were ever misconfigured.
input bool   UseFridayBackstop    = true;
input int    FridayBackstopHour   = 16;   // server time hour

input group "=== Flatten behavior -- DD floors ONLY. Schedule/cooldown brakes NEVER flatten. ==="
input bool   UseFlattenOnHardFloor  = false;  // OFF by default -- enable only after a watch-only dry run
input bool   UseFlattenOnDailyFloor = false;  // OFF by default -- enable only after a watch-only dry run

input group "=== Fleet-wide profit-target flatten (2026-10-02, OFF by default) ==="
// Sums floating P&L across ALL protected-magic positions each tick. If the total reaches
// ProfitTargetUsd, flattens the whole fleet (same PgCloseMagic/PgCancelPendings mechanism as the
// DD-floor flatten above). Fixed $1000 starting point per user's explicit decision (2026-10-02) --
// NOT swept/optimized. MFE/MAE episode logging below runs regardless of this flag so the right
// target can be found empirically (e.g. "positions closed too soon, bump to $1500") before ever
// turning this on live.
input bool   UseProfitTargetFlatten = false;    // OFF by default -- enable only after reviewing enough
                                                 // fleet_profit_log.csv episodes to trust ProfitTargetUsd
input double ProfitTargetUsd        = 1000.0;   // fixed USD target, fleet-wide floating P&L sum (not %)

input group "=== Fleet-wide same-direction basket SL (2026-10-09, logged-only by default) ==="
// Sums floating P&L separately for BUY-direction and SELL-direction positions across ALL
// g_gateMagics (fleet-wide, not just one EA -- per explicit user decision, since on BOSSAFX-Demo
// multiple EAs agreeing on direction is a real correlated-risk signal worth watching fleet-wide,
// not just within a single EA's own positions the way bot4's internal BasketSLATRMult works).
// Flat USD threshold (NOT ATR-scaled -- simpler, same style as ProfitTargetUsd above, per explicit
// user decision: "easier with fleet TP where we set 750... combined SL should be around 1k USD").
// LOGGED-ONLY first: UseBasketSLGuard starts false so nothing closes automatically; BasketSLMaxLossUsd
// is still checked and every crossing is Print()'d + written to the basket-SL CSV log every tick while
// a direction is over threshold, so real trigger frequency/severity can be reviewed before ever
// flipping UseBasketSLGuard on. One flag flip (no code change) switches it from watch to live.
input bool   UseBasketSLGuard       = false;    // OFF by default -- logged-only until reviewed
input bool   LogBasketSLGuard       = true;     // Print() + CSV row every tick a direction is over threshold
input double BasketSLMaxLossUsd     = 1000.0;   // fixed USD threshold, PER DIRECTION (BUY total and SELL
                                                 // total checked separately, not combined)

input group "=== Fleet MFE/MAE episode logging (2026-10-02, always on if LogFleetProfit=true) ==="
// An "episode" = the span from the first protected position opening (fleet floating P&L goes from
// 0 to nonzero) to the last one closing (back to 0). Logs the peak (fleet MFE) and trough (fleet MAE)
// floating P&L reached during that span, plus how/when it ended -- this is the evidence needed to
// pick ProfitTargetUsd empirically instead of guessing.
input bool   LogFleetProfit         = true;
input int    FleetSnapshotSeconds   = 60;   // also log a lightweight snapshot row at most this often
                                             // while an episode is active, to see the curve shape
                                             // (not just start/peak/end) -- 0 disables snapshot rows

input group "=== 1-per-bar PF-priority entry gate (2026-10-05) ==="
// Diversification feature: at most ONE protected magic is allowed to open a NEW position per bar
// (on this EA's own gate timeframe, not each EA's own chart timeframe -- simplest single clock).
// Guard ranks all protected magics by live Profit Factor (HistorySelect over GateLookbackDays) each
// new bar and publishes the single highest-PF magic (min GateMinTrades to be eligible, so a thin
// lucky streak can't dominate) via GlobalVariable. Each of the 5 EAs checks this via
// GGate_ShouldOpen() right before its own entry OrderSend -- fail-open (lets the EA open normally)
// if Guard isn't running, hasn't published yet, or the publish is stale. No cooldown: if Guard
// doesn't respond, EAs behave exactly as before this feature existed.
input bool   UseEntryBarGate        = true;   // user default ON per explicit instruction (2026-10-05)
input ENUM_TIMEFRAMES GateTimeframe = PERIOD_M5;
input int    GateMinTrades          = 10;     // magics with fewer closed trades than this are never
                                               // picked as the bar's winner (avoids a thin lucky streak
                                               // looking like the best performer)
input int    GateLookbackDays       = 30;     // live-PF ranking window

input group "=== Fleet-wide min re-entry distance gate (2026-10-13, additive) ==="
// Blocks a NEW entry by any protected magic when price is within MinReentryDistancePoints of the
// most recently opened fleet-wide position (any protected magic, either direction) -- prevents
// piling multiple positions at the same level. Published every tick via
// GGate_PublishDistanceState(); each protected EA reads it via GGate_PriceDistanceOk() right
// before its own OrderSend, same fail-open pattern as the bar-priority gate above. Ships OFF
// (watch the log for a while before flipping on), per explicit instruction (2026-10-13).
input bool   UsePriceDistanceGate      = false;
input int    MinReentryDistancePoints  = 150;
input bool   LogPriceDistanceGate      = true;  // Guard-side: logs its own publish (last fleet
                                                 // entry price/time); each bot's own block
                                                 // decision is logged via that bot's existing
                                                 // trade-log flag (e.g. LogBot1Trades), not here

input group "=== Per-direction loss-cooldown ENFORCEMENT gate (2026-10-13, additive) ==="
// LossCooldownMinutes above has been computed+published since 2026-09-29 but never actually
// consumed by any EA (confirmed: zero references in bot1_regime2.0/2.1 source -- Guard's own
// header docs this as "Phase 2, not yet wired"). This flag turns on real enforcement: blocks a
// NEW entry in the SAME direction as a magic that just closed a losing trade, for
// LossCooldownMinutes, fleet-wide across all protected magics (narrower than a blanket pause --
// the opposite direction is never blocked). Ships OFF (watch the log for a while before flipping
// on), same cautious pattern as the other two gates above.
input bool   UseLossCooldownGate       = false;

input group "=== Fleet-wide same-instant pile-on gate (2026-10-14, additive) ==="
// Blocks ANY protected magic from opening within FleetOpenCooldownSeconds of the last fleet-wide
// open (any magic, any direction) -- catches the same-instant race the distance gate above can't
// (multiple EAs reading its snapshot before Guard's next tick refreshes it). Confirmed live
// 2026-10-14: 16 clusters of 2-6 magics opening at the exact same minute+price despite the
// distance gate being on. Per explicit user decision: fleet-wide, 10 seconds. Ships OFF (watch
// the log for a while before flipping on), same cautious pattern as the other gates above.
input bool   UseFleetOpenCooldownGate  = false;
input int    FleetOpenCooldownSeconds  = 10;

input group "=== TP1/TP2 R-multiples per protected magic (chart legend only -- mirrors each ==="
input group "=== trading EA's own .set ExitRR_TP1R/TP2R/Close1Pct; NOT used in any brake logic) ==="
input double TP1R_SwingM5      = 0.45;  input double TP2R_SwingM5      = 1.6;  input double Close1Pct_SwingM5     = 0.90;
input double TP1R_Scalp1x1     = 0.4;   input double TP2R_Scalp1x1     = 0.8;  input double Close1Pct_Scalp1x1    = 0.97;
input double TP1R_Scalp3x1     = 0.4;   input double TP2R_Scalp3x1     = 0.8;  input double Close1Pct_Scalp3x1    = 0.97;
input double TP1R_R21A         = 1.0;   input double TP2R_R21A         = 4.0;  input double Close1Pct_R21A        = 0.20;
input double TP1R_R21B         = 0.6;   input double TP2R_R21B         = 4.0;  input double Close1Pct_R21B        = 0.20;

input group "=== On-chart legend ==="
input bool   ShowLegend            = true;
input int    LegendUpdateSeconds   = 5;   // redraw at most this often -- avoids flicker/cost on every tick

input group "=== Logs ==="
input bool   LogState              = true;
input bool   LogFlatten            = true;
input bool   LogSelfTest           = true;
input int    HeartbeatSeconds      = 300;

CTrade   g_trade;
bool     g_selftestOk       = false;
double   g_dayStartBalance  = 0.0;
datetime g_dayStamp         = 0;
datetime g_lastTickTime     = 0;
datetime g_lastHeart        = 0;
int      g_protectedMagics[11];
int      g_gateMagics[13];   // 2026-10-05: priority-gate pool -- separate from g_protectedMagics
                             // (flatten-close blast radius) on purpose; includes 54322 + bot4's
                             // two magics which are NOT flatten-protected. 2026-10-09: extended
                             // both arrays by 1 for MagicR22Pass6060 (bot1_regime2.2 demo deploy).
                             // 2026-10-11: extended both arrays by 3 more for the new WINRATE
                             // production magics 54325/54326/54327 (1250/667/3257).
                             // 2026-10-13: extended both arrays by 2 more for the new bot1_regime2.2
                             // production magics 220201/220202 (CDHV_D_7794/CDHV_C_2098).

//+------------------------------------------------------------------+
//| Fleet-wide floating-P&L episode tracking (2026-10-02)             |
//| An episode = span from first protected position open (fleet       |
//| floating P&L goes 0 -> nonzero) to last one closing (back to 0).  |
//+------------------------------------------------------------------+
bool     g_episodeActive     = false;
datetime g_episodeStart       = 0;
double   g_episodePeak        = 0.0;   // fleet MFE -- highest total floating P&L reached
datetime g_episodePeakTime    = 0;
double   g_episodeTrough      = 0.0;   // fleet MAE -- lowest (most negative) total floating P&L reached
datetime g_episodeTroughTime  = 0;
int      g_episodeMaxOpenPos  = 0;
int      g_fleetLogHandle     = INVALID_HANDLE;
datetime g_lastFleetSnapshot  = 0;
string   g_episodeEndReasonPending = "NATURAL";   // set just before a flatten call so the episode-end
                                                   // row that follows (same tick, open count drops to 0)
                                                   // records WHY it ended, not just that it did
datetime g_lastGateBarTime  = 0;   // 2026-10-05: last GateTimeframe bar we ranked+published for
datetime g_lastDistGateLoggedTime = 0;   // 2026-10-13: last fleet-entry time we logged (dedupe)

// 2026-10-13: profit-target-flatten cooldown exception. A fleet-wide profit-target flatten
// (MEG_VETO_PROFIT_TARGET) closes every protected position in one sweep; the AGGREGATE is
// profitable by definition (that's the trigger), but an individual leg can still realize a small
// loss. Per explicit user spec, that single losing leg should NOT start a loss-cooldown -- the
// basket as a whole took profit, this isn't a real stop-out. Set true for the single OnTick()
// call that performs this specific flatten, false otherwise; OnTradeTransaction() checks it
// before applying any cooldown. NOT used for basket-SL (that one is loss-side on purpose, must
// still cooldown) or broker-side SL hits (always cooldown, per user spec).
bool g_inProfitTargetFlatten = false;

//+------------------------------------------------------------------+
//| Fleet-wide same-direction basket SL tracking (2026-10-09).        |
//| Separate from the profit-target episode tracker above -- this is  |
//| loss-side, per-direction (BUY/SELL tracked independently), and    |
//| logged every tick while over threshold rather than once per       |
//| episode, since the point here is frequency/severity review, not   |
//| MFE/MAE curve shape.                                              |
//+------------------------------------------------------------------+
int      g_basketSLLogHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| GGuardCloseDirectionTagged: closes ALL g_gateMagics positions in  |
//| one direction (BUY or SELL), tagged "BSK" on the close comment    |
//| (same tagged-close pattern as PgCloseMagic's reasonTag path in    |
//| PortfolioGuard.mqh, reimplemented locally here rather than        |
//| extending that shared file -- PgCloseMagic closes by ONE magic    |
//| with no direction filter, which doesn't fit the basket-SL need,   |
//| and this feature is Guard-MultiEA-specific, not something the     |
//| other PgCloseMagic callers (EA_S_GoldSleeve, archived single-EA   |
//| Guard) need to share).                                            |
//+------------------------------------------------------------------+
int GGuardCloseDirectionTagged(const int &magics[], const ENUM_POSITION_TYPE dir, const string reasonTag)
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_TYPE) != dir) continue;
      int posMagic = (int)PositionGetInteger(POSITION_MAGIC);
      bool inPool = false;
      for(int m = 0; m < ArraySize(magics); m++)
         if(magics[m] == posMagic) { inPool = true; break; }
      if(!inPool) continue;

      string magicPart  = IntegerToString(posMagic);
      string tagComment = magicPart + "|" + reasonTag;
      if(StringLen(tagComment) > 31)
         tagComment = StringSubstr(tagComment, 0, 31);

      double volume  = PositionGetDouble(POSITION_VOLUME);
      string posSymbol = PositionGetString(POSITION_SYMBOL);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action       = TRADE_ACTION_DEAL;
      request.position     = ticket;
      request.symbol       = posSymbol;
      request.volume       = volume;
      request.magic        = posMagic;
      request.deviation    = 50;
      request.type_filling = ORDER_FILLING_IOC;
      request.comment      = tagComment;
      if(dir == POSITION_TYPE_BUY)
        {
         request.type  = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(posSymbol, SYMBOL_BID);
        }
      else
        {
         request.type  = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
        }

      if(OrderSend(request, result)
         && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED
             || result.retcode == TRADE_RETCODE_DONE_PARTIAL))
         closed++;
      // 2026-10-13 fix: the tagged OrderSend above hardcodes ORDER_FILLING_IOC, which this
      // broker/symbol rejects with "Unsupported filling mode" (confirmed live 2026-10-12/13:
      // 3700+ consecutive failures, zero real closes, across two separate basket-SL episodes --
      // see MQL5/Logs/2026101[23].log). PgCloseMagic in PortfolioGuard.mqh already has this exact
      // same IOC bug but survives it via an untagged CTrade::PositionClose() fallback -- this
      // function never had that fallback, which is why basket-SL never actually closed anything.
      // Apply the identical fallback: lose the "BSK" comment tag on this path, but actually close
      // the position, which is the entire point of a stop-loss guard.
      //
      // 2026-10-15 fix: g_trade.PositionClose() below uses g_trade's OWN ExpertMagicNumber
      // (MagicGuard=61998, set once in OnInit) for the resulting close deal -- NOT posMagic.
      // That meant every basket-SL close that hit this fallback path recorded DEAL_MAGIC=61998
      // in history, not the bot's real magic (e.g. 54323). OnTradeTransaction()'s
      // IsProtectedMagic(magic) check then silently failed (61998 is not a protected magic) and
      // the per-direction loss-cooldown was NEVER armed for any basket-SL-flattened position that
      // went through this fallback -- confirmed live 2026-10-15: two real basket-SL losses
      // (54323/54324 at 02:13, 54325 at 04:56) produced zero "[G-MULTI] Loss cooldown triggered"
      // log lines despite LossCooldownMinutes=120/UseLossCooldownGate=true being live. Fix:
      // temporarily point g_trade at posMagic for this one close, then restore MagicGuard
      // immediately after -- mirrors what the primary tagged OrderSend path above already does
      // correctly via request.magic.
      else
        {
         g_trade.SetExpertMagicNumber(posMagic);
         bool fallbackClosed = g_trade.PositionClose(ticket);
         g_trade.SetExpertMagicNumber(MagicGuard);
         if(fallbackClosed)
            closed++;
        }
     }
   return closed;
  }

//+------------------------------------------------------------------+
//| MEG_ GlobalVariable namespace helpers (own prefix, see header)    |
//+------------------------------------------------------------------+
string MegGvName(const string key) { return "MEG_" + _Symbol + "_" + key; }

void MegGvSet(const string key, const double value)
  {
   GlobalVariableSet(MegGvName(key), value);
  }

double MegGvGet(const string key, const double fallback = 0.0)
  {
   string name = MegGvName(key);
   if(!GlobalVariableCheck(name))
      return fallback;
   return GlobalVariableGet(name);
  }

//+------------------------------------------------------------------+
string VetoText(const int veto)
  {
   switch(veto)
     {
      case MEG_VETO_OK:             return "OK -- no brake active";
      case MEG_VETO_HARD_FLOOR:     return "HARD_FLOOR -- FTMO static max-loss floor breached";
      case MEG_VETO_DAILY_FLOOR:    return "DAILY_FLOOR -- 3.5% daily soft-loss floor breached";
      case MEG_VETO_LOSS_COOLDOWN:  return "LOSS_COOLDOWN -- a protected magic closed a losing trade recently";
      case MEG_VETO_GAP_BLOCK:      return "GAP_BLOCK -- weekend/outage tick gap, new entries paused";
      case MEG_VETO_FRIDAY:         return "FRIDAY -- Friday-close backstop window";
      case MEG_VETO_PROFIT_TARGET:  return "PROFIT_TARGET -- fleet floating P&L reached ProfitTargetUsd";
      default:                      return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| Floor math (see PORTFOLIO_GUARD_PLAN_v2_20260929.md section 2)    |
//+------------------------------------------------------------------+
double HardFloorLevel()
  {
   double maxLossAmt = FtmoInitialBalance * (FtmoMaxLossPct / 100.0);
   return (FtmoInitialBalance - maxLossAmt) + HardFloorBufferUsd;
  }

double DailySoftFloorLevel()
  {
   if(g_dayStartBalance <= 0)
      return 0.0;
   return g_dayStartBalance * (1.0 - DailySoftLossPct / 100.0);
  }

//+------------------------------------------------------------------+
//| Daily reset -- tracked in a CET-adjusted time domain so it lines  |
//| up with FTMO's real midnight CE(S)T reset, NOT raw server time.   |
//+------------------------------------------------------------------+
datetime CetAdjustedTime()
  {
   return TimeCurrent() - ServerToCetOffsetHours * 3600;
  }

datetime DayStartOf(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
  }

void MaybeResetDailyFloor()
  {
   datetime cet  = CetAdjustedTime();
   datetime day0 = DayStartOf(cet);
   if(day0 != g_dayStamp)
     {
      g_dayStamp        = day0;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(LogState)
         Print("[G-MULTI] New CET-adjusted day. day_start_balance=", DoubleToString(g_dayStartBalance, 2),
               " daily_floor=", DoubleToString(DailySoftFloorLevel(), 2));
     }
  }

//+------------------------------------------------------------------+
//| Weekend/gap detection -- generic "no ticks for N hours", not a    |
//| hardcoded Sunday calendar time. Persisted to a GlobalVariable so  |
//| it survives a chart/terminal restart mid-block-window.            |
//+------------------------------------------------------------------+
void DetectWeekendGap()
  {
   if(!UseGapBlock)
      return;
   datetime now = TimeCurrent();
   if(g_lastTickTime > 0)
     {
      long gapSec = (long)(now - g_lastTickTime);
      if(gapSec >= GapDetectHours * 3600)
        {
         datetime until = now + GapBlockHours * 3600;
         MegGvSet("GAP_BLOCK_UNTIL", (double)until);
         if(LogState)
            Print("[G-MULTI] Tick gap of ", gapSec / 3600, "h detected (>= ", GapDetectHours,
                  "h threshold) -- likely weekend reopen or feed outage. Blocking new entries until ",
                  TimeToString(until));
        }
     }
   g_lastTickTime = now;
  }

bool IsInGapBlock()
  {
   if(!UseGapBlock)
      return false;
   datetime until = (datetime)MegGvGet("GAP_BLOCK_UNTIL", 0);
   return TimeCurrent() < until;
  }

//+------------------------------------------------------------------+
//| Loss cooldown -- fleet-wide, triggered by ANY protected magic's   |
//| closing deal realizing profit<=0 (checked in OnTradeTransaction). |
//+------------------------------------------------------------------+
bool IsProtectedMagic(const int magic)
  {
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
      if(g_protectedMagics[i] == magic)
         return true;
   return false;
   // NOTE: if UseCounterTrendModule is ever enabled on any of these EAs, counter-trend positions
   // trade under MagicNumber+CounterTrendMagicOffset (offset=900 by default) and are NOT covered by
   // this check today. Confirmed OFF on all 5 protected configs as of 2026-09-29 -- revisit if that
   // changes.
  }

bool IsInLossCooldown()
  {
   if(!UseLossCooldown)
      return false;
   datetime until = (datetime)MegGvGet("LOSS_COOLDOWN_UNTIL", 0);
   return TimeCurrent() < until;
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   ulong deal_ticket = trans.deal;
   if(!HistoryDealSelect(deal_ticket))
      return;
   if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol)
      return;
   int magic = (int)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(!IsProtectedMagic(magic))
      return;
   long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;   // only closing deals (full close, partial close, or opposite-close) realize P&L

   double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                  + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                  + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

   if(profit <= 0)
     {
      // 2026-10-13: profit-target-flatten exception, per explicit user spec -- a losing LEG that
      // closes as part of a fleet-wide profit-target flatten (the aggregate IS profitable, that's
      // the trigger) does NOT start a loss-cooldown. Basket-SL flattens and ordinary broker-side
      // SL hits are NOT exempted -- g_inProfitTargetFlatten is only ever true during the specific
      // PgCloseMagic() loop inside MaybeFlatten()'s MEG_VETO_PROFIT_TARGET branch (see there).
      if(g_inProfitTargetFlatten)
        {
         if(LogFlatten)
            Print("[G-MULTI] Loss cooldown SKIPPED -- magic=", magic, " deal_profit_total=",
                  DoubleToString(profit, 2), " -- leg closed during a profit-target flatten (basket net positive)");
         return;
        }

      datetime until = TimeCurrent() + LossCooldownMinutes * 60;
      MegGvSet("LOSS_COOLDOWN_UNTIL", (double)until);

      // 2026-10-13: per-direction cooldown (additive, alongside the existing blanket one above
      // which Guard's own ComputeVeto()/VetoText() status display still uses unchanged). A
      // closing DEAL_TYPE is the OPPOSITE of the position that was closed (a closed BUY position
      // closes via a SELL deal) -- invert it to get which direction just took the loss, so only
      // THAT direction is blocked, not the whole fleet (narrower than the original blanket design,
      // precisely to avoid blocking a fresh opposite-direction signal after one side gets stopped).
      long dealType = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      string dirKey = (dealType == DEAL_TYPE_SELL) ? "LOSS_COOLDOWN_UNTIL_BUY" : "LOSS_COOLDOWN_UNTIL_SELL";
      MegGvSet(dirKey, (double)until);

      if(LogFlatten)
         Print("[G-MULTI] Loss cooldown triggered -- magic=", magic, " deal_profit_total=",
               DoubleToString(profit, 2), " direction_blocked=", (dirKey == "LOSS_COOLDOWN_UNTIL_BUY" ? "BUY" : "SELL"),
               " -- new entries blocked (that direction) until ", TimeToString(until));
     }
  }

//+------------------------------------------------------------------+
//| Veto computation -- priority order: worse brakes win.             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Fleet-wide floating P&L sum across all protected magics + MFE/MAE |
//| episode tracking + CSV logging (2026-10-02). Declared BEFORE      |
//| ComputeVeto() since MQL5 requires top-down declaration (no         |
//| forward-reference like C++ header prototypes).                    |
//+------------------------------------------------------------------+
double FleetFloatingTotal(int &openCountOut)
  {
   double total = 0.0;
   int    count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(!IsProtectedMagic((int)position.Magic())) continue;
      total += position.Profit() + position.Swap() + position.Commission();
      count++;
     }
   openCountOut = count;
   return total;
  }

int FleetGetLogHandle()
  {
   if(g_fleetLogHandle != INVALID_HANDLE) return g_fleetLogHandle;
   int commonFlag = 0;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      commonFlag = FILE_COMMON;
   string filename = "EA_G_PortfolioGuard_MultiEA_fleet_profit_log.csv";
   bool exists = FileIsExist(filename, commonFlag);
   ResetLastError();
   // FILE_CSV (not FILE_TXT) is required here -- FileWrite() in FILE_TXT mode concatenates every
   // argument with NO delimiter (only the literal header string below has real commas), which
   // silently produced an unparseable log for every data row until this fix (2026-10-05).
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | commonFlag);
   if(handle == INVALID_HANDLE)
     {
      Print("[G-MULTI] ERROR: fleet log FileOpen failed, err=", GetLastError());
      return INVALID_HANDLE;
     }
   if(!exists || FileSize(handle) == 0)
      FileWriteString(handle,
         "row_type,episode_start,episode_end,end_reason,snapshot_time,floating_now,"
         "peak_mfe,peak_mfe_time,trough_mae,trough_mae_time,open_positions_now,"
         "max_open_positions,equity_now\n");
   else
      FileSeek(handle, 0, SEEK_END);
   g_fleetLogHandle = handle;
   return g_fleetLogHandle;
  }

void FleetLogRow(const string rowType, const string endReason = "")
  {
   if(!LogFleetProfit) return;
   int handle = FleetGetLogHandle();
   if(handle == INVALID_HANDLE) return;
   int openNow = 0;
   double floatingNow = FleetFloatingTotal(openNow);
   FileWrite(handle, rowType,
      TimeToString(g_episodeStart, TIME_DATE | TIME_SECONDS),
      (rowType == "EPISODE_END") ? TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) : "",
      endReason,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      DoubleToString(floatingNow, 2),
      DoubleToString(g_episodePeak, 2),
      TimeToString(g_episodePeakTime, TIME_DATE | TIME_SECONDS),
      DoubleToString(g_episodeTrough, 2),
      TimeToString(g_episodeTroughTime, TIME_DATE | TIME_SECONDS),
      openNow, g_episodeMaxOpenPos,
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   FileFlush(handle);
  }

// Call every tick. Opens/updates/closes an episode and appends CSV rows --
// runs regardless of UseProfitTargetFlatten so MFE/MAE data accumulates
// even while the flatten trigger itself stays off.
void UpdateFleetEpisode()
  {
   int openNow = 0;
   double floatingNow = FleetFloatingTotal(openNow);

   if(!g_episodeActive)
     {
      if(openNow > 0)
        {
         // New episode starts.
         g_episodeActive     = true;
         g_episodeStart       = TimeCurrent();
         g_episodePeak        = floatingNow;
         g_episodePeakTime    = TimeCurrent();
         g_episodeTrough      = floatingNow;
         g_episodeTroughTime  = TimeCurrent();
         g_episodeMaxOpenPos  = openNow;
         g_lastFleetSnapshot  = 0;
         FleetLogRow("EPISODE_START");
        }
      return;
     }

   // Episode is active -- update MFE/MAE/max-open, optionally snapshot, and check for close.
   if(floatingNow > g_episodePeak)
     {
      g_episodePeak     = floatingNow;
      g_episodePeakTime = TimeCurrent();
     }
   if(floatingNow < g_episodeTrough)
     {
      g_episodeTrough     = floatingNow;
      g_episodeTroughTime = TimeCurrent();
     }
   if(openNow > g_episodeMaxOpenPos)
      g_episodeMaxOpenPos = openNow;

   if(FleetSnapshotSeconds > 0 && (TimeCurrent() - g_lastFleetSnapshot) >= FleetSnapshotSeconds)
     {
      g_lastFleetSnapshot = TimeCurrent();
      FleetLogRow("SNAPSHOT");
     }

   if(openNow == 0)
     {
      // Episode ends naturally (all protected positions closed, whatever the reason --
      // own TP/SL, a DD-floor flatten, or the new profit-target flatten; end_reason is
      // passed in by the caller that detected the trigger, "NATURAL" otherwise).
      FleetLogRow("EPISODE_END", g_episodeEndReasonPending);
      g_episodeEndReasonPending = "NATURAL";
      g_episodeActive = false;
     }
  }

//+------------------------------------------------------------------+
//| Fleet-wide same-direction basket SL (2026-10-09). Sums floating   |
//| P&L separately for BUY and SELL across ALL g_gateMagics positions |
//| (fleet-wide per explicit user decision, not per-EA like bot4's    |
//| internal basket). Returns the total for the requested direction;  |
//| does NOT filter by symbol beyond _Symbol (same scope as           |
//| FleetFloatingTotal above).                                        |
//+------------------------------------------------------------------+
bool IsGateMagic(const int magic)
  {
   for(int i = 0; i < ArraySize(g_gateMagics); i++)
      if(g_gateMagics[i] == magic)
         return true;
   return false;
  }

double BasketDirectionFloating(const ENUM_POSITION_TYPE dir, int &countOut)
  {
   double total = 0.0;
   int    count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(!IsGateMagic((int)position.Magic())) continue;
      if(position.PositionType() != dir) continue;
      total += position.Profit() + position.Swap() + position.Commission();
      count++;
     }
   countOut = count;
   return total;
  }

int BasketSLGetLogHandle()
  {
   if(g_basketSLLogHandle != INVALID_HANDLE) return g_basketSLLogHandle;
   int commonFlag = 0;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
      commonFlag = FILE_COMMON;
   string filename = "EA_G_PortfolioGuard_MultiEA_basket_sl_log.csv";
   bool exists = FileIsExist(filename, commonFlag);
   ResetLastError();
   // FILE_CSV (not FILE_TXT) -- see FleetGetLogHandle's comment above for why this matters.
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | commonFlag);
   if(handle == INVALID_HANDLE)
     {
      Print("[G-MULTI] ERROR: basket-SL log FileOpen failed, err=", GetLastError());
      return INVALID_HANDLE;
     }
   if(!exists || FileSize(handle) == 0)
      FileWriteString(handle,
         "event_time,direction,floating_total,threshold_usd,open_positions,action,equity_now\n");
   else
      FileSeek(handle, 0, SEEK_END);
   g_basketSLLogHandle = handle;
   return g_basketSLLogHandle;
  }

void BasketSLLogRow(const string direction, const double floatingTotal, const int openPositions,
                     const string action)
  {
   int handle = BasketSLGetLogHandle();
   if(handle == INVALID_HANDLE) return;
   FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), direction,
      DoubleToString(floatingTotal, 2), DoubleToString(BasketSLMaxLossUsd, 2), openPositions, action,
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   FileFlush(handle);
  }

// Call every tick (independent of UseBasketSLGuard -- logging runs whenever LogBasketSLGuard is on,
// same "collect evidence before flipping the switch" pattern as the fleet profit-target episode log).
// Checks BUY and SELL baskets separately; each crossing is logged/flattened independently so one
// direction tripping doesn't touch the other.
void UpdateBasketSL()
  {
   if(!LogBasketSLGuard && !UseBasketSLGuard) return;

   ENUM_POSITION_TYPE dirs[2] = {POSITION_TYPE_BUY, POSITION_TYPE_SELL};
   string dirNames[2] = {"BUY", "SELL"};

   for(int d = 0; d < 2; d++)
     {
      int openCount = 0;
      double floatingTotal = BasketDirectionFloating(dirs[d], openCount);
      if(openCount == 0) continue;               // nothing open this direction, nothing to check
      if(floatingTotal > -BasketSLMaxLossUsd) continue;  // not over threshold (floatingTotal is negative when losing)

      if(UseBasketSLGuard)
        {
         if(LogFlatten)
            Print("[G-MULTI] BASKET_SL TRIGGERED -- direction=", dirNames[d],
                  " floating=", DoubleToString(floatingTotal, 2),
                  " threshold=-", DoubleToString(BasketSLMaxLossUsd, 2),
                  " open_positions=", openCount, " -- flattening this direction's basket only");
         // 2026-10-13 fix: GGuardCloseDirectionTagged's return value (actual closed count) was
         // previously discarded, so the log below unconditionally wrote "FLATTENED" even when
         // every OrderSend() in that call failed/retried and zero positions actually closed --
         // confirmed live 2026-10-12 15:25-16:11: open_positions stayed at 6 for the full 46-minute
         // episode (1316 ticks) while the log claimed FLATTENED every single row. Now the logged
         // action reflects what GGuardCloseDirectionTagged actually achieved.
         int actuallyClosed = GGuardCloseDirectionTagged(g_gateMagics, dirs[d], "BSK");
         if(LogFlatten && actuallyClosed != openCount)
            Print("[G-MULTI] BASKET_SL CLOSE MISMATCH -- direction=", dirNames[d],
                  " requested_close=", openCount, " actually_closed=", actuallyClosed,
                  " -- OrderSend() did not close every targeted position this tick");
         if(LogBasketSLGuard)
           {
            string sl_action;
            if(actuallyClosed == openCount)
               sl_action = "FLATTENED";
            else if(actuallyClosed > 0)
               sl_action = "PARTIAL_FLATTEN_" + IntegerToString(actuallyClosed) + "_OF_" + IntegerToString(openCount);
            else
               sl_action = "FLATTEN_FAILED";
            BasketSLLogRow(dirNames[d], floatingTotal, openCount, sl_action);
           }
        }
      else
        {
         if(LogBasketSLGuard)
           {
            Print("[G-MULTI] BASKET_SL WOULD-TRIGGER (watch-only) -- direction=", dirNames[d],
                  " floating=", DoubleToString(floatingTotal, 2),
                  " threshold=-", DoubleToString(BasketSLMaxLossUsd, 2),
                  " open_positions=", openCount);
            BasketSLLogRow(dirNames[d], floatingTotal, openCount, "WATCH_ONLY");
           }
        }
     }
  }

int ComputeVeto()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity <= HardFloorLevel())
      return MEG_VETO_HARD_FLOOR;

   if(g_dayStartBalance > 0 && equity <= DailySoftFloorLevel())
      return MEG_VETO_DAILY_FLOOR;

   if(UseProfitTargetFlatten)
     {
      int openNow = 0;
      double floatingNow = FleetFloatingTotal(openNow);
      if(openNow > 0 && floatingNow >= ProfitTargetUsd)
         return MEG_VETO_PROFIT_TARGET;
     }

   if(IsInLossCooldown())
      return MEG_VETO_LOSS_COOLDOWN;

   if(IsInGapBlock())
      return MEG_VETO_GAP_BLOCK;

   if(UseFridayBackstop)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= FridayBackstopHour)
         return MEG_VETO_FRIDAY;
     }

   return MEG_VETO_OK;
  }

bool ShouldFlatten(const int veto)
  {
   if(veto == MEG_VETO_HARD_FLOOR  && UseFlattenOnHardFloor)  return true;
   if(veto == MEG_VETO_DAILY_FLOOR && UseFlattenOnDailyFloor) return true;
   if(veto == MEG_VETO_PROFIT_TARGET && UseProfitTargetFlatten) return true;
   return false;   // schedule/cooldown brakes (loss-cooldown, gap, Friday) NEVER flatten by design --
                    // they only ever publish a block-new-entries flag, per the confirmed spec.
  }

//+------------------------------------------------------------------+
int g_lastLoggedVeto = -1;   // -1 = never logged yet; forces one log line on first tick

void Publish(const int veto)
  {
   MegGvSet("VETO",       (double)veto);
   MegGvSet("BLOCK_NEW",  (veto != MEG_VETO_OK) ? 1.0 : 0.0);
   MegGvSet("FLAT_REQ",   ShouldFlatten(veto) ? 1.0 : 0.0);
   MegGvSet("HARD_FLOOR", HardFloorLevel());
   MegGvSet("DAILY_FLOOR",DailySoftFloorLevel());
   MegGvSet("TS",         (double)TimeCurrent());
   // 2026-09-29 bugfix: log only on a STATE TRANSITION, not every tick while a brake stays active.
   // Original unconditional "veto != MEG_VETO_OK" print produced 52,901 lines over ~9h of
   // intermittent cooldown in the BOSSAFX-Demo dry run -- found during first validation pass.
   if(LogState && veto != g_lastLoggedVeto)
     {
      Print("[G-MULTI] veto CHANGED -> ", VetoText(veto), " equity=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
            " hard_floor=", DoubleToString(HardFloorLevel(), 2),
            " daily_floor=", DoubleToString(DailySoftFloorLevel(), 2));
      g_lastLoggedVeto = veto;
     }
  }

void MaybeFlatten(const int veto)
  {
   if(!ShouldFlatten(veto))
      return;
   g_episodeEndReasonPending = VetoText(veto);   // so the EPISODE_END row that follows (open count
                                                  // drops to 0 on this same tick, caught by
                                                  // UpdateFleetEpisode()) records WHY, not just that
   // 2026-10-13: bracket the profit-target flatten so OnTradeTransaction() (fired synchronously by
   // each PgCloseMagic()->OrderSend() call below, before it returns) can tell "this losing leg
   // closed as part of a profitable fleet-wide profit-target sweep" apart from "this is a genuine
   // standalone stop-out" -- only the former skips loss-cooldown. Hard/daily-floor flattens are
   // NOT profit-target, so they're excluded here on purpose (a floor breach losing badly should
   // still cooldown like any other loss).
   bool isProfitTargetFlatten = (veto == MEG_VETO_PROFIT_TARGET);
   if(isProfitTargetFlatten)
      g_inProfitTargetFlatten = true;

   int total = 0;
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
     {
      total += PgCloseMagic(_Symbol, g_protectedMagics[i], g_trade, "GRD");
      total += PgCancelPendings(_Symbol, g_protectedMagics[i], g_trade);
     }

   if(isProfitTargetFlatten)
      g_inProfitTargetFlatten = false;

   if(LogFlatten)
      Print("[G-MULTI] FLATTEN executed -- veto=", VetoText(veto), " closed/cancelled=", total,
            " across ", ArraySize(g_protectedMagics), " protected magics");
  }

//+------------------------------------------------------------------+
//| On-chart legend -- OBJ_LABEL rows, left side, updated at most     |
//| every LegendUpdateSeconds. Purely visual, reads no state that     |
//| Publish()/ComputeVeto() haven't already computed -- this function |
//| never influences any brake decision, display only.                |
//+------------------------------------------------------------------+
#define MEG_OBJ_PREFIX "MEGLEG_"
datetime g_lastLegendDraw = 0;

void MegLabel(const string key, const int x, const int y, const string text, const color col, const int fs = 9)
  {
   string name = MEG_OBJ_PREFIX + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

string MegPosLine(const int magic, const string label, const double tp1r, const double tp2r, const double close1)
  {
   double sumRisk = 0, sumFloating = 0;
   int nOpen = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != magic) continue;
      nOpen++;
      double entry = position.PriceOpen();
      double sl    = position.StopLoss();
      double vol   = position.Volume();
      double dirSign = (position.PositionType() == POSITION_TYPE_BUY) ? 1.0 : -1.0;
      if(sl > 0)
        {
         double slDistPts = MathAbs(entry - sl) / _Point;
         double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         sumRisk += slDistPts * tickVal * vol;
        }
      sumFloating += position.Profit();
     }
   if(nOpen == 0)
      return StringFormat("%-16s magic %d: FLAT", label, magic);
   return StringFormat("%-16s magic %d: %d pos  risk=$%.0f  float=%s$%.0f  TP1@%.1fR(%.0f%%) TP2@%.1fR",
                        label, magic, nOpen, sumRisk, (sumFloating >= 0 ? "+" : "-"),
                        MathAbs(sumFloating), tp1r, close1 * 100, tp2r);
  }

void DrawLegend(const int veto)
  {
   if(!ShowLegend)
      return;
   if(PgIsOptimization())
      return;
   if(TimeCurrent() - g_lastLegendDraw < LegendUpdateSeconds)
      return;
   g_lastLegendDraw = TimeCurrent();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   color vetoColor = (veto == MEG_VETO_OK) ? clrLimeGreen
                    : (veto == MEG_VETO_HARD_FLOOR || veto == MEG_VETO_DAILY_FLOOR) ? clrOrangeRed
                    : clrOrange;

   int y = 14;
   int lh = 14;   // line height
   MegLabel("title", 10, y, "=== PORTFOLIO GUARD (Phase 1) ===", clrWhite, 10); y += lh + 2;
   MegLabel("acct", 10, y, StringFormat("Equity $%.2f  Balance $%.2f", equity, balance), clrSilver); y += lh;
   MegLabel("floors", 10, y, StringFormat("HardFloor $%.2f   DailyFloor $%.2f", HardFloorLevel(), DailySoftFloorLevel()), clrSilver); y += lh;
   MegLabel("veto", 10, y, "BRAKE: " + VetoText(veto), vetoColor, 10); y += lh + 2;
   MegLabel("flatten", 10, y, StringFormat("Flatten: hard=%s daily=%s (schedule brakes never flatten)",
            UseFlattenOnHardFloor ? "ON" : "OFF", UseFlattenOnDailyFloor ? "ON" : "OFF"),
            (UseFlattenOnHardFloor || UseFlattenOnDailyFloor) ? clrOrange : clrGray); y += lh + 4;

   int fleetOpenNow = 0;
   double fleetFloatingNow = FleetFloatingTotal(fleetOpenNow);
   string fleetTxt = StringFormat("Fleet floating: %s$%.0f / target $%.0f (%s)  peak(MFE) $%.0f  trough(MAE) $%.0f",
            (fleetFloatingNow >= 0 ? "+" : "-"), MathAbs(fleetFloatingNow), ProfitTargetUsd,
            UseProfitTargetFlatten ? "ON" : "watch-only",
            g_episodeActive ? g_episodePeak : 0.0, g_episodeActive ? g_episodeTrough : 0.0);
   MegLabel("fleetprofit", 10, y, fleetTxt,
            UseProfitTargetFlatten ? clrOrange : clrGray); y += lh + 4;

   MegLabel("hdr", 10, y, "--- Protected fleet (left=account, right=per-position) ---", clrGray); y += lh;
   MegLabel("p1", 10, y, MegPosLine(MagicSwingM5,  "SWING_M5_v2",   TP1R_SwingM5,  TP2R_SwingM5,  Close1Pct_SwingM5),  clrWhite); y += lh;
   MegLabel("p2", 10, y, MegPosLine(MagicScalp1x1, "SCALP_M15_1x1", TP1R_Scalp1x1, TP2R_Scalp1x1, Close1Pct_Scalp1x1), clrWhite); y += lh;
   MegLabel("p3", 10, y, MegPosLine(MagicScalp3x1, "SCALP_M15_3x1", TP1R_Scalp3x1, TP2R_Scalp3x1, Close1Pct_Scalp3x1), clrWhite); y += lh;
   MegLabel("p4", 10, y, MegPosLine(MagicR21A,     "R21A_BEONLY",   TP1R_R21A,     TP2R_R21A,     Close1Pct_R21A),     clrWhite); y += lh;
   MegLabel("p5", 10, y, MegPosLine(MagicR21B,     "R21B_LIVEGATE", TP1R_R21B,     TP2R_R21B,     Close1Pct_R21B),     clrWhite); y += lh + 2;

   datetime lossUntil = (datetime)MegGvGet("LOSS_COOLDOWN_UNTIL", 0);
   datetime gapUntil   = (datetime)MegGvGet("GAP_BLOCK_UNTIL", 0);
   string lossTxt = (lossUntil > TimeCurrent()) ? ("until " + TimeToString(lossUntil, TIME_MINUTES)) : "inactive";
   string gapTxt  = (gapUntil  > TimeCurrent()) ? ("until " + TimeToString(gapUntil,  TIME_MINUTES)) : "inactive";
   MegLabel("cooldowns", 10, y, StringFormat("LossCooldown: %s    GapBlock: %s", lossTxt, gapTxt), clrSilver); y += lh;

   if(MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) - FtmoInitialBalance) > FtmoInitialBalance)
      MegLabel("bossafx_note", 10, y,
               "NOTE: this account's balance is far from FtmoInitialBalance -- DD floors are NOT",
               clrYellow); y += lh;
  }

void RemoveLegendObjects()
  {
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, MEG_OBJ_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(MagicGuard);
   g_protectedMagics[0] = MagicSwingM5;
   g_protectedMagics[1] = MagicScalp1x1;
   g_protectedMagics[2] = MagicScalp3x1;
   g_protectedMagics[3] = MagicR21A;
   g_protectedMagics[4] = MagicR21B;
   g_protectedMagics[5] = MagicR22Pass6060;  // 2026-10-09: demo deployment, see magic comment above
   g_protectedMagics[6] = MagicWinrate1250;  // 2026-10-11: rank #1 by Profit/(DD*Lot) in the WINRATE table
   g_protectedMagics[7] = MagicWinrate3257;  // 2026-10-11: rank #3
   g_protectedMagics[8] = MagicWinrate667;   // 2026-10-11: rank #5 -- WATCH (win/loss-size asymmetry)
   g_protectedMagics[9] = MagicR22CDHV7794;  // 2026-10-13: best-D pick, PF 2.27, 345 positions
   g_protectedMagics[10] = MagicR22CDHV2098; // 2026-10-13: best-C pick, PF 2.47 (best of batch), 370 positions

   g_gateMagics[0] = MagicSwingM5;
   g_gateMagics[1] = MagicSwingM15;
   g_gateMagics[2] = MagicScalp1x1;
   g_gateMagics[3] = MagicScalp3x1;
   g_gateMagics[4] = MagicR21A;
   g_gateMagics[5] = MagicR21B;
   g_gateMagics[6] = MagicBot4_v49;
   g_gateMagics[7] = MagicR22Pass6060;  // 2026-10-09: demo deployment, see magic comment above
   g_gateMagics[8] = MagicWinrate1250;  // 2026-10-11: rank #1 by Profit/(DD*Lot) in the WINRATE table --
                                        // highest gate priority of the 3 new magics (placed first so it
                                        // wins ties when multiple WINRATE-family magics signal same bar)
   g_gateMagics[9] = MagicWinrate3257;  // 2026-10-11: rank #3
   g_gateMagics[10] = MagicWinrate667;  // 2026-10-11: rank #5 -- lowest gate priority of the 3, pending
                                        // live data to resolve the win/loss-size-asymmetry WATCH flag
   g_gateMagics[11] = MagicR22CDHV2098; // 2026-10-13: best-C pick, PF 2.47 (best of batch) -- placed
                                        // ahead of the D pick since it ranked higher on PF/net
   g_gateMagics[12] = MagicR22CDHV7794; // 2026-10-13: best-D pick, PF 2.27, 88.7% win rate (best win% of batch)
   // NOTE: MagicBot4_v50 intentionally NOT in g_gateMagics -- only one bot4
   // build is ever attached to a chart at a time; GGate_ShouldOpen() fail-opens
   // for any magic Guard doesn't recognize, so if v1_50 is the live build
   // instead of v1_49, it simply runs ungated rather than silently blocked.
   // Swap MagicBot4_v49 -> MagicBot4_v50 here if v1_50 becomes the live build.

   g_selftestOk = true;

   if(FtmoInitialBalance <= 0 || FtmoMaxLossPct <= 0 || DailySoftLossPct <= 0)
     {
      Print("[G-MULTI] ST00 FAIL: FtmoInitialBalance/FtmoMaxLossPct/DailySoftLossPct must be > 0");
      g_selftestOk = false;
     }
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
     {
      if(g_protectedMagics[i] <= 0)
        {
         Print("[G-MULTI] ST00 FAIL: protected magic #", i, " is <= 0");
         g_selftestOk = false;
        }
      for(int j = i + 1; j < ArraySize(g_protectedMagics); j++)
         if(g_protectedMagics[i] == g_protectedMagics[j])
           {
            Print("[G-MULTI] ST00 FAIL: duplicate protected magic ", g_protectedMagics[i]);
            g_selftestOk = false;
           }
     }
   if(HardFloorLevel() <= 0)
     {
      Print("[G-MULTI] ST00 FAIL: computed hard floor <= 0, check FtmoInitialBalance/FtmoMaxLossPct");
      g_selftestOk = false;
     }

   g_dayStamp        = 0;   // forces MaybeResetDailyFloor() to capture day-start balance on first tick
   g_dayStartBalance = 0;
   g_lastTickTime     = 0;

   if(LogSelfTest)
      Print("[G-MULTI] ST00 ", g_selftestOk ? "PASS" : "FAIL",
            " -- hard_floor=", DoubleToString(HardFloorLevel(), 2),
            " magics=", MagicSwingM5, ",", MagicScalp1x1, ",", MagicScalp3x1, ",", MagicR21A, ",", MagicR21B, ",", MagicR22Pass6060,
            " flatten_hard=", UseFlattenOnHardFloor ? "ON" : "OFF",
            " flatten_daily=", UseFlattenOnDailyFloor ? "ON" : "OFF",
            " (Phase 1 = these two flatten flags are the ONLY things that can touch a position; every"
            " other brake here only publishes MEG_ GlobalVariables for a future Phase-2 EA-side read)");

   if(!g_selftestOk)
      return INIT_FAILED;

   Publish(MEG_VETO_OK);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   RemoveLegendObjects();
   if(g_fleetLogHandle != INVALID_HANDLE)
      FileClose(g_fleetLogHandle);
   if(g_basketSLLogHandle != INVALID_HANDLE)
      FileClose(g_basketSLLogHandle);
  }

//+------------------------------------------------------------------+
//| MaybeRankAndPublishGate: 2026-10-05 (v2). Detects a new            |
//| GateTimeframe bar and, on rollover, re-ranks all gate-pool magics  |
//| by live PF and republishes the FULL priority order via             |
//| GGate_RankAndPublish/GGate_PublishPriority -- a lower-priority      |
//| magic can still trade this bar if nothing above it has a signal    |
//| (see GGate_ShouldOpen in BossafxGuardGate.mqh). Cheap no-op on      |
//| every other tick (one datetime compare).                            |
//+------------------------------------------------------------------+
void MaybeRankAndPublishGate()
  {
   datetime curBar = iTime(_Symbol, GateTimeframe, 0);
   if(curBar == 0 || curBar == g_lastGateBarTime)
      return; // same bar as last check, or history not ready yet -- nothing to do

   g_lastGateBarTime = curBar;
   datetime lookbackFrom = TimeCurrent() - GateLookbackDays * 86400;
   GGate_RankAndPublish(g_gateMagics, GateMinTrades, lookbackFrom);

   if(LogState)
     {
      string order = "";
      for(int i = 0; i < ArraySize(g_gateMagics); i++)
        {
         string varName = GGATE_VAR_PRI_PREFIX + IntegerToString(i);
         int m = GlobalVariableCheck(varName) ? (int)GlobalVariableGet(varName) : 0;
         order += (i > 0 ? ">" : "") + IntegerToString(m);
        }
      Print("[G-MULTI] GATE bar=", TimeToString(curBar), " priority_order=", order);
     }
  }

//+------------------------------------------------------------------+
//| UpdatePriceDistanceGate: 2026-10-13. Scans all open positions in  |
//| g_gateMagics (same fleet-wide pool as basket-SL/bar-priority),    |
//| finds the one with the latest POSITION_TIME, and publishes its    |
//| open price + the feature's enabled/threshold inputs every tick    |
//| via GGate_PublishDistanceState(). Each protected EA reads this    |
//| via GGate_PriceDistanceOk() right before its own OrderSend.       |
//| Logging-only while UsePriceDistanceGate=false (same "collect      |
//| evidence before flipping the switch" pattern as basket-SL/        |
//| profit-target): still publishes so the gate functions correctly   |
//| the moment it's turned on, costs nothing while off (all consumers |
//| fail-open on GGATE_VAR_DIST_ENABLED=0 before reading price/time). |
//+------------------------------------------------------------------+
void UpdatePriceDistanceGate()
  {
   double  latestPrice = 0.0;
   datetime latestTime  = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(!IsGateMagic((int)position.Magic())) continue;

      datetime openTime = (datetime)position.Time();
      if(openTime > latestTime)
        {
         latestTime  = openTime;
         latestPrice = position.PriceOpen();
        }
     }

   GGate_PublishDistanceState(UsePriceDistanceGate, MinReentryDistancePoints, latestPrice, latestTime);

   if(LogPriceDistanceGate && LogState && latestTime > 0 && latestTime != g_lastDistGateLoggedTime)
     {
      g_lastDistGateLoggedTime = latestTime;
      Print("[G-MULTI] DIST_GATE publish -- enabled=", (UsePriceDistanceGate ? "true" : "false"),
            " min_points=", MinReentryDistancePoints,
            " last_fleet_entry_price=", DoubleToString(latestPrice, _Digits),
            " last_fleet_entry_time=", TimeToString(latestTime));
     }
  }

//+------------------------------------------------------------------+
//| UpdateLossCooldownGate: 2026-10-13. Publishes the enable flag for  |
//| the per-direction loss-cooldown enforcement gate every tick. The   |
//| actual LOSS_COOLDOWN_UNTIL_BUY/SELL GlobalVariables are set        |
//| elsewhere, in OnTradeTransaction(), at the moment a losing deal    |
//| closes -- this function only publishes whether enforcement is ON,  |
//| same split (state-setter vs enable-flag-publisher) as the other   |
//| two gates above. Logging-only while UseLossCooldownGate=false,     |
//| same "collect evidence before flipping the switch" pattern.       |
//+------------------------------------------------------------------+
void UpdateLossCooldownGate()
  {
   GlobalVariableSet(GGATE_VAR_COOLDOWN_ENABLED, UseLossCooldownGate ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| UpdateFleetOpenCooldownGate: 2026-10-14. Publishes the enable flag |
//| and configured cooldown seconds for the fleet-wide same-instant    |
//| pile-on gate every tick. The actual LastOpenTime stamp is NOT      |
//| written here -- it's written directly by whichever protected EA    |
//| opens (via GGate_StampFleetOpen(), called right after its own      |
//| trade.PositionOpen() succeeds), specifically to avoid routing      |
//| through Guard's own tick, whose latency is exactly what the        |
//| race condition this gate fixes depends on.                        |
//+------------------------------------------------------------------+
void UpdateFleetOpenCooldownGate()
  {
   GlobalVariableSet(GGATE_VAR_FLEETOPEN_ENABLED, UseFleetOpenCooldownGate ? 1.0 : 0.0);
   GlobalVariableSet(GGATE_VAR_FLEETOPEN_SEC, (double)FleetOpenCooldownSeconds);
  }

void OnTick()
  {
   DetectWeekendGap();
   MaybeResetDailyFloor();

   if(UseEntryBarGate)
      MaybeRankAndPublishGate();

   int veto = ComputeVeto();
   Publish(veto);
   MaybeFlatten(veto);
   UpdateFleetEpisode();   // 2026-10-02: after MaybeFlatten so a same-tick flatten is caught as
                            // EPISODE_END with the right end_reason, not silently as "NATURAL"
   UpdateBasketSL();       // 2026-10-09: logged-only by default (UseBasketSLGuard=false); see input
                            // group comment above for the flat-$-per-direction threshold rationale
   UpdatePriceDistanceGate();  // 2026-10-13: publishes last fleet entry price/time every tick,
                                // consumed by each protected EA via GGate_PriceDistanceOk();
                                // gate itself is OFF by default (UsePriceDistanceGate=false)
   UpdateLossCooldownGate();   // 2026-10-13: publishes enable flag for the per-direction loss-
                                // cooldown enforcement gate; gate itself is OFF by default
                                // (UseLossCooldownGate=false)
   UpdateFleetOpenCooldownGate();  // 2026-10-14: publishes enable flag + cooldown seconds for the
                                     // fleet-wide same-instant pile-on gate; gate itself is OFF by
                                     // default (UseFleetOpenCooldownGate=false)
   DrawLegend(veto);

   if(!PgIsTester() && !PgIsOptimization())
     {
      if(TimeCurrent() - g_lastHeart >= HeartbeatSeconds)
        {
         g_lastHeart = TimeCurrent();
         if(LogState)
            Print("[G-MULTI] heartbeat -- veto=", VetoText(veto),
                  " equity=", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        }
     }
  }
