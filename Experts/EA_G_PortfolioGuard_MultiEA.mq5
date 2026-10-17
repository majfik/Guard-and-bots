#property copyright "Gold Multi-EA"
#property version   "1.00"
#property strict
#property description "Portfolio risk guard for the GOLD multi-EA fleet."
#property description "Publishes coherent entry gates through terminal GlobalVariables."
#property description "Supports enabled floor, profit-target, and basket flatten rules."
#property description "Requires a hedging account; see docs for the deployed contract."

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
#define MEG_VETO_STARTUP       107

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
input int    MagicBot4_v49    = 40001;  // bot4_TREND_FX_v1_49 -- gate and protected flatten pools
input int    MagicTest4_v52   = 54340;  // test4_clean_HYBRID_v52 live magic. Gate and protected pools.
                                         // Removed MagicBot4_v50 (60001): no EA or .set in this repo deploys it.
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

input group "=== Loss cooldown (fleet-wide blanket brake + optional directional gate) ==="
// UseLossCooldown publishes the blanket LOSS_COOLDOWN veto. Every non-OK veto,
// including this one, sets BLOCK_NEW. That blanket coverage is deliberate.
// UseLossCooldownGate (further down) is a separate directional consumer and
// does not narrow BLOCK_NEW.
input bool   UseLossCooldown      = true;
input int    LossCooldownMinutes  = 120;
input double LossCooldownMinNetLossUsd = 5.0; // Account-currency USD. Arm only when a fully
                                               // closed protected position's lifecycle net
                                               // (profit+swap+commission of every deal, entry
                                               // and exit) is strictly below -this. A
                                               // commission-only scratch above -this does not arm.
input bool   LossCooldownArmOnBasketSL = true; // default ON: a basket-SL full close may arm once
                                                // per fully closed losing position. OFF treats
                                                // exact basket close orders as exempt.

input group "=== Weekend/gap blackout (BLOCK_NEW veto, does not flatten) ==="
// Detected generically as "no ticks for N hours", not a hardcoded Sunday calendar time -- broker
// weekly-reopen instants vary by DST/session config, so a fixed clock time would be fragile. This
// also incidentally catches any other multi-hour feed outage, which is a reasonable bonus, not a bug.
input bool   UseGapBlock          = true;
input int    GapDetectHours       = 6;    // treat a tick gap of >= this many hours as a weekend/outage gap
input int    GapBlockHours        = 2;    // block new entries for this long after ticks resume

input group "=== Friday close backstop (BLOCK_NEW veto, does not flatten) ==="
// bot1_regime2.1.mq5 already has its own AvoidFriday/FridayCloseHour (confirmed live, input default
// true/16). This is a portfolio-wide backstop in case any single EA's own flag were ever misconfigured.
input bool   UseFridayBackstop    = true;
input int    FridayBackstopHour   = 16;   // server time hour

input group "=== Hard and daily floor flatten flags. Schedule brakes never flatten. ==="
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
// Dynamic on purpose: membership is the MegAddActiveMagic list in OnInit, not a
// hand-counted capacity. The two pools stay separate so a later magic can be
// gate-only or flatten-only via MegPoolAdd. This deployment puts every active
// production magic in both, including 54322, 40001, and test4 54340.
int      g_protectedMagics[];
int      g_gateMagics[];

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
datetime g_episodeReasonBoundStart = 0;       // episode start this reason belongs to. A later episode,
                                              // or positions still open after a profit-target latch,
                                              // must not inherit PROFIT_TARGET.
datetime g_lastGateBarTime  = 0;   // 2026-10-05: last GateTimeframe bar we ranked+published for
datetime g_lastDistGateLoggedTime = 0;   // 2026-10-13: last fleet-entry time we logged (dedupe)

// 2026-10-13: profit-target-flatten cooldown exception. A fleet-wide profit-target flatten
// (MEG_VETO_PROFIT_TARGET) closes every protected position; the AGGREGATE is profitable by
// definition (that's the trigger), but an individual leg can still realize a small loss. Per
// explicit user spec, that single losing leg should NOT start a loss-cooldown. NOT used for
// basket-SL (loss-side on purpose, must still cooldown) or broker-side SL hits (always
// cooldown, per user spec). Attribution is by close order ticket -- see PtIsAttributedDeal().

//+------------------------------------------------------------------+
//| Fleet-wide same-direction basket SL tracking (2026-10-09).        |
//| Separate from the profit-target episode tracker above -- this is  |
//| loss-side, per-direction (BUY/SELL tracked independently), and    |
//| logged every tick while over threshold rather than once per       |
//| episode, since the point here is frequency/severity review, not   |
//| MFE/MAE curve shape.                                              |
//+------------------------------------------------------------------+
int      g_basketSLLogHandle = INVALID_HANDLE;

// Basket-SL attribution is by close ORDER ticket, same idea as g_ptOrders.
// Broker comments are not used: a broker may drop "|BSK".
#define MEG_BS_ORDER_TTL_SEC 86400
ulong    g_bsOrders[];
datetime g_bsOrderTime[];

void BsRecordOrder(const ulong order)
  {
   if(order == 0)
      return;
   datetime now = TimeCurrent();
   for(int i = ArraySize(g_bsOrders) - 1; i >= 0; i--)
     {
      if(g_bsOrders[i] == order)
         return;
      if(now - g_bsOrderTime[i] > MEG_BS_ORDER_TTL_SEC)
        {
         int last = ArraySize(g_bsOrders) - 1;
         g_bsOrders[i]    = g_bsOrders[last];
         g_bsOrderTime[i] = g_bsOrderTime[last];
         ArrayResize(g_bsOrders, last);
         ArrayResize(g_bsOrderTime, last);
        }
     }
   int n = ArraySize(g_bsOrders);
   ArrayResize(g_bsOrders, n + 1);
   ArrayResize(g_bsOrderTime, n + 1);
   g_bsOrders[n]    = order;
   g_bsOrderTime[n] = now;
  }

bool BsIsAttributedDeal(const ulong dealTicket)
  {
   ulong order = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   if(order == 0)
      return false;
   for(int i = 0; i < ArraySize(g_bsOrders); i++)
      if(g_bsOrders[i] == order)
         return (TimeCurrent() - g_bsOrderTime[i] <= MEG_BS_ORDER_TTL_SEC);
   return false;
  }

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

      double volume = PositionGetDouble(POSITION_VOLUME);
      string tagComment = GGate_BuildCloseComment(posMagic, reasonTag);
      // Shared close core: legal filling policy, no resend while a close order is
      // still working, emergency CTrade fallback only after the tagged send is
      // rejected. 2026-10-13: a literal IOC policy was rejected ("Unsupported filling
      // mode") for thousands of ticks; the policy is now derived from the symbol.
      //
      // 2026-10-15 fix kept: the CTrade fallback must run under posMagic, not
      // MagicGuard=61998, or DEAL_MAGIC=61998 fails IsProtectedMagic() and the
      // per-direction loss-cooldown is never armed (confirmed live 2026-10-15:
      // 54323/54324 at 02:13, 54325 at 04:56 produced no cooldown). The core
      // restores exactly MagicGuard afterwards. RequestMagic() is not used.
      // The close order ticket is recorded for cooldown attribution. Comments
      // are not consulted. Only a FULL close counts; PARTIAL/PENDING retry.
      ulong deal = 0, order = 0;
      double filled = 0.0;
      int outcome = GGate_CloseVolumeCore(g_trade, ticket, volume, true, tagComment, MagicGuard, deal, filled, order);
      BsRecordOrder(order);
      g_trade.SetExpertMagicNumber(MagicGuard);
      if(outcome == GGATE_CLOSE_FULL && !PositionSelectByTicket(ticket))
         closed++;
     }
   g_trade.SetExpertMagicNumber(MagicGuard);
   return closed;
  }

//+------------------------------------------------------------------+
//| Profit-target flatten latch + deal attribution.                   |
//| The trigger snapshots the protected positions open at that moment |
//| (g_ptTargets). The latch stays on, and every tick closes whatever |
//| targets remain, until all are gone -- closing winners first can   |
//| no longer pull floating P&L under the target and leave the losing |
//| legs open. Terminal: MEG_PT_LATCH_MAX_SEC, logged, then released  |
//| (remaining legs keep their own SL/TP). Stall progress is logged.  |
//|                                                                    |
//| Attribution is by close ORDER ticket, not a flag: every order the |
//| latch sends (tagged or CTrade fallback, including one resolved    |
//| later from PENDING) is recorded in g_ptOrders. OnTradeTransaction |
//| may run after OnTick returns, so it matches DEAL_ORDER against    |
//| that set. A broker SL/TP or a bot's own close on a target has a   |
//| different order ticket and is never exempted. Entries expire      |
//| after MEG_PT_ORDER_TTL_SEC.                                        |
//+------------------------------------------------------------------+
#define MEG_PT_LATCH_MAX_SEC      3600
#define MEG_PT_STALL_LOG_SEC      60
#define MEG_PT_ORDER_TTL_SEC      86400

bool     g_ptLatchActive   = false;
datetime g_ptLatchStart    = 0;
datetime g_ptLastStallLog  = 0;
ulong    g_ptTargets[];
ulong    g_ptOrders[];
datetime g_ptOrderTime[];

void PtRecordOrder(const ulong order)
  {
   if(order == 0)
      return;
   datetime now = TimeCurrent();
   for(int i = ArraySize(g_ptOrders) - 1; i >= 0; i--)
     {
      if(g_ptOrders[i] == order)
         return;
      if(now - g_ptOrderTime[i] > MEG_PT_ORDER_TTL_SEC)
        {
         int last = ArraySize(g_ptOrders) - 1;
         g_ptOrders[i]    = g_ptOrders[last];
         g_ptOrderTime[i] = g_ptOrderTime[last];
         ArrayResize(g_ptOrders, last);
         ArrayResize(g_ptOrderTime, last);
        }
     }
   int n = ArraySize(g_ptOrders);
   ArrayResize(g_ptOrders, n + 1);
   ArrayResize(g_ptOrderTime, n + 1);
   g_ptOrders[n]    = order;
   g_ptOrderTime[n] = now;
  }

bool PtIsAttributedDeal(const ulong dealTicket)
  {
   ulong order = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
   if(order == 0)
      return false;
   for(int i = 0; i < ArraySize(g_ptOrders); i++)
      if(g_ptOrders[i] == order)
         return (TimeCurrent() - g_ptOrderTime[i] <= MEG_PT_ORDER_TTL_SEC);
   return false;
  }

// Snapshot of protected positions on this symbol at trigger time.
int PtSnapshotTargets()
  {
   ArrayResize(g_ptTargets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!IsProtectedMagic((int)PositionGetInteger(POSITION_MAGIC))) continue;
      int n = ArraySize(g_ptTargets);
      ArrayResize(g_ptTargets, n + 1);
      g_ptTargets[n] = ticket;
     }
   return ArraySize(g_ptTargets);
  }

// One close pass over the remaining targets. Returns how many are still open
// (including ones with a close order still working).
int PtCloseRemainingTargets()
  {
   int remaining = 0;
   for(int t = ArraySize(g_ptTargets) - 1; t >= 0; t--)
     {
      ulong ticket = g_ptTargets[t];
      bool open = PositionSelectByTicket(ticket);
      if(!open && GGate_PendingFind(ticket) < 0)
        {
         int last = ArraySize(g_ptTargets) - 1;
         g_ptTargets[t] = g_ptTargets[last];
         ArrayResize(g_ptTargets, last);
         continue;
        }
      double volume = open ? PositionGetDouble(POSITION_VOLUME) : 0.0;
      string comment = open ? GGate_BuildCloseComment(PositionGetInteger(POSITION_MAGIC), GGATE_REASON_GRD) : "";
      ulong deal = 0, order = 0;
      double filled = 0.0;
      int outcome = GGate_CloseVolumeCore(g_trade, ticket, volume, true, comment, MagicGuard, deal, filled, order);
      g_trade.SetExpertMagicNumber(MagicGuard);
      PtRecordOrder(order);
      if(outcome == GGATE_CLOSE_FULL && !PositionSelectByTicket(ticket) && GGate_PendingFind(ticket) < 0)
        {
         int last = ArraySize(g_ptTargets) - 1;
         g_ptTargets[t] = g_ptTargets[last];
         ArrayResize(g_ptTargets, last);
         continue;
        }
      remaining++;
     }
   return remaining;
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
      case MEG_VETO_STARTUP:        return "STARTUP -- Guard is initializing; new entries blocked until the first tick";
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

// DEAL_POSITION_ID is the position identifier, not a deal ticket. On a hedging
// account POSITION_IDENTIFIER equals the position ticket; on other modes it
// may not. Match the identifier, never the ticket, to see if any volume remains.
bool MegPositionIdStillOpen(const ulong positionId)
  {
   if(positionId == 0)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return true;
     }
   return false;
  }

// An OUT/OUT_BY deal is exempt only when its own close order was recorded.
// A later SL on a remainder has a different order and is not exempt. Basket
// orders are exempt only when LossCooldownArmOnBasketSL is false.
bool MegOutDealExempt(const ulong deal)
  {
   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return false;
   if(PtIsAttributedDeal(deal))
      return true;
   if(!LossCooldownArmOnBasketSL && BsIsAttributedDeal(deal))
      return true;
   return false;
  }

// Full lifecycle net in account-currency USD: every deal's profit + swap +
// commission, including the entry. allOutDealsExempt is true only when every
// closing deal is an exact attributed profit-target (or policy-exempt basket)
// order. outDeals == 0 means history is not complete yet.
double MegPositionLifecycleNet(const ulong positionId, bool &allOutDealsExempt, int &outDeals, long &closeDealType)
  {
   allOutDealsExempt = false;
   outDeals = 0;
   closeDealType = -1;
   double net = 0.0;
   if(positionId == 0 || !HistorySelectByPosition(positionId))
      return 0.0;
   int exemptOut = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId)
         continue;
      net += HistoryDealGetDouble(deal, DEAL_PROFIT)
           + HistoryDealGetDouble(deal, DEAL_SWAP)
           + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      outDeals++;
      closeDealType = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(MegOutDealExempt(deal))
         exemptOut++;
     }
   allOutDealsExempt = (outDeals > 0 && exemptOut == outDeals);
   return net;
  }

// Bounded terminal marker, one slot ring per account login. The value is the
// position identifier; the paired _NET variable is the lifecycle net in USD.
// A restart that sees the same identifier again does not arm a second time.
#define MEG_CD_MARK_SLOTS 128

string MegCdMarkName(const int slot)
  {
   return "MEG_CDMARK_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(slot);
  }

string MegCdMarkIdxName()
  {
   return "MEG_CDMARK_IDX_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN));
  }

bool MegCooldownMarked(const ulong positionId)
  {
   if(positionId == 0)
      return false;
   for(int i = 0; i < MEG_CD_MARK_SLOTS; i++)
     {
      string name = MegCdMarkName(i);
      if(!GlobalVariableCheck(name))
         continue;
      if((ulong)GlobalVariableGet(name) == positionId)
         return true;
     }
   return false;
  }

void MegCooldownMark(const ulong positionId, const double netUsd)
  {
   if(positionId == 0)
      return;
   string idxName = MegCdMarkIdxName();
   int idx = GlobalVariableCheck(idxName) ? (int)GlobalVariableGet(idxName) : 0;
   if(idx < 0)
      idx = 0;
   int slot = idx % MEG_CD_MARK_SLOTS;
   GlobalVariableSet(MegCdMarkName(slot), (double)positionId);
   GlobalVariableSet(MegCdMarkName(slot) + "_NET", netUsd);
   GlobalVariableSet(idxName, (double)(slot + 1));
  }

// Closing deals are only queued here. The position may still be open when
// the transaction arrives, so the final deal can be missing from history.
// MegProcessCooldownQueue evaluates an id only after no open position has
// that POSITION_IDENTIFIER.
#define MEG_CD_QUEUE_MAX 256
ulong g_cdQueue[];

void MegCooldownEnqueue(const ulong positionId)
  {
   if(positionId == 0 || MegCooldownMarked(positionId))
      return;
   int n = ArraySize(g_cdQueue);
   for(int i = 0; i < n; i++)
      if(g_cdQueue[i] == positionId)
         return;
   if(n >= MEG_CD_QUEUE_MAX)
     {
      for(int i = 0; i < n - 1; i++)
         g_cdQueue[i] = g_cdQueue[i + 1];
      g_cdQueue[n - 1] = positionId;
      return;
     }
   ArrayResize(g_cdQueue, n + 1);
   g_cdQueue[n] = positionId;
  }

void MegCooldownDequeueAt(const int idx)
  {
   int last = ArraySize(g_cdQueue) - 1;
   if(idx < 0 || idx > last)
      return;
   g_cdQueue[idx] = g_cdQueue[last];
   ArrayResize(g_cdQueue, last);
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
      return;
   ulong positionId = (ulong)HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
   MegCooldownEnqueue(positionId);
  }

void MegProcessCooldownQueue()
  {
   for(int i = ArraySize(g_cdQueue) - 1; i >= 0; i--)
     {
      ulong positionId = g_cdQueue[i];
      if(MegPositionIdStillOpen(positionId))
         continue;
      if(MegCooldownMarked(positionId))
        {
         MegCooldownDequeueAt(i);
         continue;
        }
      bool allExempt = false;
      int outDeals = 0;
      long closeType = -1;
      double net = MegPositionLifecycleNet(positionId, allExempt, outDeals, closeType);
      if(outDeals <= 0)
         continue;
      MegCooldownDequeueAt(i);
      MegCooldownMark(positionId, net);
      if(!UseLossCooldown)
         continue;
      string dirName = (closeType == DEAL_TYPE_SELL) ? "BUY" : "SELL";
      if(allExempt)
        {
         Print("[G-MULTI] Loss cooldown SKIPPED -- position_id=", positionId,
               " lifecycle_net_usd=", DoubleToString(net, 2),
               " -- every closing deal is an exact attributed exempt order");
         continue;
        }
      if(net >= -LossCooldownMinNetLossUsd)
        {
         Print("[G-MULTI] Loss cooldown SKIPPED -- position_id=", positionId,
               " lifecycle_net_usd=", DoubleToString(net, 2),
               " threshold_usd=", DoubleToString(LossCooldownMinNetLossUsd, 2),
               " -- not below -threshold");
         continue;
        }
      datetime until = TimeCurrent() + LossCooldownMinutes * 60;
      MegGvSet("LOSS_COOLDOWN_UNTIL", (double)until);
      string dirKey = (closeType == DEAL_TYPE_SELL) ? "LOSS_COOLDOWN_UNTIL_BUY" : "LOSS_COOLDOWN_UNTIL_SELL";
      MegGvSet(dirKey, (double)until);
      Print("[G-MULTI] Loss cooldown ARMED -- position_id=", positionId,
            " lifecycle_net_usd=", DoubleToString(net, 2),
            " threshold_usd=", DoubleToString(LossCooldownMinNetLossUsd, 2),
            " direction_blocked=", dirName,
            " until ", TimeToString(until));
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
         // New episode starts. A reason stamped for a previous episode must not
         // label this one (a leftover PROFIT_TARGET in particular).
         g_episodeActive     = true;
         g_episodeStart       = TimeCurrent();
         g_episodeEndReasonPending = "NATURAL";
         g_episodeReasonBoundStart = 0;
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
      string endReason = "NATURAL";
      if(g_episodeReasonBoundStart == g_episodeStart)
         endReason = g_episodeEndReasonPending;
      FleetLogRow("EPISODE_END", endReason);
      g_episodeEndReasonPending = "NATURAL";
      g_episodeReasonBoundStart = 0;
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

bool EquityAtOrBelowHardFloor()
  {
   return (AccountInfoDouble(ACCOUNT_EQUITY) <= HardFloorLevel());
  }

bool EquityAtOrBelowDailyFloor()
  {
   return (g_dayStartBalance > 0.0 && AccountInfoDouble(ACCOUNT_EQUITY) <= DailySoftFloorLevel());
  }

bool FleetProfitTargetReached()
  {
   int openNow = 0;
   double floatingNow = FleetFloatingTotal(openNow);
   return (openNow > 0 && floatingNow >= ProfitTargetUsd);
  }

// Status veto only. Precedence is unchanged (worse brakes win) and is what
// Publish() writes to VETO / BLOCK_NEW. Flatten execution does not use this
// value: a disabled hard/daily floor must not mask an enabled profit target.
int ComputeVeto()
  {
   if(EquityAtOrBelowHardFloor())
      return MEG_VETO_HARD_FLOOR;

   if(EquityAtOrBelowDailyFloor())
      return MEG_VETO_DAILY_FLOOR;

   if(g_ptLatchActive || (UseProfitTargetFlatten && FleetProfitTargetReached()))
      return MEG_VETO_PROFIT_TARGET;

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

// Highest-precedence ENABLED flatten that is currently true, or MEG_VETO_OK.
// Hard, then daily, then profit. Each flag is required, so a disabled floor
// falls through instead of swallowing a later enabled flatten. An active
// profit-target latch keeps returning PROFIT_TARGET even after floating P&L
// drops back under the target, until every snapshotted leg is closed.
int ComputeFlattenReason()
  {
   if(UseFlattenOnHardFloor && EquityAtOrBelowHardFloor())
      return MEG_VETO_HARD_FLOOR;
   if(UseFlattenOnDailyFloor && EquityAtOrBelowDailyFloor())
      return MEG_VETO_DAILY_FLOOR;
   if(g_ptLatchActive)
      return MEG_VETO_PROFIT_TARGET;
   if(UseProfitTargetFlatten && FleetProfitTargetReached())
      return MEG_VETO_PROFIT_TARGET;
   return MEG_VETO_OK;
  }

//+------------------------------------------------------------------+
int g_lastLoggedVeto = -1;   // -1 = never logged yet; forces one log line on first tick

void Publish(const int veto, const int flattenReason)
  {
   // BLOCK_NEW covers every non-OK veto (loss cooldown, gap, Friday, floors,
   // profit target). That blanket is deliberate. UseLossCooldown controls
   // whether the cooldown veto is computed; it does not narrow BLOCK_NEW.
   // Odd sequence, then the variables, then even sequence and the heartbeat
   // of this completed publication.
   GGate_PublishBegin();
   MegGvSet("VETO",       (double)veto);
   MegGvSet("BLOCK_NEW",  (veto != MEG_VETO_OK) ? 1.0 : 0.0);
   MegGvSet("FLAT_REQ",   (flattenReason != MEG_VETO_OK) ? 1.0 : 0.0);
   MegGvSet("HARD_FLOOR", HardFloorLevel());
   MegGvSet("DAILY_FLOOR",DailySoftFloorLevel());
   MegGvSet("TS",         (double)TimeCurrent());
   GGate_PublishEnd();
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

void MaybeFlatten(const int flattenReason)
  {
   if(flattenReason == MEG_VETO_OK)
      return;
   // One close pass for every enabled flatten that is true this tick. The
   // reason is the highest-precedence enabled trigger, so a disabled hard or
   // daily floor cannot stamp HARD_FLOOR/DAILY_FLOOR over an actual profit
   // flatten, and we do not run the close loop once per reason.
   // Profit-target stamps its own reason inside the latch, and only for the
   // episode that is active when the latch starts.
   if(flattenReason == MEG_VETO_PROFIT_TARGET)
     {
      MaybeFlattenProfitTarget();
      return;
     }

   // Episode end reason is recorded only while an episode is active, so a
   // floor breach with nothing open cannot poison the next episode.
   if(g_episodeActive)
     {
      g_episodeEndReasonPending = VetoText(flattenReason);
      g_episodeReasonBoundStart = g_episodeStart;
     }

   // Hard/daily floor: not profit-target, so no loss-cooldown exemption (a floor breach
   // losing badly should still cooldown like any other loss). If a profit-target latch
   // was active its targets are closed here too; the latch clears itself once they are gone.
   int total = 0;
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
     {
      total += PgCloseMagic(_Symbol, g_protectedMagics[i], g_trade, "GRD", MagicGuard);
      total += PgCancelPendings(_Symbol, g_protectedMagics[i], g_trade);
     }
   g_trade.SetExpertMagicNumber(MagicGuard);

   if(LogFlatten)
      Print("[G-MULTI] FLATTEN executed -- reason=", VetoText(flattenReason), " closed/cancelled=", total,
            " across ", ArraySize(g_protectedMagics), " protected magics");
  }

void MaybeFlattenProfitTarget()
  {
   datetime now = TimeCurrent();
   if(!g_ptLatchActive)
     {
      int n = PtSnapshotTargets();
      if(n == 0)
         return;
      g_ptLatchActive  = true;
      g_ptLatchStart   = now;
      g_ptLastStallLog = now;
      if(g_episodeActive)
        {
         g_episodeEndReasonPending = VetoText(MEG_VETO_PROFIT_TARGET);
         g_episodeReasonBoundStart = g_episodeStart;
        }
      if(LogFlatten)
         Print("[G-MULTI] PROFIT_TARGET latch ON -- targets=", n,
               " (closing every snapshotted leg even if floating P&L falls back under target)");
     }

   // The episode may be opened later in this same OnTick (UpdateFleetEpisode
   // runs after the flatten). Bind the reason once that episode exists, and
   // only to that start time, so a later episode cannot inherit it.
   if(g_ptLatchActive && g_episodeActive && g_episodeReasonBoundStart != g_episodeStart)
     {
      g_episodeEndReasonPending = VetoText(MEG_VETO_PROFIT_TARGET);
      g_episodeReasonBoundStart = g_episodeStart;
     }

   int remaining = PtCloseRemainingTargets();
   int cancelled = 0;
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
      cancelled += PgCancelPendings(_Symbol, g_protectedMagics[i], g_trade);

   if(remaining == 0)
     {
      g_ptLatchActive = false;
      ArrayResize(g_ptTargets, 0);
      int stillOpen = 0;
      FleetFloatingTotal(stillOpen);
      if(stillOpen > 0)
        {
         // Targeted legs are gone, but other protected positions are still
         // open. Those are not this flatten; do not leave PROFIT_TARGET on them.
         g_episodeEndReasonPending = "NATURAL";
         g_episodeReasonBoundStart = 0;
         if(LogFlatten)
            Print("[G-MULTI] PROFIT_TARGET latch OFF -- targets closed, ", stillOpen,
                  " unrelated protected position(s) still open; episode end reason cleared");
        }
      else if(LogFlatten)
         Print("[G-MULTI] PROFIT_TARGET latch OFF -- all targeted legs closed after ",
               (int)(now - g_ptLatchStart), "s; pendings cancelled=", cancelled);
      return;
     }

   if(now - g_ptLatchStart >= MEG_PT_LATCH_MAX_SEC)
     {
      Print("[G-MULTI] PROFIT_TARGET latch ABANDONED (terminal) -- ", remaining,
            " targeted leg(s) still open after ", MEG_PT_LATCH_MAX_SEC,
            "s of retries; they keep their own SL/TP. Close manually if required.");
      g_ptLatchActive = false;
      ArrayResize(g_ptTargets, 0);
      g_episodeEndReasonPending = "NATURAL"; // remaining legs will end the episode on their own
      g_episodeReasonBoundStart = 0;
      return;
     }

   if(LogFlatten && now - g_ptLastStallLog >= MEG_PT_STALL_LOG_SEC)
     {
      g_ptLastStallLog = now;
      Print("[G-MULTI] PROFIT_TARGET latch RETRY -- ", remaining, " targeted leg(s) still open after ",
            (int)(now - g_ptLatchStart), "s (working close orders are not resent)");
     }
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
   MegLabel("title", 10, y, "=== PORTFOLIO GUARD ===", clrWhite, 10); y += lh + 2;
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
//| One pool slot. Duplicate or non-positive magic fails OnInit.      |
//| Gate-only or flatten-only membership is a direct MegPoolAdd call. |
//+------------------------------------------------------------------+
void MegPoolAdd(int &pool[], const int magic, const string poolName)
  {
   if(magic <= 0)
     {
      Print("[G-MULTI] ST00 FAIL: ", poolName, " magic <= 0");
      g_selftestOk = false;
      return;
     }
   for(int i = 0; i < ArraySize(pool); i++)
     {
      if(pool[i] == magic)
        {
         Print("[G-MULTI] ST00 FAIL: duplicate ", poolName, " magic ", magic);
         g_selftestOk = false;
         return;
        }
     }
   int n = ArraySize(pool);
   ArrayResize(pool, n + 1);
   pool[n] = magic;
  }

// Current deployment: every active production magic is in the gate pool and
// the protected flatten pool. MagicGuard is not a fleet participant.
void MegAddActiveMagic(const int magic)
  {
   MegPoolAdd(g_protectedMagics, magic, "protected");
   MegPoolAdd(g_gateMagics, magic, "gate");
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!GGate_RequireHedgingAccount())
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(MagicGuard);
   g_selftestOk = true;
   ArrayResize(g_protectedMagics, 0);
   ArrayResize(g_gateMagics, 0);
   MegAddActiveMagic(MagicSwingM5);
   MegAddActiveMagic(MagicSwingM15);     // 54322: was gate-only; now also flattened
   MegAddActiveMagic(MagicScalp1x1);
   MegAddActiveMagic(MagicScalp3x1);
   MegAddActiveMagic(MagicR21A);
   MegAddActiveMagic(MagicR21B);
   MegAddActiveMagic(MagicBot4_v49);     // 40001: was gate-only; now also flattened
   MegAddActiveMagic(MagicTest4_v52);    // 54340
   MegAddActiveMagic(MagicR22Pass6060);
   MegAddActiveMagic(MagicWinrate1250);
   MegAddActiveMagic(MagicWinrate3257);
   MegAddActiveMagic(MagicWinrate667);
   MegAddActiveMagic(MagicR22CDHV2098);
   MegAddActiveMagic(MagicR22CDHV7794);

   if(LossCooldownMinNetLossUsd < 0.0)
     {
      Print("[G-MULTI] INIT FAILED: LossCooldownMinNetLossUsd (",
            DoubleToString(LossCooldownMinNetLossUsd, 2),
            ") must be nonnegative USD. The cooldown arms only when lifecycle net is below -this.");
      return INIT_FAILED;
     }

   if(FtmoInitialBalance <= 0 || FtmoMaxLossPct <= 0 || DailySoftLossPct <= 0)
     {
      Print("[G-MULTI] ST00 FAIL: FtmoInitialBalance/FtmoMaxLossPct/DailySoftLossPct must be > 0");
      g_selftestOk = false;
     }
   if(ArraySize(g_protectedMagics) != ArraySize(g_gateMagics) || ArraySize(g_protectedMagics) <= 0)
     {
      Print("[G-MULTI] ST00 FAIL: protected and gate pools must both be non-empty and the same size");
      g_selftestOk = false;
     }
   for(int i = 0; i < ArraySize(g_protectedMagics); i++)
     {
      if(g_protectedMagics[i] <= 0 || g_protectedMagics[i] == MagicGuard)
        {
         Print("[G-MULTI] ST00 FAIL: protected magic #", i, " is <= 0 or is MagicGuard");
         g_selftestOk = false;
        }
      bool inGate = false;
      for(int j = 0; j < ArraySize(g_gateMagics); j++)
         if(g_gateMagics[j] == g_protectedMagics[i])
            inGate = true;
      if(!inGate)
        {
         Print("[G-MULTI] ST00 FAIL: protected magic ", g_protectedMagics[i], " is missing from the gate pool");
         g_selftestOk = false;
        }
      for(int j = i + 1; j < ArraySize(g_protectedMagics); j++)
         if(g_protectedMagics[i] == g_protectedMagics[j])
           {
            Print("[G-MULTI] ST00 FAIL: duplicate protected magic ", g_protectedMagics[i]);
            g_selftestOk = false;
           }
     }
   for(int i = 0; i < ArraySize(g_gateMagics); i++)
     {
      if(g_gateMagics[i] <= 0 || g_gateMagics[i] == MagicGuard)
        {
         Print("[G-MULTI] ST00 FAIL: gate magic #", i, " is <= 0 or is MagicGuard");
         g_selftestOk = false;
        }
      for(int j = i + 1; j < ArraySize(g_gateMagics); j++)
         if(g_gateMagics[i] == g_gateMagics[j])
           {
            Print("[G-MULTI] ST00 FAIL: duplicate gate magic ", g_gateMagics[i]);
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
            " flatten_profit=", UseProfitTargetFlatten ? "ON" : "OFF",
            " basket_sl=", UseBasketSLGuard ? "ON" : "OFF",
            " (hard/daily flags are not the only closers: profit flatten and basket SL close when enabled."
            " Gap, Friday, and loss cooldown set BLOCK_NEW and do not flatten."
            " Trading EAs consume BLOCK_NEW. Startup publishes that block until the first tick.)");

   if(!g_selftestOk)
      return INIT_FAILED;

   // Real floors, cooldown, and profit state are not known until OnTick.
   // Publish a coherent fail-closed STARTUP block first. The first OnTick
   // replaces it with ComputeVeto()/ComputeFlattenReason(). A stale or missing
   // snapshot still fail-opens in the trading EAs.
   Publish(MEG_VETO_STARTUP, MEG_VETO_OK);
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

// A floor flatten that is no longer true must not keep attributing later
// closes. Protected positions that are still open clear that pending reason.
void ClearStaleFloorEpisodeReason()
  {
   if(!g_episodeActive)
      return;
   bool hardPending  = (StringFind(g_episodeEndReasonPending, "HARD_FLOOR") == 0);
   bool dailyPending = (StringFind(g_episodeEndReasonPending, "DAILY_FLOOR") == 0);
   if(!hardPending && !dailyPending)
      return;
   int openNow = 0;
   FleetFloatingTotal(openNow);
   if(openNow <= 0)
      return;
   bool hardActive  = (UseFlattenOnHardFloor && EquityAtOrBelowHardFloor());
   bool dailyActive = (UseFlattenOnDailyFloor && EquityAtOrBelowDailyFloor());
   if(hardPending && !hardActive)
     {
      Print("[G-MULTI] HARD_FLOOR flatten is no longer active and positions remain -- clearing stale episode reason");
      g_episodeEndReasonPending = "NATURAL";
      g_episodeReasonBoundStart = 0;
     }
   else if(dailyPending && !dailyActive)
     {
      Print("[G-MULTI] DAILY_FLOOR flatten is no longer active and positions remain -- clearing stale episode reason");
      g_episodeEndReasonPending = "NATURAL";
      g_episodeReasonBoundStart = 0;
     }
  }

void OnTick()
  {
   DetectWeekendGap();
   MaybeResetDailyFloor();

   if(UseEntryBarGate)
      MaybeRankAndPublishGate();
   else
      GlobalVariableSet(GGATE_VAR_PRI_COUNT, 0.0); // gate off: heartbeat must not keep an old ranking alive

   MegProcessCooldownQueue();  // before the veto, so a loss that already closed arms this tick
   int veto = ComputeVeto();
   int flattenReason = ComputeFlattenReason();
   Publish(veto, flattenReason);
   MaybeFlatten(flattenReason);
   ClearStaleFloorEpisodeReason();
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
