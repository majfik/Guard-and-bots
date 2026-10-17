//+------------------------------------------------------------------+
//| BossafxGuardGate.mqh                                              |
//| Shared helpers for: (1) Guard's 1-per-bar PF-priority entry gate, |
//|                      (2) closure-reason comment tagging           |
//| Added 2026-10-05. Included identically by all 5 protected EAs     |
//| (bot1_regime2.0/2.1, test4_clean_HYBRID_v52, bot4_TREND_FX_v1_49) |
//| and by EA_G_PortfolioGuard_MultiEA itself.                        |
//+------------------------------------------------------------------+
#ifndef BOSSAFX_GUARD_GATE_MQH
#define BOSSAFX_GUARD_GATE_MQH
#property strict

// --- Shared GlobalVariable names (terminal-wide, so must be unique) ---
// 2026-10-05 (v2): replaced the single-winner "GGATE_VAR_MAGIC" scheme with a
// full PRIORITY ORDER + per-magic SIGNAL flags, so a lower-priority magic can
// still trade a bar when no higher-priority magic actually has a signal this
// bar (the original scheme blocked the whole bar even when its pre-computed
// "winner" never attempted to trade).
//
// GGATE_VAR_TIME is ONLY the priority-list publish stamp (once per GateTimeframe
// bar). It is not a liveness signal. Production GateTimeframe is M30 (1800s);
// treating this stamp as "Guard alive" with a 400s stale window fail-opened the
// gate for most of every bar. Liveness and the publication sequence are
// symbol-scoped (one Guard per symbol). Two symbols must not tear each
// other's snapshot. A missing, odd, or stale symbol snapshot still fail-opens.
// The unsuffixed names are legacy; the first publication copies them into
// the symbol key when that key is absent.
#define GGATE_VAR_TIME        "BOSSAFX_GuardBarGate_BarTime"
#define GGATE_VAR_PRI_COUNT   "BOSSAFX_GuardPriority_Count"
#define GGATE_VAR_PRI_PREFIX  "BOSSAFX_GuardPriority_"   // + rank index 0..N-1 -> magic
#define GGATE_VAR_SIGNAL_PREFIX "BOSSAFX_GuardSignal_"   // + magic -> bar time it last signaled
#define GGATE_VAR_HEARTBEAT   "BOSSAFX_GuardHeartbeat"   // prefix; live key is prefix + "_" + symbol
#define GGATE_VAR_PUBSEQ      "BOSSAFX_GuardPubSeq"      // prefix; odd = in progress, even = complete
// Read-side bound only. Publish writes the full ranked array (no slot cap).
// A published count outside 1..this is corrupt and fail-opens.
#define GGATE_PRIORITY_COUNT_SANITY_MAX 64
#define GGATE_SIGNAL_TIMEFRAME PERIOD_M5   // shared "what is a bar" clock for signal flags

// Close outcome returned by GGate_CloseTaggedEx / GGate_ClosePartialTaggedEx /
// GGate_CloseVolumeCore. outFilled always carries the volume executed by THIS
// result (never volume already reported by an earlier call).
#define GGATE_CLOSE_NONE      0   // nothing executed and nothing working: safe to retry the same amount
#define GGATE_CLOSE_PARTIAL   1   // some of the requested volume executed (outFilled > 0), rest did not
#define GGATE_CLOSE_FULL      2   // the whole requested volume executed
#define GGATE_CLOSE_PENDING   3   // a close order is working on the server: do NOT send another
#define GGATE_CLOSE_REJECTED_ -1  // internal only: send rejected, emergency fallback allowed
#define GGATE_CLOSE_AMBIGUOUS -2  // internal only: timeout/connection; observe, do not fallback
#define GGATE_VOLUME_EPS      1e-8

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
//| True only on a retail hedging account. One implementation so the  |
//| Guard and the trading EAs cannot drift.                           |
//+------------------------------------------------------------------+
bool GGate_IsHedgingAccount()
  {
   return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

//+------------------------------------------------------------------+
//| OnInit helper. Prints a clear error and returns false when the    |
//| account is not hedging. Caller must return INIT_FAILED.           |
//+------------------------------------------------------------------+
bool GGate_RequireHedgingAccount()
  {
   if(GGate_IsHedgingAccount())
      return true;
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   Print("[GGATE] INIT FAILED: hedging account required, but ACCOUNT_MARGIN_MODE=",
         EnumToString(mode), " (", (int)mode,
         "). Netting and exchange accounts are not supported.");
   return false;
  }

//+------------------------------------------------------------------+
//| Guard-alive stamp. Guard calls this on every OnTick. Consumers    |
//| use GGate_HeartbeatFresh(); they must not treat GGATE_VAR_TIME    |
//| (rank publish, once per GateTimeframe bar) as liveness.           |
//+------------------------------------------------------------------+
string GGate_SymbolGv(const string base)
  {
   return base + "_" + _Symbol;
  }

// Copy a pre-symbol key once. Never overwrites a key this symbol already has.
void GGate_MigrateLegacyGv(const string scoped, const string legacy)
  {
   if(GlobalVariableCheck(scoped))
      return;
   if(!GlobalVariableCheck(legacy))
      return;
   GlobalVariableSet(scoped, GlobalVariableGet(legacy));
  }

void GGate_PublishHeartbeat()
  {
   string name = GGate_SymbolGv(GGATE_VAR_HEARTBEAT);
   GGate_MigrateLegacyGv(name, GGATE_VAR_HEARTBEAT);
   GlobalVariableSet(name, (double)TimeCurrent());
  }

// Odd sequence: a publication has started and its variables may be torn.
// Even sequence: the last publication finished. Heartbeat is written only
// from GGate_PublishEnd, after the even value, so a fresh heartbeat means
// a completed snapshot for THIS symbol.
void GGate_PublishBegin()
  {
   string name = GGate_SymbolGv(GGATE_VAR_PUBSEQ);
   GGate_MigrateLegacyGv(name, GGATE_VAR_PUBSEQ);
   double cur = GlobalVariableCheck(name) ? GlobalVariableGet(name) : 0.0;
   long seq = (long)cur;
   if(seq < 0)
      seq = 0;
   if((seq % 2) != 0)
      seq++;
   GlobalVariableSet(name, (double)(seq + 1));
  }

void GGate_PublishEnd()
  {
   string name = GGate_SymbolGv(GGATE_VAR_PUBSEQ);
   double cur = GlobalVariableCheck(name) ? GlobalVariableGet(name) : 1.0;
   long seq = (long)cur;
   if((seq % 2) == 0)
      seq++;
   GlobalVariableSet(name, (double)(seq + 1));
   GGate_PublishHeartbeat();
  }

bool GGate_PubSeqEven(double &seq)
  {
   string name = GGate_SymbolGv(GGATE_VAR_PUBSEQ);
   if(!GlobalVariableCheck(name))
      return false;
   seq = GlobalVariableGet(name);
   long s = (long)seq;
   if(s <= 0)
      return false;
   return ((s % 2) == 0);
  }

bool GGate_HeartbeatFresh(const int staleSeconds)
  {
   if(staleSeconds < 0)
      return false;
   string name = GGate_SymbolGv(GGATE_VAR_HEARTBEAT);
   if(!GlobalVariableCheck(name))
      return false;
   datetime hb = (datetime)GlobalVariableGet(name);
   if(hb <= 0)
      return false;
   return ((TimeCurrent() - hb) <= staleSeconds);
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
//| staleSeconds : how old the Guard heartbeat can be before it's      |
//|                 treated as Guard-not-running (fail-open). The       |
//|                 priority list itself stays valid across the whole   |
//|                 GateTimeframe bar; only a missing/stale heartbeat   |
//|                 fail-opens.                                         |
//+------------------------------------------------------------------+
bool GGate_ShouldOpen(const int myMagic, const int staleSeconds = 400)
  {
   datetime curBar = GGate_CurrentSignalBar();
   GGate_PublishSignal(myMagic); // always publish -- this call means "I have a signal right now"

   // Heartbeat, not the rank-publish stamp. A fresh heartbeat with an M30-old
   // priority list is normal; a missing/stale heartbeat means Guard is down.
   if(!GGate_HeartbeatFresh(staleSeconds))
      return true;

   if(!GlobalVariableCheck(GGATE_VAR_PRI_COUNT))
      return true; // Guard hasn't published a ranking yet -- fail-open

   int count = (int)GlobalVariableGet(GGATE_VAR_PRI_COUNT);
   // <=0: feature off or "nobody eligible". Above the sanity max: corrupt
   // publish -- do not ArrayResize to it and do not gate on a truncated prefix.
   if(count <= 0 || count > GGATE_PRIORITY_COUNT_SANITY_MAX)
      return true;

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
   // Publish the whole ranked array. Cap only to the array that was actually
   // passed so we never read off the end -- this is not a priority-slot cap.
   int available = ArraySize(rankedMagics);
   int n = count;
   if(n < 0)
      n = 0;
   if(n > available)
      n = available;
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

   // lastTime is the fleet POSITION's open time, which can legitimately be old
   // (a position opened hours ago and still held) -- that is NOT staleness.
   // Liveness is the per-tick heartbeat, not the GateTimeframe rank stamp.
   // Missing/stale heartbeat: Guard is down -- fail-open. Old lastTime alone
   // means the position is old -- keep gating.
   if(!GGate_HeartbeatFresh(staleSeconds))
      return true;

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
//| "_LOSS_COOLDOWN_UNTIL_BUY"/"_SELL"). Only that direction is        |
//| blocked by this check. It does not narrow MEG_<symbol>_BLOCK_NEW. |
//| Fail-open when BOSSAFX_GuardCooldownGate_Enabled is missing or    |
//| below 0.5, or the direction key is absent. This function does not |
//| read UseLossCooldown and does not clear BLOCK_NEW. A fresh        |
//| STARTUP publication is a separate fail-closed BLOCK_NEW. A stale  |
//| or missing Guard snapshot still fail-opens in GGate_EntryBlocked. |
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

// --- Guard entry block (BLOCK_NEW / VETO). Numeric values match     ---
// EA_G_PortfolioGuard_MultiEA's MEG_VETO_* publish. FLAT_REQ is not  ---
// read here and must not be wired into a trading EA.                 ---
#define GGATE_VETO_OK             0
#define GGATE_VETO_HARD_FLOOR   101
#define GGATE_VETO_DAILY_FLOOR  102
#define GGATE_VETO_LOSS_COOLDOWN 103
#define GGATE_VETO_GAP_BLOCK     104
#define GGATE_VETO_FRIDAY        105
#define GGATE_VETO_PROFIT_TARGET 106
#define GGATE_VETO_STARTUP       107

string GGate_MegVar(const string symbol, const string key)
  {
   return "MEG_" + symbol + "_" + key;
  }

string GGate_EntryVetoText(const int veto)
  {
   switch(veto)
     {
      case GGATE_VETO_OK:             return "OK";
      case GGATE_VETO_HARD_FLOOR:     return "HARD_FLOOR";
      case GGATE_VETO_DAILY_FLOOR:    return "DAILY_FLOOR";
      case GGATE_VETO_LOSS_COOLDOWN:  return "LOSS_COOLDOWN";
      case GGATE_VETO_GAP_BLOCK:      return "GAP_BLOCK";
      case GGATE_VETO_FRIDAY:         return "FRIDAY";
      case GGATE_VETO_PROFIT_TARGET:  return "PROFIT_TARGET";
      case GGATE_VETO_STARTUP:        return "STARTUP";
      default:                        return "VETO_" + IntegerToString(veto);
     }
  }

//+------------------------------------------------------------------+
//| One coherent snapshot of MEG_<symbol>_BLOCK_NEW and _VETO.        |
//| Requires the same even publication sequence before and after the  |
//| pair, plus a fresh heartbeat. An odd sequence means a publication |
//| is in progress (torn). Missing or stale state is not a snapshot   |
//| (caller fail-opens). Does not read FLAT_REQ.                      |
//|                                                                    |
//| BLOCK_NEW is the blanket brake for every non-OK Guard veto        |
//| (startup, loss cooldown, gap, Friday, floors, profit target).     |
//| UseLossCooldown decides whether the cooldown veto is published.   |
//| UseLossCooldownGate is only the directional consumer and does not |
//| narrow BLOCK_NEW. A missing or stale snapshot still fail-opens.   |
//+------------------------------------------------------------------+
bool GGate_ReadEntryBlock(double &blockNew, double &veto, const int staleSeconds)
  {
   blockNew = 0.0;
   veto = 0.0;
   double seqBefore = 0.0;
   if(!GGate_PubSeqEven(seqBefore))
      return false;
   if(!GGate_HeartbeatFresh(staleSeconds))
      return false;
   string blockName = GGate_MegVar(_Symbol, "BLOCK_NEW");
   string vetoName  = GGate_MegVar(_Symbol, "VETO");
   if(!GlobalVariableCheck(blockName) || !GlobalVariableCheck(vetoName))
      return false;
   blockNew = GlobalVariableGet(blockName);
   veto     = GlobalVariableGet(vetoName);
   double seqAfter = 0.0;
   if(!GGate_PubSeqEven(seqAfter))
      return false;
   if(seqBefore != seqAfter)
      return false;
   if(!GGate_HeartbeatFresh(staleSeconds))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Final pre-order Guard block. Returns true when the order may be   |
//| sent. Missing/stale/torn Guard state fail-opens (returns true,    |
//| outVeto=0, outReason explains why it was not trusted). A coherent |
//| fresh BLOCK_NEW >= 0.5 returns false and fills outVeto/outReason  |
//| from the published VETO so the EA can log the exact brake. One    |
//| retry covers a heartbeat that moved during the first read.        |
//+------------------------------------------------------------------+
bool GGate_GuardEntryAllowed(int &outVeto, string &outReason, const int staleSeconds = 400)
  {
   outVeto = GGATE_VETO_OK;
   outReason = "FAIL_OPEN";
   double blockNew = 0.0;
   double veto = 0.0;
   bool coherent = false;
   for(int attempt = 0; attempt < 2 && !coherent; attempt++)
      coherent = GGate_ReadEntryBlock(blockNew, veto, staleSeconds);
   if(!coherent)
     {
      if(!GGate_HeartbeatFresh(staleSeconds))
         outReason = "FAIL_OPEN_STALE_HEARTBEAT";
      else
         outReason = "FAIL_OPEN_TORN_OR_MISSING";
      return true;
     }
   if(blockNew < 0.5)
     {
      outReason = "ALLOWED";
      return true;
     }
   outVeto = (int)veto;
   outReason = GGate_EntryVetoText(outVeto);
   if(outVeto == GGATE_VETO_OK)
      outReason = "BLOCK_NEW";
   return false;
  }

// One logger for every entry path. `where` names the path (trend, countertrend, pyramid).
void GGate_LogEntryBlocked(const int magic, const string where, const int veto, const string reason)
  {
   Print("[GGATE-BLOCK] MN:", magic, " ", where,
         " skipped -- Guard BLOCK_NEW veto=", veto, " reason=", reason);
  }

// True when this entry must not be sent. Logs the exact veto. Fail-open
// (stale, torn, or missing Guard state) returns false so the order proceeds.
bool GGate_EntryBlocked(const int magic, const string where, const int staleSeconds = 400)
  {
   int veto = 0;
   string reason = "";
   if(GGate_GuardEntryAllowed(veto, reason, staleSeconds))
      return false;
   GGate_LogEntryBlocked(magic, where, veto, reason);
   return true;
  }

//+------------------------------------------------------------------+
//| OnInit staged-exit check. Prints nothing and changes nothing.     |
//| pointMode: TP2_Distance must be strictly greater than TP1.        |
//| rrMode: ExitRR_TP2R must be strictly greater than ExitRR_TP1R,    |
//|         and ExitRR_Close1Pct must be within 0..1.                 |
//| Close percents must be within 0..1. Trailing inputs must be       |
//| nonnegative. Max position counts must be >= 1. ctMax < 0 skips    |
//| the counter-trend count (the EA has no such input).               |
//| On failure, reason is an exact [GGATE] INIT FAILED message and    |
//| the caller must return INIT_FAILED without rewriting the inputs.  |
//+------------------------------------------------------------------+
bool GGate_ValidateStageConfig(const bool pointMode, const bool rrMode,
                               const int tp1Dist, const int tp2Dist,
                               const double tp1Pct, const double tp2Pct, const double rrClosePct,
                               const double rr1, const double rr2,
                               const int trailAct, const int trailDist,
                               const int maxBuy, const int maxSell, const int ctMax,
                               string &reason)
  {
   reason = "";
   if(tp1Pct < 0.0 || tp1Pct > 1.0)
     {
      reason = StringFormat("[GGATE] INIT FAILED: TP1_ClosePercent (%s) must be within 0..1",
                            DoubleToString(tp1Pct, 4));
      return false;
     }
   if(tp2Pct < 0.0 || tp2Pct > 1.0)
     {
      reason = StringFormat("[GGATE] INIT FAILED: TP2_ClosePercent (%s) must be within 0..1",
                            DoubleToString(tp2Pct, 4));
      return false;
     }
   if(pointMode && (tp1Dist < 0 || tp2Dist < 0 || tp2Dist <= tp1Dist))
     {
      reason = StringFormat("[GGATE] INIT FAILED: TP2_Distance (%d) must be greater than TP1_Distance (%d) in staged point mode",
                            tp2Dist, tp1Dist);
      return false;
     }
   if(rrMode)
     {
      if(rr1 < 0.0 || rr2 < 0.0 || !(rr2 > rr1))
        {
         reason = StringFormat("[GGATE] INIT FAILED: ExitRR_TP2R (%s) must be greater than ExitRR_TP1R (%s) in RR partial mode",
                               DoubleToString(rr2, 4), DoubleToString(rr1, 4));
         return false;
        }
      if(rrClosePct < 0.0 || rrClosePct > 1.0)
        {
         reason = StringFormat("[GGATE] INIT FAILED: ExitRR_Close1Pct (%s) must be within 0..1",
                               DoubleToString(rrClosePct, 4));
         return false;
        }
     }
   if(trailAct < 0)
     {
      reason = StringFormat("[GGATE] INIT FAILED: TrailingActivation (%d) must be nonnegative", trailAct);
      return false;
     }
   if(trailDist < 0)
     {
      reason = StringFormat("[GGATE] INIT FAILED: TrailingDistance (%d) must be nonnegative", trailDist);
      return false;
     }
   if(maxBuy < 1)
     {
      reason = StringFormat("[GGATE] INIT FAILED: MaxBuyPositions (%d) must be >= 1", maxBuy);
      return false;
     }
   if(maxSell < 1)
     {
      reason = StringFormat("[GGATE] INIT FAILED: MaxSellPositions (%d) must be >= 1", maxSell);
      return false;
     }
   if(ctMax >= 0 && ctMax < 1)
     {
      reason = StringFormat("[GGATE] INIT FAILED: CounterTrendMaxPositions (%d) must be >= 1", ctMax);
      return false;
     }
   return true;
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
//| Legal filling policy for a market DEAL on `symbol`.               |
//| SYMBOL_FILLING_MODE is a bit set (SYMBOL_FILLING_FOK=1,           |
//| SYMBOL_FILLING_IOC=2; both may be set). ORDER_FILLING_* are enum  |
//| values, not bits. Legality depends on SYMBOL_TRADE_EXEMODE:       |
//|   REQUEST / INSTANT : FOK.                                        |
//|   MARKET            : FOK if flagged, else IOC if flagged.        |
//|                       RETURN is never legal here.                 |
//|   EXCHANGE          : FOK, else IOC, else RETURN.                 |
//| FOK first when both are flagged (same order as CTrade's           |
//| SetTypeFillingBySymbol; a close either completes or does nothing).|
//| Returns false when no legal mode can be derived -- the caller      |
//| must not guess.                                                    |
//+------------------------------------------------------------------+
bool GGate_MarketDealFilling(const string symbol, ENUM_ORDER_TYPE_FILLING &filling)
  {
   ENUM_SYMBOL_TRADE_EXECUTION exec = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   long flags = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   bool fok = ((flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK);
   bool ioc = ((flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC);

   if(exec == SYMBOL_TRADE_EXECUTION_REQUEST || exec == SYMBOL_TRADE_EXECUTION_INSTANT)
     {
      filling = ORDER_FILLING_FOK;
      return true;
     }
   if(exec == SYMBOL_TRADE_EXECUTION_MARKET)
     {
      if(fok) { filling = ORDER_FILLING_FOK; return true; }
      if(ioc) { filling = ORDER_FILLING_IOC; return true; }
      return false;
     }
   if(exec == SYMBOL_TRADE_EXECUTION_EXCHANGE)
     {
      if(fok) { filling = ORDER_FILLING_FOK; return true; }
      if(ioc) { filling = ORDER_FILLING_IOC; return true; }
      filling = ORDER_FILLING_RETURN;
      return true;
     }
   return false;
  }

string GGate_CloseOutcomeText(const int outcome)
  {
   switch(outcome)
     {
      case GGATE_CLOSE_NONE:    return "NONE";
      case GGATE_CLOSE_PARTIAL: return "PARTIAL";
      case GGATE_CLOSE_FULL:    return "FULL";
      case GGATE_CLOSE_PENDING: return "PENDING";
      default:                  return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| Pending close-order registry. One slot per position that has a    |
//| close order still working on the server (PLACED, or DONE_PARTIAL  |
//| with the remainder left live). While a slot exists no new close   |
//| is sent for that position; the slot is resolved from order        |
//| history once the order leaves the live list. `reported` is volume |
//| already returned to a caller so it is never reported twice.       |
//+------------------------------------------------------------------+
ulong    g_ggPendPos[];
ulong    g_ggPendOrder[];
double   g_ggPendReq[];
double   g_ggPendReported[];
datetime g_ggPendTime[];
bool     g_ggPendCancelAsked[];
bool     g_ggPendFull[];      // true: this slot is a full-close request
int      g_ggPendStage[];     // staged-exit stage, or -1
string   g_ggPendReason[];    // reason code the caller asked to tag
uint     g_ggLastCloseRetcode = 0;

uint GGate_LastCloseRetcode()
  {
   return g_ggLastCloseRetcode;
  }
// A working close is left alone until this age, then cancelled once.
// The slot stays until the order is in history (or is confirmed gone after
// the cancel), so a retry cannot send a second close while the first lives.
#define GGATE_PENDING_CLOSE_TTL_SEC 30

int GGate_PendingFind(const ulong positionTicket)
  {
   for(int i = 0; i < ArraySize(g_ggPendPos); i++)
      if(g_ggPendPos[i] == positionTicket)
         return i;
   return -1;
  }

bool GGate_PendingIsCloseOrder(const ulong orderTicket)
  {
   if(orderTicket == 0)
      return false;
   for(int i = 0; i < ArraySize(g_ggPendOrder); i++)
      if(g_ggPendOrder[i] == orderTicket)
         return true;
   return false;
  }

void GGate_PendingAdd(const ulong positionTicket, const ulong orderTicket, const double requested,
                      const double reported, const bool fullIntent, const int stage, const string reasonCode)
  {
   int idx = GGate_PendingFind(positionTicket);
   if(idx < 0)
     {
      idx = ArraySize(g_ggPendPos);
      ArrayResize(g_ggPendPos, idx + 1);
      ArrayResize(g_ggPendOrder, idx + 1);
      ArrayResize(g_ggPendReq, idx + 1);
      ArrayResize(g_ggPendReported, idx + 1);
      ArrayResize(g_ggPendTime, idx + 1);
      ArrayResize(g_ggPendCancelAsked, idx + 1);
      ArrayResize(g_ggPendFull, idx + 1);
      ArrayResize(g_ggPendStage, idx + 1);
      ArrayResize(g_ggPendReason, idx + 1);
     }
   g_ggPendPos[idx]      = positionTicket;
   g_ggPendOrder[idx]    = orderTicket;
   g_ggPendReq[idx]      = requested;
   g_ggPendReported[idx] = reported;
   g_ggPendTime[idx]     = TimeCurrent();
   g_ggPendCancelAsked[idx] = false;
   g_ggPendFull[idx]     = fullIntent;
   g_ggPendStage[idx]    = stage;
   g_ggPendReason[idx]   = reasonCode;
  }

void GGate_PendingRemoveAt(const int idx)
  {
   int last = ArraySize(g_ggPendPos) - 1;
   if(idx < 0 || idx > last)
      return;
   g_ggPendPos[idx]      = g_ggPendPos[last];
   g_ggPendOrder[idx]    = g_ggPendOrder[last];
   g_ggPendReq[idx]      = g_ggPendReq[last];
   g_ggPendReported[idx] = g_ggPendReported[last];
   g_ggPendTime[idx]     = g_ggPendTime[last];
   g_ggPendCancelAsked[idx] = g_ggPendCancelAsked[last];
   g_ggPendFull[idx]     = g_ggPendFull[last];
   g_ggPendStage[idx]    = g_ggPendStage[last];
   g_ggPendReason[idx]   = g_ggPendReason[last];
   ArrayResize(g_ggPendPos, last);
   ArrayResize(g_ggPendOrder, last);
   ArrayResize(g_ggPendReq, last);
   ArrayResize(g_ggPendReported, last);
   ArrayResize(g_ggPendTime, last);
   ArrayResize(g_ggPendCancelAsked, last);
   ArrayResize(g_ggPendFull, last);
   ArrayResize(g_ggPendStage, last);
   ArrayResize(g_ggPendReason, last);
  }

// Cancel one working order. Not a new close: TRADE_ACTION_REMOVE only.
bool GGate_CancelWorkingOrder(const ulong orderTicket)
  {
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_REMOVE;
   request.order  = orderTicket;
   bool sent = OrderSend(request, result);
   Print("[GGATE] pending close timeout: cancel order=", orderTicket,
         " sent=", (sent ? "true" : "false"), " retcode=", result.retcode);
   return sent;
  }

//+------------------------------------------------------------------+
//| Resolve a registered pending close. Never sends.                  |
//| Still live, or gone from the live list but not yet in history:    |
//| PENDING (keep waiting; sending now could double-close).           |
//| In history: return only the newly filled volume, then free slot.  |
//+------------------------------------------------------------------+
int GGate_ResolvePendingClose(const int idx, ulong &outDeal, double &outFilled, ulong &outOrder)
  {
   ulong pos   = g_ggPendPos[idx];
   ulong closeOrder = g_ggPendOrder[idx];
   outDeal = 0;
   outFilled = 0.0;
   outOrder = closeOrder;

   if(OrderSelect(closeOrder))
     {
      int age = (int)(TimeCurrent() - g_ggPendTime[idx]);
      if(age < GGATE_PENDING_CLOSE_TTL_SEC)
         return GGATE_CLOSE_PENDING;
      if(!g_ggPendCancelAsked[idx])
        {
         GGate_CancelWorkingOrder(closeOrder);
         g_ggPendCancelAsked[idx] = true;
        }
      // Still on the book. Sending another close here could double-fill.
      return GGATE_CLOSE_PENDING;
     }
   if(!HistoryOrderSelect(closeOrder))
     {
      // Cancel was asked and the order is on neither list. After a second
      // TTL the slot is released so the caller can retry the remainder.
      if(g_ggPendCancelAsked[idx] &&
         (TimeCurrent() - g_ggPendTime[idx]) >= (GGATE_PENDING_CLOSE_TTL_SEC * 2))
        {
         Print("[GGATE] pending close order ", closeOrder,
               " absent after cancel — releasing slot so the remainder can be retried");
         GGate_PendingRemoveAt(idx);
         return GGATE_CLOSE_NONE;
        }
      return GGATE_CLOSE_PENDING;
     }

   double initialVol = HistoryOrderGetDouble(closeOrder, ORDER_VOLUME_INITIAL);
   double currentVol = HistoryOrderGetDouble(closeOrder, ORDER_VOLUME_CURRENT);
   double totalFilled = MathMax(0.0, initialVol - currentVol);
   double fresh = MathMax(0.0, totalFilled - g_ggPendReported[idx]);
   double stillWanted = MathMax(0.0, g_ggPendReq[idx] - g_ggPendReported[idx]);

   if(fresh > GGATE_VOLUME_EPS && HistorySelectByPosition(pos))
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d != 0 && (ulong)HistoryDealGetInteger(d, DEAL_ORDER) == closeOrder)
           {
            outDeal = d;
            break;
           }
        }
     }

   GGate_PendingRemoveAt(idx);
   outFilled = fresh;
   if(fresh <= GGATE_VOLUME_EPS)
      return GGATE_CLOSE_NONE;
   if(fresh >= stillWanted - GGATE_VOLUME_EPS)
      return GGATE_CLOSE_FULL;
   return GGATE_CLOSE_PARTIAL;
  }

//+------------------------------------------------------------------+
//| Ambiguous close (TIMEOUT / connection). The request may already   |
//| have executed. Do not send a second close until live volume, a    |
//| working order, or an out-deal proves what happened, or until      |
//| GGATE_UNCERTAIN_RETRY_SEC passes with the volume unchanged.       |
//+------------------------------------------------------------------+
#define GGATE_UNCERTAIN_RETRY_SEC 30
#define GGATE_OBS_NONE 0
#define GGATE_OBS_WAIT 1
#define GGATE_OBS_DONE 2
#define GGATE_OBS_SEND 3

ulong    g_ggUncPos[];
ulong    g_ggUncIdent[];
double   g_ggUncBefore[];
double   g_ggUncReq[];
datetime g_ggUncTime[];
bool     g_ggUncFull[];
int      g_ggUncStage[];
string   g_ggUncReason[];

bool GGate_RetcodeAmbiguous(const uint retcode)
  {
   return (retcode == TRADE_RETCODE_TIMEOUT || retcode == TRADE_RETCODE_CONNECTION);
  }

int GGate_UncertainFind(const ulong positionTicket)
  {
   for(int i = 0; i < ArraySize(g_ggUncPos); i++)
      if(g_ggUncPos[i] == positionTicket)
         return i;
   return -1;
  }

void GGate_UncertainRemoveAt(const int idx)
  {
   int last = ArraySize(g_ggUncPos) - 1;
   if(idx < 0 || idx > last)
      return;
   g_ggUncPos[idx]    = g_ggUncPos[last];
   g_ggUncIdent[idx]  = g_ggUncIdent[last];
   g_ggUncBefore[idx] = g_ggUncBefore[last];
   g_ggUncReq[idx]    = g_ggUncReq[last];
   g_ggUncTime[idx]   = g_ggUncTime[last];
   g_ggUncFull[idx]   = g_ggUncFull[last];
   g_ggUncStage[idx]  = g_ggUncStage[last];
   g_ggUncReason[idx] = g_ggUncReason[last];
   ArrayResize(g_ggUncPos, last);
   ArrayResize(g_ggUncIdent, last);
   ArrayResize(g_ggUncBefore, last);
   ArrayResize(g_ggUncReq, last);
   ArrayResize(g_ggUncTime, last);
   ArrayResize(g_ggUncFull, last);
   ArrayResize(g_ggUncStage, last);
   ArrayResize(g_ggUncReason, last);
  }

void GGate_UncertainRecord(const ulong positionTicket, const ulong ident, const double volumeBefore,
                           const double requested, const bool fullIntent, const int stage,
                           const string reasonCode)
  {
   int idx = GGate_UncertainFind(positionTicket);
   if(idx < 0)
     {
      idx = ArraySize(g_ggUncPos);
      ArrayResize(g_ggUncPos, idx + 1);
      ArrayResize(g_ggUncIdent, idx + 1);
      ArrayResize(g_ggUncBefore, idx + 1);
      ArrayResize(g_ggUncReq, idx + 1);
      ArrayResize(g_ggUncTime, idx + 1);
      ArrayResize(g_ggUncFull, idx + 1);
      ArrayResize(g_ggUncStage, idx + 1);
      ArrayResize(g_ggUncReason, idx + 1);
     }
   g_ggUncPos[idx]    = positionTicket;
   g_ggUncIdent[idx]  = ident;
   g_ggUncBefore[idx] = volumeBefore;
   g_ggUncReq[idx]    = requested;
   g_ggUncTime[idx]   = TimeCurrent();
   g_ggUncFull[idx]   = fullIntent;
   g_ggUncStage[idx]  = stage;
   g_ggUncReason[idx] = reasonCode;
  }

bool GGate_FindLiveCloseOrder(const ulong positionTicket, ulong &orderTicket)
  {
   orderTicket = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ord = OrderGetTicket(i);
      if(ord == 0 || !OrderSelect(ord))
         continue;
      if((ulong)OrderGetInteger(ORDER_POSITION_ID) != positionTicket)
         continue;
      ENUM_ORDER_TYPE kind = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(kind != ORDER_TYPE_BUY && kind != ORDER_TYPE_SELL)
         continue;
      orderTicket = ord;
      return true;
     }
   return false;
  }

bool GGate_OutDealSince(const ulong ident, const datetime since, ulong &deal, double &dealVolume)
  {
   deal = 0;
   dealVolume = 0.0;
   if(ident == 0 || !HistorySelectByPosition(ident))
      return false;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      if((datetime)HistoryDealGetInteger(d, DEAL_TIME) < since)
         continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
         HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY)
         continue;
      deal = d;
      dealVolume = HistoryDealGetDouble(d, DEAL_VOLUME);
      return true;
     }
   return false;
  }

// Returns GGATE_OBS_WAIT/DONE when the caller must not send, GGATE_OBS_SEND
// when a proof says the earlier request landed and a full caller may close
// the live remainder, GGATE_OBS_NONE when there is nothing to observe.
int GGate_ObserveUncertain(const ulong ticket, const bool fullClose, const int stage,
                           ulong &outDeal, double &outFilled, ulong &outOrder, int &outcome)
  {
   int idx = GGate_UncertainFind(ticket);
   if(idx < 0)
      return GGATE_OBS_NONE;
   if(!fullClose && !g_ggUncFull[idx] && g_ggUncStage[idx] >= 0 && stage >= 0 &&
      g_ggUncStage[idx] != stage)
     {
      outDeal = 0;
      outFilled = 0.0;
      outOrder = 0;
      outcome = GGATE_CLOSE_PENDING;
      return GGATE_OBS_WAIT;
     }

   double before = g_ggUncBefore[idx];
   ulong ident = g_ggUncIdent[idx];
   bool wasFull = g_ggUncFull[idx];
   datetime since = g_ggUncTime[idx];
   bool open = PositionSelectByTicket(ticket);
   double nowVol = open ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   ulong liveOrder = 0;
   if(GGate_FindLiveCloseOrder(ticket, liveOrder))
     {
      GGate_PendingAdd(ticket, liveOrder, g_ggUncReq[idx], 0.0, wasFull, g_ggUncStage[idx], g_ggUncReason[idx]);
      GGate_UncertainRemoveAt(idx);
      outDeal = 0;
      outFilled = 0.0;
      outOrder = liveOrder;
      outcome = GGATE_CLOSE_PENDING;
      g_ggLastCloseRetcode = TRADE_RETCODE_PLACED;
      return GGATE_OBS_WAIT;
     }

   ulong histDeal = 0;
   double histVol = 0.0;
   bool dealt = GGate_OutDealSince(ident, since, histDeal, histVol);
   bool volumeMoved = open ? (nowVol < before - GGATE_VOLUME_EPS) : (before > GGATE_VOLUME_EPS);
   if(dealt || volumeMoved)
     {
      GGate_UncertainRemoveAt(idx);
      bool foreignPartial = (fullClose && !wasFull);
      if(foreignPartial)
        {
         outDeal = 0;
         outFilled = 0.0;
         outOrder = 0;
         if(!PositionSelectByTicket(ticket))
           {
            outcome = GGATE_CLOSE_FULL;
            g_ggLastCloseRetcode = TRADE_RETCODE_DONE;
            return GGATE_OBS_DONE;
           }
         return GGATE_OBS_SEND;
        }
      outDeal = histDeal;
      outFilled = (histVol > GGATE_VOLUME_EPS) ? histVol : MathMax(0.0, before - nowVol);
      outOrder = 0;
      g_ggLastCloseRetcode = TRADE_RETCODE_DONE;
      if(!open || nowVol <= GGATE_VOLUME_EPS)
         outcome = GGATE_CLOSE_FULL;
      else
         outcome = GGATE_CLOSE_PARTIAL;
      return GGATE_OBS_DONE;
     }

   int age = (int)(TimeCurrent() - since);
   if(age < GGATE_UNCERTAIN_RETRY_SEC)
     {
      Print("[GGATE] ambiguous close still unproven position=", ticket,
            " age=", age, "s retcode was timeout/connection -- no second close yet");
      outDeal = 0;
      outFilled = 0.0;
      outOrder = 0;
      outcome = GGATE_CLOSE_PENDING;
      g_ggLastCloseRetcode = TRADE_RETCODE_TIMEOUT;
      return GGATE_OBS_WAIT;
     }
   Print("[GGATE] ambiguous close unproven after ", age,
         "s position=", ticket, " volume unchanged -- retry allowed");
   GGate_UncertainRemoveAt(idx);
   outDeal = 0;
   outFilled = 0.0;
   outOrder = 0;
   return GGATE_OBS_SEND;
  }

//+------------------------------------------------------------------+
//| Classify one trade-server answer for a close of `requested`.      |
//| Both the send boolean and the retcode must agree before anything  |
//| counts. Registers a pending slot when an order is left working.   |
//+------------------------------------------------------------------+
int GGate_ApplyCloseResult(const ulong positionTicket, const double requested,
                           const bool sent, const uint retcode, const ulong closeOrder,
                           const ulong deal, const double dealVolume,
                           const bool fullIntent, const int stage, const string reasonCode,
                           ulong &outDeal, double &outFilled, ulong &outOrder)
  {
   outDeal = 0;
   outFilled = 0.0;
   outOrder = closeOrder;
   g_ggLastCloseRetcode = retcode;
   if(GGate_RetcodeAmbiguous(retcode))
     {
      outOrder = 0;
      return GGATE_CLOSE_AMBIGUOUS;
     }
   if(!sent)
      return GGATE_CLOSE_REJECTED_;

   if(retcode == TRADE_RETCODE_DONE)
     {
      outDeal = deal;
      outFilled = (dealVolume > GGATE_VOLUME_EPS) ? dealVolume : requested;
      if(outFilled < requested - GGATE_VOLUME_EPS)
         return GGATE_CLOSE_PARTIAL;
      return GGATE_CLOSE_FULL;
     }

   if(retcode == TRADE_RETCODE_DONE_PARTIAL)
     {
      outDeal = deal;
      outFilled = MathMax(0.0, dealVolume);
      bool live = (closeOrder != 0 && OrderSelect(closeOrder));
      if(live)
         GGate_PendingAdd(positionTicket, closeOrder, requested, outFilled, fullIntent, stage, reasonCode);
      if(outFilled > GGATE_VOLUME_EPS)
         return GGATE_CLOSE_PARTIAL;
      return live ? GGATE_CLOSE_PENDING : GGATE_CLOSE_REJECTED_;
     }

   if(retcode == TRADE_RETCODE_PLACED)
     {
      if(closeOrder != 0)
         GGate_PendingAdd(positionTicket, closeOrder, requested, 0.0, fullIntent, stage, reasonCode);
      return GGATE_CLOSE_PENDING;
     }

   return GGATE_CLOSE_REJECTED_;
  }

// A full-close API may return FULL only when the position is actually gone.
// Completion of an earlier partial request, or a full request that left volume,
// is PARTIAL so the caller keeps managing the remainder.
int GGate_ConfirmFullClose(const ulong ticket, const bool fullClose, const int outcome)
  {
   if(fullClose && outcome == GGATE_CLOSE_FULL && PositionSelectByTicket(ticket))
      return GGATE_CLOSE_PARTIAL;
   return outcome;
  }

// Same position can have only one working close. TP1 and TP2 partial callers
// must not consume each other's slot. A full-close caller is not isolated by
// this function: it resolves a partial pending order, including the TTL cancel.
bool GGate_PendingMatches(const int idx, const bool fullClose, const int stage)
  {
   if(idx < 0 || idx >= ArraySize(g_ggPendPos))
      return false;
   if(g_ggPendFull[idx] != fullClose)
      return false;
   if(fullClose)
      return true;
   if(g_ggPendStage[idx] >= 0 && stage >= 0 && g_ggPendStage[idx] != stage)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| GGate_CloseVolumeCore: the one close primitive.                    |
//|  1. A different TP stage's pending partial is left untouched.     |
//|     A full-close caller resolves a partial pending order, so the  |
//|     TTL cancel runs. While that order is working this returns     |
//|     PENDING. After it finishes, the old fill is not this call's   |
//|     deal; the live remainder is what gets sent.                   |
//|  2. An ambiguous TIMEOUT/connection is observed, not followed by  |
//|     an immediate CTrade fallback.                                  |
//|  3. Tagged TRADE_ACTION_DEAL with a legal filling policy.         |
//|  4. Emergency untagged CTrade close ONLY if (3) was not legal or  |
//|     was rejected with a definite retcode.                         |
//| restoreMagic < 0 : bot caller. Do not touch the trade object's    |
//| magic; it is already the EA's configured magic.                   |
//| restoreMagic >= 0: Guard/shared caller. Fallback runs under the   |
//| position magic, then the object is restored to exactly this value |
//| (MagicGuard). Never read CTrade::RequestMagic() — it is the last  |
//| request magic and is often 0.                                      |
//+------------------------------------------------------------------+
int GGate_CloseVolumeCore(CTrade &tradeObj, const ulong ticket, const double volume, const bool fullClose,
                          const string comment, const long restoreMagic,
                          ulong &outDeal, double &outFilled, ulong &outOrder,
                          const int stage = -1, const string reasonCode = "")
  {
   outDeal = 0;
   outFilled = 0.0;
   outOrder = 0;
   double sendVolume = volume;

   int pend = GGate_PendingFind(ticket);
   bool partialStageIsolated = (pend >= 0 && !fullClose && !GGate_PendingMatches(pend, fullClose, stage));
   if(partialStageIsolated)
     {
      // Another TP stage owns this slot. Do not poll, cancel, report, or remove it.
      g_ggLastCloseRetcode = TRADE_RETCODE_PLACED;
      return GGATE_CLOSE_PENDING;
     }
   if(pend >= 0)
     {
      bool pendWasFull = g_ggPendFull[pend];
      int resolved = GGate_ResolvePendingClose(pend, outDeal, outFilled, outOrder);
      if(fullClose && !pendWasFull)
        {
         // The partial fill belongs to the earlier caller and to the deal comment.
         outDeal = 0;
         outFilled = 0.0;
         outOrder = 0;
         if(resolved == GGATE_CLOSE_PENDING)
           {
            g_ggLastCloseRetcode = TRADE_RETCODE_PLACED;
            return GGATE_CLOSE_PENDING;
           }
         if(!PositionSelectByTicket(ticket))
           {
            g_ggLastCloseRetcode = TRADE_RETCODE_DONE;
            if(resolved == GGATE_CLOSE_NONE)
               return GGATE_CLOSE_NONE;
            return GGATE_CLOSE_FULL;
           }
         sendVolume = PositionGetDouble(POSITION_VOLUME);
        }
      else
        {
         if(resolved == GGATE_CLOSE_PENDING)
            g_ggLastCloseRetcode = TRADE_RETCODE_PLACED;
         else if(resolved == GGATE_CLOSE_NONE)
            g_ggLastCloseRetcode = 0;
         else
            g_ggLastCloseRetcode = TRADE_RETCODE_DONE;
         return GGate_ConfirmFullClose(ticket, fullClose, resolved);
        }
     }

   int observed = GGATE_CLOSE_NONE;
   int obs = GGate_ObserveUncertain(ticket, fullClose, stage, outDeal, outFilled, outOrder, observed);
   if(obs == GGATE_OBS_WAIT || obs == GGATE_OBS_DONE)
      return observed;

   if(!PositionSelectByTicket(ticket))
      return GGATE_CLOSE_NONE;
   if(obs == GGATE_OBS_SEND && fullClose)
      sendVolume = PositionGetDouble(POSITION_VOLUME);
   else if(sendVolume <= GGATE_VOLUME_EPS)
      sendVolume = PositionGetDouble(POSITION_VOLUME);
   if(sendVolume <= GGATE_VOLUME_EPS)
      return GGATE_CLOSE_NONE;

   long   magic   = PositionGetInteger(POSITION_MAGIC);
   string symbol  = PositionGetString(POSITION_SYMBOL);
   long   posType = PositionGetInteger(POSITION_TYPE);

   ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_FOK;
   if(GGate_MarketDealFilling(symbol, filling))
     {
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action       = TRADE_ACTION_DEAL;
      request.position     = ticket;
      request.symbol       = symbol;
      request.volume       = sendVolume;
      request.magic        = magic;
      request.deviation    = 50; // points -- project slippage convention
      request.type_filling = filling;
      request.comment      = comment;
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

      double volumeBefore = PositionGetDouble(POSITION_VOLUME);
      ulong ident = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      bool sent = OrderSend(request, result);
      int tagged = GGate_ApplyCloseResult(ticket, sendVolume, sent, result.retcode, result.order,
                                          result.deal, result.volume, fullClose, stage, reasonCode,
                                          outDeal, outFilled, outOrder);
      if(tagged == GGATE_CLOSE_AMBIGUOUS)
        {
         GGate_UncertainRecord(ticket, ident, volumeBefore, sendVolume, fullClose, stage, reasonCode);
         Print("[GGATE] ambiguous close retcode=", result.retcode, " position=", ticket,
               " -- observing volume/order/deals, no CTrade fallback");
         outDeal = 0;
         outFilled = 0.0;
         outOrder = 0;
         return GGATE_CLOSE_PENDING;
        }
      if(tagged != GGATE_CLOSE_REJECTED_)
         return GGate_ConfirmFullClose(ticket, fullClose, tagged);
     }
   else
      Print("[GGATE] no legal market filling for ", symbol, " exemode=",
            SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE), " flags=",
            SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE), " -- using CTrade fallback");

   bool ok = false;
   if(restoreMagic < 0)
     {
      ok = fullClose ? tradeObj.PositionClose(ticket) : tradeObj.PositionClosePartial(ticket, sendVolume);
     }
   else
     {
      tradeObj.SetExpertMagicNumber((ulong)magic);
      ok = fullClose ? tradeObj.PositionClose(ticket) : tradeObj.PositionClosePartial(ticket, sendVolume);
      tradeObj.SetExpertMagicNumber((ulong)restoreMagic);
     }

   double volumeBeforeFb = 0.0;
   ulong identFb = 0;
   if(PositionSelectByTicket(ticket))
     {
      volumeBeforeFb = PositionGetDouble(POSITION_VOLUME);
      identFb = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
     }
   int fb = GGate_ApplyCloseResult(ticket, sendVolume, ok, tradeObj.ResultRetcode(), tradeObj.ResultOrder(),
                                   tradeObj.ResultDeal(), tradeObj.ResultVolume(), fullClose, stage, reasonCode,
                                   outDeal, outFilled, outOrder);
   if(fb == GGATE_CLOSE_AMBIGUOUS)
     {
      GGate_UncertainRecord(ticket, identFb, volumeBeforeFb, sendVolume, fullClose, stage, reasonCode);
      Print("[GGATE] ambiguous CTrade close retcode=", tradeObj.ResultRetcode(), " position=", ticket,
            " -- observing volume/order/deals before any retry");
      outDeal = 0;
      outFilled = 0.0;
      outOrder = 0;
      return GGATE_CLOSE_PENDING;
     }
   if(fb == GGATE_CLOSE_REJECTED_ || fb == GGATE_CLOSE_NONE)
      return GGATE_CLOSE_NONE;
   return GGate_ConfirmFullClose(ticket, fullClose, fb);
  }

//+------------------------------------------------------------------+
//| Full close of the position's current volume, reason-tagged.       |
//| PARTIAL: some volume closed (log outFilled/outDeal); the rest of  |
//| the position is still open and the next call closes what remains. |
//+------------------------------------------------------------------+
int GGate_CloseTaggedEx(CTrade &tradeObj, const ulong ticket, const string reasonCode,
                        ulong &outDealTicket, double &outFilled, const string freeText = "")
  {
   outDealTicket = 0;
   outFilled = 0.0;
   ulong closeOrder = 0;
   double volume = 0.0;
   string comment = "";
   if(PositionSelectByTicket(ticket))
     {
      volume  = PositionGetDouble(POSITION_VOLUME);
      comment = GGate_BuildCloseComment(PositionGetInteger(POSITION_MAGIC), reasonCode, freeText);
     }
   else if(GGate_PendingFind(ticket) < 0 && GGate_UncertainFind(ticket) < 0)
      return GGATE_CLOSE_NONE;
   int outcome = GGate_CloseVolumeCore(tradeObj, ticket, volume, true, comment, -1,
                                       outDealTicket, outFilled, closeOrder, -1, reasonCode);
   if(outcome == GGATE_CLOSE_FULL && PositionSelectByTicket(ticket))
      return GGATE_CLOSE_PARTIAL;
   return outcome;
  }

// True only when the whole position closed. Callers that must log or
// attribute partial fills use GGate_CloseTaggedEx instead.
bool GGate_CloseTagged(CTrade &tradeObj, const ulong ticket, const string reasonCode, const string freeText = "")
  {
   ulong deal = 0;
   double filled = 0.0;
   return (GGate_CloseTaggedEx(tradeObj, ticket, reasonCode, deal, filled, freeText) == GGATE_CLOSE_FULL);
  }

bool GGate_CloseTagged(CTrade &tradeObj, const ulong ticket, const string reasonCode, ulong &outDealTicket, const string freeText = "")
  {
   double filled = 0.0;
   return (GGate_CloseTaggedEx(tradeObj, ticket, reasonCode, outDealTicket, filled, freeText) == GGATE_CLOSE_FULL);
  }

//+------------------------------------------------------------------+
//| Partial close of `volumeToClose`, reason-tagged. There is no bool |
//| form: a partial fill is an execution, and callers must log it and |
//| retry only the unfilled remainder (see GGate_PartialPlan*).       |
//+------------------------------------------------------------------+
int GGate_ClosePartialTaggedEx(CTrade &tradeObj, const ulong ticket, const double volumeToClose,
                               const string reasonCode, ulong &outDealTicket, double &outFilled,
                               const string freeText = "", const int stage = -1)
  {
   outDealTicket = 0;
   outFilled = 0.0;
   ulong closeOrder = 0;
   string comment = "";
   if(PositionSelectByTicket(ticket))
      comment = GGate_BuildCloseComment(PositionGetInteger(POSITION_MAGIC), reasonCode, freeText);
   else if(GGate_PendingFind(ticket) < 0 && GGate_UncertainFind(ticket) < 0)
      return GGATE_CLOSE_NONE;
   return GGate_CloseVolumeCore(tradeObj, ticket, volumeToClose, false, comment, -1,
                                outDealTicket, outFilled, closeOrder, stage, reasonCode);
  }

//+------------------------------------------------------------------+
//| Partial-close plan: the unfilled remainder of one intended staged |
//| close, keyed by (position ticket, stage). Lets a retry send only  |
//| what is still owed instead of a fresh percentage of the reduced   |
//| position. Bounded; oldest slot is reused when full.               |
//+------------------------------------------------------------------+
#define GGATE_PARTIAL_PLAN_SLOTS 512
ulong  g_ggPlanTicket[];
int    g_ggPlanStage[];
double g_ggPlanRemaining[];
int    g_ggPlanNext = 0;

int GGate_PartialPlanFind(const ulong ticket, const int stage)
  {
   for(int i = 0; i < ArraySize(g_ggPlanTicket); i++)
      if(g_ggPlanTicket[i] == ticket && g_ggPlanStage[i] == stage)
         return i;
   return -1;
  }

void GGate_PartialPlanSet(const ulong ticket, const int stage, const double remaining)
  {
   int idx = GGate_PartialPlanFind(ticket, stage);
   if(idx < 0)
     {
      int n = ArraySize(g_ggPlanTicket);
      if(n < GGATE_PARTIAL_PLAN_SLOTS)
        {
         idx = n;
         ArrayResize(g_ggPlanTicket, n + 1);
         ArrayResize(g_ggPlanStage, n + 1);
         ArrayResize(g_ggPlanRemaining, n + 1);
        }
      else
        {
         idx = g_ggPlanNext;
         g_ggPlanNext = (g_ggPlanNext + 1) % GGATE_PARTIAL_PLAN_SLOTS;
        }
     }
   g_ggPlanTicket[idx]    = ticket;
   g_ggPlanStage[idx]     = stage;
   g_ggPlanRemaining[idx] = remaining;
  }

void GGate_PartialPlanClear(const ulong ticket, const int stage)
  {
   int idx = GGate_PartialPlanFind(ticket, stage);
   if(idx < 0)
      return;
   g_ggPlanTicket[idx] = 0;
   g_ggPlanStage[idx] = 0;
   g_ggPlanRemaining[idx] = 0.0;
  }

// Volume to send for this stage: the owed remainder if a previous attempt
// partially filled or is pending, else the caller's freshly planned volume.
double GGate_PartialPlanVolume(const ulong ticket, const int stage, const double planned)
  {
   int idx = GGate_PartialPlanFind(ticket, stage);
   if(idx >= 0)
      return g_ggPlanRemaining[idx];
   return planned;
  }

// Record an outcome against the stage plan. Returns true when the stage's
// intended amount is fully done (or the unfilled residue is below the
// symbol minimum and cannot be sent).
bool GGate_PartialPlanApply(const ulong ticket, const int stage, const double requested,
                            const int outcome, const double filled)
  {
   if(outcome == GGATE_CLOSE_FULL)
     {
      GGate_PartialPlanClear(ticket, stage);
      return true;
     }
   if(outcome == GGATE_CLOSE_PENDING)
     {
      GGate_PartialPlanSet(ticket, stage, requested);
      return false;
     }
   if(outcome == GGATE_CLOSE_PARTIAL)
     {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double rest   = requested - filled;
      if(step > 0.0)
         rest = MathFloor(rest / step + GGATE_VOLUME_EPS) * step;
      rest = NormalizeDouble(rest, 8);
      if(minLot <= 0.0)
         minLot = 0.01;
      if(rest < minLot - GGATE_VOLUME_EPS)
        {
         GGate_PartialPlanClear(ticket, stage);
         return true;
        }
      GGate_PartialPlanSet(ticket, stage, rest);
      return false;
     }
   return false; // NONE: plan (if any) unchanged, same amount retried
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
   // Insertion sort. nMagics stays small, but the full array is published
   // (no priority-slot cap).
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

#endif // BOSSAFX_GUARD_GATE_MQH
