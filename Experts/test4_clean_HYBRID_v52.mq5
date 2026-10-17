//+------------------------------------------------------------------+
//| test4_clean_HYBRID.mq5
//| Multi-Layer Scalp-Swing EA with Stage Exits & Flexible Entries
//| Based on test4_clean architecture + v6.0 stage profit taking
//| Production Ready - January 6, 2026
//| Modified: Enhanced Legend System - January 8, 2026 (FIXED)
//+------------------------------------------------------------------+
#property strict
#property version   "5.2"
#property description "XAU/USD Multi-layer EA with stage exits + flexible entry thresholds + Enhanced Legend"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <BossafxGuardGate.mqh>  // 2026-10-05: 1-per-bar PF-priority entry gate + closure-reason tagging

//+------------------------------------------------------------------+
//| ENUMS                                                            
//+------------------------------------------------------------------+
enum ENUM_LOT_TYPE {
   LOT_FIXED = 0,
   LOT_RISK = 1
};

//+------------------------------------------------------------------+
//| INPUTS - CORE SETTINGS                                          
//+------------------------------------------------------------------+
input group "═══ General Settings ═══"
input ENUM_LOT_TYPE LotType = LOT_FIXED;
input double LotSize = 0.10;
input double RiskPercent = 1.0;
input int MagicNumber = 54321;
input bool CloseOpposite = false;
input int MaxBuyPositions = 1;
input int MaxSellPositions = 1;
input bool OneTradePerBar = true;

input group "=== 1-per-bar PF-priority entry gate (2026-10-05, additive) ==="
input bool UseGuardBarGate = true;  // user default ON; fail-open if EA_G_PortfolioGuard_MultiEA
                                     // isn't running or hasn't published a gate decision yet -- see
                                     // BossafxGuardGate.mqh GGate_ShouldOpen()

input group "═══ STAGE PROFIT TAKING (NEW!) ═══"
input bool UseStageExits = true;
input int TP1_Distance = 30;               // First target: 30 pips
input double TP1_ClosePercent = 0.25;      // Close 25% of position
input int TP2_Distance = 50;               // Second target: 50 pips
input double TP2_ClosePercent = 0.30;      // Close 30% of position
input bool UseTrailingOnRemainder = true;
input int TrailingActivation = 50;         // Start trailing after 50 pips
input int TrailingDistance = 20;           // Trail 20 pips from peak

input group "═══ RISK MANAGEMENT ═══"
input bool UseADR = true;
input int ADRPeriod = 14;
input double ADRMultiplierSL = 0.3;
input double ADRMultiplierTP = 0.9;
input int StopLoss = 100;
input int TakeProfit = 200;
input bool UseKumoSL = true;

input group "═══ FTMO PROTECTION ═══"
input double InitialBalance = 10000.0;
input double MaxDailyLossAmount = 500.0;
input double MaxOverallLossAmount = 1000.0;
input double MaxRiskPerTradeFraction = 0.5;
input double SafetyBuffer = 10.0;

input group "═══ ENTRY FILTERS (MORE FLEXIBLE!) ═══"
input bool UseStrictLayers = false;        
input int Layer1MinConfirmations = 2;      // Need 2/3 from Layer 1 (was 3/3)
input int Layer2MinConfirmations = 1;      // Need 1/3 from Layer 2 (was 2/3)
input int Layer3MinConfirmations = 1;      // Need 1/3 from Layer 3 (was 2/3)

input group "═══ VOLATILITY FILTER (CRITICAL) ═══"
input bool UseVolatilityRatio = true;
input int ATRShortPeriod = 5;
input int ATRLongPeriod = 20;
input double VolatilityRatioTrendMin = 1.15;
input double VolatilityRatioRangeMax = 1.1;
input double VolatilityRatioRangeMin = 0.9;
input double VolatilityRatioLowVol = 0.8;
input bool TradeTrendingOnly = false;
input bool AvoidLowVol = true;
input bool AvoidRanging = false;

input group "═══ MARKET FILTER ═══"
input bool UseMarketFilter = false;
input bool UseTrendStrength = false;
input int ADXPeriod = 14;
input double ADXThreshold = 20.0;
input double StrongADXThreshold = 30.0;

input group "═══ Layer 1: Baseline (HTF Ichimoku) ═══"
input bool UseIchimoku = true;
input bool UseEMACross = false;
input bool UsePSAR = true;
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

input group "═══ Layer 2: Momentum (TF) ═══"
input bool UseMACD = true;
input bool UseRSI = true;
input bool UseADX = true;
input int MACDFast = 12;
input int MACDSlow = 26;
input int MACDSignal = 9;
input ENUM_APPLIED_PRICE MACDPrice = PRICE_CLOSE;
input int RSIPeriod = 14;
input double RSIMomentumLevel = 50.0;

input group "═══ Layer 3: Entry Triggers ═══"
input bool UseBollinger = true;
input bool UseOBV = true;
input bool UseDonchian = true;
input int BollingerPeriod = 20;
input double BollingerDev = 2.0;
input int DonchianPeriod = 20;

input group "═══ Time Filter ═══"
input bool UseTimeFilter = false;
input string StartTime = "00:00";
input string EndTime = "23:59";
input bool AvoidFriday = true;
input int FridayCloseHour = 16;

input group "═══ Display ═══"
input bool ShowLeftLegend = true;
input bool ShowRightLegend = true;
input int LegendFontSize = 8;              // Font size for legend

//+------------------------------------------------------------------+
//| GLOBALS                                                          
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
COrderInfo order;

int atrHandle = INVALID_HANDLE;
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
int atrShortHandle = INVALID_HANDLE;
int atrLongHandle = INVALID_HANDLE;

double adr = 0.0;
datetime lastBarTime = 0;
datetime lastTradeBarTime = 0;
double startDayBalance = 0.0;
datetime lastCestDayStart = 0;

struct StageTracker {
   ulong ticket;
   ulong ident;         // POSITION_IDENTIFIER, stable across a partial close
   int stage;           // 0=open, 1=TP1 closed, 2=TP2 closed, 3=trailing
   double profitLocked;
};
StageTracker stages[];

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
   if(atrShortHandle == INVALID_HANDLE || atrLongHandle == INVALID_HANDLE) return 1.0;

   double s[], l[];
   ArraySetAsSeries(s,true);
   ArraySetAsSeries(l,true);
   if(CopyBuffer(atrShortHandle,0,0,1,s)<1) return 1.0;
   if(CopyBuffer(atrLongHandle,0,0,1,l)<1) return 1.0;
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
      if(TradeTrendingOnly && volState != 1) return false;
      if(AvoidLowVol && volState == -1) return false;
      if(AvoidRanging && volState == 0) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| LAYER 1: BASELINE TREND                                         
//+------------------------------------------------------------------+
int GetIchimokuTrend() {
   if(!UseIchimoku || ichimokuHandleHTF==INVALID_HANDLE) return 0;

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
   if(!UseEMACross || emaFastHandle==INVALID_HANDLE || emaSlowHandle==INVALID_HANDLE) return 0;

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
   if(!UsePSAR || psarHandle==INVALID_HANDLE) return 0;

   double p[];
   ArraySetAsSeries(p,true);
   if(CopyBuffer(psarHandle,0,0,1,p)<1) return 0;
   double c = iClose(_Symbol, HigherTimeframe, 0);

   if(p[0] < c) return 1;
   if(p[0] > c) return -1;
   return 0;
}

int GetLayer1Trend() {
   int sum=0, n=0;
   if(UseIchimoku){ sum += GetIchimokuTrend(); n++; }
   if(UseEMACross){ sum += GetEMACrossTrend(); n++; }
   if(UsePSAR){ sum += GetPSARTrend(); n++; }
   if(n<=0) return 0;

   // More flexible: require 2/3 instead of 3/3
   int thr = UseStrictLayers ? ((n+1)/2) : (Layer1MinConfirmations);
   if(thr > n) thr = (n+1)/2;

   if(sum >= thr) return 1;
   if(sum <= -thr) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| LAYER 2: MOMENTUM CONFIRMATION                                  
//+------------------------------------------------------------------+
int GetMACDMomentum() {
   if(!UseMACD || macdHandle==INVALID_HANDLE) return 0;

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
   if(!UseRSI || rsiHandle==INVALID_HANDLE) return 0;

   double r[];
   ArraySetAsSeries(r,true);
   if(CopyBuffer(rsiHandle,0,0,1,r)<1) return 0;

   if(r[0] > RSIMomentumLevel) return 1;
   if(r[0] < RSIMomentumLevel) return -1;
   return 0;
}

bool GetADXStrength(int trend) {
   if(!UseADX || adxHandle==INVALID_HANDLE) return false;

   double adx[], pdi[], mdi[];
   ArraySetAsSeries(adx,true);
   ArraySetAsSeries(pdi,true);
   ArraySetAsSeries(mdi,true);

   if(CopyBuffer(adxHandle,0,0,1,adx)<1) return false;
   if(CopyBuffer(adxHandle,1,0,1,pdi)<1) return false;
   if(CopyBuffer(adxHandle,2,0,1,mdi)<1) return false;

   bool dirAlign = (trend == 1) ? (pdi[0] > mdi[0]) : (mdi[0] > pdi[0]);
   return (adx[0] > ADXThreshold && dirAlign);
}

bool CheckLayer2Momentum(int trend) {
   int count=0, aligned=0;
   if(UseMACD) {
      if(GetMACDMomentum() == trend) aligned++;
      count++;
   }
   if(UseRSI) {
      if(GetRSIMomentum() == trend) aligned++;
      count++;
   }
   if(UseADX) {
      if(GetADXStrength(trend)) aligned++;
      count++;
   }
   if(count == 0) return false;

   // More flexible: need 1/3 instead of 2/3
   int thr = UseStrictLayers ? (count/2 + 1) : Layer2MinConfirmations;
   if(thr > count) thr = (count/2 + 1);

   return (aligned >= thr);
}

//+------------------------------------------------------------------+
//| LAYER 3: ENTRY TRIGGERS                                         
//+------------------------------------------------------------------+
int GetBollingerTrigger() {
   if(!UseBollinger || bollHandle==INVALID_HANDLE) return 0;

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
   if(!UseOBV || obvHandle==INVALID_HANDLE) return 0;

   double obv[];
   ArraySetAsSeries(obv,true);
   if(CopyBuffer(obvHandle,0,0,3,obv)<3) return 0;

   if(obv[0] > obv[1] && obv[1] > obv[2]) return 1;
   if(obv[0] < obv[1] && obv[1] < obv[2]) return -1;
   return 0;
}

int GetDonchianTrigger() {
   if(!UseDonchian) return 0;

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
   int sum=0, n=0;
   if(UseBollinger){ sum += GetBollingerTrigger(); n++; }
   if(UseOBV){ sum += GetOBVTrigger(); n++; }
   if(UseDonchian){ sum += GetDonchianTrigger(); n++; }
   if(n<=0) return 0;

   // More flexible: need 1/3 instead of 2/3
   int thr = UseStrictLayers ? ((n+1)/2) : Layer3MinConfirmations;
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

   // Layer 2 is now MORE FLEXIBLE (can proceed without full confirmation)
   if(!CheckLayer2Momentum(trend)) return 0;

   int trigger = GetLayer3Trigger();
   // NOW: trigger just needs to MATCH direction, not be absolute
   if(trigger == trend) return trend;

   return 0;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT                                                 
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_POSITION_TYPE posType, double entryPrice) {
   double sl = 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(UseADR && adr > 0) {
      sl = (posType == POSITION_TYPE_BUY) ? 
           entryPrice - (adr * ADRMultiplierSL) : 
           entryPrice + (adr * ADRMultiplierSL);
   } else if(StopLoss > 0) {
      sl = (posType == POSITION_TYPE_BUY) ? 
           entryPrice - (StopLoss * _Point) : 
           entryPrice + (StopLoss * _Point);
   }

   if(UseKumoSL && ichimokuHandleCur != INVALID_HANDLE) {
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

   return (sl > 0) ? NormalizeDouble(sl, digits) : 0.0;
}

double CalculateTakeProfit(ENUM_POSITION_TYPE posType, double entryPrice) {
   double tp = 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(UseADR && adr > 0) {
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

double CalculateLotSize(double sl, double entryPrice) {
   if(LotType == LOT_FIXED) return NormalizeVolume(LotSize);
   if(sl == 0.0 || MathAbs(entryPrice - sl) < _Point) return NormalizeVolume(LotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyFloor = startDayBalance - MaxDailyLossAmount;
   double overallFloor = InitialBalance - MaxOverallLossAmount;

   double riskAmount = balance * (RiskPercent / 100.0);
   double remainingDaily = equity - dailyFloor;
   double remainingOverall = equity - overallFloor;
   double maxRiskFromBuffer = MathMin(remainingDaily, remainingOverall) * 0.9;
   double maxRiskFromDaily = MaxDailyLossAmount * MaxRiskPerTradeFraction;

   riskAmount = MathMin(riskAmount, maxRiskFromBuffer);
   riskAmount = MathMin(riskAmount, maxRiskFromDaily);

   if(riskAmount <= 0) return NormalizeVolume(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double slDistance = MathAbs(entryPrice - sl);
   double slPoints = slDistance / _Point;
   double valuePerPt = ValuePerPoint();

   if(valuePerPt <= 0.0 || slPoints <= 0.0) return NormalizeVolume(LotSize);

   double lotSize = riskAmount / (slPoints * valuePerPt);
   return NormalizeVolume(lotSize);
}

// Wires the existing StageTracker so each ticket takes TP1 once and TP2 once.
// Percents, distances, and trailing activation are unchanged. Stage advances
// only when that stage's plan is fully done, so a pending TP1 cannot be
// consumed by TP2 and cannot be re-percented on the next tick.
#define TEST4_STAGE_SLOTS 64

string Test4StagePrefix() {
   return "T4STG_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + _Symbol + "_";
}

string Test4StageGv(const ulong ident) {
   return Test4StagePrefix() + IntegerToString((long)ident);
}

int Test4FindStage(const ulong ticket) {
   int n = ArraySize(stages);
   for(int i = 0; i < n; i++)
      if(stages[i].ticket == ticket) return i;
   return -1;
}

bool Test4IdentStillOpen(const ulong ident, const ulong ticket) {
   if(ticket != 0 && PositionSelectByTicket(ticket))
      return true;
   if(ident == 0)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong openTicket = PositionGetTicket(i);
      if(openTicket == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == ident)
         return true;
   }
   return false;
}

bool Test4IdentConfirmedClosed(const ulong ident) {
   if(ident == 0) return false;
   if(Test4IdentStillOpen(ident, 0)) return false;
   if(!HistorySelectByPosition(ident)) return false;
   return (HistoryDealsTotal() > 0);
}

int Test4StageFromHistory(const ulong ident) {
   if(ident == 0 || !HistorySelectByPosition(ident)) return 0;
   int found = 0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++) {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      string comment = HistoryDealGetString(deal, DEAL_COMMENT);
      if(StringFind(comment, "|TP2") >= 0) found = MathMax(found, 2);
      else if(StringFind(comment, "|TP1") >= 0) found = MathMax(found, 1);
   }
   return found;
}

void Test4RemoveStageSlot(const int idx) {
   int last = ArraySize(stages) - 1;
   if(idx < 0 || idx > last) return;
   stages[idx] = stages[last];
   ArrayResize(stages, last);
}

void Test4PruneClosedStages() {
   for(int i = ArraySize(stages) - 1; i >= 0; i--) {
      if(Test4IdentStillOpen(stages[i].ident, stages[i].ticket))
         continue;
      if(!Test4IdentConfirmedClosed(stages[i].ident))
         continue;
      string key = Test4StageGv(stages[i].ident);
      if(stages[i].ident != 0 && GlobalVariableCheck(key))
         GlobalVariableDel(key);
      Test4RemoveStageSlot(i);
   }
}

void Test4PruneStageGlobals() {
   string prefix = Test4StagePrefix();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--) {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0) continue;
      ulong ident = (ulong)StringToInteger(StringSubstr(name, StringLen(prefix)));
      if(Test4IdentStillOpen(ident, 0)) continue;
      if(!Test4IdentConfirmedClosed(ident)) continue;
      GlobalVariableDel(name);
   }
}

bool Test4RememberStage(const ulong ticket, const ulong ident, const int stage) {
   int idx = Test4FindStage(ticket);
   if(idx >= 0) {
      stages[idx].stage = stage;
      if(ident != 0) stages[idx].ident = ident;
      return true;
   }
   Test4PruneClosedStages();
   int n = ArraySize(stages);
   if(n >= TEST4_STAGE_SLOTS) {
      Print("[TEST4] stage table full; not overwriting an active slot ticket=", ticket);
      return false;
   }
   ArrayResize(stages, n + 1);
   stages[n].ticket = ticket;
   stages[n].ident = ident;
   stages[n].stage = stage;
   stages[n].profitLocked = 0.0;
   return true;
}

int Test4LoadPersistedStage(const ulong ticket) {
   if(!PositionSelectByTicket(ticket)) return 0;
   ulong ident = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(ident == 0) ident = ticket;
   string key = Test4StageGv(ident);
   int stage = 0;
   if(GlobalVariableCheck(key))
      stage = (int)GlobalVariableGet(key);
   if(stage <= 0)
      stage = Test4StageFromHistory(ident);
   if(stage > 0) {
      GlobalVariableSet(key, (double)stage);
      Test4RememberStage(ticket, ident, stage);
   }
   return stage;
}

int Test4GetStage(const ulong ticket) {
   int idx = Test4FindStage(ticket);
   if(idx >= 0) return stages[idx].stage;
   return Test4LoadPersistedStage(ticket);
}

void Test4SetStage(const ulong ticket, const int stage) {
   if(ticket == 0) return;
   ulong ident = 0;
   if(PositionSelectByTicket(ticket)) {
      ident = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(ident == 0) ident = ticket;
      GlobalVariableSet(Test4StageGv(ident), (double)stage);
   }
   Test4RememberStage(ticket, ident, stage);
}

void Test4RestoreOpenStages() {
   Test4PruneStageGlobals();
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      Test4LoadPersistedStage(ticket);
   }
}

//+------------------------------------------------------------------+
//| STAGE PROFIT MANAGEMENT (NEW!)                                  
//+------------------------------------------------------------------+
void ManageStagedProfits() {
   Test4PruneClosedStages();
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

         int stageNow = Test4GetStage(ticket);
         bool tp1StillOpen = false;

         // STAGE 1: Close 25% at 30 pips. Once per ticket.
         if(UseStageExits && stageNow < 1 && profitDistance >= TP1_Distance && position.Volume() > 0.01) {
            double volumeToClose = NormalizeVolume(position.Volume() * TP1_ClosePercent);
            volumeToClose = GGate_PartialPlanVolume(ticket, 1, volumeToClose);
            if(volumeToClose >= 0.01) {
               ulong tp1Deal = 0;
               double tp1Filled = 0;
               int tp1Outcome = GGate_ClosePartialTaggedEx(trade, ticket, volumeToClose, GGATE_REASON_TP1, tp1Deal, tp1Filled, "", 1);
               if(GGate_PartialPlanApply(ticket, 1, volumeToClose, tp1Outcome, tp1Filled))
                  Test4SetStage(ticket, 1);
               else if(tp1Outcome == GGATE_CLOSE_PENDING || tp1Outcome == GGATE_CLOSE_PARTIAL)
                  tp1StillOpen = true;
               Print("TP1 ", GGate_CloseOutcomeText(tp1Outcome), ": closed ", tp1Filled, " of ", volumeToClose,
                     " at ", TP1_Distance, " pips");
            }
         }

         if(!position.SelectByTicket(ticket))
            continue;
         stageNow = Test4GetStage(ticket);

         // STAGE 2: Close 30% at 50 pips of the volume still open. Once per ticket.
         // Not started while TP1's own close is still pending or only partly filled.
         if(UseStageExits && !tp1StillOpen && stageNow < 2 && profitDistance >= TP2_Distance && position.Volume() > 0.01) {
            double volumeToClose = NormalizeVolume(position.Volume() * TP2_ClosePercent);
            volumeToClose = GGate_PartialPlanVolume(ticket, 2, volumeToClose);
            if(volumeToClose >= 0.01) {
               ulong tp2Deal = 0;
               double tp2Filled = 0;
               int tp2Outcome = GGate_ClosePartialTaggedEx(trade, ticket, volumeToClose, GGATE_REASON_TP2, tp2Deal, tp2Filled, "", 2);
               if(GGate_PartialPlanApply(ticket, 2, volumeToClose, tp2Outcome, tp2Filled))
                  Test4SetStage(ticket, 2);
               Print("TP2 ", GGate_CloseOutcomeText(tp2Outcome), ": closed ", tp2Filled, " of ", volumeToClose,
                     " at ", TP2_Distance, " pips");
            }
         }

         // STAGE 3: Trail remaining
         if(UseStageExits && UseTrailingOnRemainder && profitDistance >= TrailingActivation) {
            double trailingStopPrice = 0;
            if(posType == POSITION_TYPE_BUY) {
               trailingStopPrice = currentPrice - (TrailingDistance * _Point);
               if(position.StopLoss() < trailingStopPrice - _Point) {
                  trade.PositionModify(ticket, trailingStopPrice, 0);
               }
            } else {
               trailingStopPrice = currentPrice + (TrailingDistance * _Point);
               if(position.StopLoss() > trailingStopPrice + _Point) {
                  trade.PositionModify(ticket, trailingStopPrice, 0);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK FOR TRADING SIGNALS                                       
//+------------------------------------------------------------------+
void CheckForTradingSignals() {
   if(!IsTradingTimeAllowed()) return;

   int signal = CheckIndicatorFilters();
   if(signal == 0) return;

   // 2026-10-05: 1-per-bar PF-priority diversification gate (additive, fail-open).
   if(UseGuardBarGate && !GGate_ShouldOpen(MagicNumber))
      return;

   // 2026-10-13: fleet-wide min re-entry distance gate (additive, fail-open). OFF by default on
   // the Guard (UsePriceDistanceGate=false) -- GGate_PriceDistanceOk() returns true until enabled.
   if(!GGate_PriceDistanceOk())
      return;

   // 2026-10-13: per-direction loss-cooldown enforcement gate (additive, fail-open). OFF by
   // default on the Guard (UseLossCooldownGate=false) -- GGate_LossCooldownOk() returns true
   // until enabled.
   if(!GGate_LossCooldownOk((signal == 1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
      return;

   // 2026-10-14: fleet-wide same-instant pile-on gate (additive, fail-open). OFF by default on
   // the Guard (UseFleetOpenCooldownGate=false) -- GGate_FleetOpenCooldownOk() returns true until
   // enabled. Catches the race the price-distance gate above can't (multiple EAs reading its
   // once-per-tick snapshot before anyone's open registers).
   if(!GGate_FleetOpenCooldownOk())
      return;

   // Final pre-order gate. Missing or stale Guard state fail-opens.
   // FLAT_REQ is not read.
   if(GGate_EntryBlocked(MagicNumber, "hybrid"))
      return;

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(OneTradePerBar && lastTradeBarTime == currentBarTime) return;

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
               GGate_CloseTagged(trade, position.Ticket(), GGATE_REASON_MAN, "OppFlip");
            }
         }
      }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = CalculateStopLoss(POSITION_TYPE_BUY, ask);
      double tp = CalculateTakeProfit(POSITION_TYPE_BUY, ask);
      double lot = CalculateLotSize(sl, ask);
      string comment = StringFormat("BUY|MN:%d|Stage", MagicNumber);

      if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lot, ask, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         lastTradeBarTime = currentBarTime;
         Print("BUY OPENED: ", ask, " SL: ", sl, " TP: ", tp, " Lot: ", lot);
      }
   }
   else if(signal == -1) {
      if(posCount >= MaxSellPositions) return;

      if(CloseOpposite) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
               position.Magic() == MagicNumber && position.PositionType() == POSITION_TYPE_BUY) {
               GGate_CloseTagged(trade, position.Ticket(), GGATE_REASON_MAN, "OppFlip");
            }
         }
      }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = CalculateStopLoss(POSITION_TYPE_SELL, bid);
      double tp = CalculateTakeProfit(POSITION_TYPE_SELL, bid);
      double lot = CalculateLotSize(sl, bid);
      string comment = StringFormat("SELL|MN:%d|Stage", MagicNumber);

      if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lot, bid, sl, tp, comment)) {
         GGate_StampFleetOpen();  // 2026-10-14: fleet-wide same-instant pile-on gate
         lastTradeBarTime = currentBarTime;
         Print("SELL OPENED: ", bid, " SL: ", sl, " TP: ", tp, " Lot: ", lot);
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

   if(UseIchimoku) {
      string statusIchi = SignalToString(ichiSignal);
      CreateLabel("Legend_Ichi", "  Ichimoku: " + statusIchi, x+10, y, SignalColor(ichiSignal), fontSize-1);
      y += lineHeight;
   }

   if(UseEMACross) {
      string statusEMA = SignalToString(emaSignal);
      CreateLabel("Legend_EMA", "  EMA Cross: " + statusEMA, x+10, y, SignalColor(emaSignal), fontSize-1);
      y += lineHeight;
   }

   if(UsePSAR) {
      string statusPSAR = SignalToString(psarSignal);
      CreateLabel("Legend_PSAR", "  PSAR: " + statusPSAR, x+10, y, SignalColor(psarSignal), fontSize-1);
      y += lineHeight;
   }

   CreateLabel("Legend_L1_Result", "  → Result: " + SignalToString(l1Signal), x+5, y, SignalColor(l1Signal), fontSize, "Arial Bold");
   y += lineHeight + 3;

   // === LAYER 2: MOMENTUM ===
   CreateLabel("Legend_L2_Title", "▼ LAYER 2: Momentum", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   if(UseMACD) {
      CreateLabel("Legend_MACD", "  MACD: " + SignalToString(l2MACDSignal), x+10, y, SignalColor(l2MACDSignal), fontSize-1);
      y += lineHeight;
   }

   if(UseRSI) {
      CreateLabel("Legend_RSI", "  RSI: " + SignalToString(l2RSISignal), x+10, y, SignalColor(l2RSISignal), fontSize-1);
      y += lineHeight;
   }

   if(UseADX) {
      string adxStatus = l2ADXOk ? "STRONG" : "WEAK";
      color adxColor = l2ADXOk ? clrDarkGreen : clrDarkRed;
      CreateLabel("Legend_ADX", "  ADX: " + adxStatus, x+10, y, adxColor, fontSize-1);
      y += lineHeight;
   }

   bool l2Pass = CheckLayer2Momentum(l1Signal);
   CreateLabel("Legend_L2_Result", "  → Result: " + (l2Pass ? "PASS" : "FAIL"), x+5, y, l2Pass ? clrDarkGreen : clrDarkRed, fontSize, "Arial Bold");
   y += lineHeight + 3;

   // === LAYER 3: ENTRY TRIGGERS ===
   CreateLabel("Legend_L3_Title", "▼ LAYER 3: Entry Triggers", x, y, clrNavy, fontSize, "Arial Bold");
   y += lineHeight;

   if(UseBollinger) {
      CreateLabel("Legend_BB", "  Bollinger: " + SignalToString(l3BollSignal), x+10, y, SignalColor(l3BollSignal), fontSize-1);
      y += lineHeight;
   }

   if(UseOBV) {
      CreateLabel("Legend_OBV", "  OBV: " + SignalToString(l3OBVSignal), x+10, y, SignalColor(l3OBVSignal), fontSize-1);
      y += lineHeight;
   }

   if(UseDonchian) {
      CreateLabel("Legend_Donchian", "  Donchian: " + SignalToString(l3DonchianSignal), x+10, y, SignalColor(l3DonchianSignal), fontSize-1);
      y += lineHeight;
   }

   int l3Signal = GetLayer3Trigger();
   CreateLabel("Legend_L3_Result", "  → Result: " + SignalToString(l3Signal), x+5, y, SignalColor(l3Signal), fontSize, "Arial Bold");
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
      color adxColor = (adxVals[0] > StrongADXThreshold) ? clrDarkGreen : (adxVals[0] > ADXThreshold) ? clrOrange : clrDarkRed;
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
   double dailyFloor = startDayBalance - MaxDailyLossAmount;
   double overallFloor = InitialBalance - MaxOverallLossAmount;
   double dailyRemaining = equity - dailyFloor;
   double overallRemaining = equity - overallFloor;

   CreateLabel("MarketCond_FTMO", "▼ FTMO PROTECTION", x, y, clrNavy, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
   y += lineHeight;

   color dailyColor = (dailyRemaining > MaxDailyLossAmount * 0.5) ? clrDarkGreen : (dailyRemaining > MaxDailyLossAmount * 0.2) ? clrOrange : clrDarkRed;
   CreateLabel("MarketCond_DailyRem", StringFormat("Daily Remaining: %.2f", dailyRemaining), x, y, dailyColor, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   y += lineHeight;

   color overallColor = (overallRemaining > MaxOverallLossAmount * 0.5) ? clrDarkGreen : (overallRemaining > MaxOverallLossAmount * 0.2) ? clrOrange : clrDarkRed;
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
   if(UseStageExits && posCount > 0) {
      y += 2;
      CreateLabel("MarketCond_StageTitle", "▼ STAGE TARGETS", x, y, clrNavy, fontSize, "Arial Bold", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_TP1", StringFormat("TP1: %d pips (%.0f%%)", TP1_Distance, TP1_ClosePercent*100), x, y, clrDarkOrange, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_TP2", StringFormat("TP2: %d pips (%.0f%%)", TP2_Distance, TP2_ClosePercent*100), x, y, clrDarkOrange, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
      y += lineHeight;

      CreateLabel("MarketCond_Trail", StringFormat("Trail: %d pips @ %d pips", TrailingDistance, TrailingActivation), x, y, clrDarkGreen, fontSize-1, "Arial", CORNER_RIGHT_UPPER);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           
//+------------------------------------------------------------------+
int OnInit() {
   if(!GGate_RequireHedgingAccount())
      return INIT_FAILED;
   string stageWhy = "";
   if(!GGate_ValidateStageConfig(UseStageExits, false,
                                 TP1_Distance, TP2_Distance, TP1_ClosePercent, TP2_ClosePercent,
                                 0.0, 0.0, 0.0,
                                 TrailingActivation, TrailingDistance,
                                 MaxBuyPositions, MaxSellPositions, -1,
                                 stageWhy)) {
      Print(stageWhy);
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);

   atrHandle = iATR(_Symbol, _Period, ADRPeriod);
   if(atrHandle == INVALID_HANDLE) return INIT_FAILED;

   if(UseIchimoku) {
      ichimokuHandleHTF = iIchimoku(_Symbol, HigherTimeframe, IchimokuTenkan, IchimokuKijun, IchimokuSenkou);
      if(ichimokuHandleHTF == INVALID_HANDLE) return INIT_FAILED;

      if(UseKumoSL) {
         ichimokuHandleCur = iIchimoku(_Symbol, _Period, IchimokuTenkan, IchimokuKijun, IchimokuSenkou);
         if(ichimokuHandleCur == INVALID_HANDLE) return INIT_FAILED;
      }
   }

   if(UseEMACross) {
      emaFastHandle = iMA(_Symbol, HigherTimeframe, EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      emaSlowHandle = iMA(_Symbol, HigherTimeframe, EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UsePSAR) {
      psarHandle = iSAR(_Symbol, HigherTimeframe, PSARStep, PSARMax);
      if(psarHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseMACD) {
      macdHandle = iMACD(_Symbol, _Period, MACDFast, MACDSlow, MACDSignal, MACDPrice);
      if(macdHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseRSI) {
      rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseADX || UseMarketFilter) {
      adxHandle = iADX(_Symbol, _Period, ADXPeriod);
      if(adxHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseBollinger) {
      bollHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDev, PRICE_CLOSE);
      if(bollHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseOBV) {
      obvHandle = iOBV(_Symbol, _Period, VOLUME_TICK);
      if(obvHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   if(UseVolatilityRatio) {
      atrShortHandle = iATR(_Symbol, _Period, ATRShortPeriod);
      atrLongHandle = iATR(_Symbol, _Period, ATRLongPeriod);
      if(atrShortHandle == INVALID_HANDLE || atrLongHandle == INVALID_HANDLE) return INIT_FAILED;
   }

   startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   ArrayResize(stages, 0);
   Test4RestoreOpenStages();

   Print("═════════════════════════════════════════");
   Print("test4_clean_HYBRID v5.2 Initialized");
   Print("Magic: ", MagicNumber);
   Print("Stage Exits: ", UseStageExits);
   if(UseStageExits) {
      Print("TP1: ", TP1_Distance, " pips (", (int)(TP1_ClosePercent*100), "%)");
      Print("TP2: ", TP2_Distance, " pips (", (int)(TP2_ClosePercent*100), "%)");
      Print("Trailing: ", TrailingDistance, " pips");
   }
   Print("Entry Mode: ", UseStrictLayers ? "STRICT" : "FLEXIBLE");
   Print("Volatility Filters: ENABLED");
   Print("Legend: LEFT=", ShowLeftLegend, " RIGHT=", ShowRightLegend);
   Print("═════════════════════════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| REGIME 2.3 OnTester PORT -- shared scoring module                |
//| Ported verbatim (logic unchanged) from bot1_regime2.3.mq5's       |
//| current OnTester(), 2026-09-22/23, per user request to confront   |
//| every EA on this account against ONE common selection criterion.  |
//| All new inputs/functions are prefixed R23_ to guarantee zero name |
//| collisions with this file's own pre-existing inputs/functions.    |
//+------------------------------------------------------------------+
input group "═══ REGIME 2.3 SHARED ONTESTER (ported score, 2026-09-23) ═══"
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
//| OnDeinit                                                         
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DeleteLegendObjects();

   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
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
   if(atrShortHandle != INVALID_HANDLE) IndicatorRelease(atrShortHandle);
   if(atrLongHandle != INVALID_HANDLE) IndicatorRelease(atrLongHandle);
}

//+------------------------------------------------------------------+
//| OnTick                                                           
//+------------------------------------------------------------------+
void OnTick() {
   adr = CalculateADR(ADRPeriod);

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime != lastBarTime);

   if(isNewBar) {
      lastBarTime = currentBarTime;
      CheckForTradingSignals();
   }

   ManageStagedProfits();

   // Update legends every tick
   DrawLeftLegend();
   DrawRightLegend();

   ChartRedraw();
}
//+------------------------------------------------------------------+
