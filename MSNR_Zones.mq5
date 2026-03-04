//+------------------------------------------------------------------+
//|                                              MSNR_Zones.mq5      |
//|                    Malaysian SNR Zone Indicator  v3.0             |
//|                                                                   |
//|  PIPELINE PER CANDLE:                                             |
//|  1. Engulf candidate MUST sit at a ZigZag A or V level (p=15)    |
//|     BUY:  bearish after bullish, R[i-1] is a zigzag HIGH (A)     |
//|     SELL: bullish after bearish, R[i-1] is a zigzag LOW  (V)     |
//|  2. ISL check (sell/buy strictly separated, 3 cases each)        |
//|  3. Double breakout — from engulf going RIGHT:                   |
//|     BUY:  2 fresh A levels (highs) broken above                  |
//|     SELL: 2 fresh V levels (lows)  broken below                  |
//|     Fresh = level not broken between its bar and the engulf      |
//|  4. Zone not already broken by later price action                |
//|  5. Draw zone = full wick range of ISL candle                    |
//+------------------------------------------------------------------+
#property copyright   "MSNR Trading System"
#property version     "3.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "SellEngulf"
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrRed

#property indicator_label2  "BuyEngulf"
#property indicator_type2   DRAW_NONE
#property indicator_color2  clrLime

//=============================================================================
//  INPUTS
//=============================================================================
input group "=== Scan Settings ==="
input int   InpLookback      = 2000;  // Bars to scan back
input int   InpZZPeriod      = 10;   // Period (A/V levels + breakout)
input int   InpEngulfWindow  = 5;    // Bars left of engulf to search for breakout A/V
input int   InpBOScan        = 1000;  // Bars left to search for fresh EG 

input group "=== Zone Appearance ==="
input color InpSellColor   = C'78,7,21';
input color InpBuyColor    = C'15,45,29';
input uchar InpZoneAlpha   = 80;
input int   InpZoneBorder  = 1;
input int   InpZoneLen     = 500;            // Zone length in bars to the right

input group "=== Double Breakout Lines ==="
input bool  InpShowBOLines = true;
input int   InpBOLineLen   = 50;             // Bars extending RIGHT from pivot
input color InpBOLineColor = clrWhiteSmoke;
input int   InpBOLineWidth = 1;
input ENUM_LINE_STYLE InpBOLineStyle = STYLE_SOLID;

//=============================================================================
//  STRUCTURE
//=============================================================================
struct ZoneData {
   string   name;
   double   zHigh;
   double   zLow;
   datetime zTime;
   bool     isBuy;
};

//=============================================================================
//  GLOBALS
//=============================================================================
double   SellEngulfBuffer[];
double   BuyEngulfBuffer[];
ZoneData g_zones[600];
int      g_zoneCount = 0;
int      g_zzHandle  = INVALID_HANDLE;  // period 15 — A/V levels and breakout

datetime g_endTime = D'2030.12.31 00:00';

//=============================================================================
//  HELPERS
//=============================================================================
string SafeName(datetime t) {
   string s = TimeToString(t, TIME_DATE|TIME_MINUTES);
   StringReplace(s, ".", "");
   StringReplace(s, " ", "_");
   StringReplace(s, ":", "");
   return s;
}

// Blend zone color toward white for fill (avoids ARGB byte-swap bug)
color BlendWithWhite(color c, uchar alpha) {
   int r = (int)((c >> 16) & 0xFF);
   int g = (int)((c >> 8)  & 0xFF);
   int b = (int)( c        & 0xFF);
   double a = alpha / 255.0;
   r = (int)(r * a + 255.0 * (1.0 - a));
   g = (int)(g * a + 255.0 * (1.0 - a));
   b = (int)(b * a + 255.0 * (1.0 - a));
   return (color)((r << 16) | (g << 8) | b);
}

//=============================================================================
//  INIT / DEINIT
//=============================================================================
int OnInit() {
   SetIndexBuffer(0, SellEngulfBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BuyEngulfBuffer,  INDICATOR_DATA);
   ArraySetAsSeries(SellEngulfBuffer, true);
   ArraySetAsSeries(BuyEngulfBuffer,  true);

   // Single ZigZag period 10 — used for both A/V level anchoring and breakout
   g_zzHandle = iCustom(_Symbol, _Period, "iHighLowZigZag", InpZZPeriod);
   if(g_zzHandle == INVALID_HANDLE) {
      Alert("MSNR: Could not load iHighLowZigZag. Make sure it is compiled.");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "MSNR v3.0");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(g_zzHandle != INVALID_HANDLE) IndicatorRelease(g_zzHandle);
   DeleteAllObjects();
}

//=============================================================================
//  MAIN
//=============================================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[]) {

   if(rates_total < 50) return 0;

   static int lastTotal = 0;
   if(prev_calculated > 0 && rates_total == lastTotal) return rates_total;
   lastTotal = rates_total;

   DeleteAllObjects();
   ArrayInitialize(SellEngulfBuffer, EMPTY_VALUE);
   ArrayInitialize(BuyEngulfBuffer,  EMPTY_VALUE);

   // Price bars — oldest first (index 0 = oldest)
   MqlRates R[];
   int count = CopyRates(_Symbol, _Period, 0, MathMin(rates_total, InpLookback), R);
   if(count < 20) return 0;
   ArraySetAsSeries(R, false);

   // ZigZag buffers — match exact same bars, oldest first
   // Buffer 0: pivot prices (EMPTY_VALUE at non-pivots)
   // Buffer 1: direction (+1 = high pivot, -1 = low pivot, carries forward)
   double zzVal[];   // zigzag price at pivot bars
   double zzDir[];   // direction at every bar
   ArraySetAsSeries(zzVal, false);
   ArraySetAsSeries(zzDir, false);

   if(CopyBuffer(g_zzHandle, 0, 0, count, zzVal) != count) return 0;
   if(CopyBuffer(g_zzHandle, 1, 0, count, zzDir) != count) return 0;

   ScanForZones(R, zzVal, zzDir, count);
   RemoveOverlappingZones();

   // Data Window buffers
   for(int z = 0; z < g_zoneCount; z++) {
      int bi = iBarShift(_Symbol, _Period, g_zones[z].zTime, false);
      if(bi < 0 || bi >= rates_total) continue;
      if(g_zones[z].isBuy) BuyEngulfBuffer[bi]  = g_zones[z].zHigh;
      else                 SellEngulfBuffer[bi] = g_zones[z].zLow;
   }

   return rates_total;
}

//=============================================================================
//  SCAN — main loop
//=============================================================================
void ScanForZones(const MqlRates &R[], const double &zzVal[],
                  const double &zzDir[], int count) {
   int start = 3;

   for(int i = start; i < count - 2; i++) {

      //--- SELL: bullish candle near a ZZ HIGH (A level)
      if(IsAssumedSellEngulf(R, zzVal, zzDir, i, count)) {
         int islBar = FindSellISL(R, i, count);
         if(islBar >= 0) {
            int bo1 = -1, bo2 = -1;
            if(HasDoubleBreakoutZZ(R, zzVal, zzDir, i, count, false, bo1, bo2)) {
               double zH = R[islBar].high;
               double zL = R[islBar].low;
               if(!IsZoneBroken(R, islBar, count, false, zH, zL)) {
                  DrawZone(R, islBar, false);
                  if(InpShowBOLines && bo1 >= 0 && bo2 >= 0)
                     DrawBOLines(R, bo1, bo2, false);
               }
            }
         }
      }

      //--- BUY: bearish candle near a ZZ LOW (V level)
      if(IsAssumedBuyEngulf(R, zzVal, zzDir, i, count)) {
         int islBar = FindBuyISL(R, i, count);
         if(islBar >= 0) {
            int bo1 = -1, bo2 = -1;
            if(HasDoubleBreakoutZZ(R, zzVal, zzDir, i, count, true, bo1, bo2)) {
               double zH = R[islBar].high;
               double zL = R[islBar].low;
               if(!IsZoneBroken(R, islBar, count, true, zH, zL)) {
                  DrawZone(R, islBar, true);
                  if(InpShowBOLines && bo1 >= 0 && bo2 >= 0)
                     DrawBOLines(R, bo1, bo2, true);
               }
            }
         }
      }
   }
}

//=============================================================================
//  CANDLE TYPE CHECK — near ZigZag period-15 A and V levels
//
//  BUY candidate:
//    R[i] is bearish. A ZigZag LOW pivot (V level) must exist within
//    InpEngulfWindow bars to the LEFT of i (inclusive of i-1).
//    Price dropped to a V level and is now reversing up.
//
//  SELL candidate:
//    R[i] is bullish. A ZigZag HIGH pivot (A level) must exist within
//    InpEngulfWindow bars to the LEFT of i (inclusive of i-1).
//    Price rose to an A level and is now reversing down.
//=============================================================================
bool IsAssumedBuyEngulf(const MqlRates &R[], const double &zzVal[],
                         const double &zzDir[], int i, int count) {
   if(i < 1) return false;
   if(R[i].close >= R[i].open) return false;  // current must be bearish
   // Search left within window for a ZZ LOW pivot (V level)
   int lo = MathMax(0, i - InpEngulfWindow);
   for(int k = i - 1; k >= lo; k--) {
      if(zzVal[k] != EMPTY_VALUE && zzDir[k] == -1.0) return true;
   }
   return false;
}

bool IsAssumedSellEngulf(const MqlRates &R[], const double &zzVal[],
                          const double &zzDir[], int i, int count) {
   if(i < 1) return false;
   if(R[i].close <= R[i].open) return false;  // current must be bullish
   // Search left within window for a ZZ HIGH pivot (A level)
   int lo = MathMax(0, i - InpEngulfWindow);
   for(int k = i - 1; k >= lo; k--) {
      if(zzVal[k] != EMPTY_VALUE && zzDir[k] == 1.0) return true;
   }
   return false;
}

//=============================================================================
//  ISL — SELL ZONES ONLY
//
//  The ISL candle is the one that qualifies by breaking the prior low.
//  Zone = full wick range of that ISL candle.
//
//  Case 1: R[eIdx-1].low < R[eIdx-2].low
//          → R[eIdx-1] is the ISL candle → return eIdx-1
//
//  Case 2: R[eIdx+1].low < R[eIdx-1].low
//          The first post-engulf candle breaks the engulfed candle's low
//          → R[eIdx+1] is the ISL candle → return eIdx+1
//
//  Case 3: R[eIdx+2].low < R[eIdx+1].low
//          The second post-engulf candle breaks the first post-engulf low
//          → R[eIdx+2] is the ISL candle → return eIdx+2
//
//  Fail: return -1 → discard
//=============================================================================
int FindSellISL(const MqlRates &R[], int eIdx, int count) {
   if(eIdx < 2) return -1;
   if(R[eIdx-1].low < R[eIdx-2].low)                              return eIdx-1;
   if(eIdx+1 < count && R[eIdx+1].low < R[eIdx-1].low)           return eIdx+1;
   if(eIdx+2 < count && R[eIdx+2].low < R[eIdx+1].low)           return eIdx+2;
   return -1;
}

//=============================================================================
//  ISL — BUY ZONES ONLY
//
//  The ISL candle is the one that qualifies by breaking the prior high.
//  Zone = full wick range of that ISL candle.
//
//  Case 1: R[eIdx-1].high > R[eIdx-2].high
//          → R[eIdx-1] is the ISL candle → return eIdx-1
//
//  Case 2: R[eIdx+1].high > R[eIdx-1].high
//          The first post-engulf candle breaks the engulfed candle's high
//          → R[eIdx+1] is the ISL candle → return eIdx+1
//
//  Case 3: R[eIdx+2].high > R[eIdx+1].high
//          The second post-engulf candle breaks the first post-engulf high
//          → R[eIdx+2] is the ISL candle → return eIdx+2
//
//  Fail: return -1 → discard
//=============================================================================
int FindBuyISL(const MqlRates &R[], int eIdx, int count) {
   if(eIdx < 2) return -1;
   if(R[eIdx-1].high > R[eIdx-2].high)                            return eIdx-1;
   if(eIdx+1 < count && R[eIdx+1].high > R[eIdx-1].high)         return eIdx+1;
   if(eIdx+2 < count && R[eIdx+2].high > R[eIdx+1].high)         return eIdx+2;
   return -1;
}

//=============================================================================
//  DOUBLE BREAKOUT — ZigZag based with fresh/stale pivot filtering
//
//  SELL engulf — scan LEFT for zigzag LOW pivots:
//    A LOW pivot at bar k is FRESH if no candle between k and eIdx had a
//    low below zzVal[k]. If any candle did go below it → STALE, skip it.
//    Collect the first 2 FRESH lows going left. Save their levels + indices.
//    Then scan RIGHT from eIdx: both saved levels must be broken by price
//    going below them (wick counts = use R[k].low). Both broken → valid.
//
//  BUY engulf — scan LEFT for zigzag HIGH pivots:
//    A HIGH pivot at bar k is FRESH if no candle between k and eIdx had a
//    high above zzVal[k]. If any candle went above it → STALE, skip it.
//    Collect the first 2 FRESH highs going left. Save their levels + indices.
//    Then scan RIGHT from eIdx: both saved levels must be broken by price
//    going above them (wick counts = use R[k].high). Both broken → valid.
//=============================================================================
bool HasDoubleBreakoutZZ(const MqlRates &R[], const double &zzVal[],
                          const double &zzDir[], int eIdx, int count,
                          bool isBuy, int &bo1, int &bo2) {
   bo1 = -1; bo2 = -1;

   int farBack = MathMax(0, eIdx - InpBOScan);

   //--- Step 1: scan LEFT, collect up to 2 FRESH pivots
   double lv1 = 0, lv2 = 0;
   int    found = 0;
   int    tmp[2];

   for(int k = eIdx - 1; k >= farBack && found < 2; k--) {
      if(zzVal[k] == EMPTY_VALUE) continue;

      // Check this is the right pivot type
      if(!isBuy && zzDir[k] != -1.0) continue;  // SELL wants LOW pivots
      if( isBuy && zzDir[k] !=  1.0) continue;  // BUY  wants HIGH pivots

      double pivotLevel = zzVal[k];

      // Freshness check: scan candles between this pivot and the engulf
      // If any candle broke the pivot level → stale, skip
      bool stale = false;
      for(int m = k + 1; m < eIdx; m++) {
         if(!isBuy && R[m].low  < pivotLevel) { stale = true; break; }
         if( isBuy && R[m].high > pivotLevel) { stale = true; break; }
      }
      if(stale) continue;

      // Fresh pivot — keep it
      if(found == 0) { lv1 = pivotLevel; tmp[0] = k; }
      else           { lv2 = pivotLevel; tmp[1] = k; }
      found++;
   }

   if(found < 2) return false;

   //--- Step 2: scan RIGHT from engulf, confirm both levels are broken
   bool broke1 = false, broke2 = false;
   for(int k = eIdx + 1; k < count; k++) {
      if(!isBuy) {
         if(R[k].low < lv1) broke1 = true;
         if(R[k].low < lv2) broke2 = true;
      } else {
         if(R[k].high > lv1) broke1 = true;
         if(R[k].high > lv2) broke2 = true;
      }
      if(broke1 && broke2) break;
   }

   if(!broke1 || !broke2) return false;

   bo1 = tmp[0];
   bo2 = tmp[1];
   return true;
}

//=============================================================================
//  ZONE VALIDITY — skip if already broken after it formed
//  SELL broken: any candle after islBar closed ABOVE zHigh
//  BUY  broken: any candle after islBar closed BELOW zLow
//=============================================================================
bool IsZoneBroken(const MqlRates &R[], int islBar, int count,
                  bool isBuy, double zH, double zL) {
   for(int k = islBar + 1; k < count; k++) {
      if(isBuy  && R[k].close < zL) return true;
      if(!isBuy && R[k].close > zH) return true;
   }
   return false;
}

//=============================================================================
//  DRAW ZONE
//  Zone = full wick range (high–low) of the ISL candle.
//  Fill = zone color blended toward white (no ARGB byte-swap issue).
//=============================================================================
void DrawZone(const MqlRates &R[], int zIdx, bool isBuy) {
   if(g_zoneCount >= 599) return;

   double   zH = R[zIdx].high;
   double   zL = R[zIdx].low;
   datetime zT = R[zIdx].time;
   double   pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   color borderClr = isBuy ? InpBuyColor  : InpSellColor;
   color fillClr   = BlendWithWhite(borderClr, InpZoneAlpha);

   // Duplicate guard — same direction AND same ISL candle time only
   for(int z = 0; z < g_zoneCount; z++) {
      if(g_zones[z].isBuy == isBuy && g_zones[z].zTime == zT) return;
   }

   string name = "MSNR_Z_" + (isBuy ? "B" : "S") + "_" + SafeName(zT);

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, zT, zH,
                    zT + (datetime)(PeriodSeconds(_Period) * InpZoneLen), zL)) return;

   // Border = full zone color. Fill = blended toward white at InpZoneAlpha.
   ObjectSetInteger(0, name, OBJPROP_COLOR,      (long)borderClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    (long)fillClr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpZoneBorder);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);

   g_zones[g_zoneCount].name  = name;
   g_zones[g_zoneCount].zHigh = zH;
   g_zones[g_zoneCount].zLow  = zL;
   g_zones[g_zoneCount].zTime = zT;
   g_zones[g_zoneCount].isBuy = isBuy;
   g_zoneCount++;
}

//=============================================================================
//  DRAW BREAKOUT LINES
//  Line starts at the pivot bar and extends RIGHT (InpBOLineLen bars).
//  No rightward extension — keeps the chart clean.
//=============================================================================
void DrawBOLines(const MqlRates &R[], int bo1, int bo2, bool isBuy) {
   int idx[2]; idx[0] = bo1; idx[1] = bo2;
   int barSecs = PeriodSeconds(_Period);
   string dir  = isBuy ? "B" : "S";

   for(int n = 0; n < 2; n++) {
      // SELL: bo bars are zigzag LOW pivots → line at the low of that bar
      // BUY:  bo bars are zigzag HIGH pivots → line at the high of that bar
      double   lvl = isBuy ? R[idx[n]].high : R[idx[n]].low;
      datetime tp  = R[idx[n]].time;                              // left end = pivot bar
      datetime t1  = tp + (datetime)(barSecs * InpBOLineLen);    // right end
      string   ln  = "MSNR_BO_" + dir + "_" + SafeName(tp) + "_" + (string)n;

      if(ObjectFind(0, ln) >= 0) ObjectDelete(0, ln);
      if(!ObjectCreate(0, ln, OBJ_TREND, 0, tp, lvl, t1, lvl)) continue; // pivot → right

      ObjectSetInteger(0, ln, OBJPROP_COLOR,      InpBOLineColor);
      ObjectSetInteger(0, ln, OBJPROP_STYLE,      InpBOLineStyle);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH,      InpBOLineWidth);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, ln, OBJPROP_RAY_LEFT,   false);
      ObjectSetInteger(0, ln, OBJPROP_BACK,       true);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN,     true);
   }
}

//=============================================================================
//  REMOVE OVERLAPPING ZONES
//  For every pair of zones, if one is fully inside the other (its high is
//  below the outer high AND its low is above the outer low), delete the
//  inner one from the chart and mark it inactive in the array.
//  Direction (buy/sell) does not matter — overlapping zones of any type
//  are collapsed to the outermost one.
//=============================================================================
void RemoveOverlappingZones() {
   for(int a = 0; a < g_zoneCount; a++) {
      if(g_zones[a].name == "") continue;  // already removed

      for(int b = a + 1; b < g_zoneCount; b++) {
         if(g_zones[b].name == "") continue;

         double aH = g_zones[a].zHigh, aL = g_zones[a].zLow;
         double bH = g_zones[b].zHigh, bL = g_zones[b].zLow;

         // Check if b is fully inside a
         if(bH <= aH && bL >= aL) {
            if(ObjectFind(0, g_zones[b].name) >= 0)
               ObjectDelete(0, g_zones[b].name);
            g_zones[b].name = "";
            continue;
         }
         // Check if a is fully inside b
         if(aH <= bH && aL >= bL) {
            if(ObjectFind(0, g_zones[a].name) >= 0)
               ObjectDelete(0, g_zones[a].name);
            g_zones[a].name = "";
            break;  // a is gone, move to next a
         }
      }
   }
}

//=============================================================================
//  CLEANUP
//=============================================================================
void DeleteAllObjects() {
   for(int i = 0; i < g_zoneCount; i++)
      if(ObjectFind(0, g_zones[i].name) >= 0)
         ObjectDelete(0, g_zones[i].name);
   g_zoneCount = 0;

   for(int i = ObjectsTotal(0,0,-1) - 1; i >= 0; i--) {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, "MSNR_") == 0) ObjectDelete(0, n);
   }
}
//+------------------------------------------------------------------+
