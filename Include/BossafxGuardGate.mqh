//+------------------------------------------------------------------+
//| BossafxGuardGate.mqh                                              |
//| Shared helpers for: (1) Guard's 1-per-bar PF-priority entry gate, |
//|                      (2) closure-reason comment tagging           |
//| Added 2026-10-05. Included identically by all 5 protected EAs     |
//| (bot1_regime2.0/2.1, test4_clean_HYBRID_v52, bot4_TREND_FX_v1_49) |
//| and by EA_G_PortfolioGuard_MultiEA itself.                        |
//+------------------------------------------------------------------+
#property strict

// --- Shared GlobalVariable names (terminal-wide, so must be unique) ---
// 2026-10-05 (v2): replaced the single-winner "GGATE_VAR_MAGIC" scheme with a
// full PRIORITY ORDER + per-magic SIGNAL flags, so a lower-priority magic can
// still trade a bar when no higher-priority magic actually has a signal this
// bar (the original scheme blocked the whole bar even when its pre-computed
// "winner" never attempted to trade). GGATE_VAR_TIME is reused as the
// priority-list's freshness stamp.
#define GGATE_VAR_TIME        "BOSSAFX_GuardBarGate_BarTime"
#define GGATE_VAR_PRI_COUNT   "BOSSAFX_GuardPriority_Count"
#define GGATE_VAR_PRI_PREFIX  "BOSSAFX_GuardPriority_"   // + rank index 0..N-1 -> magic
#define GGATE_VAR_SIGNAL_PREFIX "BOSSAFX_GuardSignal_"   // + magic -> bar time it last signaled
#define GGATE_MAX_PRIORITY_SLOTS 13   // 2026-10-15 fix: was 10, but g_gateMagics now holds 13 entries
                                       // (grown over several deployments without this constant being
                                       // bumped) -- GGate_PublishPriority() silently truncated the
                                       // published list to the first 10 ranked magics every bar, so the
                                       // last 3 in g_gateMagics[] (whichever array-index lands beyond
                                       // slot 10 after ranking) were NEVER found in the published list
                                       // by GGate_ShouldOpen(), which fail-opens ("Guard doesn't know
                                       // this magic") whenever myRank stays -1. Confirmed live
                                       // 2026-10-15: MagicBot4_v49/MagicR22Pass6060/MagicWinrate3257
                                       // never appeared in any of today's "[G-MULTI] GATE priority_order="
                                       // log lines (only 10 magics printed, every single bar) -- these
                                       // 3 magics' 1-per-bar PF-priority gate has been a permanent
                                       // fail-open (i.e. completely inert) since whichever deployment
                                       // grew g_gateMagics past 10 entries, not something a .set flag
                                       // can fix (GGATE_MAX_PRIORITY_SLOTS is a compile-time #define).
#define GGATE_SIGNAL_TIMEFRAME PERIOD_M5   // shared "what is a bar" clock for signal flags

// --- Price-distance re-entry gate (2026-10-13, additive) ---
// Guard publishes the last fleet-wide entry price + its enabled/threshold inputs every tick;
// each protected EA reads these via GGate_PriceDistanceOk() right before OrderSend, same
// fail-open pattern as GGate_ShouldOpen above. Ships OFF (GGATE_VAR_DIST_ENABLED defaults to
// "not set" -> fail-open -> always allowed) until Guard's UsePriceDistanceGate input is flipped on.
#define GGATE_VAR_DIST_ENABLED   "BOSSAFX_GuardDistGate_Enabled"    // 1.0/0.0 -- mirrors UsePriceDistanceGate
#define GGATE_VAR_DIST_MINPTS    "BOSSAFX_GuardDistGate_MinPoints"  // mirrors MinReentryDistancePoints
#define GGATE_VAR_DIST_PRICE     "BOSSAFX_GuardDistGate_LastPrice"  // open price of the most recent fleet entry
#define GGATE_VAR_DIST_TIME      "BOSSAFX_GuardDistGate_LastTime"   // open time of that entry -- freshness stamp

// --- Per-direction loss-cooldown ENFORCEMENT gate (2026-10-13, additive) ---
// The Guard has published LOSS_COOLDOWN_UNTIL (blanket) since 2026-09-29, but no EA ever
// consumed it (confirmed: zero references in bot1_regime2.0/2.1 -- the Guard's own header docs
// this as "Phase 2, not yet wired"). Ships OFF (UseLossCooldownGate=false on the Guard) until
// watched for a while, same cautious pattern as the other two gates above.
#define GGATE_VAR_COOLDOWN_ENABLED "BOSSAFX_GuardCooldownGate_Enabled"  // 1.0/0.0 -- mirrors UseLossCooldownGate

// --- Fleet-wide same-instant pile-on gate (2026-10-14, additive) ---
// Problem this solves: the price-distance gate above reads a snapshot that Guard refreshes once
// per tick -- when 2+ protected EAs evaluate the SAME bar close within the same second (every
// bot ticks independently off the same price feed), they can all read "nothing just opened yet",
// all pass, and all open together before Guard's next tick updates the snapshot for anyone.
// Confirmed live 2026-10-14: 16 separate clusters of 2-6 different magics opening at the exact
// same minute+price despite the distance gate being ON.
//
// Fix: instead of routing through Guard's once-per-tick snapshot, each protected EA stamps a
// SHARED "an open just happened" GlobalVariable the INSTANT its own trade.PositionOpen() call
// returns true -- no waiting for Guard's next tick. Every EA (including the one that just
// stamped it) checks this stamp before its NEXT open attempt. This is a short fleet-wide lock,
// not a queue: the first EA through still opens immediately; everyone else is blocked for
// GGATE_FLEET_OPEN_COOLDOWN_SEC regardless of direction, magic, or price distance. Per explicit
// user decision (2026-10-14): fleet-wide (not just within correlated pairs), 10 seconds.
//
// Enable-flag published by Guard every tick (same split pattern as the other two gates: Guard
// owns the on/off input, consumers fail-open if Guard isn't running or the feature is off).
// The timestamp itself is written directly by whichever protected EA opens -- NOT by Guard --
// because Guard's own tick is exactly the latency this feature exists to route around.
#define GGATE_VAR_FLEETOPEN_ENABLED "BOSSAFX_GuardFleetOpenGate_Enabled"  // 1.0/0.0 -- mirrors UseFleetOpenCooldownGate
#define GGATE_VAR_FLEETOPEN_SEC     "BOSSAFX_GuardFleetOpenGate_Seconds"  // mirrors FleetOpenCooldownSeconds
#define GGATE_VAR_FLEETOPEN_TIME    "BOSSAFX_GuardFleetOpenGate_LastOpenTime"  // TimeCurrent() stamped by whichever EA opened last

// --- Closure-reason short codes (kept <=4 chars: comment budget is tight) ---
#define GGATE_REASON_TP1   "TP1"
#define GGATE_REASON_TP2   "TP2"
#define GGATE_REASON_SL    "SL"
#define GGATE_REASON_TSL   "TSL"
#define GGATE_REASON_GRD   "GRD"   // closed by Portfolio Guard (hard floor / daily floor / profit target)
#define GGATE_REASON_FCT   "FCT"   // closed by UseFinalCloseTarget mechanism
#define GGATE_REASON_MAN   "MAN"   // manual / other / unclassified

//+------------------------------------------------------------------+
//| GGate_CurrentSignalBar: the shared "what bar is it" clock used by |
//| the signal-flag side of the gate (independent of each EA's own    |
//| chart period or Guard's own ranking cadence).                     |
//+------------------------------------------------------------------+
datetime GGate_CurrentSignalBar()
  {
   return iTime(_Symbol, GGATE_SIGNAL_TIMEFRAME, 0);
  }

//+------------------------------------------------------------------+
//| GGate_PublishSignal: called by a protected EA the instant it has  |
//| a real signal and is about to open, so OTHER (lower-priority)     |
//| EAs can see "magic X wants to trade this bar" before deciding      |
//| whether they're allowed to proceed instead.                       |
//+------------------------------------------------------------------+
void GGate_PublishSignal(const int magic)
  {
   GlobalVariableSet(GGATE_VAR_SIGNAL_PREFIX + IntegerToString(magic), (double)GGate_CurrentSignalBar());
  }

//+------------------------------------------------------------------+
//| GGate_HasSignaledThisBar: did `magic` publish a signal for the     |
//| given bar? Used by lower-priority EAs to check whether any higher-|
//| priority magic is also trying to trade this same bar.             |
//+------------------------------------------------------------------+
bool GGate_HasSignaledThisBar(const int magic, const datetime barTime)
  {
   string varName = GGATE_VAR_SIGNAL_PREFIX + IntegerToString(magic);
   if(!GlobalVariableCheck(varName))
      return false;
   return ((datetime)GlobalVariableGet(varName) == barTime);
  }

//+------------------------------------------------------------------+
//| GGate_ShouldOpen: entry-side check, called by each protected EA   |
//| immediately before its OrderSend (i.e. only when it already has   |
//| a real signal). v2 (2026-10-05): priority-list + signal-flag       |
//| scheme -- allows a lower-priority magic to trade a bar when no     |
//| higher-priority magic has ALSO signaled this same bar, instead of  |
//| blocking the whole bar for a single pre-computed "winner" that     |
//| might never actually attempt to trade. Fail-open semantics         |
//| preserved throughout: if Guard isn't running, hasn't published     |
//| yet, or doesn't know this magic at all, this returns true so the   |
//| EA behaves exactly as it did before this feature existed.          |
//|                                                                    |
//| myMagic      : this EA's own MagicNumber                          |
//| staleSeconds : how old a priority publish can be before it's       |
//|                 treated as Guard-not-running (fail-open).          |
//+------------------------------------------------------------------+
bool GGate_ShouldOpen(const int myMagic, const int staleSeconds = 400)
  {
   datetime curBar = GGate_CurrentSignalBar();
   GGate_PublishSignal(myMagic); // always publish -- this call means "I have a signal right now"

   if(!GlobalVariableCheck(GGATE_VAR_PRI_COUNT) || !GlobalVariableCheck(GGATE_VAR_TIME))
      return true; // Guard not running / hasn't published yet -- fail-open

   datetime gateTime = (datetime)GlobalVariableGet(GGATE_VAR_TIME);
   if(gateTime <= 0 || (TimeCurrent() - gateTime) > staleSeconds)
      return true; // stale publish (Guard stopped updating) -- fail-open

   int count = (int)GlobalVariableGet(GGATE_VAR_PRI_COUNT);
   if(count <= 0)
      return true; // Guard published "nobody eligible" sentinel -- fail-open

   int ranked[];
   ArrayResize(ranked, count);
   int myRank = -1;
   for(int i = 0; i < count; i++)
     {
      string varName = GGATE_VAR_PRI_PREFIX + IntegerToString(i);
      ranked[i] = GlobalVariableCheck(varName) ? (int)GlobalVariableGet(varName) : 0;
      if(ranked[i] == myMagic)
         myRank = i;
     }

   if(myRank < 0)
      return true; // Guard doesn't know this magic (not in its protected list) -- fail-open

   // Block only if a STRICTLY higher-priority magic has also signaled this exact bar.
   for(int i = 0; i < myRank; i++)
     {
      if(ranked[i] == 0)
         continue;
      if(GGate_HasSignaledThisBar(ranked[i], curBar))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| GGate_PublishPriority: Guard-side, called once per new bar after  |
//| it has ranked all protected magics by live PF. Publishes the FULL |
//| rank order (index 0 = highest priority), not just a single        |
//| winner, so GGate_ShouldOpen can fall back down the list when a     |
//| higher-priority magic has no signal this bar.                      |
//+------------------------------------------------------------------+
void GGate_PublishPriority(const int &rankedMagics[], const int count)
  {
   int n = MathMin(count, GGATE_MAX_PRIORITY_SLOTS);
   GlobalVariableSet(GGATE_VAR_PRI_COUNT, (double)n);
   for(int i = 0; i < n; i++)
      GlobalVariableSet(GGATE_VAR_PRI_PREFIX + IntegerToString(i), (double)rankedMagics[i]);
   GlobalVariableSet(GGATE_VAR_TIME, (double)TimeCurrent());
  }

//+------------------------------------------------------------------+
//| GGate_PublishDistanceState: Guard-side, called every tick with    |
//| whatever it currently knows about the most recently opened fleet  |
//| position (price=0/time=0 if nothing is open). Also publishes its  |
//| own enabled flag + threshold so every EA reads the SAME live      |
//| values without needing its own copy of those inputs.              |
//+------------------------------------------------------------------+
void GGate_PublishDistanceState(const bool enabled, const int minPoints,
                                 const double lastPrice, const datetime lastTime)
  {
   GlobalVariableSet(GGATE_VAR_DIST_ENABLED, enabled ? 1.0 : 0.0);
   GlobalVariableSet(GGATE_VAR_DIST_MINPTS, (double)minPoints);
   GlobalVariableSet(GGATE_VAR_DIST_PRICE, lastPrice);
   GlobalVariableSet(GGATE_VAR_DIST_TIME, (double)lastTime);
  }

//+------------------------------------------------------------------+
//| GGate_PriceDistanceOk: entry-side check, called by each protected |
//| EA immediately before its OrderSend, same spot as GGate_ShouldOpen|
//| above. Blocks a new entry when the current price is within        |
//| MinReentryDistancePoints of the most recent fleet-wide entry       |
//| (any protected magic, either direction -- per 2026-10-13 decision) |
//| -- prevents piling multiple positions at the same level. Fail-open|
//| throughout: Guard not running / feature off / nothing open yet /  |
//| stale publish all return true so this never blocks a trade unless |
//| the feature is deliberately enabled and actively publishing.      |
//+------------------------------------------------------------------+
bool GGate_PriceDistanceOk(const int staleSeconds = 400)
  {
   if(!GlobalVariableCheck(GGATE_VAR_DIST_ENABLED))
      return true; // Guard not running this feature / older Guard build -- fail-open

   if(GlobalVariableGet(GGATE_VAR_DIST_ENABLED) < 0.5)
      return true; // UsePriceDistanceGate=false on the Guard -- fail-open (feature off)

   if(!GlobalVariableCheck(GGATE_VAR_DIST_TIME))
      return true; // Guard hasn't published yet -- fail-open

   datetime lastTime = (datetime)GlobalVariableGet(GGATE_VAR_DIST_TIME);
   if(lastTime <= 0)
      return true; // nothing open fleet-wide yet -- nothing to measure against

   // Guard publishes every tick while running; lastTime is the fleet POSITION's open time, which
   // can legitimately be old (a position opened hours ago and still held) -- that is NOT
   // staleness. Use a separate "Guard is alive" signal instead: GGATE_VAR_TIME from the bar-gate
   // publish, which Guard updates every tick it runs regardless of this feature. If THAT is
   // stale, Guard itself is down -- fail-open. If only lastTime (the position's open time) is
   // old, the position is just old -- keep gating normally.
   if(!GlobalVariableCheck(GGATE_VAR_TIME) ||
      (TimeCurrent() - (datetime)GlobalVariableGet(GGATE_VAR_TIME)) > staleSeconds)
      return true; // Guard itself appears stopped -- fail-open

   if(!GlobalVariableCheck(GGATE_VAR_DIST_PRICE) || !GlobalVariableCheck(GGATE_VAR_DIST_MINPTS))
      return true; // incomplete publish -- fail-open

   double lastPrice = GlobalVariableGet(GGATE_VAR_DIST_PRICE);
   if(lastPrice <= 0)
      return true; // nothing open fleet-wide yet

   int minPoints = (int)GlobalVariableGet(GGATE_VAR_DIST_MINPTS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0)
      return true; // can't compute -- fail-open rather than divide by zero

   double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID); // mid-ish reference, matches basket-SL's use of position data
   double distancePoints = MathAbs(curPrice - lastPrice) / point;

   return (distancePoints >= minPoints);
  }

//+------------------------------------------------------------------+
//| GGate_LossCooldownOk: entry-side check, called by each protected  |
//| EA immediately before its OrderSend, same spot as the other gates |
//| above. Reads the Guard's per-direction loss-cooldown GlobalVars   |
//| directly (Guard's MegGvName() namespacing: "MEG_" + _Symbol +     |
//| "_LOSS_COOLDOWN_UNTIL_BUY"/"_SELL", written in OnTradeTransaction  |
//| alongside the pre-existing fleet-wide blanket flag). Only the     |
//| direction that just took a loss is blocked -- a fresh signal in   |
//| the OPPOSITE direction is unaffected, narrower than the Guard's   |
//| original blanket MEG_..._BLOCK_NEW flag (which is still published |
//| unchanged for the Guard's own status display/other consumers).   |
//| Fail-open: Guard not running / UseLossCooldown=false / no cooldown|
//| published yet all return true, same pattern as every other gate.  |
//+------------------------------------------------------------------+
bool GGate_LossCooldownOk(const ENUM_POSITION_TYPE dir)
  {
   if(!GlobalVariableCheck(GGATE_VAR_COOLDOWN_ENABLED))
      return true; // Guard not running this feature / older Guard build -- fail-open

   if(GlobalVariableGet(GGATE_VAR_COOLDOWN_ENABLED) < 0.5)
      return true; // UseLossCooldownGate=false on the Guard -- fail-open (feature off)

   string key = (dir == POSITION_TYPE_BUY) ? "MEG_" + _Symbol + "_LOSS_COOLDOWN_UNTIL_BUY"
                                            : "MEG_" + _Symbol + "_LOSS_COOLDOWN_UNTIL_SELL";
   if(!GlobalVariableCheck(key))
      return true; // no loss recorded yet this direction -- fail-open

   datetime until = (datetime)GlobalVariableGet(key);
   return (TimeCurrent() >= until);
  }

//+------------------------------------------------------------------+
//| GGate_FleetOpenCooldownOk: entry-side check, called by each        |
//| protected EA immediately before its OrderSend, same spot as the    |
//| other gates above. Blocks a new entry when ANY protected magic     |
//| opened within the last N seconds (fleet-wide, any direction) --    |
//| catches the same-instant pile-on race the price-distance gate      |
//| cannot (that gate's snapshot only refreshes once per Guard tick).  |
//| Fail-open: Guard not running / feature off / nothing stamped yet   |
//| all return true, same pattern as every other gate.                 |
//+------------------------------------------------------------------+
bool GGate_FleetOpenCooldownOk()
  {
   if(!GlobalVariableCheck(GGATE_VAR_FLEETOPEN_ENABLED))
      return true; // Guard not running this feature / older Guard build -- fail-open

   if(GlobalVariableGet(GGATE_VAR_FLEETOPEN_ENABLED) < 0.5)
      return true; // UseFleetOpenCooldownGate=false on the Guard -- fail-open (feature off)

   if(!GlobalVariableCheck(GGATE_VAR_FLEETOPEN_TIME))
      return true; // nobody has opened fleet-wide yet since this feature went live

   datetime lastOpen = (datetime)GlobalVariableGet(GGATE_VAR_FLEETOPEN_TIME);
   if(lastOpen <= 0)
      return true;

   int cooldownSec = GlobalVariableCheck(GGATE_VAR_FLEETOPEN_SEC)
                      ? (int)GlobalVariableGet(GGATE_VAR_FLEETOPEN_SEC) : 10;

   return (TimeCurrent() - lastOpen >= cooldownSec);
  }

//+------------------------------------------------------------------+
//| GGate_StampFleetOpen: called by each protected EA immediately      |
//| AFTER its own trade.PositionOpen() returns true (success only --   |
//| a failed/rejected attempt must NOT stamp the lock). Writes the     |
//| timestamp directly rather than waiting for Guard's next tick --    |
//| that latency gap is exactly what let same-instant races through.   |
//| Harmless no-op cost when the feature is off (one extra            |
//| GlobalVariableSet call); the ENABLED flag still gates whether      |
//| GGate_FleetOpenCooldownOk() actually blocks on it.                  |
//+------------------------------------------------------------------+
void GGate_StampFleetOpen()
  {
   GlobalVariableSet(GGATE_VAR_FLEETOPEN_TIME, (double)TimeCurrent());
  }

//+------------------------------------------------------------------+
//| GGate_BuildCloseComment: produces a close-side comment tagged     |
//| with a reason code, respecting MT5's hard 31-char comment cap.    |
//| Truncates the free-text tail first; NEVER truncates the magic     |
//| number or the reason code themselves (both are needed to recover  |
//| attribution later -- see the 2026-10 31-char truncation bug that  |
//| cost a magic's worth of live P&L attribution once already).       |
//|                                                                    |
//| magic      : the position's magic number                          |
//| reasonCode : one of the GGATE_REASON_* constants above             |
//| freeText   : optional extra tag (e.g. "Stage", "MeanRev") -- will  |
//|              be shortened or dropped entirely if it doesn't fit    |
//+------------------------------------------------------------------+
string GGate_BuildCloseComment(const long magic, const string reasonCode, const string freeText = "")
  {
   string magicPart  = IntegerToString(magic);
   string reasonPart = reasonCode;
   string fixed = magicPart + "|" + reasonPart; // always-present part, e.g. "54511|TP1"
   int budget = 31 - StringLen(fixed);
   if(freeText == "" || budget <= 1)
      return fixed;
   string tail = freeText;
   if(StringLen(tail) > budget - 1) // -1 for the separating "|"
      tail = StringSubstr(tail, 0, MathMax(0, budget - 1));
   if(StringLen(tail) == 0)
      return fixed;
   return fixed + "|" + tail;
  }

//+------------------------------------------------------------------+
//| GGate_CloseTagged: replacement for trade.PositionClose() that     |
//| also stamps a reason-coded comment on the closing deal. CTrade's  |
//| own PositionClose() has no comment parameter (MT5 API limitation),|
//| so this builds the MqlTradeRequest manually (TRADE_ACTION_DEAL,   |
//| opposite order type, full position volume, deviation copied from  |
//| the passed CTrade's own setting). Falls back to a plain            |
//| trade.PositionClose() (no tag) if OrderSend itself fails, so a     |
//| logging feature can never prevent a real close from happening.    |
//+------------------------------------------------------------------+
bool GGate_CloseTagged(CTrade &tradeObj, const ulong ticket, const string reasonCode, const string freeText = "")
  {
   ulong dummyDeal = 0;
   return GGate_CloseTagged(tradeObj, ticket, reasonCode, dummyDeal, freeText);
  }

bool GGate_CloseTagged(CTrade &tradeObj, const ulong ticket, const string reasonCode, ulong &outDealTicket, const string freeText = "")
  {
   outDealTicket = 0;
   if(!PositionSelectByTicket(ticket))
      return false;

   long   magic   = PositionGetInteger(POSITION_MAGIC);
   string symbol  = PositionGetString(POSITION_SYMBOL);
   double volume  = PositionGetDouble(POSITION_VOLUME);
   long   posType = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol   = symbol;
   request.volume   = volume;
   request.magic    = magic;
   request.deviation = 50; // points -- matches the project's standing slippage-tolerance convention
   request.type_filling = ORDER_FILLING_IOC;
   request.comment  = GGate_BuildCloseComment(magic, reasonCode, freeText);

   if(posType == POSITION_TYPE_BUY)
     {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
     }
   else
     {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
     }

   if(!OrderSend(request, result))
     {
      bool fallbackOk = tradeObj.PositionClose(ticket); // fail-safe: untagged close beats no close at all
      outDealTicket = tradeObj.ResultDeal();
      return fallbackOk;
     }

   outDealTicket = result.deal;
   return (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED
           || result.retcode == TRADE_RETCODE_DONE_PARTIAL);
  }

//+------------------------------------------------------------------+
//| GGate_ClosePartialTagged: same idea for PositionClosePartial().   |
//+------------------------------------------------------------------+
bool GGate_ClosePartialTagged(CTrade &tradeObj, const ulong ticket, const double volumeToClose,
                               const string reasonCode, const string freeText = "")
  {
   ulong dummyDeal = 0;
   return GGate_ClosePartialTagged(tradeObj, ticket, volumeToClose, reasonCode, dummyDeal, freeText);
  }

bool GGate_ClosePartialTagged(CTrade &tradeObj, const ulong ticket, const double volumeToClose,
                               const string reasonCode, ulong &outDealTicket, const string freeText = "")
  {
   outDealTicket = 0;
   if(!PositionSelectByTicket(ticket))
      return false;

   long   magic   = PositionGetInteger(POSITION_MAGIC);
   string symbol  = PositionGetString(POSITION_SYMBOL);
   long   posType = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol   = symbol;
   request.volume   = volumeToClose;
   request.magic    = magic;
   request.deviation = 50;
   request.type_filling = ORDER_FILLING_IOC;
   request.comment  = GGate_BuildCloseComment(magic, reasonCode, freeText);

   if(posType == POSITION_TYPE_BUY)
     {
      request.type  = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
     }
   else
     {
      request.type  = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
     }

   if(!OrderSend(request, result))
     {
      bool fallbackOk = tradeObj.PositionClosePartial(ticket, volumeToClose); // fail-safe: untagged beats not closing
      outDealTicket = tradeObj.ResultDeal();
      return fallbackOk;
     }

   outDealTicket = result.deal;
   return (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED
           || result.retcode == TRADE_RETCODE_DONE_PARTIAL);
  }

//+------------------------------------------------------------------+
//| GGate_RankIsWorse: true if candidate (a) should rank AFTER (b) --  |
//| i.e. b is better-or-equal priority than a. Below-floor magics      |
//| always rank after at-or-above-floor magics; within the same        |
//| eligibility bucket, higher PF ranks first.                         |
//+------------------------------------------------------------------+
bool GGate_RankIsWorse(const int aMagic, const double aPf, const int aTrades,
                       const int bMagic, const double bPf, const int bTrades, const int minTrades)
  {
   bool aEligible = (aTrades >= minTrades);
   bool bEligible = (bTrades >= minTrades);
   if(aEligible != bEligible)
      return bEligible; // a is worse if a is NOT eligible but b IS
   return (bPf > aPf);
  }

//+------------------------------------------------------------------+
//| GGate_RankAndPublish: Guard-side. Computes live PF per magic from  |
//| closed-trade history (HistorySelect over a lookback window) for    |
//| each magic in the passed array, applies a minimum-trade floor      |
//| (magics under the floor rank last, by trade-count then PF, so a    |
//| 2-trade 100% win streak can never out-rank an established          |
//| performer -- but they're still RANKED, not dropped, since a        |
//| thin-sample magic should still get its bar if nobody above it      |
//| has a signal). Publishes the FULL rank order via                   |
//| GGate_PublishPriority (index 0 = highest priority). Call once per  |
//| new bar (the caller detects the bar rollover; this function does   |
//| no timeframe logic itself).                                        |
//+------------------------------------------------------------------+
void GGate_RankAndPublish(const int &magics[], const int minTrades, const datetime lookbackFrom)
  {
   int    nMagics = ArraySize(magics);
   int    rankedMagics[];
   double rankedPf[];
   int    rankedTrades[];
   ArrayResize(rankedMagics, nMagics);
   ArrayResize(rankedPf, nMagics);
   ArrayResize(rankedTrades, nMagics);

   bool haveHistory = HistorySelect(lookbackFrom, TimeCurrent());
   int total = haveHistory ? HistoryDealsTotal() : 0;

   for(int m = 0; m < nMagics; m++)
     {
      int    magic     = magics[m];
      int    nTrades   = 0;
      double grossWin  = 0.0;
      double grossLoss = 0.0;

      for(int i = 0; i < total; i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != magic)
            continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT
            && HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY)
            continue; // only count realized closes, not opens

         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                        + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                        + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         nTrades++;
         if(profit >= 0)
            grossWin  += profit;
         else
            grossLoss += MathAbs(profit);
        }

      double pf;
      if(grossLoss <= 0.0)
         pf = (grossWin > 0.0) ? 999.0 : 0.0; // treat "no losses yet" as a high but finite PF, never a fake infinity
      else
         pf = grossWin / grossLoss;

      rankedMagics[m]  = magic;
      rankedPf[m]      = pf;
      rankedTrades[m]  = nTrades;
     }

   // Sort descending: magics that CLEAR minTrades first (by PF desc), then
   // magics below the trade-count floor last (by PF desc among themselves).
   // Simple insertion sort -- nMagics is always small (<=10).
   for(int i = 1; i < nMagics; i++)
     {
      int    mMagic  = rankedMagics[i];
      double mPf     = rankedPf[i];
      int    mTrades = rankedTrades[i];
      int j = i - 1;
      while(j >= 0 && GGate_RankIsWorse(rankedMagics[j], rankedPf[j], rankedTrades[j], mMagic, mPf, mTrades, minTrades))
        {
         rankedMagics[j+1] = rankedMagics[j];
         rankedPf[j+1]     = rankedPf[j];
         rankedTrades[j+1] = rankedTrades[j];
         j--;
        }
      rankedMagics[j+1] = mMagic;
      rankedPf[j+1]     = mPf;
      rankedTrades[j+1] = mTrades;
     }

   GGate_PublishPriority(rankedMagics, nMagics);
  }
