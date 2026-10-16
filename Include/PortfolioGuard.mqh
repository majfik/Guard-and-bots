#ifndef PORTFOLIO_GUARD_MQH
#define PORTFOLIO_GUARD_MQH

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| PortfolioGuard.mqh — shared by EA-G and EA-S                     |
//| Logs, visuals, heartbeats: callers pass flags; this file also    |
//| hard-skips CSV during MQL_OPTIMIZATION (bot4 §3.8).              |
//+------------------------------------------------------------------+

#define PG_MAGIC_T     60001
#define PG_MAGIC_S     61001
#define PG_MAGIC_G     61999

#define PG_VETO_OK          0
#define PG_VETO_NEWS        1
#define PG_VETO_FRIDAY      2
#define PG_VETO_DD_DAILY    3
#define PG_VETO_DD_OVERALL  4
#define PG_VETO_DEAD        5
#define PG_VETO_BUDGET      6
#define PG_VETO_OVERLAP     7
#define PG_VETO_NETTING     8
#define PG_VETO_STALE       9

#define PG_OBJ_PREFIX  "PGKID_"

enum ENUM_PG_BUCKET
  {
   PG_BUCKET_UNKNOWN = 0,
   PG_BUCKET_HELD    = 1,
   PG_BUCKET_ARMED   = 2,
   PG_BUCKET_NO_BIAS = 3,
   PG_BUCKET_VETO    = 4
  };

//+------------------------------------------------------------------+
bool PgIsOptimization()
  {
   return (bool)MQLInfoInteger(MQL_OPTIMIZATION);
  }

bool PgIsTester()
  {
   return (bool)MQLInfoInteger(MQL_TESTER);
  }

bool PgIsHedging()
  {
   return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

string PgGvPrefix(const string symbol)
  {
   return "PG_" + symbol + "_";
  }

void PgGvSet(const string symbol, const string key, const double value)
  {
   GlobalVariableSet(PgGvPrefix(symbol) + key, value);
  }

double PgGvGet(const string symbol, const string key, const double fallback = 0.0)
  {
   string name = PgGvPrefix(symbol) + key;
   if(!GlobalVariableCheck(name))
      return fallback;
   return GlobalVariableGet(name);
  }

void PgTouchTs(const string symbol)
  {
   PgGvSet(symbol, "TS", (double)TimeCurrent());
  }

bool PgTsFresh(const string symbol, const int max_age_sec)
  {
   datetime ts = (datetime)PgGvGet(symbol, "TS", 0);
   if(ts <= 0)
      return false;
   return ((TimeCurrent() - ts) <= max_age_sec);
  }

int PgCountPositions(const string symbol, const int magic)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      n++;
     }
   return n;
  }

int PgNetDirection(const string symbol, const int magic)
  {
   int dir = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
         dir = 1;
      else if(type == POSITION_TYPE_SELL)
         dir = -1;
     }
   return dir;
  }

ENUM_PG_BUCKET PgBucketFromFlags(const bool t_held, const int t_bias)
  {
   if(t_held)
      return PG_BUCKET_HELD;
   if(t_bias != 0)
      return PG_BUCKET_ARMED;
   return PG_BUCKET_NO_BIAS;
  }

string PgBucketKid(const ENUM_PG_BUCKET b)
  {
   switch(b)
     {
      case PG_BUCKET_HELD:    return "Trend bot is IN a trade. We wait. No bouncing.";
      case PG_BUCKET_ARMED:   return "Trend bot sees a direction. Waiting for a dip. No bouncing.";
      case PG_BUCKET_NO_BIAS: return "No big trend right now. Price may go sideways.";
      case PG_BUCKET_VETO:    return "Trend bot said skip. We also wait.";
      default:                return "Not sure yet. Watching.";
     }
  }

string PgVetoKid(const int veto)
  {
   switch(veto)
     {
      case PG_VETO_OK:         return "Brakes OFF. Trading allowed (if your engine is on).";
      case PG_VETO_NEWS:       return "STOP: big news window. Nobody new trades.";
      case PG_VETO_FRIDAY:     return "STOP: Friday close rule. Go flat / no new trades.";
      case PG_VETO_DD_DAILY:   return "STOP: today lost too much (daily brake).";
      case PG_VETO_DD_OVERALL: return "STOP: account down too much (overall brake).";
      case PG_VETO_DEAD:       return "STOP: Guard heartbeat died. Sleeve will not trade.";
      case PG_VETO_BUDGET:     return "STOP: no risk budget left for this engine.";
      case PG_VETO_OVERLAP:    return "STOP: trend bot already holds this side of gold.";
      case PG_VETO_NETTING:    return "STOP: this account nets positions. Two EAs cannot share gold.";
      case PG_VETO_STALE:      return "STOP: Guard numbers are old. Sleeve sits out.";
      default:                 return "STOP: unknown brake.";
     }
  }

string PgCouldHappenKid(const ENUM_PG_BUCKET b, const int family)
  {
   if(family == 0)
      return "COULD: nothing trades until you pick ORB or Bounce (still OBSERVE).";
   if(b == PG_BUCKET_HELD || b == PG_BUCKET_ARMED)
      return "COULD: only the trend bot. Sleeve stays asleep.";
   if(family == 1)
      return "COULD: London may break the night box. Sleeve may buy/sell that break.";
   if(family == 2)
      return "COULD: price stretched from the middle may snap back. Sleeve may fade.";
   return "COULD: we sit.";
  }

//+------------------------------------------------------------------+
//| Pipeline CSV — skipped in optimization; tester = state-change    |
//+------------------------------------------------------------------+
bool PgLogAllowed(const bool user_flag)
  {
   if(PgIsOptimization())
      return false;
   return user_flag;
  }

void PgPipeLog(const bool user_flag,
               const string ea_tag,
               const string fn,
               const string stage,
               const int ok,
               const string in_txt,
               const string out_txt,
               const string block_reason,
               const string next_stage,
               const int magic,
               const string config_label)
  {
   if(!PgLogAllowed(user_flag))
      return;
   string filename = "port_" + ea_tag + "_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
      FileWriteString(handle, "event_time,fn,stage,ok,in,out,block_reason,next,magic,ConfigLabel,symbol\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   string ts = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                            mdt.year, mdt.mon, mdt.day, mdt.hour, mdt.min, mdt.sec);
   string in_s = in_txt;
   string out_s = out_txt;
   StringReplace(in_s, ",", ";");
   StringReplace(out_s, ",", ";");
   string br = block_reason;
   StringReplace(br, ",", ";");
   string line = ts + "," + fn + "," + stage + "," + IntegerToString(ok) + "," +
                 in_s + "," + out_s + "," + br + "," + next_stage + "," +
                 IntegerToString(magic) + "," + config_label + "," + _Symbol + "\n";
   FileWriteString(handle, line);
   FileClose(handle);
  }

void PgHeartbeat(const bool user_flag,
                 const string ea_tag,
                 const string kid_now,
                 const int magic)
  {
   if(!user_flag)
      return;
   if(PgIsOptimization())
      return;
   if(PgIsTester())
      return;
   string filename = "port_" + ea_tag + "_heart_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
      FileWriteString(handle, "event_time,magic,kid_now,symbol\n");
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   string ts = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                            mdt.year, mdt.mon, mdt.day, mdt.hour, mdt.min, mdt.sec);
   FileWriteString(handle, ts + "," + IntegerToString(magic) + "," + kid_now + "," + _Symbol + "\n");
   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Kid chart objects — no indicators. Expire after keep_hours.      |
//+------------------------------------------------------------------+
void PgObjStamp(const string name)
  {
   string tip = ObjectGetString(0, name, OBJPROP_TOOLTIP);
   if(StringFind(tip, "created=") < 0)
     {
      if(StringLen(tip) > 0)
         tip = tip + " | ";
      tip = tip + "created=" + IntegerToString((long)TimeCurrent());
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
     }
  }

datetime PgObjCreated(const string name)
  {
   string tip = ObjectGetString(0, name, OBJPROP_TOOLTIP);
   int p = StringFind(tip, "created=");
   if(p < 0)
      return TimeCurrent();
   return (datetime)StringToInteger(StringSubstr(tip, p + 8));
  }

void PgSweepExpiredObjects(const int keep_hours)
  {
   if(keep_hours <= 0)
      return;
   datetime cutoff = TimeCurrent() - keep_hours * 3600;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PG_OBJ_PREFIX) != 0)
         continue;
      if(PgObjCreated(name) < cutoff)
         ObjectDelete(0, name);
     }
  }

void PgDeleteOurObjects()
  {
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PG_OBJ_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

void PgLabel(const string key, const int x, const int y, const string text, const color col, const int fs = 10)
  {
   string name = PG_OBJ_PREFIX + "L_" + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PgObjStamp(name);
  }

void PgRect(const string key, datetime t1, double p1, datetime t2, double p2, const color col, const string tip)
  {
   string name = PG_OBJ_PREFIX + "R_" + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   PgObjStamp(name);
  }

void PgHLine(const string key, const double price, const color col, const string tip)
  {
   string name = PG_OBJ_PREFIX + "H_" + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   PgObjStamp(name);
  }

void PgText(const string key, datetime t, double price, const string text, const color col)
  {
   string name = PG_OBJ_PREFIX + "T_" + key;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   PgObjStamp(name);
  }

void PgKidLegend(const bool show,
                 const string title,
                 const string now_txt,
                 const string could_txt,
                 const string guard_txt,
                 const string extra)
  {
   if(!show || PgIsOptimization())
      return;
   PgLabel("title", 12, 18, title, clrWhite, 11);
   PgLabel("now", 12, 38, "NOW: " + now_txt, clrGold, 10);
   PgLabel("could", 12, 56, could_txt, clrSilver, 9);
   PgLabel("guard", 12, 74, "BRAKE: " + guard_txt, clrOrange, 9);
   if(StringLen(extra) > 0)
      PgLabel("extra", 12, 92, extra, clrGray, 9);
  }

//+------------------------------------------------------------------+
//| PgCloseMagic: closes all positions for (symbol, magic). Optional  |
//| reasonTag (2026-10-06, additive) -- when non-empty, closes go     |
//| through a raw OrderSend carrying a "<magic>|<reasonTag>" comment  |
//| (same 31-char-safe format as GGate_BuildCloseComment() in         |
//| BossafxGuardGate.mqh, reimplemented inline here rather than       |
//| #include'd so this file stays dependency-free for callers that   |
//| don't use the gate feature, e.g. EA_S_GoldSleeve.mq5 and the      |
//| archived single-EA EA_G_PortfolioGuard.mq5). Omitting reasonTag   |
//| (or passing "") preserves the exact old untagged-close behavior   |
//| for every existing caller -- purely additive, zero behavior       |
//| change unless a caller opts in.                                   |
//+------------------------------------------------------------------+
int PgCloseMagic(const string symbol, const int magic, CTrade &trade, const string reasonTag = "")
  {
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      if(reasonTag == "")
        {
         if(trade.PositionClose(ticket))
            closed++;
         continue;
        }

      // Tagged close path: raw OrderSend so the reason survives as the DEAL comment (CTrade's
      // PositionClose() has no comment parameter -- same constraint GGate_CloseTagged works around).
      long   posMagic = PositionGetInteger(POSITION_MAGIC);
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      string magicPart = IntegerToString(posMagic);
      string tagComment = magicPart + "|" + reasonTag;
      if(StringLen(tagComment) > 31)
         tagComment = StringSubstr(tagComment, 0, 31); // never truncate below magic+reasonTag in practice -- GRD is short

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      request.action        = TRADE_ACTION_DEAL;
      request.position      = ticket;
      request.symbol        = posSymbol;
      request.volume        = volume;
      request.magic         = posMagic;
      request.deviation     = 50;
      request.type_filling  = ORDER_FILLING_IOC;
      request.comment       = tagComment;
      if(posType == POSITION_TYPE_BUY)
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
        {
         closed++;
        }
      // 2026-10-15 fix: trade.PositionClose() below previously used trade's OWN
      // ExpertMagicNumber (e.g. Guard's MagicGuard) for the resulting close deal instead of
      // posMagic -- so any caller gating on DEAL_MAGIC after a close that hit this fallback
      // (e.g. EA_G_PortfolioGuard_MultiEA's loss-cooldown, which checks IsProtectedMagic(magic)
      // before arming a cooldown) would silently see the wrong magic and skip that logic.
      // Confirmed live 2026-10-15 via the sibling GGuardCloseDirectionTagged() bug (identical
      // pattern, basket-SL path) -- fixed there and here together. posMagic == magic (the
      // function's own filter parameter) in this tagged branch, so restore to `magic` after --
      // CTrade exposes no getter for its currently-configured ExpertMagicNumber, but we already
      // know what it should be from the caller's own filter, no need to read it back.
      else
        {
         trade.SetExpertMagicNumber(posMagic);
         bool fallbackClosed = trade.PositionClose(ticket); // fail-safe: untagged close beats no close at all
         trade.SetExpertMagicNumber(magic);
         if(fallbackClosed)
            closed++;
        }
     }
   return closed;
  }

int PgCancelPendings(const string symbol, const int magic, CTrade &trade)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      if(trade.OrderDelete(ticket))
         n++;
     }
   return n;
  }

#endif
