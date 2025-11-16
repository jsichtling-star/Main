//+------------------------------------------------------------------+
//|                                           ZigZagFibonacciEA.mq5 |
//|                                    Professional Trading Systems |
//|                                       Jan's Retracement Strategy |
//+------------------------------------------------------------------+
#property copyright "Professional Trading Systems"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "ZigZag-Fibonacci Retracement Strategy - CORRECTED"
#property description "BUY/SELL LIMIT orders on retracement levels with partial close"

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters - ZIGZAG SETTINGS                               |
//+------------------------------------------------------------------+
input group "========== ZIGZAG SETTINGS =========="
input int      InpZigZagDepth      = 12;        // ZigZag Depth (3-100)
input int      InpZigZagDeviation  = 5;         // ZigZag Deviation (1-50)
input int      InpZigZagBackstep   = 3;         // ZigZag Backstep (1-20)
input int      InpMinConfirmBars   = 3;         // Min Confirmation Bars (2-10)
input int      InpMinSwingDistance = 200;       // Min Swing Distance in Points (50-10000)

//+------------------------------------------------------------------+
//| Input Parameters - FIBONACCI SETTINGS                            |
//+------------------------------------------------------------------+
input group "========== FIBONACCI SETTINGS =========="
input bool     InpUseLevel_0382    = true;      // Use Fib 0.382 Level (Entry)
input bool     InpUseLevel_0500    = true;      // Use Fib 0.500 Level (Entry)
input bool     InpUseLevel_0618    = true;      // Use Fib 0.618 Level (Entry)
input bool     InpUseLevel_0786    = true;      // Use Fib 0.786 Level (Entry)

enum ENUM_FIB_TP_LEVEL {
   FIB_TP_MINUS_0272 = 0,    // -0.272 (127.2% Extension)
   FIB_TP_MINUS_0618 = 1,    // -0.618 (161.8% Extension)
   FIB_TP_MINUS_1000 = 2,    // -1.000 (200% Extension)
   FIB_TP_MINUS_1618 = 3     // -1.618 (261.8% Extension)
};
input ENUM_FIB_TP_LEVEL InpTakeProfitLevel = FIB_TP_MINUS_0618; // Take Profit Extension

enum ENUM_PRICE_MODE {
   PRICE_MODE_CLOSE_ONLY = 0,  // Use Close Prices Only
   PRICE_MODE_WICKS = 1         // Use High/Low (Wicks)
};
input ENUM_PRICE_MODE InpPriceMode = PRICE_MODE_CLOSE_ONLY; // Price Mode

//+------------------------------------------------------------------+
//| Input Parameters - RISK MANAGEMENT                               |
//+------------------------------------------------------------------+
input group "========== RISK MANAGEMENT =========="
input double   InpRiskPercent      = 0.5;       // Total Risk per Setup % (0.01-5.0)
input double   InpPartialClosePercent = 80.0;   // Partial Close % at Fib 0.0 (1-100)
input int      InpBreakevenBuffer  = 5;         // Breakeven Buffer in Points (0-50)
input int      InpMaxSimultaneousSetups = 3;    // Max Simultaneous Setups (1-10)
input double   InpMaxSpreadPoints  = 20.0;      // Max Spread in Points (0-100)
input int      InpSlippagePoints   = 10;        // Max Slippage in Points (0-100)

//+------------------------------------------------------------------+
//| Input Parameters - TRAILING STOP                                 |
//+------------------------------------------------------------------+
input group "========== TRAILING STOP =========="
enum ENUM_TRAIL_MODE {
   TRAIL_FIXED_PERCENT = 1,     // Fixed % of Setup Range
   TRAIL_ATR_BASED = 2,         // ATR Multiple
   TRAIL_FIBONACCI_LEVELS = 3   // Fibonacci Levels
};
input ENUM_TRAIL_MODE InpTrailMode = TRAIL_FIBONACCI_LEVELS;  // Trailing Mode
input double   InpTrailDistance_Percent = 10.0;  // Trail Distance % (1-50)
input double   InpTrailDistance_ATR = 1.5;       // ATR Multiple (0.5-5.0)
input int      InpTrailATR_Period = 14;          // ATR Period (5-50)
input double   InpTrailActivation_R = 1.0;       // Activate at R-Multiple (0.5-10.0)

//+------------------------------------------------------------------+
//| Input Parameters - DRAWDOWN PROTECTION                           |
//+------------------------------------------------------------------+
input group "========== DRAWDOWN PROTECTION =========="
input bool     InpUseDrawdownFilter = true;     // Use Total Drawdown Filter
input double   InpMaxDrawdownPercent = 10.0;    // Max Total Drawdown % (1-50)
input bool     InpUseDailyLossLimit = true;     // Use Daily Loss Limit
input double   InpMaxDailyLossPercent = 3.0;    // Max Daily Loss % (0.1-20)

//+------------------------------------------------------------------+
//| Input Parameters - TIME FILTER                                   |
//+------------------------------------------------------------------+
input group "========== TIME FILTER =========="
input bool     InpUseTimeFilter    = false;     // Use Time Filter
input int      InpStartHour        = 8;         // Trading Start Hour (0-23)
input int      InpStartMinute      = 0;         // Trading Start Minute (0-59)
input int      InpEndHour          = 20;        // Trading End Hour (0-23)
input int      InpEndMinute        = 0;         // Trading End Minute (0-59)

//+------------------------------------------------------------------+
//| Input Parameters - GENERAL SETTINGS                              |
//+------------------------------------------------------------------+
input group "========== GENERAL SETTINGS =========="
input int      InpMagicNumber      = 100000;    // Magic Number Base
input string   InpTradeComment     = "ZZFib";   // Trade Comment
input bool     InpEnableLogging    = true;      // Enable Detailed Logging
input bool     InpEnableCSVExport  = false;     // Enable CSV Data Export

//+------------------------------------------------------------------+
//| Structure Definitions                                             |
//+------------------------------------------------------------------+

// Fibonacci Setup Structure
struct SFibonacciSetup {
   bool           active;
   datetime       setupTime;
   int            setupID;
   int            trendDirection;        // 1 = Uptrend, -1 = Downtrend
   
   // Fibonacci Levels
   double         fibLevel_0;            // Extreme (High in Up, Low in Down)
   double         fibLevel_1;            // Structure/SL (Low in Up, High in Down)
   double         fibLevels[5];          // 0.236, 0.382, 0.500, 0.618, 0.786
   double         takeProfitLevel;
   
   // Pending Orders (0.382, 0.500, 0.618, 0.786 only!)
   ulong          pendingTickets[4];     // [0]=0.382, [1]=0.500, [2]=0.618, [3]=0.786
   double         pendingPrices[4];
   double         pendingLots[4];
   bool           pendingActive[4];
   
   // Active Positions
   ulong          positionTickets[4];
   bool           partialClosed[4];
   bool           breakEvenSet[4];
   
   // Risk Management
   double         initialSL;
   double         partialClosePrice;     // Fib 0.0 level
   
   // Statistics
   int            pendingCount;
   int            activePositions;
   double         totalRisk;
   
   void Init() {
      active = false;
      setupTime = 0;
      setupID = 0;
      trendDirection = 0;
      fibLevel_0 = 0;
      fibLevel_1 = 0;
      takeProfitLevel = 0;
      initialSL = 0;
      partialClosePrice = 0;
      pendingCount = 0;
      activePositions = 0;
      totalRisk = 0;
      
      for(int i = 0; i < 5; i++) {
         fibLevels[i] = 0;
      }
      
      for(int i = 0; i < 4; i++) {
         pendingTickets[i] = 0;
         pendingPrices[i] = 0;
         pendingLots[i] = 0;
         pendingActive[i] = false;
         positionTickets[i] = 0;
         partialClosed[i] = false;
         breakEvenSet[i] = false;
      }
   }
};

// Fibonacci Monitor
struct SFibonacciMonitor {
   bool           active;
   int            trendDirection;
   datetime       swingTime;
   double         swingPrice;            // Fib 1.0 (Structure/SL)
   datetime       extremeTime;
   double         extremePrice;          // Fib 0.0 (Extreme)
   double         fibLevels[5];
   bool           reached236;
   datetime       timeWhen236Reached;

   void Init() {
      active = false;
      trendDirection = 0;
      swingTime = 0;
      swingPrice = 0;
      extremeTime = 0;
      extremePrice = 0;
      reached236 = false;
      timeWhen236Reached = 0;
      for(int i = 0; i < 5; i++) fibLevels[i] = 0;
   }

   void Reset() {
      Init();
   }
};

// Trading Statistics
struct STradingStats {
   datetime       lastResetTime;
   double         dailyProfit;
   double         totalProfit;
   int            dailySignals;
   int            dailyTrades;
   int            totalTrades;
   bool           dailyLimitReached;
   bool           drawdownLimitReached;
   
   void Reset() {
      lastResetTime = TimeCurrent();
      dailyProfit = 0;
      dailySignals = 0;
      dailyTrades = 0;
      dailyLimitReached = false;
   }
   
   void Init() {
      Reset();
      totalProfit = 0;
      totalTrades = 0;
      drawdownLimitReached = false;
   }
};

// Trend Analysis Structure
struct STrendData {
   bool           hasData;
   int            direction;
   double         lastHigh;
   double         lastLow;
   double         prevHigh;
   double         prevLow;
   datetime       lastHighTime;
   datetime       lastLowTime;
   bool           higherHighs;
   bool           higherLows;
   bool           lowerHighs;
   bool           lowerLows;
   double         swingDistance;

   void Init() {
      hasData = false;
      direction = 0;
      lastHigh = 0;
      lastLow = 0;
      prevHigh = 0;
      prevLow = 0;
      lastHighTime = 0;
      lastLowTime = 0;
      higherHighs = false;
      higherLows = false;
      lowerHighs = false;
      lowerLows = false;
      swingDistance = 0;
   }
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade            g_trade;
CPositionInfo     g_position;
COrderInfo        g_order;

int               g_zigzagHandle = INVALID_HANDLE;
int               g_atrHandle = INVALID_HANDLE;

SFibonacciSetup   g_setups[];
SFibonacciMonitor g_monitorUp;
SFibonacciMonitor g_monitorDown;

datetime          g_zzPointTimes[];
double            g_zzPointPrices[];
int               g_zzPointTypes[];
int               g_zzPointBarIndices[];
bool              g_zzPointConfirmed[];
int               g_zzPointCount = 0;

int               g_nextSetupID = 1;
STradingStats     g_stats;
double            g_startBalance = 0;
int               g_csvHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("═══════════════════════════════════════════════");
   Print("ZigZag-Fibonacci EA v2.00 (CORRECTED) Starting...");
   Print("═══════════════════════════════════════════════");
   
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetAsyncMode(false);
   SetBestFillingMode();
   
   // Try multiple ZigZag paths (different MT5 installations have different structures)
   g_zigzagHandle = iCustom(_Symbol, PERIOD_CURRENT, "Examples\\ZigZag",
                            InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep);

   if(g_zigzagHandle == INVALID_HANDLE) {
      Print("⚠ WARNING: ZigZag not found at 'Examples\\ZigZag', trying alternative path...");
      g_zigzagHandle = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Examples\\ZigZag",
                               InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep);
   }

   if(g_zigzagHandle == INVALID_HANDLE) {
      Print("⚠ WARNING: Trying ZigZag without path...");
      g_zigzagHandle = iCustom(_Symbol, PERIOD_CURRENT, "ZigZag",
                               InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep);
   }

   if(g_zigzagHandle == INVALID_HANDLE) {
      Print("❌ ERROR: Failed to create ZigZag indicator!");
      Print("   Please ensure ZigZag indicator is installed in:");
      Print("   - <MT5_Data>\\MQL5\\Indicators\\Examples\\ZigZag.ex5");
      Print("   - OR compile it from ZigZag.mq5 source");
      return INIT_FAILED;
   }

   Print("✓ ZigZag indicator loaded successfully");

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpTrailATR_Period);
   if(g_atrHandle == INVALID_HANDLE) {
      Print("❌ ERROR: Failed to create ATR indicator!");
      return INIT_FAILED;
   }
   
   ArrayResize(g_setups, InpMaxSimultaneousSetups);
   for(int i = 0; i < InpMaxSimultaneousSetups; i++) {
      g_setups[i].Init();
   }

   g_monitorUp.Init();
   g_monitorDown.Init();

   ArrayResize(g_zzPointTimes, 100);
   ArrayResize(g_zzPointPrices, 100);
   ArrayResize(g_zzPointTypes, 100);
   ArrayResize(g_zzPointBarIndices, 100);
   ArrayResize(g_zzPointConfirmed, 100);
   
   g_stats.Init();
   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(InpEnableCSVExport) InitializeCSV();
   if(!ValidateInputParameters()) return INIT_PARAMETERS_INCORRECT;
   
   // Check if at least one entry level is enabled
   if(!InpUseLevel_0382 && !InpUseLevel_0500 && !InpUseLevel_0618 && !InpUseLevel_0786) {
      Print("❌ ERROR: At least one ENTRY level (0.382-0.786) must be enabled!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   Print("✓ Initialization successful!");
   Print("  Symbol: ", _Symbol);
   Print("  Timeframe: ", PeriodToString(PERIOD_CURRENT));
   Print("  Start Balance: ", DoubleToString(g_startBalance, 2));
   Print("  Risk per Setup: ", DoubleToString(InpRiskPercent, 2), "%");
   Print("  Entry Levels: 0.382, 0.500, 0.618, 0.786");
   Print("  Trigger Level: 0.236 (confirmation only)");
   Print("═══════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   Print("═══════════════════════════════════════════════");
   Print("EA Shutting Down: ", GetDeinitReasonText(reason));
   Print("═══════════════════════════════════════════════");

   if(g_zigzagHandle != INVALID_HANDLE) IndicatorRelease(g_zigzagHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_csvHandle != INVALID_HANDLE) FileClose(g_csvHandle);

   // Clean up ALL chart objects
   CleanupAllChartObjects();
   DeleteMonitorObjects();
   PrintFinalStatistics();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
   static datetime lastBarTime = 0;
   static datetime lastCleanup = 0;

   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (currentBarTime != lastBarTime);

   if(isNewBar) {
      lastBarTime = currentBarTime;
      OnNewBar();

      // Cleanup orphaned chart objects every 10 bars
      if(TimeCurrent() - lastCleanup > PeriodSeconds(PERIOD_CURRENT) * 10) {
         CleanupOrphanedObjects();
         lastCleanup = TimeCurrent();
      }
   }

   CheckSetupValidationTick();
   ManageActiveSetups();
   UpdateMonitorDisplay();
}

//+------------------------------------------------------------------+
//| New Bar Handler                                                   |
//+------------------------------------------------------------------+
void OnNewBar() {
   CheckDailyReset();
   if(!IsTradingAllowed()) return;
   
   UpdateZigZagPoints();
   UpdateFibonacciMonitor();
   DrawMonitorFibonacci();
   Check236Confirmation();
   
   if(InpEnableLogging) {
      LogMessage("INFO", StringFormat("Bar: %s | ZZ: %d | Setups: %d",
                 TimeToString(TimeCurrent(), TIME_MINUTES),
                 g_zzPointCount, GetActiveSetupsCount()));
   }
}

//+------------------------------------------------------------------+
//| Validate Input Parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputParameters() {
   if(InpZigZagDepth < 3 || InpZigZagDepth > 100 ||
      InpZigZagDeviation < 1 || InpZigZagDeviation > 50 ||
      InpMinConfirmBars < 2 || InpMinConfirmBars > 10 ||
      InpRiskPercent < 0.01 || InpRiskPercent > 5.0 ||
      InpPartialClosePercent < 1 || InpPartialClosePercent > 100) {
      Print("❌ ERROR: Invalid input parameters!");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Update ZigZag Points - OPTIMIZED                                  |
//+------------------------------------------------------------------+
void UpdateZigZagPoints() {
   double zzBuffer[];
   ArraySetAsSeries(zzBuffer, true);

   int copied = CopyBuffer(g_zigzagHandle, 0, 0, 100, zzBuffer);
   if(copied <= 0) {
      LogMessage("ERROR", "Failed to copy ZigZag buffer");
      return;
   }

   g_zzPointCount = 0;

   for(int i = InpMinConfirmBars; i < copied && g_zzPointCount < 100; i++) {
      if(zzBuffer[i] > 0) {
         g_zzPointTimes[g_zzPointCount] = iTime(_Symbol, PERIOD_CURRENT, i);
         g_zzPointPrices[g_zzPointCount] = zzBuffer[i];
         g_zzPointBarIndices[g_zzPointCount] = i;
         g_zzPointConfirmed[g_zzPointCount] = true;

         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         g_zzPointTypes[g_zzPointCount] = (MathAbs(zzBuffer[i] - high) < MathAbs(zzBuffer[i] - low)) ? 1 : -1;

         g_zzPointCount++;
      }
   }

   DrawZigZagLines();
}

//+------------------------------------------------------------------+
//| Analyze Trend                                                     |
//+------------------------------------------------------------------+
STrendData AnalyzeTrend() {
   STrendData result;
   result.Init();

   if(g_zzPointCount < 4) return result;

   int highsFound = 0, lowsFound = 0;

   for(int i = 0; i < g_zzPointCount && (highsFound < 2 || lowsFound < 2); i++) {
      if(g_zzPointTypes[i] == 1) {
         if(highsFound == 0) {
            result.lastHigh = g_zzPointPrices[i];
            result.lastHighTime = g_zzPointTimes[i];
         }
         else if(highsFound == 1) {
            result.prevHigh = g_zzPointPrices[i];
         }
         highsFound++;
      }
      else {
         if(lowsFound == 0) {
            result.lastLow = g_zzPointPrices[i];
            result.lastLowTime = g_zzPointTimes[i];
         }
         else if(lowsFound == 1) {
            result.prevLow = g_zzPointPrices[i];
         }
         lowsFound++;
      }
   }

   if(highsFound < 2 || lowsFound < 2) return result;

   result.swingDistance = MathAbs(result.lastHigh - result.lastLow) / _Point;
   if(result.swingDistance < InpMinSwingDistance) return result;

   result.higherHighs = (result.lastHigh > result.prevHigh);
   result.higherLows = (result.lastLow > result.prevLow);
   result.lowerHighs = (result.lastHigh < result.prevHigh);
   result.lowerLows = (result.lastLow < result.prevLow);

   if(result.higherHighs && result.higherLows) {
      result.direction = 1;
   }
   else if(result.lowerHighs && result.lowerLows) {
      result.direction = -1;
   }

   result.hasData = true;
   return result;
}

//+------------------------------------------------------------------+
//| Draw ZigZag Lines                                                 |
//+------------------------------------------------------------------+
void DrawZigZagLines() {
   for(int k = 0; k < 200; k++) {
      string oldName = StringFormat("ZZLine_%d", k);
      if(ObjectFind(0, oldName) >= 0) ObjectDelete(0, oldName);
   }

   for(int i = 0; i < g_zzPointCount - 1; i++) {
      string name = StringFormat("ZZLine_%d", i);
      if(ObjectCreate(0, name, OBJ_TREND, 0, g_zzPointTimes[i], g_zzPointPrices[i],
                      g_zzPointTimes[i+1], g_zzPointPrices[i+1])) {
         color col = (g_zzPointPrices[i+1] > g_zzPointPrices[i]) ? clrLime : clrRed;
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      }
   }
}

//+------------------------------------------------------------------+
//| Update Fibonacci Monitor                                          |
//+------------------------------------------------------------------+
void UpdateFibonacciMonitor() {
   STrendData trend = AnalyzeTrend();

   if(!trend.hasData) {
      g_monitorUp.active = false;
      g_monitorDown.active = false;
      return;
   }

   // ===== UPTREND MONITOR =====
   if(trend.direction == 1) {
      if(!g_monitorUp.active || g_monitorUp.swingTime != trend.lastLowTime) {
         g_monitorUp.Reset();
         g_monitorUp.active = true;
         g_monitorUp.trendDirection = 1;
         g_monitorUp.swingTime = trend.lastLowTime;
         g_monitorUp.swingPrice = trend.lastLow; // Fib 1.0 = SL

         LogMessage("MONITOR", StringFormat("📊 UPTREND Monitor | SL (Fib 1.0): %.5f", trend.lastLow));
      }

      // Find highest High since last Low (Fib 0.0)
      double highestHigh = 0;
      datetime highestHighTime = 0;
      int barsToCheck = iBars(_Symbol, PERIOD_CURRENT) - iBarShift(_Symbol, PERIOD_CURRENT, trend.lastLowTime);

      for(int i = 0; i < barsToCheck && i < 500; i++) {
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(high > highestHigh) {
            highestHigh = high;
            highestHighTime = iTime(_Symbol, PERIOD_CURRENT, i);
         }
      }

      g_monitorUp.extremePrice = highestHigh;
      g_monitorUp.extremeTime = highestHighTime;

      double range = MathAbs(g_monitorUp.extremePrice - g_monitorUp.swingPrice);
      double fibRatios[5] = {0.236, 0.382, 0.500, 0.618, 0.786};

      for(int i = 0; i < 5; i++) {
         g_monitorUp.fibLevels[i] = g_monitorUp.extremePrice - (range * fibRatios[i]);
      }
   }
   else if(g_monitorUp.active && !g_monitorUp.reached236) {
      g_monitorUp.active = false;
   }

   // ===== DOWNTREND MONITOR =====
   if(trend.direction == -1) {
      if(!g_monitorDown.active || g_monitorDown.swingTime != trend.lastHighTime) {
         g_monitorDown.Reset();
         g_monitorDown.active = true;
         g_monitorDown.trendDirection = -1;
         g_monitorDown.swingTime = trend.lastHighTime;
         g_monitorDown.swingPrice = trend.lastHigh; // Fib 1.0 = SL

         LogMessage("MONITOR", StringFormat("📊 DOWNTREND Monitor | SL (Fib 1.0): %.5f", trend.lastHigh));
      }

      double lowestLow = 999999;
      datetime lowestLowTime = 0;
      int barsToCheck = iBars(_Symbol, PERIOD_CURRENT) - iBarShift(_Symbol, PERIOD_CURRENT, trend.lastHighTime);

      for(int i = 0; i < barsToCheck && i < 500; i++) {
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         if(low < lowestLow) {
            lowestLow = low;
            lowestLowTime = iTime(_Symbol, PERIOD_CURRENT, i);
         }
      }

      g_monitorDown.extremePrice = lowestLow;
      g_monitorDown.extremeTime = lowestLowTime;

      double range = MathAbs(g_monitorDown.swingPrice - g_monitorDown.extremePrice);
      double fibRatios[5] = {0.236, 0.382, 0.500, 0.618, 0.786};

      for(int i = 0; i < 5; i++) {
         g_monitorDown.fibLevels[i] = g_monitorDown.extremePrice + (range * fibRatios[i]);
      }
   }
   else if(g_monitorDown.active && !g_monitorDown.reached236) {
      g_monitorDown.active = false;
   }
}

//+------------------------------------------------------------------+
//| Check 0.236 Confirmation - CORRECTED                              |
//+------------------------------------------------------------------+
void Check236Confirmation() {
   // ===== UPTREND =====
   if(g_monitorUp.active && !g_monitorUp.reached236) {
      double fib236 = g_monitorUp.fibLevels[0];
      double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
      double lastLow = iLow(_Symbol, PERIOD_CURRENT, 1);

      bool reached = (InpPriceMode == PRICE_MODE_CLOSE_ONLY) ?
                     (lastClose <= fib236) : (lastLow <= fib236);

      if(reached) {
         LogMessage("SIGNAL", "🎯 UPTREND 0.236 REACHED! Creating setup...");

         g_monitorUp.reached236 = true;
         g_monitorUp.timeWhen236Reached = TimeCurrent();
         
         CreateNewSetup(1, g_monitorUp.extremePrice, g_monitorUp.swingPrice);
      }
   }

   // ===== DOWNTREND =====
   if(g_monitorDown.active && !g_monitorDown.reached236) {
      double fib236 = g_monitorDown.fibLevels[0];
      double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
      double lastHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);

      bool reached = (InpPriceMode == PRICE_MODE_CLOSE_ONLY) ?
                     (lastClose >= fib236) : (lastHigh >= fib236);

      if(reached) {
         LogMessage("SIGNAL", "🎯 DOWNTREND 0.236 REACHED! Creating setup...");

         g_monitorDown.reached236 = true;
         g_monitorDown.timeWhen236Reached = TimeCurrent();
         
         CreateNewSetup(-1, g_monitorDown.extremePrice, g_monitorDown.swingPrice);
      }
   }
}

//+------------------------------------------------------------------+
//| Create New Setup                                                  |
//+------------------------------------------------------------------+
void CreateNewSetup(int trend, double fib0, double fib1) {
   if(GetActiveSetupsCount() >= InpMaxSimultaneousSetups) {
      LogMessage("WARNING", "Max setups reached, skipping");
      return;
   }

   int setupIndex = -1;
   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(!g_setups[i].active) {
         setupIndex = i;
         break;
      }
   }
   
   if(setupIndex == -1) {
      LogMessage("ERROR", "No free setup slot!");
      return;
   }
   
   g_setups[setupIndex].Init();
   g_setups[setupIndex].active = true;
   g_setups[setupIndex].setupTime = TimeCurrent();
   g_setups[setupIndex].setupID = g_nextSetupID++;
   g_setups[setupIndex].trendDirection = trend;
   g_setups[setupIndex].fibLevel_0 = fib0;
   g_setups[setupIndex].fibLevel_1 = fib1;
   g_setups[setupIndex].initialSL = fib1;
   g_setups[setupIndex].partialClosePrice = fib0;
   
   CalculateFibonacciLevels(setupIndex);
   PlacePendingOrders(setupIndex);
   
   g_stats.dailySignals++;
   
   string trendName = (trend == 1) ? "UPTREND" : "DOWNTREND";
   LogMessage("SETUP", StringFormat("═══ Setup #%d Created: %s ═══", g_setups[setupIndex].setupID, trendName));
   LogMessage("INFO", StringFormat("  Fib 0.0 (Extreme): %.5f", fib0));
   LogMessage("INFO", StringFormat("  Fib 1.0 (SL):      %.5f", fib1));
   LogMessage("INFO", StringFormat("  Take Profit:       %.5f", g_setups[setupIndex].takeProfitLevel));
   LogMessage("INFO", StringFormat("  Pending Orders:    %d", g_setups[setupIndex].pendingCount));
   
   if(InpEnableCSVExport) ExportSetupToCSV(setupIndex);
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                        |
//+------------------------------------------------------------------+
void CalculateFibonacciLevels(int setupIndex) {
   double fib0 = g_setups[setupIndex].fibLevel_0;
   double fib1 = g_setups[setupIndex].fibLevel_1;
   double range = MathAbs(fib1 - fib0);
   int trend = g_setups[setupIndex].trendDirection;

   double fibRatios[5] = {0.236, 0.382, 0.500, 0.618, 0.786};

   for(int i = 0; i < 5; i++) {
      if(trend == 1) {
         g_setups[setupIndex].fibLevels[i] = fib0 - (range * fibRatios[i]);
      }
      else {
         g_setups[setupIndex].fibLevels[i] = fib0 + (range * fibRatios[i]);
      }
   }

   double tpExtension = 0;
   switch(InpTakeProfitLevel) {
      case FIB_TP_MINUS_0272: tpExtension = 0.272; break;
      case FIB_TP_MINUS_0618: tpExtension = 0.618; break;
      case FIB_TP_MINUS_1000: tpExtension = 1.000; break;
      case FIB_TP_MINUS_1618: tpExtension = 1.618; break;
   }

   if(trend == 1) {
      g_setups[setupIndex].takeProfitLevel = fib0 + (range * tpExtension);
   }
   else {
      g_setups[setupIndex].takeProfitLevel = fib0 - (range * tpExtension);
   }
   
   DrawFibonacciLevels(setupIndex);
}

//+------------------------------------------------------------------+
//| Place Pending Orders - FEHLERKORREKTUR                            |
//+------------------------------------------------------------------+
void PlacePendingOrders(int setupIndex) {
   /*
   CRITICAL: 0.236 is ONLY a trigger, NOT an entry level!
   We place orders ONLY on: 0.382, 0.500, 0.618, 0.786
   
   Order Types:
   - UPTREND: BUY LIMIT (price must fall to level)
   - DOWNTREND: SELL LIMIT (price must rise to level)
   */
   
   // Entry level configuration (0.236 excluded!)
   bool levelEnabled[4];
   levelEnabled[0] = InpUseLevel_0382;  // 0.382
   levelEnabled[1] = InpUseLevel_0500;  // 0.500
   levelEnabled[2] = InpUseLevel_0618;  // 0.618
   levelEnabled[3] = InpUseLevel_0786;  // 0.786
   
   int enabledCount = 0;
   for(int i = 0; i < 4; i++) {
      if(levelEnabled[i]) enabledCount++;
   }
   
   if(enabledCount == 0) {
      LogMessage("ERROR", "No entry levels enabled!");
      return;
   }
   
   // Risk weights (0.236 not included!)
   double weights[4] = {0.20, 0.25, 0.30, 0.25}; // Total = 1.0
   
   // Normalize weights
   double totalWeight = 0;
   for(int i = 0; i < 4; i++) {
      if(levelEnabled[i]) totalWeight += weights[i];
   }
   for(int i = 0; i < 4; i++) {
      if(levelEnabled[i]) weights[i] = weights[i] / totalWeight;
   }
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double totalRiskMoney = accountBalance * (InpRiskPercent / 100.0);
   g_setups[setupIndex].totalRisk = totalRiskMoney;
   
   int trend = g_setups[setupIndex].trendDirection;
   int ordersPlaced = 0;
   
   // Get current market price
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // FIX: Korrekte String-Formatierung
   string trendStr = (trend == 1) ? "UP" : "DOWN";
   LogMessage("INFO", StringFormat("Placing orders | Trend=%s | Bid=%.5f | Ask=%.5f",
              trendStr, currentBid, currentAsk));
   
   // Map: levelIndex 0-3 → fibLevels array 1-4 (skip 0.236 at index 0)
   int fibIndices[4] = {1, 2, 3, 4}; // 0.382, 0.500, 0.618, 0.786
   string levelNames[4] = {"0.382", "0.500", "0.618", "0.786"};
   
   for(int i = 0; i < 4; i++) {
      if(!levelEnabled[i]) continue;
      
      int fibIdx = fibIndices[i];
      double entryPrice = g_setups[setupIndex].fibLevels[fibIdx];
      double stopLoss = g_setups[setupIndex].initialSL;
      double takeProfit = g_setups[setupIndex].takeProfitLevel;
      
      // ===== LEVEL VALIDATION =====
      bool levelValid = false;
      ENUM_ORDER_TYPE orderType;
      string skipReason = "";
      
      if(trend == 1) {
         // ===== UPTREND: BUY LIMIT =====
         orderType = ORDER_TYPE_BUY_LIMIT;
         
         if(entryPrice < currentAsk) {
            levelValid = true;
         } else {
            skipReason = StringFormat("Entry %.5f >= ASK %.5f (already passed)", entryPrice, currentAsk);
         }
      }
      else {
         // ===== DOWNTREND: SELL LIMIT =====
         orderType = ORDER_TYPE_SELL_LIMIT;
         
         if(entryPrice > currentBid) {
            levelValid = true;
         } else {
            skipReason = StringFormat("Entry %.5f <= BID %.5f (already passed)", entryPrice, currentBid);
         }
      }
      
      if(!levelValid) {
         // FIX: Verwende levelNames Array (entfernt Warning)
         LogMessage("INFO", StringFormat("  └─ Level %s SKIPPED: %s", levelNames[i], skipReason));
         continue;
      }
      
      // ===== CALCULATE LOT SIZE =====
      double riskForThisOrder = totalRiskMoney * weights[i];
      double lotSize = CalculateLotSize(entryPrice, stopLoss, riskForThisOrder);
      
      if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         LogMessage("WARNING", StringFormat("Lot size %.2f too small for %s", lotSize, levelNames[i]));
         continue;
      }
      
      // ===== NORMALIZE PRICES =====
      entryPrice = NormalizeDouble(entryPrice, _Digits);
      stopLoss = NormalizeDouble(stopLoss, _Digits);
      takeProfit = NormalizeDouble(takeProfit, _Digits);
      lotSize = NormalizeDouble(lotSize, 2);
      
      // ===== VALIDATE SPREAD =====
      if(!CheckSpread()) {
         LogMessage("WARNING", "Spread too high");
         continue;
      }
      
      // ===== VALIDATE SL =====
      if(!ValidateStopLevel(stopLoss, entryPrice, trend)) {
         double adjustedSL = AdjustStopLevel(stopLoss, entryPrice, trend);
         if(adjustedSL != 0) {
            stopLoss = adjustedSL;
            LogMessage("INFO", StringFormat("SL adjusted: %.5f", stopLoss));
         } else {
            LogMessage("ERROR", "Cannot adjust SL, skipping");
            continue;
         }
      }
      
      // ===== PLACE ORDER =====
      string comment = StringFormat("%s_S%d_%s", InpTradeComment, g_setups[setupIndex].setupID, levelNames[i]);
      
      bool orderResult = false;
      
      if(orderType == ORDER_TYPE_BUY_LIMIT) {
         orderResult = g_trade.BuyLimit(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, 0, comment);
      }
      else if(orderType == ORDER_TYPE_SELL_LIMIT) {
         orderResult = g_trade.SellLimit(lotSize, entryPrice, _Symbol, stopLoss, takeProfit, ORDER_TIME_GTC, 0, comment);
      }
      
      if(!orderResult || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_PLACED)) {
         LogMessage("ERROR", StringFormat("Order failed: %s", g_trade.ResultComment()));
         continue;
      }
      
      // ===== STORE ORDER INFO =====
      g_setups[setupIndex].pendingTickets[i] = g_trade.ResultOrder();
      g_setups[setupIndex].pendingPrices[i] = entryPrice;
      g_setups[setupIndex].pendingLots[i] = lotSize;
      g_setups[setupIndex].pendingActive[i] = true;
      ordersPlaced++;
      
      // FIX: Korrekte String-Konvertierung für GetOrderTypeName
      string orderTypeName = GetOrderTypeName(orderType);
      LogMessage("ORDER", StringFormat("  ✓ %s | Level %s | Entry=%.5f | Lots=%.2f | SL=%.5f | TP=%.5f | Ticket=%llu",
                 orderTypeName,
                 levelNames[i],
                 entryPrice,
                 lotSize,
                 stopLoss,
                 takeProfit,
                 g_trade.ResultOrder()));
   }
   
   g_setups[setupIndex].pendingCount = ordersPlaced;
   
   if(ordersPlaced > 0) {
      // FIX: Korrekte String-Konvertierung für AccountInfoString
      string currencyStr = AccountInfoString(ACCOUNT_CURRENCY);
      LogMessage("INFO", StringFormat("✓ %d orders placed | Total Risk: %.2f %s",
                 ordersPlaced, totalRiskMoney, currencyStr));
   } else {
      LogMessage("WARNING", "⚠ NO ORDERS PLACED (all levels already passed?)");
   }
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels - FEHLERKORREKTUR                           |
//+------------------------------------------------------------------+
void DrawFibonacciLevels(int setupIndex) {
   if(!g_setups[setupIndex].active) return;

   int setupID = g_setups[setupIndex].setupID;
   
   // Draw Fib 0.0 (Extreme)
   string fib0Name = StringFormat("ZZFib_S%d_F0", setupID);
   if(ObjectFind(0, fib0Name) < 0) {
      ObjectCreate(0, fib0Name, OBJ_HLINE, 0, 0, g_setups[setupIndex].fibLevel_0);
      ObjectSetInteger(0, fib0Name, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, fib0Name, OBJPROP_WIDTH, 2);
   }
   
   // Draw Fib 1.0 (SL)
   string fib1Name = StringFormat("ZZFib_S%d_F1", setupID);
   if(ObjectFind(0, fib1Name) < 0) {
      ObjectCreate(0, fib1Name, OBJ_HLINE, 0, 0, g_setups[setupIndex].fibLevel_1);
      ObjectSetInteger(0, fib1Name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, fib1Name, OBJPROP_WIDTH, 2);
   }
   
   // Draw entry levels (skip 0.236!)
   // FIX: Variable wird jetzt verwendet (entfernt Warning)
   string levelNames[4] = {"0.382", "0.500", "0.618", "0.786"};
   int fibIndices[4] = {1, 2, 3, 4};
   
   for(int i = 0; i < 4; i++) {
      string name = StringFormat("ZZFib_S%d_%s", setupID, levelNames[i]);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, g_setups[setupIndex].fibLevels[fibIndices[i]]);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      }
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete Fibonacci Objects - FEHLERKORREKTUR                        |
//+------------------------------------------------------------------+
void DeleteFibonacciObjects(int setupIndex) {
   int setupID = g_setups[setupIndex].setupID;
   ObjectDelete(0, StringFormat("ZZFib_S%d_F0", setupID));
   ObjectDelete(0, StringFormat("ZZFib_S%d_F1", setupID));

   // FIX: Verwende gleiche Namen wie beim Erstellen
   string levelNames[4] = {"0.382", "0.500", "0.618", "0.786"};
   for(int i = 0; i < 4; i++) {
      ObjectDelete(0, StringFormat("ZZFib_S%d_%s", setupID, levelNames[i]));
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Clean Up ALL Chart Objects (for OnDeinit)                        |
//+------------------------------------------------------------------+
void CleanupAllChartObjects() {
   // Delete ALL ZigZag Fibonacci objects from chart
   int totalObjects = ObjectsTotal(0, 0, -1);

   for(int i = totalObjects - 1; i >= 0; i--) {
      string objName = ObjectName(0, i, 0, -1);

      // Delete all objects starting with "ZZFib_"
      if(StringFind(objName, "ZZFib_") == 0) {
         ObjectDelete(0, objName);
      }

      // Also delete monitor objects
      if(StringFind(objName, "Mon_Up_") == 0 || StringFind(objName, "Mon_Down_") == 0) {
         ObjectDelete(0, objName);
      }
   }

   ChartRedraw();
   Print("Chart cleanup: All EA objects removed");
}

//+------------------------------------------------------------------+
//| Clean Up Orphaned Objects (objects from inactive setups)         |
//+------------------------------------------------------------------+
void CleanupOrphanedObjects() {
   // Collect all active setup IDs
   int activeIDs[];
   int activeCount = 0;

   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(g_setups[i].active) {
         ArrayResize(activeIDs, activeCount + 1);
         activeIDs[activeCount] = g_setups[i].setupID;
         activeCount++;
      }
   }

   // Check all chart objects
   int totalObjects = ObjectsTotal(0, 0, -1);
   int deletedCount = 0;

   for(int i = totalObjects - 1; i >= 0; i--) {
      string objName = ObjectName(0, i, 0, -1);

      // Only check our ZZFib objects
      if(StringFind(objName, "ZZFib_S") == 0) {
         // Extract setup ID from name (format: ZZFib_S123_...)
         int pos = StringFind(objName, "_", 7); // Find second underscore
         if(pos > 7) {
            string idStr = StringSubstr(objName, 7, pos - 7);
            int setupID = (int)StringToInteger(idStr);

            // Check if this ID is in active list
            bool isActive = false;
            for(int j = 0; j < activeCount; j++) {
               if(activeIDs[j] == setupID) {
                  isActive = true;
                  break;
               }
            }

            // Delete if not active
            if(!isActive) {
               ObjectDelete(0, objName);
               deletedCount++;
            }
         }
      }
   }

   if(deletedCount > 0) {
      ChartRedraw();
      LogMessage("DEBUG", StringFormat("Cleaned up %d orphaned chart objects", deletedCount));
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss, double riskMoney) {
   double slDistance = MathAbs(entryPrice - stopLoss);
   if(slDistance == 0) return 0;
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double volumeMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double lotSize = (riskMoney * tickSize) / (slDistance * tickValue);
   lotSize = MathFloor(lotSize / volumeStep) * volumeStep;
   
   if(lotSize < volumeMin) lotSize = volumeMin;
   if(lotSize > volumeMax) lotSize = volumeMax;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Check Pending Orders Status                                       |
//+------------------------------------------------------------------+
void CheckPendingOrdersStatus(int setupIndex) {
   for(int i = 0; i < 4; i++) {
      if(!g_setups[setupIndex].pendingActive[i]) continue;
      
      ulong ticket = g_setups[setupIndex].pendingTickets[i];
      
      if(!g_order.Select(ticket)) {
         g_setups[setupIndex].pendingActive[i] = false;
         
         if(g_position.SelectByTicket(ticket)) {
            g_setups[setupIndex].positionTickets[i] = ticket;
            g_setups[setupIndex].activePositions++;
            g_stats.dailyTrades++;
            g_stats.totalTrades++;
            
            LogMessage("POSITION", StringFormat("✅ Order FILLED: Ticket=%llu | Entry=%.5f | Vol=%.2f",
                       ticket, g_position.PriceOpen(), g_position.Volume()));
         }
      }
   }
   
   int pendingCount = 0;
   for(int i = 0; i < 4; i++) {
      if(g_setups[setupIndex].pendingActive[i]) pendingCount++;
   }
   g_setups[setupIndex].pendingCount = pendingCount;
}

//+------------------------------------------------------------------+
//| Check Setup Invalidation - CORRECTED!                             |
//+------------------------------------------------------------------+
bool CheckSetupInvalidation(int setupIndex) {
   /*
   CRITICAL FIX:
   - Invalidation ONLY when Fib 1.0 (SL) is breached!
   - Fib 0.0 triggers PARTIAL CLOSE (not invalidation!)
   */
   
   if(g_setups[setupIndex].pendingCount == 0) return false;

   double currentPriceHigh, currentPriceLow;
   if(InpPriceMode == PRICE_MODE_CLOSE_ONLY) {
      double closePrice = iClose(_Symbol, PERIOD_CURRENT, 0);
      currentPriceHigh = closePrice;
      currentPriceLow = closePrice;
   }
   else {
      currentPriceHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
      currentPriceLow = iLow(_Symbol, PERIOD_CURRENT, 0);
   }

   double fib1Level = g_setups[setupIndex].fibLevel_1;  // SL Level
   bool invalidated = false;
   string reason = "";

   if(g_setups[setupIndex].trendDirection == 1) {
      // UPTREND: Invalidate if price breaks BELOW Fib 1.0 (Low/SL)
      if(currentPriceLow <= fib1Level) {
         invalidated = true;
         reason = "Price broke SL (Fib 1.0 = Structure broken)";
      }
   }
   else {
      // DOWNTREND: Invalidate if price breaks ABOVE Fib 1.0 (High/SL)
      if(currentPriceHigh >= fib1Level) {
         invalidated = true;
         reason = "Price broke SL (Fib 1.0 = Structure broken)";
      }
   }
   
   if(invalidated) {
      LogMessage("INVALIDATION", StringFormat("❌ Setup #%d INVALIDATED: %s",
                 g_setups[setupIndex].setupID, reason));
      
      int ordersDeleted = 0;
      for(int i = 0; i < 4; i++) {
         if(g_setups[setupIndex].pendingActive[i]) {
            ulong ticket = g_setups[setupIndex].pendingTickets[i];
            
            if(g_order.Select(ticket)) {
               if(g_trade.OrderDelete(ticket)) {
                  g_setups[setupIndex].pendingActive[i] = false;
                  ordersDeleted++;
               }
            }
         }
      }
      
      g_setups[setupIndex].pendingCount = 0;
      LogMessage("INFO", StringFormat("  └─ %d pending orders deleted", ordersDeleted));
      
      if(g_setups[setupIndex].activePositions == 0) {
         // Completely reset setup slot for reuse
         DeleteFibonacciObjects(setupIndex);
         g_setups[setupIndex].Init();  // CRITICAL: Reset all data!
         LogMessage("INFO", "  └─ Setup completely deactivated and reset");
      }
      
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check Setup Validation (Tick)                                     |
//+------------------------------------------------------------------+
void CheckSetupValidationTick() {
   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(g_setups[i].active) {
         CheckSetupInvalidation(i);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Active Setups                                              |
//+------------------------------------------------------------------+
void ManageActiveSetups() {
   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(!g_setups[i].active) continue;
      
      CheckPendingOrdersStatus(i);
      ManagePositions(i);
   }
}

//+------------------------------------------------------------------+
//| Manage Positions - COMPLETE LIFECYCLE                             |
//+------------------------------------------------------------------+
void ManagePositions(int setupIndex) {
   if(!g_setups[setupIndex].active || g_setups[setupIndex].activePositions == 0) return;

   int trend = g_setups[setupIndex].trendDirection;
   double currentPrice = (trend == 1) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int closedCount = 0;

   for(int i = 0; i < 4; i++) {
      ulong ticket = g_setups[setupIndex].positionTickets[i];
      if(ticket == 0) continue;

      if(!g_position.SelectByTicket(ticket)) {
         LogMessage("CLOSED", StringFormat("Position %llu closed (TP/SL)", ticket));
         g_setups[setupIndex].positionTickets[i] = 0;
         g_setups[setupIndex].partialClosed[i] = false;
         g_setups[setupIndex].breakEvenSet[i] = false;
         closedCount++;
         continue;
      }

      double positionProfit = g_position.Profit();

      // ===== STAGE 1: PARTIAL CLOSE =====
      if(!g_setups[setupIndex].partialClosed[i]) {
         double partialClosePrice = g_setups[setupIndex].partialClosePrice;
         bool partialCloseTriggered = false;
         bool inProfit = (positionProfit > 0);

         if(trend == 1) {
            partialCloseTriggered = (currentPrice >= partialClosePrice) && inProfit;
         } else {
            partialCloseTriggered = (currentPrice <= partialClosePrice) && inProfit;
         }

         if(partialCloseTriggered) {
            LogMessage("PARTIAL", StringFormat("💰 Partial close triggered: Ticket=%llu", ticket));
            ExecutePartialClose(setupIndex, i);

            // ===== FIX: DELETE ALL REMAINING PENDING ORDERS WHEN FIB 0.0 REACHED =====
            // Bei Erreichen von Fib 0.0 müssen alle pending orders gelöscht werden!
            if(g_setups[setupIndex].pendingCount > 0) {
               int ordersDeleted = 0;
               for(int j = 0; j < 4; j++) {
                  if(g_setups[setupIndex].pendingActive[j]) {
                     ulong pendingTicket = g_setups[setupIndex].pendingTickets[j];
                     if(g_order.Select(pendingTicket)) {
                        if(g_trade.OrderDelete(pendingTicket)) {
                           g_setups[setupIndex].pendingActive[j] = false;
                           ordersDeleted++;
                           LogMessage("INFO", StringFormat("  └─ ❌ Pending order deleted (Fib 0.0 reached): Ticket=%llu", pendingTicket));
                        }
                     } else {
                        // Order existiert nicht mehr (wurde bereits gefüllt oder gelöscht)
                        g_setups[setupIndex].pendingActive[j] = false;
                     }
                  }
               }
               g_setups[setupIndex].pendingCount = 0;
               if(ordersDeleted > 0) {
                  LogMessage("INFO", StringFormat("✅ Deleted %d pending orders (Fib 0.0 reached)", ordersDeleted));
               }
            }

            if(g_position.SelectByTicket(ticket)) {
               MoveToBreakEven(setupIndex, i);
            } else {
               g_setups[setupIndex].positionTickets[i] = 0;
               closedCount++;
               continue;
            }
         }
      }

      // ===== STAGE 2: BREAKEVEN CHECK =====
      if(g_setups[setupIndex].partialClosed[i] && !g_setups[setupIndex].breakEvenSet[i]) {
         if(g_position.SelectByTicket(ticket)) {
            MoveToBreakEven(setupIndex, i);
         }
      }

      // ===== STAGE 3: TRAILING STOP =====
      if(g_setups[setupIndex].breakEvenSet[i]) {
         if(g_position.SelectByTicket(ticket)) {
            TrailStopLoss(setupIndex, i);
         }
      }
   }

   if(closedCount > 0) {
      g_setups[setupIndex].activePositions -= closedCount;
      if(g_setups[setupIndex].activePositions < 0) {
         g_setups[setupIndex].activePositions = 0;
      }
   }

   if(g_setups[setupIndex].activePositions == 0 && g_setups[setupIndex].pendingCount == 0) {
      // Completely reset setup slot for reuse
      int completedID = g_setups[setupIndex].setupID;
      DeleteFibonacciObjects(setupIndex);
      g_setups[setupIndex].Init();  // CRITICAL: Reset all data!
      LogMessage("INFO", StringFormat("✓ Setup #%d COMPLETED and reset", completedID));
   }
}

//+------------------------------------------------------------------+
//| Execute Partial Close                                             |
//+------------------------------------------------------------------+
void ExecutePartialClose(int setupIndex, int posIndex) {
   ulong ticket = g_setups[setupIndex].positionTickets[posIndex];
   if(!g_position.SelectByTicket(ticket)) return;
   
   double currentVolume = g_position.Volume();
   double closeVolume = NormalizeDouble(currentVolume * (InpPartialClosePercent / 100.0), 2);
   
   if(closeVolume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
      g_setups[setupIndex].partialClosed[posIndex] = true;
      return;
   }
   
   if(g_trade.PositionClosePartial(ticket, closeVolume)) {
      g_setups[setupIndex].partialClosed[posIndex] = true;
      
      if(g_position.SelectByTicket(ticket)) {
         LogMessage("PARTIAL", StringFormat("✓ Closed %.0f%% (%.2f lots) | Remaining: %.2f lots",
                    InpPartialClosePercent, closeVolume, g_position.Volume()));
      }
   }
}

//+------------------------------------------------------------------+
//| Move to Breakeven                                                 |
//+------------------------------------------------------------------+
void MoveToBreakEven(int setupIndex, int posIndex) {
   ulong ticket = g_setups[setupIndex].positionTickets[posIndex];
   if(!g_position.SelectByTicket(ticket)) return;

   double openPrice = g_position.PriceOpen();
   double currentSL = g_position.StopLoss();
   double currentTP = g_position.TakeProfit();
   int trend = g_setups[setupIndex].trendDirection;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = InpBreakevenBuffer * point;
   double newSL = (trend == 1) ? openPrice + buffer : openPrice - buffer;
   
   newSL = NormalizeDouble(newSL, _Digits);

   double marketPrice = (trend == 1) ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!ValidateStopLevel(newSL, marketPrice, trend)) {
      newSL = AdjustStopLevel(newSL, marketPrice, trend);
      if(newSL == 0) return;
   }

   if(g_trade.PositionModify(ticket, newSL, currentTP)) {
      g_setups[setupIndex].breakEvenSet[posIndex] = true;
      LogMessage("BREAKEVEN", StringFormat("🔒 SL → Breakeven+%d: Ticket=%llu | New SL=%.5f",
                 InpBreakevenBuffer, ticket, newSL));
   }
}

//+------------------------------------------------------------------+
//| Trail Stop Loss                                                   |
//+------------------------------------------------------------------+
void TrailStopLoss(int setupIndex, int posIndex) {
   if(setupIndex < 0 || setupIndex >= ArraySize(g_setups)) return;
   if(!g_setups[setupIndex].active) return;

   ulong ticket = g_setups[setupIndex].positionTickets[posIndex];
   if(ticket == 0) return;

   if(!g_position.SelectByTicket(ticket)) return;

   int trend = g_setups[setupIndex].trendDirection;
   double currentPrice = (trend == 1) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double openPrice = g_position.PriceOpen();
   double initialSL = g_setups[setupIndex].initialSL;
   double initialRisk = MathAbs(openPrice - initialSL);

   if(initialRisk < _Point * 5) return;

   double currentProfit = (trend == 1) ? (currentPrice - openPrice) : (openPrice - currentPrice);
   double rMultiple = currentProfit / initialRisk;

   if(rMultiple < InpTrailActivation_R) return;

   double newSL = 0;
   
   switch(InpTrailMode) {
      case TRAIL_FIBONACCI_LEVELS:
         newSL = CalculateFibonacciTrail(setupIndex, currentPrice);
         break;
      case TRAIL_ATR_BASED:
         newSL = CalculateATRTrail(setupIndex, currentPrice);
         break;
      case TRAIL_FIXED_PERCENT:
         {
            double range = MathAbs(g_setups[setupIndex].fibLevel_1 - g_setups[setupIndex].fibLevel_0);
            double trailDistance = range * (InpTrailDistance_Percent / 100.0);
            newSL = (trend == 1) ? currentPrice - trailDistance : currentPrice + trailDistance;
         }
         break;
   }

   if(newSL == 0) return;

   newSL = NormalizeDouble(newSL, _Digits);
   double currentSL = NormalizeDouble(g_position.StopLoss(), _Digits);
   double currentTP = NormalizeDouble(g_position.TakeProfit(), _Digits);

   if(!ValidateStopLevel(newSL, currentPrice, trend)) return;

   bool improved = false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(trend == 1) {
      improved = (newSL > currentSL + point);
   } else {
      improved = (currentSL == 0 || newSL < currentSL - point);
   }

   if(!improved) return;

   if(g_trade.PositionModify(ticket, newSL, currentTP)) {
      LogMessage("TRAIL", StringFormat("📈 SL trailed: %.5f → %.5f (R=%.2f)",
                 currentSL, newSL, rMultiple));
   }
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Trail                                         |
//+------------------------------------------------------------------+
double CalculateFibonacciTrail(int setupIndex, double currentPrice) {
   double fib0 = g_setups[setupIndex].fibLevel_0;
   double fib1 = g_setups[setupIndex].fibLevel_1;
   double range = MathAbs(fib1 - fib0);
   int trend = g_setups[setupIndex].trendDirection;

   if(range < _Point * 10) return g_setups[setupIndex].initialSL;

   double fibRatios[4] = {0.236, 0.382, 0.500, 0.618};
   double trailLevel = fib1;
   double bestLevel = fib1;

   if(trend == 1) {
      if(currentPrice <= fib1) return fib1;

      for(int i = 3; i >= 0; i--) {
         double fibPrice = fib0 + (range * fibRatios[i]);
         if(currentPrice >= fibPrice && fibPrice > bestLevel) {
            bestLevel = fibPrice;
         }
      }
   }
   else {
      if(currentPrice >= fib1) return fib1;

      for(int i = 3; i >= 0; i--) {
         double fibPrice = fib0 - (range * fibRatios[i]);
         if(currentPrice <= fibPrice && (fibPrice < bestLevel || bestLevel == fib1)) {
            bestLevel = fibPrice;
         }
      }
   }

   return NormalizeDouble(bestLevel, _Digits);
}

//+------------------------------------------------------------------+
//| Calculate ATR Trail                                               |
//+------------------------------------------------------------------+
double CalculateATRTrail(int setupIndex, double currentPrice) {
   if(g_atrHandle == INVALID_HANDLE) return g_setups[setupIndex].fibLevel_1;

   double atrBuffer[1];
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) <= 0) {
      return g_setups[setupIndex].fibLevel_1;
   }

   double atr = atrBuffer[0];
   if(atr <= 0) return g_setups[setupIndex].fibLevel_1;

   int trend = g_setups[setupIndex].trendDirection;
   double trailDistance = atr * InpTrailDistance_ATR;

   double newSL = (trend == 1) ? currentPrice - trailDistance : currentPrice + trailDistance;

   return NormalizeDouble(newSL, _Digits);
}

//+------------------------------------------------------------------+
//| Validate Stop Level                                               |
//+------------------------------------------------------------------+
bool ValidateStopLevel(double stopLevel, double marketPrice, int trend) {
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minDistance = MathMax(stopsLevel, freezeLevel) * point * 1.1;
   double actualDistance = MathAbs(stopLevel - marketPrice);

   if(actualDistance < minDistance) return false;

   if(trend == 1 && stopLevel >= marketPrice) return false;
   if(trend == -1 && stopLevel <= marketPrice) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Adjust Stop Level                                                 |
//+------------------------------------------------------------------+
double AdjustStopLevel(double stopLevel, double marketPrice, int trend) {
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double minDistance = MathMax(stopsLevel, freezeLevel) * point * 1.15;
   double adjustedSL = (trend == 1) ? marketPrice - minDistance : marketPrice + minDistance;

   return NormalizeDouble(adjustedSL, _Digits);
}


//+------------------------------------------------------------------+
//| Draw Monitor Fibonacci                                            |
//+------------------------------------------------------------------+
void DrawMonitorFibonacci() {
   // Uptrend monitor
   if(g_monitorUp.active && !g_monitorUp.reached236) {
      if(ObjectFind(0, "Mon_Up_F0") < 0) {
         ObjectCreate(0, "Mon_Up_F0", OBJ_HLINE, 0, 0, g_monitorUp.extremePrice);
         ObjectSetInteger(0, "Mon_Up_F0", OBJPROP_COLOR, clrLimeGreen);
         ObjectSetInteger(0, "Mon_Up_F0", OBJPROP_STYLE, STYLE_DOT);
      }
      ObjectSetDouble(0, "Mon_Up_F0", OBJPROP_PRICE, 0, g_monitorUp.extremePrice);
      
      if(ObjectFind(0, "Mon_Up_F1") < 0) {
         ObjectCreate(0, "Mon_Up_F1", OBJ_HLINE, 0, 0, g_monitorUp.swingPrice);
         ObjectSetInteger(0, "Mon_Up_F1", OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, "Mon_Up_F1", OBJPROP_STYLE, STYLE_DOT);
      }
      ObjectSetDouble(0, "Mon_Up_F1", OBJPROP_PRICE, 0, g_monitorUp.swingPrice);
   } else {
      ObjectDelete(0, "Mon_Up_F0");
      ObjectDelete(0, "Mon_Up_F1");
   }
   
   // Downtrend monitor
   if(g_monitorDown.active && !g_monitorDown.reached236) {
      if(ObjectFind(0, "Mon_Down_F0") < 0) {
         ObjectCreate(0, "Mon_Down_F0", OBJ_HLINE, 0, 0, g_monitorDown.extremePrice);
         ObjectSetInteger(0, "Mon_Down_F0", OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, "Mon_Down_F0", OBJPROP_STYLE, STYLE_DOT);
      }
      ObjectSetDouble(0, "Mon_Down_F0", OBJPROP_PRICE, 0, g_monitorDown.extremePrice);
      
      if(ObjectFind(0, "Mon_Down_F1") < 0) {
         ObjectCreate(0, "Mon_Down_F1", OBJ_HLINE, 0, 0, g_monitorDown.swingPrice);
         ObjectSetInteger(0, "Mon_Down_F1", OBJPROP_COLOR, clrLimeGreen);
         ObjectSetInteger(0, "Mon_Down_F1", OBJPROP_STYLE, STYLE_DOT);
      }
      ObjectSetDouble(0, "Mon_Down_F1", OBJPROP_PRICE, 0, g_monitorDown.swingPrice);
   } else {
      ObjectDelete(0, "Mon_Down_F0");
      ObjectDelete(0, "Mon_Down_F1");
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper Functions                                                  |
//+------------------------------------------------------------------+

bool IsTradingAllowed() {
   if(InpUseDrawdownFilter && g_stats.drawdownLimitReached) return false;
   if(InpUseDailyLossLimit && g_stats.dailyLimitReached) return false;
   
   if(InpUseTimeFilter) {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int currentMinutes = dt.hour * 60 + dt.min;
      int startMinutes = InpStartHour * 60 + InpStartMinute;
      int endMinutes = InpEndHour * 60 + InpEndMinute;
      
      if(startMinutes <= endMinutes) {
         if(currentMinutes < startMinutes || currentMinutes > endMinutes) return false;
      } else {
         if(currentMinutes < startMinutes && currentMinutes > endMinutes) return false;
      }
   }
   
   return true;
}

void CheckDailyReset() {
   MqlDateTime now, lastReset;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(g_stats.lastResetTime, lastReset);
   
   if(now.day != lastReset.day || now.mon != lastReset.mon || now.year != lastReset.year) {
      LogMessage("INFO", "═══ NEW TRADING DAY ═══");
      g_stats.Reset();
   }
}

void SetBestFillingMode() {
   int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   
   if((filling & 4) == 4) {
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   } else if((filling & 2) == 2) {
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   } else {
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }
}

bool CheckSpread() {
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   return (spread <= InpMaxSpreadPoints * _Point);
}

int GetActiveSetupsCount() {
   int count = 0;
   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(g_setups[i].active) count++;
   }
   return count;
}

void InitializeCSV() {
   string filename = StringFormat("ZZFib_%s_%s.csv", _Symbol, TimeToString(TimeCurrent(), TIME_DATE));
   g_csvHandle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(g_csvHandle != INVALID_HANDLE) {
      FileWrite(g_csvHandle, "Time", "SetupID", "Trend", "Fib0", "Fib1", "Result");
   }
}

void ExportSetupToCSV(int setupIndex) {
   if(g_csvHandle == INVALID_HANDLE) return;
   FileWrite(g_csvHandle,
             TimeToString(g_setups[setupIndex].setupTime),
             g_setups[setupIndex].setupID,
             (g_setups[setupIndex].trendDirection == 1 ? "UP" : "DOWN"),
             g_setups[setupIndex].fibLevel_0,
             g_setups[setupIndex].fibLevel_1,
             "ACTIVE");
}

void UpdateMonitorDisplay() {
   string prefix = "Monitor_";
   int yPos = 20;
   
   CreateLabel(prefix+"BG", 10, 10, 200, 200, clrDarkSlateGray, clrWhite);
   
   CreateTextLabel(prefix+"Title", 20, yPos, "ZigZag Fib EA v2.0", clrYellow, 10);
   yPos += 25;
   
   int activeSetups = GetActiveSetupsCount();
   CreateTextLabel(prefix+"Setups", 20, yPos, StringFormat("Setups: %d/%d", activeSetups, InpMaxSimultaneousSetups), clrWhite, 8);
   yPos += 20;
   
   int totalPending = 0;
   int totalPositions = 0;
   for(int i = 0; i < ArraySize(g_setups); i++) {
      if(g_setups[i].active) {
         totalPending += g_setups[i].pendingCount;
         totalPositions += g_setups[i].activePositions;
      }
   }
   
   CreateTextLabel(prefix+"Pending", 20, yPos, StringFormat("Pending: %d", totalPending), clrWhite, 8);
   yPos += 20;
   CreateTextLabel(prefix+"Positions", 20, yPos, StringFormat("Positions: %d", totalPositions), clrWhite, 8);
   
   ChartRedraw();
}

void CreateLabel(string name, int x, int y, int width, int height, color bgColor, color borderColor) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void CreateTextLabel(string name, int x, int y, string text, color clr, int fontSize = 8) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DeleteMonitorObjects() {
   string prefix = "Monitor_";
   ObjectDelete(0, prefix+"BG");
   ObjectDelete(0, prefix+"Title");
   ObjectDelete(0, prefix+"Setups");
   ObjectDelete(0, prefix+"Pending");
   ObjectDelete(0, prefix+"Positions");
}

void LogMessage(string level, string message) {
   if(!InpEnableLogging && level != "ERROR") return;
   Print(StringFormat("[%s] %s: %s", TimeToString(TimeCurrent(), TIME_SECONDS), level, message));
}

void PrintFinalStatistics() {
   Print("═══════════════════════════════════════════════");
   Print("FINAL STATISTICS");
   Print("Total Signals: ", g_stats.dailySignals);
   Print("Total Trades: ", g_stats.totalTrades);
   Print("Start Balance: ", g_startBalance);
   Print("Final Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("═══════════════════════════════════════════════");
}

string GetDeinitReasonText(int reason) {
   switch(reason) {
      case REASON_PROGRAM: return "Stopped by user";
      case REASON_REMOVE: return "Removed from chart";
      case REASON_RECOMPILE: return "Recompiled";
      default: return "Unknown";
   }
}

string PeriodToString(ENUM_TIMEFRAMES period) {
   switch(period) {
      case PERIOD_M1: return "M1";
      case PERIOD_M5: return "M5";
      case PERIOD_M10: return "M10";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      default: return "UNKNOWN";
   }
}

string GetOrderTypeName(ENUM_ORDER_TYPE type) {
   switch(type) {
      case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT";
      case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
      default: return "UNKNOWN";
   }
}
//+------------------------------------------------------------------+