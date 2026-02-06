//+------------------------------------------------------------------+
//|                                     Magic V Binary No-Repaint.mq4 |
//|                               Copyright 2026, Antigravity AI Team|
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI Team"
#property link      "https://www.mql5.com"
#property version   "1.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLime
#property indicator_color2  clrRed
//--- Buffers
double BufferUp[];
double BufferDown[];

//--- Input Parameters
extern string  _             = "--- Strategy Settings ---";
extern int     Depth         = 12;          // ZigZag depth (used for V validation logic)
extern int     Period_RSI    = 14;          // RSI Period
extern double  MinLegSize    = 5;           // Min body size (points) to consider a leg valid
extern bool    UsePointFilter = true;        // Use MinLegSize filter

extern string  __            = "--- Binary Settings ---";
extern int     ExpiryCandles = 1;           // Expiry Candles (1-5)
extern bool    UseMartingale = true;        // Enable Martingale
extern int     MartingaleSteps = 2;         // Martingale Steps (1-3)

extern string  ___           = "--- Visuals ---";
extern color   UpArrowColor  = clrLime;
extern color   DownArrowColor= clrRed;
extern color   WinColor      = clrLime;
extern color   LossColor     = clrRed;
extern int     ArrowWidth    = 2;
extern bool    ShowDebug     = true;        // Show debug messages in Experts tab

extern string  ____          = "--- Timer Settings ---";
extern bool    ShowTimer     = true;        // Show Candle Timer
extern color   TimerColor    = clrGold;     // Timer Color
extern int     TimerFontSize = 16;          // Timer Font Size

//--- Global variants for stats
int total_wins = 0;
int total_loss = 0;
int total_martingale_wins = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- indicator buffers mapping
   SetIndexBuffer(0,BufferUp);
   SetIndexStyle(0,DRAW_ARROW,STYLE_SOLID,ArrowWidth);
   SetIndexArrow(0,233); // Up Arrow
   SetIndexLabel(0,"Buy Signal");
   
   SetIndexBuffer(1,BufferDown);
   SetIndexStyle(1,DRAW_ARROW,STYLE_SOLID,ArrowWidth);
   SetIndexArrow(1,234); // Down Arrow
   SetIndexLabel(1,"Sell Signal");
   
   IndicatorShortName("Magic V Binary No-Repaint v1.1");
   
   //--- Auto-format chart properties (ক্যান্ডেল সাইজ বড় এবং ব্যাকগ্রাউন্ড কালার)
   // Background color - Dark Blue/Gray
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrDarkSlateGray);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(0, CHART_COLOR_GRID, C'40,60,70'); // Subtle grid
   
   // Candle colors - Make them vibrant
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrDodgerBlue);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrRed);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, clrDodgerBlue);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrRed);
   
   // Chart display settings
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES); // Candle chart
   ChartSetInteger(0, CHART_SHOW_GRID, true);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, true);
   ChartSetInteger(0, CHART_SHIFT, true);
   ChartSetInteger(0, CHART_AUTOSCROLL, true);
   
   // Zoom settings - Make candles bigger
   ChartSetInteger(0, CHART_SCALE, 4); // Scale 0-5, 4 is large candles
   ChartSetDouble(0, CHART_SHIFT_SIZE, 25); // Shift percentage
   
   Comment("Magic V Indicator Loaded. Waiting for tick...");
   
   // Enable Timer
   if(ShowTimer) EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(ShowTimer) EventKillTimer();
   ObjectsDeleteAll(0, "MV_"); // Clean up our objects
   Comment("");
  }
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   // Safety check for data sufficiency
   if (rates_total < 50) return(0);

   int i, limit;
   
   //--- Calculation limit
   // IMPORTANT: Fix for Array Out of Range
   // We look back at i+3. So 'i' cannot be equal to 'rates_total-1' 
   // because rates_total-1+3 would be out of bounds.
   // Max 'i' should be rates_total - 1 - 3 = rates_total - 4.
   
   if(prev_calculated == 0) {
      limit = rates_total - 5; 
      total_wins = 0;
      total_loss = 0;
      ObjectsDeleteAll(0, "MV_"); 
      if(ShowDebug) Print("Magic V: Full Latency calculation started on ", rates_total, " bars.");
   }
   else {
      limit = rates_total - prev_calculated + 1;
      // Cap the limit to ensure strictly safe bounds
      if (limit > rates_total - 5) limit = rates_total - 5;
   }
   
   // Main Loop
   for(i = limit; i >= 1; i--)
     {
      // Clear signals for current bar
      BufferUp[i] = EMPTY_VALUE;
      BufferDown[i] = EMPTY_VALUE;

      //---------------------------------------------------------
      // PATTERN RECOGNITION (MAGIC V)
      // Indexes: i (Signal/Reversal), i+1 (Leg), i+2 (Leg), i+3 (Start)
      //---------------------------------------------------------
      
      // 1. POSITIVE (BULLISH) MAGIC V
      // Formation: 
      // i+3: Green (Start of drop)
      // i+2: Red
      // i+1: Red
      // i: Green (Reversal)
      
      bool c3_green = close[i+3] > open[i+3];
      bool c2_red   = close[i+2] < open[i+2];
      bool c1_red   = close[i+1] < open[i+1];
      bool c0_green = close[i] > open[i];
      
      // Size Filter
      double pnt = Point;
      if(UsePointFilter) {
         if(MathAbs(close[i+2]-open[i+2]) < MinLegSize*pnt) c2_red = false; 
         if(MathAbs(close[i+1]-open[i+1]) < MinLegSize*pnt) c1_red = false; 
      }
      
      // Pattern Logic
      bool isBullishV = false;
      if(c3_green && c2_red && c1_red && c0_green)
      {
         // Strong Reversal Check
         // Close of 'i' must be significant
         double midpoint_drop = (open[i+2] + close[i+1]) / 2.0;
         
         // 1. Strong engulfing of the first red candle's open
         if(close[i] >= open[i+2]) isBullishV = true;
         // 2. Or Recover > 50% of the drop AND Low[i] is the bottom
         else if(close[i] >= midpoint_drop) 
         {
             // Check RSI
             double rsi = iRSI(NULL, 0, Period_RSI, PRICE_CLOSE, i);
             if(rsi > 50) isBullishV = true;
         }
      }
      
      // RSI Filter global
      if(isBullishV)
      {
         double rsi = iRSI(NULL, 0, Period_RSI, PRICE_CLOSE, i);
         if(rsi <= 40) isBullishV = false; // Must be somewhat bullish rsi, not oversold deep
      }
      
      // Execution Bullish
      if(isBullishV)
      {
         BufferUp[i] = low[i] - 10 * Point;
         
         // Binary Outcome Check (History)
         // Signal at bar 'i'
         // For 1-minute expiry (ExpiryCandles=1):
         // - Entry: open[i-1] (next candle after signal)
         // - Expiry: close[i-1] (same candle closes)
         // So we check: close[i-1] vs open[i-1]
         
         if(i >= 1)  // Need at least 1 bar after signal
         {
             double entryPrice = open[i-1];  // Entry at next candle's open
             double expiryClose = close[i-1];  // Close of the same entry candle
             
             // For CALL: Win if expiry close > entry open
             bool win = (expiryClose > entryPrice);
             
             DrawResult(win, i, 0, true);  // Draw at i-1 (offset 0 from signal)
         }
      }

      // 2. NEGATIVE (BEARISH) MAGIC V
      // i+3: Red
      // i+2: Green
      // i+1: Green
      // i: Red
      
      bool c3_red = close[i+3] < open[i+3];
      bool c2_green = close[i+2] > open[i+2];
      bool c1_green = close[i+1] > open[i+1];
      bool c0_red   = close[i] < open[i];
      
      if(UsePointFilter) {
         if(MathAbs(close[i+2]-open[i+2]) < MinLegSize*pnt) c2_green = false; 
         if(MathAbs(close[i+1]-open[i+1]) < MinLegSize*pnt) c1_green = false; 
      }
      
      bool isBearishV = false;
      if(c3_red && c2_green && c1_green && c0_red)
      {
         double midpoint_rise = (open[i+2] + close[i+1]) / 2.0;
         
         if(close[i] <= open[i+2]) isBearishV = true;
         else if(close[i] <= midpoint_rise)
         {
             double rsi = iRSI(NULL, 0, Period_RSI, PRICE_CLOSE, i);
             if(rsi < 50) isBearishV = true;
         }
      }
      
      if(isBearishV)
      {
         double rsi = iRSI(NULL, 0, Period_RSI, PRICE_CLOSE, i);
         if(rsi >= 60) isBearishV = false; // Must be somewhat bearish, not overbought high
      }
      
      if(isBearishV)
      {
         BufferDown[i] = high[i] + 10 * Point;
         
         // Binary Outcome Check (History)
         // Signal at bar 'i'
         // For 1-minute expiry (ExpiryCandles=1):
         // - Entry: open[i-1] (next candle after signal)
         // - Expiry: close[i-1] (same candle closes)
         // So we check: close[i-1] vs open[i-1]
         
         if(i >= 1)  // Need at least 1 bar after signal
         {
             double entryPrice = open[i-1];  // Entry at next candle's open
             double expiryClose = close[i-1];  // Close of the same entry candle
             
             // For PUT: Win if expiry close < entry open
             bool win = (expiryClose < entryPrice);
             
             DrawResult(win, i, 0, false);  // Draw at i-1 (offset 0 from signal)
         }
      }
     } // End Loop
     
   // Live Alerts
   static datetime lastAlertTime = 0;
   if(Time[0] != lastAlertTime)
   {
      if(BufferUp[1] != EMPTY_VALUE && BufferUp[1] != 0) {
         Alert("Magic V: CALL Pattern on ", Symbol());
         PlaySound("alert.wav");
         lastAlertTime = Time[0];
      }
      if(BufferDown[1] != EMPTY_VALUE && BufferDown[1] != 0) {
         Alert("Magic V: PUT Pattern on ", Symbol());
         PlaySound("alert.wav");
         lastAlertTime = Time[0];
      }
   }
   
   // Dashboard update
   UpdateUnstats();
   
   return(rates_total);
  }

void DrawResult(bool win, int signalBar, int expiry, bool isCall)
{
   // Signal is at 'signalBar'
   // Entry candle is at 'signalBar - 1'
   // We draw the win/loss marker ON the entry candle
   
   int entryBar = signalBar - 1;
   if(entryBar < 0) return;
   
   if(win) {
      // Direct win - show checkmark on entry candle
      string objName = "MV_Res_" + TimeToString(Time[entryBar], TIME_DATE|TIME_MINUTES);
      if(ObjectFind(objName) >= 0) return;
      
      datetime t_res = Time[entryBar];
      double p_res = isCall ? High[entryBar] + 15*Point : Low[entryBar] - 15*Point;
      
      ObjectCreate(0, objName, OBJ_TEXT, 0, t_res, p_res);
      ObjectSetString(0, objName, OBJPROP_TEXT, CharToString(252)); // Wingdings checkmark
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 18);  // Bigger size
      ObjectSetString(0, objName, OBJPROP_FONT, "Wingdings");
      ObjectSetInteger(0, objName, OBJPROP_COLOR, WinColor);
      total_wins++;
   } else {
      // Loss - check if martingale is enabled
      if(UseMartingale && MartingaleSteps > 0) {
         // Don't draw loss marker yet - try martingale first
         // Pass the original signal bar for final loss marker placement
         ProcessMartingale(entryBar, isCall, 1, signalBar);
      } else {
         // No martingale - show loss on entry candle
         string objName = "MV_Res_" + TimeToString(Time[entryBar], TIME_DATE|TIME_MINUTES);
         if(ObjectFind(objName) >= 0) return;
         
         datetime t_res = Time[entryBar];
         double p_res = isCall ? High[entryBar] + 15*Point : Low[entryBar] - 15*Point;
         
         ObjectCreate(0, objName, OBJ_TEXT, 0, t_res, p_res);
         ObjectSetString(0, objName, OBJPROP_TEXT, CharToString(251)); // Wingdings X
         ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 18);  // Bigger size
         ObjectSetString(0, objName, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, objName, OBJPROP_COLOR, LossColor);
         total_loss++;
      }
   }
}

void ProcessMartingale(int lossBar, bool isCall, int step, int originalSignalBar)
{
   if(step > MartingaleSteps) {
      // Final loss after all martingale attempts - draw loss marker on LAST martingale candle
      int finalLossBar = lossBar;
      string lossObjName = "MV_Res_" + TimeToString(Time[finalLossBar], TIME_DATE|TIME_MINUTES);
      if(ObjectFind(lossObjName) < 0) {
         double lossPrice = isCall ? High[finalLossBar] + 15*Point : Low[finalLossBar] - 15*Point;
         ObjectCreate(0, lossObjName, OBJ_TEXT, 0, Time[finalLossBar], lossPrice);
         ObjectSetString(0, lossObjName, OBJPROP_TEXT, CharToString(251)); // Wingdings X
         ObjectSetInteger(0, lossObjName, OBJPROP_FONTSIZE, 18);
         ObjectSetString(0, lossObjName, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, lossObjName, OBJPROP_COLOR, LossColor);
      }
      total_loss++;
      return;
   }
   
   // Next martingale entry is on the next candle
   int martBar = lossBar - 1;
   if(martBar < 0) {
      // Can't continue - draw loss on current bar
      string lossObjName = "MV_Res_" + TimeToString(Time[lossBar], TIME_DATE|TIME_MINUTES);
      if(ObjectFind(lossObjName) < 0) {
         double lossPrice = isCall ? High[lossBar] + 15*Point : Low[lossBar] - 15*Point;
         ObjectCreate(0, lossObjName, OBJ_TEXT, 0, Time[lossBar], lossPrice);
         ObjectSetString(0, lossObjName, OBJPROP_TEXT, CharToString(251));
         ObjectSetInteger(0, lossObjName, OBJPROP_FONTSIZE, 18);
         ObjectSetString(0, lossObjName, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, lossObjName, OBJPROP_COLOR, LossColor);
      }
      total_loss++;
      return;
   }
   
   // Draw martingale arrow (smaller, different color)
   string arrowName = "MV_Mart" + IntegerToString(step) + "_" + TimeToString(Time[martBar]);
   if(ObjectFind(arrowName) < 0) {
      double arrowPrice = isCall ? Low[martBar] - 5*Point : High[martBar] + 5*Point;
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, Time[martBar], arrowPrice);
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isCall ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isCall ? clrYellow : clrOrange);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 1);
   }
   
   // Check martingale result
   double martEntry = Open[martBar];
   double martExit = Close[martBar];
   bool martWin = isCall ? (martExit > martEntry) : (martExit < martEntry);
   
   if(martWin) {
      // Martingale recovered! Show checkmark on THIS candle only
      string martResName = "MV_Res_" + TimeToString(Time[martBar], TIME_DATE|TIME_MINUTES);
      if(ObjectFind(martResName) < 0) {
         double resPrice = isCall ? High[martBar] + 15*Point : Low[martBar] - 15*Point;
         ObjectCreate(0, martResName, OBJ_TEXT, 0, Time[martBar], resPrice);
         ObjectSetString(0, martResName, OBJPROP_TEXT, CharToString(252)); // Checkmark
         ObjectSetInteger(0, martResName, OBJPROP_FONTSIZE, 18);  // Bigger size
         ObjectSetString(0, martResName, OBJPROP_FONT, "Wingdings");
         ObjectSetInteger(0, martResName, OBJPROP_COLOR, WinColor);
         total_wins++;
      }
   } else {
      // Martingale lost, try next step (no marker shown)
      ProcessMartingale(martBar, isCall, step + 1, originalSignalBar);
   }
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!ShowTimer) return;
   
   long timeLeft = (long)(Time[0] + PeriodSeconds() - TimeCurrent());
   
   if(timeLeft < 0) timeLeft = 0;
   
   string timeStr = "";
   long min = timeLeft / 60;
   long sec = timeLeft % 60;
   
   if(min < 10) timeStr += "0";
   timeStr += IntegerToString(min) + ":";
   if(sec < 10) timeStr += "0";
   timeStr += IntegerToString(sec);
   
   string name = "MV_Timer";
   if(ObjectFind(name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 50);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      
      // Static properties set only on creation
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Black");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, TimerFontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, TimerColor);
   }
   
   ObjectSetString(0, name, OBJPROP_TEXT, timeStr); // Removed emoji to fix '?'
   ChartRedraw(0); // Force redraw to reduce flicker
}

void UpdateUnstats()
{
   double winRate = 0;
   int totalSignals = total_wins + total_loss;
   
   if(totalSignals > 0) 
      winRate = (double)total_wins / totalSignals * 100.0;
   
   // Create styled dashboard using OBJ_LABEL objects
   int x = 10;
   int y = 25;
   int lineHeight = 22;
   
   // Title
   string titleObj = "MV_Title";
   if(ObjectFind(titleObj) < 0) {
      ObjectCreate(0, titleObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, titleObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, titleObj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, titleObj, OBJPROP_YDISTANCE, y);
   }
   ObjectSetString(0, titleObj, OBJPROP_TEXT, "⚡ MAGIC V BINARY v1.3");
   ObjectSetString(0, titleObj, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, titleObj, OBJPROP_FONTSIZE, 11);
   ObjectSetInteger(0, titleObj, OBJPROP_COLOR, clrGold);
   
   // Total Signals
   string signalsObj = "MV_Signals";
   if(ObjectFind(signalsObj) < 0) {
      ObjectCreate(0, signalsObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, signalsObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, signalsObj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, signalsObj, OBJPROP_YDISTANCE, y + lineHeight);
   }
   ObjectSetString(0, signalsObj, OBJPROP_TEXT, "Total Signals: " + IntegerToString(totalSignals));
   ObjectSetString(0, signalsObj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, signalsObj, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, signalsObj, OBJPROP_COLOR, clrWhite);
   
   // Wins
   string winsObj = "MV_Wins";
   if(ObjectFind(winsObj) < 0) {
      ObjectCreate(0, winsObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, winsObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, winsObj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, winsObj, OBJPROP_YDISTANCE, y + lineHeight * 2);
   }
   ObjectSetString(0, winsObj, OBJPROP_TEXT, "Wins: " + IntegerToString(total_wins));
   ObjectSetString(0, winsObj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, winsObj, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, winsObj, OBJPROP_COLOR, clrLime);
   
   // Losses
   string lossObj = "MV_Loss";
   if(ObjectFind(lossObj) < 0) {
      ObjectCreate(0, lossObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, lossObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, lossObj, OBJPROP_XDISTANCE, x + 100);
      ObjectSetInteger(0, lossObj, OBJPROP_YDISTANCE, y + lineHeight * 2);
   }
   ObjectSetString(0, lossObj, OBJPROP_TEXT, "| Losses: " + IntegerToString(total_loss));
   ObjectSetString(0, lossObj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, lossObj, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, lossObj, OBJPROP_COLOR, clrRed);
   
   // Win Rate
   string rateObj = "MV_Rate";
   if(ObjectFind(rateObj) < 0) {
      ObjectCreate(0, rateObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, rateObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, rateObj, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, rateObj, OBJPROP_YDISTANCE, y + lineHeight * 3);
   }
   color rateColor = winRate >= 70 ? clrLime : (winRate >= 50 ? clrYellow : clrRed);
   ObjectSetString(0, rateObj, OBJPROP_TEXT, "Win Rate: " + DoubleToString(winRate, 1) + "%");
   ObjectSetString(0, rateObj, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, rateObj, OBJPROP_FONTSIZE, 11);
   ObjectSetInteger(0, rateObj, OBJPROP_COLOR, rateColor);
}
//+------------------------------------------------------------------+
