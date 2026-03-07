//+------------------------------------------------------------------+
//|                                          MSNR_Levels.mq5         |
//|              SMC-Style Double BOS Zone Detector                  |
//|                                                                   |
//|  Detection order mirrors SMC order block logic:                  |
//|                                                                   |
//|  SELL zone:                                                       |
//|    1. Scan forward. Track fresh V levels (swing lows).           |
//|    2. When a bar's LOW breaks a fresh V level → BOS 1 down       |
//|    3. When another fresh V level is broken    → BOS 2 down       |
//|    4. Look BACK from BOS 1 bar to find the last A level pivot    |
//|       before the move started = the order block candle           |
//|    5. Draw SELL zone at that A level candle                      |
//|                                                                   |
//|  BUY zone:                                                        |
//|    1. Scan forward. Track fresh A levels (swing highs).          |
//|    2. When a bar's HIGH breaks a fresh A level → BOS 1 up        |
//|    3. When another fresh A level is broken    → BOS 2 up         |
//|    4. Look BACK from BOS 1 bar to find the last V level pivot    |
//|       before the move started = the order block candle           |
//|    5. Draw BUY zone at that V level candle                       |
//|                                                                   |
//|  Break = wick OR close crossing the level (both valid).          |
//|  A level is fresh if no bar between it and now touched it.       |
//|  Zone only drawn AFTER double BOS confirmed — never before.      |
//+------------------------------------------------------------------+
#property copyright   "MSNR Trading System"
#property version     "4.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input group "=== ZigZag ==="
input int   InpZZPeriod     = 10;
input int   InpLookback     = 500;
input int   InpBoxExtend    = 50;

input group "=== Level Lines ==="
input color InpAColor       = clrDodgerBlue;
input color InpVColor       = clrOrangeRed;
input int   InpLineWidth    = 1;
input ENUM_LINE_STYLE InpLineStyle = STYLE_SOLID;

input group "=== Zone Boxes ==="
input color InpSellColor    = clrFireBrick;
input color InpBuyColor     = clrForestGreen;
input uchar InpBoxAlpha     = 60;

int g_zzHandle = INVALID_HANDLE;

//=============================================================================
int OnInit() {
   g_zzHandle = iCustom(_Symbol, _Period, "iHighLowZigZag", InpZZPeriod);
   if(g_zzHandle == INVALID_HANDLE) {
      Alert("MSNR: Cannot load iHighLowZigZag.");
      return INIT_FAILED;
   }
   IndicatorSetString(INDICATOR_SHORTNAME, "MSNR Zones v4");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   if(g_zzHandle != INVALID_HANDLE) IndicatorRelease(g_zzHandle);
   DeleteAll();
}

//=============================================================================
//  PIVOT TYPE — by proximity to bar high/low, no zzDir used
//  +1 = A level (swing HIGH), -1 = V level (swing LOW), 0 = not a pivot
//=============================================================================
int PivotType(double val, double barHigh, double barLow) {
   if(val == EMPTY_VALUE || val == 0.0) return 0;
   double dH = MathAbs(val - barHigh);
   double dL = MathAbs(val - barLow);
   if(dH < dL) return  1;
   if(dL < dH) return -1;
   return 0;
}

//=============================================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[], const double &high[],
                const double &low[],  const double &close[],
                const long &tick_volume[], const long &volume[],
                const int &spread[]) {

   if(rates_total < 20) return 0;

   static int lastTotal = 0;
   if(prev_calculated > 0 && rates_total == lastTotal) return rates_total;
   lastTotal = rates_total;

   DeleteAll();

   // oldest-first: index 0 = oldest, index count-1 = current bar
   MqlRates R[];
   int count = CopyRates(_Symbol, _Period, 0, MathMin(rates_total, InpLookback), R);
   if(count < 10) return 0;
   ArraySetAsSeries(R, false);

   double zzVal[];
   ArraySetAsSeries(zzVal, false);
   if(CopyBuffer(g_zzHandle, 0, 0, count, zzVal) != count) return 0;

   int      barSecs = PeriodSeconds(_Period);
   datetime nowTime = R[count-1].time + barSecs;

   //--------------------------------------------------------------------------
   //  Collect all pivots in time order (oldest first)
   //--------------------------------------------------------------------------
   int    pivBar[];  ArrayResize(pivBar,  count);
   double pivVal[];  ArrayResize(pivVal,  count);
   int    pivType[]; ArrayResize(pivType, count);
   int    pivN = 0;

   for(int i = 1; i < count - 1; i++) {
      int pt = PivotType(zzVal[i], R[i].high, R[i].low);
      if(pt == 0) continue;
      pivBar [pivN] = i;
      pivVal [pivN] = zzVal[i];
      pivType[pivN] = pt;
      pivN++;
   }

   //--------------------------------------------------------------------------
   //  MODULE 1 — Fresh level lines
   //--------------------------------------------------------------------------
   for(int pi = 0; pi < pivN; pi++) {
      int    bar = pivBar[pi];
      double lvl = pivVal[pi];
      bool   isA = (pivType[pi] == 1);
      bool   fresh = true;
      for(int k = bar + 1; k < count; k++) {
         if( isA && R[k].high > lvl) { fresh = false; break; }
         if(!isA && R[k].low  < lvl) { fresh = false; break; }
      }
      if(fresh) DrawLevel(R[bar].time, nowTime, lvl, isA);
   }

   //--------------------------------------------------------------------------
   //  MODULE 2 — SMC-style double BOS zone detection
   //
   //  Scan forward bar by bar (oldest to newest = increasing index).
   //  Maintain a live list of fresh levels of each type.
   //  A level stays fresh until a bar's wick or close touches it.
   //
   //  When a bar breaks a fresh level:
   //    → mark that level as broken (BOS event)
   //    → if this is the 2nd break of same type → double BOS confirmed
   //    → look BACK from the first BOS bar to find the last opposing pivot
   //    → that opposing pivot is the order block = zone location
   //
   //  SELL: track fresh V levels. Two broken downward → look back for last A pivot
   //  BUY:  track fresh A levels. Two broken upward   → look back for last V pivot
   //--------------------------------------------------------------------------

   // Fresh level tracking arrays (max 200 active levels at a time)
   double freshA[200]; int freshABar[200]; int freshAN = 0;
   double freshV[200]; int freshVBar[200]; int freshVN = 0;

   // Already-drawn zone anchor bars (to avoid duplicates)
   int drawnBars[500]; int drawnN = 0;

   for(int i = 1; i < count - 1; i++) {

      // --- Add new pivot at this bar to fresh lists ---
      int pt = PivotType(zzVal[i], R[i].high, R[i].low);
      if(pt == 1 && freshAN < 200) {          // A level
         freshA   [freshAN] = zzVal[i];
         freshABar[freshAN] = i;
         freshAN++;
      }
      if(pt == -1 && freshVN < 200) {         // V level
         freshV   [freshVN] = zzVal[i];
         freshVBar[freshVN] = i;
         freshVN++;
      }

      // --- Check this bar for BOS events ---
      // Collect which fresh levels this bar breaks (wick or close)
      // SELL: bar low breaks fresh V levels downward
      // BUY:  bar high breaks fresh A levels upward

      // --- SELL: check fresh V levels broken downward ---
      int   bosVIdx[2]; int bosVN = 0;   // indices into freshV[] that got broken
      for(int vi = 0; vi < freshVN && bosVN < 2; vi++) {
         // A V level is broken if this bar's low goes below it
         // The bar that FORMED the V level cannot break it — skip same bar
         if(freshVBar[vi] >= i) continue;
         if(R[i].low < freshV[vi]) {
            bosVIdx[bosVN] = vi;
            bosVN++;
         }
      }

      if(bosVN >= 2) {
         // Double BOS down confirmed on bar i
         // Find the first BOS bar — the bar that broke the first (most recent) V level
         // Both broken by the same bar here, so first BOS bar = i
         // Look BACK from bar i for the last A level pivot before bar i
         int obBar = -1;
         for(int k = i - 1; k >= 0; k--) {
            if(PivotType(zzVal[k], R[k].high, R[k].low) == 1) { obBar = k; break; }
         }
         if(obBar >= 0 && !AlreadyDrawn(drawnBars, drawnN, obBar)) {
            datetime t0 = R[obBar].time;
            datetime t1 = t0 + (datetime)(barSecs * InpBoxExtend);
            DrawBox(t0, t1, R[obBar].high, R[obBar].low, true);
            drawnBars[drawnN++] = obBar;
         }
         // Remove the broken V levels from fresh list
         RemoveFreshLevel(freshV, freshVBar, freshVN, bosVIdx[0]);
         // Recalculate index after removal (bosVIdx[1] may have shifted)
         if(bosVIdx[1] > bosVIdx[0]) bosVIdx[1]--;
         RemoveFreshLevel(freshV, freshVBar, freshVN, bosVIdx[1]);
      }
      else if(bosVN == 1) {
         // Only one V level broken — remove it, keep scanning for second
         RemoveFreshLevel(freshV, freshVBar, freshVN, bosVIdx[0]);
      }

      // --- BUY: check fresh A levels broken upward ---
      int   bosAIdx[2]; int bosAN = 0;
      for(int ai = 0; ai < freshAN && bosAN < 2; ai++) {
         if(freshABar[ai] >= i) continue;
         if(R[i].high > freshA[ai]) {
            bosAIdx[bosAN] = ai;
            bosAN++;
         }
      }

      if(bosAN >= 2) {
         // Double BOS up confirmed on bar i
         // Look BACK for last V level pivot before bar i
         int obBar = -1;
         for(int k = i - 1; k >= 0; k--) {
            if(PivotType(zzVal[k], R[k].high, R[k].low) == -1) { obBar = k; break; }
         }
         if(obBar >= 0 && !AlreadyDrawn(drawnBars, drawnN, obBar)) {
            datetime t0 = R[obBar].time;
            datetime t1 = t0 + (datetime)(barSecs * InpBoxExtend);
            DrawBox(t0, t1, R[obBar].high, R[obBar].low, false);
            drawnBars[drawnN++] = obBar;
         }
         RemoveFreshLevel(freshA, freshABar, freshAN, bosAIdx[0]);
         if(bosAIdx[1] > bosAIdx[0]) bosAIdx[1]--;
         RemoveFreshLevel(freshA, freshABar, freshAN, bosAIdx[1]);
      }
      else if(bosAN == 1) {
         RemoveFreshLevel(freshA, freshABar, freshAN, bosAIdx[0]);
      }

      // --- Remove any levels that are now stale due to this bar ---
      // A V level is stale (no longer fresh) if bar's low went below it
      // A A level is stale if bar's high went above it
      // (handled by the break detection above — broken levels are removed)
   }

   return rates_total;
}

//=============================================================================
//  REMOVE FROM FRESH LEVEL ARRAY (compact in place)
//=============================================================================
void RemoveFreshLevel(double &vals[], int &bars[], int &n, int idx) {
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++) {
      vals[i] = vals[i+1];
      bars[i] = bars[i+1];
   }
   n--;
}

//=============================================================================
//  ALREADY DRAWN CHECK
//=============================================================================
bool AlreadyDrawn(const int &arr[], int n, int bar) {
   for(int i = 0; i < n; i++)
      if(arr[i] == bar) return true;
   return false;
}

//=============================================================================
//  DRAW ZONE BOX
//=============================================================================
void DrawBox(datetime t0, datetime t1, double hi, double lo, bool isSell) {
   string name = "MSNRZ_" + (isSell ? "S" : "B") + "_" +
                 TimeToString(t0, TIME_DATE|TIME_MINUTES);
   StringReplace(name, ".", "");
   StringReplace(name, " ", "_");
   StringReplace(name, ":", "");

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t0, hi, t1, lo)) return;

   color clr  = isSell ? InpSellColor : InpBuyColor;
   color fill = BlendWithWhite(clr, InpBoxAlpha);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    fill);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_FILL,       true);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//=============================================================================
//  DRAW LEVEL LINE
//=============================================================================
void DrawLevel(datetime t0, datetime t1, double price, bool isHigh) {
   string name = "MSNRL_" + (isHigh ? "A" : "V") + "_" +
                 TimeToString(t0, TIME_DATE|TIME_MINUTES);
   StringReplace(name, ".", "");
   StringReplace(name, " ", "_");
   StringReplace(name, ":", "");

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price)) return;

   color clr = isHigh ? InpAColor : InpVColor;
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      InpLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//=============================================================================
//  BLEND TOWARD WHITE
//=============================================================================
color BlendWithWhite(color c, uchar alpha) {
   int r = (int)((c >> 16) & 0xFF);
   int g = (int)((c >>  8) & 0xFF);
   int b = (int)( c        & 0xFF);
   double a = alpha / 255.0;
   r = (int)(r * a + 255.0 * (1.0 - a));
   g = (int)(g * a + 255.0 * (1.0 - a));
   b = (int)(b * a + 255.0 * (1.0 - a));
   return (color)((r << 16) | (g << 8) | b);
}

//=============================================================================
//  CLEANUP
//=============================================================================
void DeleteAll() {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
      string n = ObjectName(0, i, 0, -1);
      if(StringFind(n, "MSNRL_") == 0 || StringFind(n, "MSNRZ_") == 0)
         ObjectDelete(0, n);
   }
}
//+------------------------------------------------------------------+
