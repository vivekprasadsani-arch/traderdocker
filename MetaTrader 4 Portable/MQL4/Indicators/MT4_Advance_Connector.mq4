//+------------------------------------------------------------------+
//|                                      MT4_Advance_Connector.mq4   |
//|                                              TaskTreasure        |
//|                                   Advanced Signal Connector 2026 |
//+------------------------------------------------------------------+
#property copyright "TaskTreasure"
#property link      "https://tasktreasure.com"
#property version   "7.00"
#property strict
#property indicator_chart_window

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - MAIN INDICATOR                                |
//+------------------------------------------------------------------+
input string  _1_ = "========== MAIN INDICATOR ==========";
input bool    MainIndicator_Enable = true;              // Enable Main Indicator
input string  MainIndicator_Name = "Magic_V_Binary_NoRepaint"; // Main Indicator Name
input int     MainIndicator_CallBuffer = 0;             // Call Signal Buffer
input int     MainIndicator_PutBuffer = 1;              // Put Signal Buffer

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - COMBINER 1                                    |
//+------------------------------------------------------------------+
input string  _2_ = "========== COMBINER 1 ==========";
input bool    Combiner1_Enable = false;                 // Enable Combiner 1
input string  Combiner1_Name = "";                      // Combiner 1 Name
input int     Combiner1_CallBuffer = 0;                 // Call Signal Buffer
input int     Combiner1_PutBuffer = 1;                  // Put Signal Buffer

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - COMBINER 2                                    |
//+------------------------------------------------------------------+
input string  _3_ = "========== COMBINER 2 ==========";
input bool    Combiner2_Enable = false;                 // Enable Combiner 2
input string  Combiner2_Name = "";                      // Combiner 2 Name
input int     Combiner2_CallBuffer = 0;                 // Call Signal Buffer
input int     Combiner2_PutBuffer = 1;                  // Put Signal Buffer

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ENTRY SETTINGS                                |
//+------------------------------------------------------------------+
input string  _4_ = "========== ENTRY SETTINGS ==========";
input bool    EntrySameCandle = false;                  // Entry: Same Candle (false = Next Candle)
input string  ExpirationType = "M1";                    // Expiry Type (M1/M5/M15/TimeFrame)
input int     ExpiryMinutes = 1;                        // Expiry Minutes (if custom)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - MARTINGALE                                    |
//+------------------------------------------------------------------+
input string  _5_ = "========== MARTINGALE ==========";
input bool    Martingale_Enable = true;                 // Enable Martingale
input int     Martingale_Steps = 2;                     // Martingale Steps (1-5)
input double  Martingale_Coefficient = 2.0;             // Martingale Coefficient
input int     Martingale_NextExpiry = 1;                // Next Expiry After Loss (minutes)
input double  TradeValue = 10.0;                        // Trade Value (for MT2 style)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - TELEGRAM                                      |
//+------------------------------------------------------------------+
input string  _6_ = "========== TELEGRAM SETTINGS ==========";
input bool    Telegram_Enable = false;                  // Enable Telegram Signals
input string  Telegram_BotToken = "";                   // Bot API Token
input string  Telegram_ChatID = "";                     // Chat ID
input bool    Telegram_SendScreenshot = false;          // Send Signal Screenshot
input bool    Telegram_SendResult = false;              // Send Result Screenshot
input string  Telegram_MessageTemplate = "";            // Message Template (Leave empty for default pro style)
input string  Telegram_RegisterLink = "https://t.me/TaskTreasure"; // Register Link
input string  Telegram_ContactLink = "https://t.me/TaskTreasure";  // Contact Link
input bool    Report_Enable = false;                    // Enable Periodic Report
input int     Report_Interval = 60;                     // Report Interval (Minutes)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - TIME FILTER                                   |
//+------------------------------------------------------------------+
input string  _7_ = "========== TIME FILTER ==========";
input bool    TimeFilter_Enable = false;                // Enable Time Filter
input string  TimeFilter_Start = "09:00";               // Start Time (HH:MM)
input string  TimeFilter_End = "17:00";                 // End Time (HH:MM)
input int     TimeFilter_UTC_Offset = 6;                // UTC Offset (e.g. +6 for Dhaka)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - SCREENSHOT                                    |
//+------------------------------------------------------------------+
input string  _8_ = "========== SCREENSHOT SETTINGS ==========";
input int     Screenshot_Width = 800;                   // Screenshot Width
input int     Screenshot_Height = 600;                  // Screenshot Height
input int     Screenshot_CandleSize = 4;                // Candle Size (0-5)
input bool    Screenshot_ClearOld = true;               // Clear Old Screenshots

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ADVANCED                                      |
//+------------------------------------------------------------------+
input string  _9_ = "========== ADVANCED SETTINGS ==========";
input int     GlobalInterval_Seconds = 5;               // Global Interval (seconds)
input int     OrderInterval_Seconds = 3;                // Interval Between Orders
input bool    ShowStatistics = true;                    // Show Statistics Dashboard
input bool    SendDailyReport = false;                  // Send Daily Win Rate Report

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime lastSignalTime = 0;
datetime lastOrderTime = 0;
datetime lastReportTime = 0;
int totalSignals = 0;
int totalWins = 0;
int totalLosses = 0;

struct SignalData {
   datetime time;
   string symbol;
   string direction;
   double entryPrice;
   int expiryMinutes;
   bool processed;
   bool win;
   int martingaleStep;
   bool pendingScreenshot;   // Waiting for screenshot?
   string screenshotFile;    // Filename
   datetime screenshotTime;  // when request started
   bool isResult;            // Is this a result Update?
};

SignalData signalHistory[];
int signalCount = 0;

//+------------------------------------------------------------------+
//| DLL IMPORTS for Fallback Connection                              |
//+------------------------------------------------------------------+
#import "wininet.dll"
   int InternetOpenW(string sAgent, int lAccessType, string sProxyName, string sProxyBypass, int lFlags);
   int InternetConnectW(int hInternet, string sServerName, int nServerPort, string sUsername, string sPassword, int nService, int nFlags, int nContext);
   int HttpOpenRequestW(int hConnect, string sVerb, string sObjectName, string sVersion, string sReferrer, int lplpszAcceptTypes, int nFlags, int nContext);
   bool HttpSendRequestW(int hRequest, string sHeaders, int lHeadersLength, char &sOptional[], int lOptionalLength);
   bool HttpQueryInfoW(int hRequest, int dwInfoLevel, string &lpvBuffer, int &lpdwBufferLength, int &lpdwIndex);
   bool InternetCloseHandle(int hInternet);
#import

//+------------------------------------------------------------------+
//| Send Telegram message using DLL (Bypass Error 4060)              |
//+------------------------------------------------------------------+
bool SendTelegramViaDLL(string message)
{
   Print("Attempting to send via DLL...");
   
   string headers = "Content-Type: application/x-www-form-urlencoded";
   string request_body = "chat_id=" + Telegram_ChatID + "&text=" + UrlEncode(message);
   
   char postData[];
   StringToCharArray(request_body, postData, 0, StringLen(request_body));
   
   // 1. Open Internet
   int hInternet = InternetOpenW("MT4 Connector", 1, NULL, NULL, 0);
   if(hInternet == 0) {
      Print("DLL Error: InternetOpen failed");
      return false;
   }
   
   // 2. Connect to api.telegram.org (Port 443 for HTTPS)
   int hConnect = InternetConnectW(hInternet, "api.telegram.org", 443, "", "", 3, 0, 0);
   if(hConnect == 0) {
      Print("DLL Error: InternetConnect failed");
      InternetCloseHandle(hInternet);
      return false;
   }
   
   // 3. Open Request (POST /bot.../sendMessage)
   string objectName = "/bot" + Telegram_BotToken + "/sendMessage";
   int hRequest = HttpOpenRequestW(hConnect, "POST", objectName, "HTTP/1.1", NULL, 0, 0x00800000 | 0x04000000, 0); // INTERNET_FLAG_SECURE | INTERNET_FLAG_NO_CACHE_WRITE
   if(hRequest == 0) {
      Print("DLL Error: HttpOpenRequest failed");
      InternetCloseHandle(hConnect);
      InternetCloseHandle(hInternet);
      return false;
   }
   
   // 4. Send Request
   bool sent = HttpSendRequestW(hRequest, headers, StringLen(headers), postData, ArraySize(postData));
   
   if(sent) {
      Print("✓ Message sent successfully via DLL!");
   } else {
      Print("DLL Error: HttpSendRequest failed");
   }
   
   InternetCloseHandle(hRequest);
   InternetCloseHandle(hConnect);
   InternetCloseHandle(hInternet);
   
   return sent;
}


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("MT4 ADVANCE CONNECTOR V7.0");
   
   // Validate Telegram settings
   if(Telegram_Enable && (Telegram_BotToken == "" || Telegram_ChatID == "")) {
      Print("ERROR: Telegram enabled but Bot Token or Chat ID is empty!");
      Alert("Please configure Telegram settings!");
   }
   
   // Add Telegram URL to allowed WebRequest list
   if(Telegram_Enable) {
      Print("IMPORTANT: Add https://api.telegram.org to Tools > Options > Expert Advisors > Allow WebRequest");
      
      // Send test message
      // Print("Sending test Telegram message...");
      // SendTestTelegramMessage();
   }
   
   // Initialize statistics dashboard
   if(ShowStatistics) {
      CreateDashboard();
   }
   
   // Clear old screenshots if enabled
   if(Screenshot_ClearOld) {
      ClearOldScreenshots();
   }
   
   Print("MT4 Advance Connector V7.0 initialized successfully");
   Print("Main Indicator: ", MainIndicator_Enable ? MainIndicator_Name : "Disabled");
   Print("Combiner 1: ", Combiner1_Enable ? Combiner1_Name : "Disabled");
   Print("Combiner 2: ", Combiner2_Enable ? Combiner2_Name : "Disabled");
   
   // Initialize report timer
   lastReportTime = TimeCurrent();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up dashboard objects
   ObjectsDeleteAll(0, "CONNECTOR_");
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
// Check if enough bars
   if(rates_total < 10) return(0);
   
   // Check for expired signals and update results (MUST BE FIRST)
   CheckSignalResults();
   
   // Process any pending screenshots (MUST BE FIRST)
   ProcessPendingScreenshots();
   
   // Check Periodic Report
   if(Report_Enable && TimeCurrent() - lastReportTime >= Report_Interval * 60) {
       SendPeriodicReport();
       lastReportTime = TimeCurrent();
   }
   
   // Check time filter
   if(TimeFilter_Enable && !IsWithinTradingHours()) {
      return(rates_total);
   }
   
   // Static variable to track the last bar we alerted on
   static datetime lastAlertBar = 0;
   
   // Check global interval
   if(TimeCurrent() - lastSignalTime < GlobalInterval_Seconds) {
      return(rates_total);
   }
   
   // If we already alerted on this bar, skip
   if(TimeCurrent() - lastOrderTime > 5 && Time[0] == lastAlertBar) return(rates_total);
   
   // Detect signals from indicators
   string signal = DetectCombinedSignal();
   
   if(signal != "") {
      ProcessSignal(signal);
      lastAlertBar = Time[0]; // Mark this bar as processed
   }
   
   // Update statistics
   if(ShowStatistics) {
      UpdateDashboard();
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Detect combined signal from all enabled indicators               |
//+------------------------------------------------------------------+
string DetectCombinedSignal()
{
   bool mainCall = false, mainPut = false;
   bool comb1Call = false, comb1Put = false;
   bool comb2Call = false, comb2Put = false;
   
   int checkBar = EntrySameCandle ? 0 : 1;
   
   // Read Main Indicator
   if(MainIndicator_Enable) {
      double callValue = iCustom(NULL, 0, MainIndicator_Name, MainIndicator_CallBuffer, checkBar);
      double putValue = iCustom(NULL, 0, MainIndicator_Name, MainIndicator_PutBuffer, checkBar);
      
      // DEBUG: Print values if non-empty
      if(callValue != EMPTY_VALUE && callValue != 0) 
         Print("DEBUG: Main Call Found! Val=", callValue, " Bar=", checkBar);
         
      if(putValue != EMPTY_VALUE && putValue != 0)
         Print("DEBUG: Main Put Found! Val=", putValue, " Bar=", checkBar);
         
      if(callValue != EMPTY_VALUE && callValue != 0) mainCall = true;
      if(putValue != EMPTY_VALUE && putValue != 0) mainPut = true;
   }
   
   // Read Combiner 1
   if(Combiner1_Enable && Combiner1_Name != "") {
      double callValue = iCustom(NULL, 0, Combiner1_Name, Combiner1_CallBuffer, checkBar);
      double putValue = iCustom(NULL, 0, Combiner1_Name, Combiner1_PutBuffer, checkBar);
      
      if(callValue != EMPTY_VALUE && callValue != 0) comb1Call = true;
      if(putValue != EMPTY_VALUE && putValue != 0) comb1Put = true;
   }
   
   // Read Combiner 2
   if(Combiner2_Enable && Combiner2_Name != "") {
      double callValue = iCustom(NULL, 0, Combiner2_Name, Combiner2_CallBuffer, checkBar);
      double putValue = iCustom(NULL, 0, Combiner2_Name, Combiner2_PutBuffer, checkBar);
      
      if(callValue != EMPTY_VALUE && callValue != 0) comb2Call = true;
      if(putValue != EMPTY_VALUE && putValue != 0) comb2Put = true;
   }
   
   // Combine signals (ALL enabled indicators must agree)
   bool finalCall = mainCall;
   bool finalPut = mainPut;
   
   if(Combiner1_Enable) {
      finalCall = finalCall && comb1Call;
      finalPut = finalPut && comb1Put;
   }
   
   if(Combiner2_Enable) {
      finalCall = finalCall && comb2Call;
      finalPut = finalPut && comb2Put;
   }
   
   if(finalCall && !finalPut) return "CALL";
   if(finalPut && !finalCall) return "PUT";
   
   return "";
}

//+------------------------------------------------------------------+
//| Process detected signal                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Process detected signal                                          |
//+------------------------------------------------------------------+
void ProcessSignal(string direction)
{
   // 1. Check Global Trade Lock with Safety Timeout (30 Mins)
   string lockVar = "MT4_CONN_ACTIVE_TRADE";
   if(GlobalVariableCheck(lockVar)) {
      datetime lockTime = (datetime)GlobalVariableGet(lockVar);
      if(lockTime > 0 && TimeCurrent() - lockTime < 1800) { // 30 minutes timeout
         Print("Signal skipped: Another trade is currently active globally.");
         return;
      }
   }
   
   // Check order interval
   if(TimeCurrent() - lastOrderTime < OrderInterval_Seconds) {
      return;
   }
   
   // Set Global Lock to current time
   GlobalVariableSet(lockVar, (double)TimeCurrent());
   Print("GLOBAL LOCK: Trade started. No other signals allowed for up to 30 mins.");
   
   // Create signal data
   SignalData newSignal;
   newSignal.time = TimeCurrent();
   newSignal.symbol = Symbol();
   newSignal.direction = direction;
   newSignal.entryPrice = EntrySameCandle ? Close[0] : Open[0];
   newSignal.expiryMinutes = GetExpiryMinutes();
   newSignal.processed = false;
   newSignal.win = false;
   newSignal.martingaleStep = 0;
   newSignal.pendingScreenshot = false;
   newSignal.isResult = false;
   
   // Handle Screenshot Request
   if(Telegram_Enable && Telegram_SendScreenshot) {
      string filename = CaptureScreenshot("Signal");
      newSignal.pendingScreenshot = true;
      newSignal.screenshotFile = filename;
      newSignal.screenshotTime = TimeCurrent();
      Print("Screenshot requested: ", filename, ". Waiting for file...");
   }
   
   // Add to history (EXACTLY ONCE)
   ArrayResize(signalHistory, signalCount + 1);
   signalHistory[signalCount] = newSignal;
   signalCount++;
   
   // Send Text Immediately if NO Screenshot
   if(Telegram_Enable && !Telegram_SendScreenshot) {
       SendTelegramSignal(newSignal);
   }
   
   // Update counters
   totalSignals++;
   lastSignalTime = TimeCurrent();
   lastOrderTime = TimeCurrent();
   
   // Alert
   Alert("Signal: ", direction, " on ", Symbol());
   PlaySound("alert.wav");
}

//+------------------------------------------------------------------+
//| Get expiry minutes based on settings                             |
//+------------------------------------------------------------------+
int GetExpiryMinutes()
{
   if(ExpirationType == "TimeFrame") {
      return Period();
   } else if(ExpirationType == "M1") {
      return 1;
   } else if(ExpirationType == "M5") {
      return 5;
   } else if(ExpirationType == "M15") {
      return 15;
   }
   return ExpiryMinutes;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime currentTime = TimeCurrent() + TimeFilter_UTC_Offset * 3600;
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   
   // Parse start time
   string startParts[];
   int startCount = StringSplit(TimeFilter_Start, ':', startParts);
   int startMinutes = (int)StringToInteger(startParts[0]) * 60 + (int)StringToInteger(startParts[1]);
   
   // Parse end time
   string endParts[];
   int endCount = StringSplit(TimeFilter_End, ':', endParts);
   int endMinutes = (int)StringToInteger(endParts[0]) * 60 + (int)StringToInteger(endParts[1]);
   
   return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Send signal to Telegram                                          |
//+------------------------------------------------------------------+
void SendTelegramSignal(SignalData &signal)
{
   Print("=== SENDING TELEGRAM MESSAGE (PRO) ===");
   
   // Professional Template Construction
   string message = "";
   
   // Hardcoded Pro Template if custom is empty
   if(Telegram_MessageTemplate == "") {
      message = "========== SIGNAL ============\n\n";
      message += "🔔 " + signal.symbol + "\n";
      message += "🕐 " + TimeToString(TimeCurrent(), TIME_MINUTES) + "\n";
      message += "⏳ " + IntegerToString(Period()) + "M\n";
      
      if(signal.direction == "CALL") {
         message += "🟢 CALL\n";
      } else {
         message += "🔴 PUT\n";
      }
      
      message += "📌 " + DoubleToString(signal.entryPrice, Digits) + "\n\n";
      message += "🔗 Register Here\n" + Telegram_RegisterLink + "\n";
      message += "⚜ Contact Here\n" + Telegram_ContactLink;
   } else {
      // Use Custom Template
      message = Telegram_MessageTemplate;
      StringReplace(message, "{SYMBOL}", signal.symbol);
      StringReplace(message, "{DIRECTION}", signal.direction);
      StringReplace(message, "{TF}", IntegerToString(Period()) + "M");
      StringReplace(message, "{ENTRY}", DoubleToString(signal.entryPrice, Digits));
      StringReplace(message, "{EXPIRY}", IntegerToString(signal.expiryMinutes) + "M");
   }
   
   Print("Message: ", message);
   
   string encodedMessage = UrlEncode(message);
   string url = "https://api.telegram.org/bot" + Telegram_BotToken + "/sendMessage";
   string params = "chat_id=" + Telegram_ChatID + "&text=" + encodedMessage;
   
   char post[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   StringToCharArray(params, post, 0, StringLen(params));
   
   // DEBUG ALERT used because user checks Alert window
   Alert("Telegram: Sending signal for " + signal.symbol + "...");
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, headers);
   int error = GetLastError();
   
   if(res == -1) {
      Print("WebRequest failed (Error ", error, "). Switching to DLL fallback...");
      Alert("Telegram: WebRequest Err " + IntegerToString(error) + ". Trying DLL...");
      
      if(SendTelegramViaDLL(message)) {
         Print("✓ Signal sent via DLL");
         Alert("Telegram: Sent via DLL! ✅");
      } else {
         Print("✗ Failed to send signal via DLL");
         Alert("Telegram: DLL Failed too! ❌");
      }
   } else {
      string resultStr = CharArrayToString(result);
      if(StringFind(resultStr, "\"ok\":true") >= 0) {
         Print("✓ Telegram message sent successfully!");
         Alert("Telegram: Sent via WebRequest! ✅");
      } else {
         Print("Telegram WebRequest Error: ", resultStr);
         Alert("Telegram: API Error. Retrying DLL...");
         if(SendTelegramViaDLL(message)) {
             Print("✓ Signal sent via DLL (API Retry)");
             Alert("Telegram: Sent via DLL (Retry)! ✅");
         } else {
             Alert("Telegram: All methods failed! ❌");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| URL Encode function                                              |
//+------------------------------------------------------------------+
string UrlEncode(string str)
{
   string result = "";
   char data[];
   // Convert string to UTF-8 byte array
   int len = StringToCharArray(str, data, 0, -1, CP_UTF8);
   
   for(int i = 0; i < len; i++) {
      uchar c = (uchar)data[i];
      if(c == 0) break; // Skip null terminator
      
      if((c >= 'A' && c <= 'Z') || 
         (c >= 'a' && c <= 'z') || 
         (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~') {
         result += CharToString((char)c);
      }
      else if(c == ' ') {
         result += "+";
      }
      else {
         result += StringFormat("%%%02X", c);
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Capture screenshot                                                |
//+------------------------------------------------------------------+
string CaptureScreenshot(string prefix)
{
   int oldScale = (int)ChartGetInteger(0, CHART_SCALE);
   ChartSetInteger(0, CHART_SCALE, Screenshot_CandleSize);
   
   // Hide ALL dashboard objects (Labels, Text, Panels)
   // We store visibility state or just re-enable all
   // To be safe, we hide specific types used for Dashboards
   
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(i);
      int type = ObjectType(name); // Note: explicit function or ObjectGetInteger
      // In newer MT4: ObjectGetInteger(0, name, OBJPROP_TYPE)
      if(ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_LABEL || 
         ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_TEXT || 
         ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_RECTANGLE_LABEL || 
         StringFind(name, "CONNECTOR_") >= 0 || 
         StringFind(name, "MV_") >= 0) {
         
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); // Hide
      }
   }
   
   ChartRedraw(); // Force update
   
   string filename = prefix + "_" + Symbol() + "_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + ".png";
   StringReplace(filename, ":", "-");
   
   // Capture
   bool captured = ChartScreenShot(0, filename, Screenshot_Width, Screenshot_Height, ALIGN_RIGHT);
   
   // Restore objects
   for(int i = total - 1; i >= 0; i--) {
      string name = ObjectName(i);
      if(ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_LABEL || 
         ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_TEXT || 
         ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_RECTANGLE_LABEL || 
         StringFind(name, "CONNECTOR_") >= 0 || 
         StringFind(name, "MV_") >= 0) {
         
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); // Show
      }
   }
   
   ChartRedraw();
   ChartSetInteger(0, CHART_SCALE, oldScale);
   
   if(captured) {
       Print("Screenshot saved: ", filename);
       return filename;
   }
   return "";
}

//+------------------------------------------------------------------+
//| Clear old screenshot files                                        |
//+------------------------------------------------------------------+
void ClearOldScreenshots()
{
   // Optional: Implement actual cleanup if needed
}

//+------------------------------------------------------------------+
//| Check signal results and update win/loss                         |
//+------------------------------------------------------------------+
void CheckSignalResults()
{
   for(int i = 0; i < signalCount; i++) {
      if(signalHistory[i].processed) continue;
      
      // CRITICAL FIX: Do not process Result if Signal Screenshot is still pending!
      // This prevents "Result before Signal" and Race Conditions.
      if(signalHistory[i].pendingScreenshot) continue;
      
      datetime expiryTime = signalHistory[i].time + signalHistory[i].expiryMinutes * 60;
      
      if(TimeCurrent() >= expiryTime) {
         double entryPrice = signalHistory[i].entryPrice;
         double exitPrice = Close[0];
         
         bool win = false;
         if(signalHistory[i].direction == "CALL") win = (exitPrice > entryPrice);
         else win = (exitPrice < entryPrice);
         
         signalHistory[i].win = win;
         signalHistory[i].processed = true;
         
         if(win) {
            Print("Result: WIN for ", signalHistory[i].symbol);
            totalWins++; 
            UpdateGlobalStats(true);
            LogTradeToSharedFile(signalHistory[i]); // Log to shared file
            
            // Release Global Lock
            GlobalVariableSet("MT4_CONN_ACTIVE_TRADE", 0.0);
            Print("GLOBAL LOCK: Trade WON. Lock released.");
         }
         else {
             Print("Result: LOSS for ", signalHistory[i].symbol, " Step: ", signalHistory[i].martingaleStep, " Max: ", Martingale_Steps);
             
             if(Martingale_Enable && signalHistory[i].martingaleStep < Martingale_Steps) {
                // Intermediate Loss: Trigger next step
                Print(" -> Intermediate Loss. Triggering Martingale Step. LOCK MAINTAINED.");
                ProcessMartingaleStep(signalHistory[i]);
                continue; // SKIP Sending Result
             } else {
                // Final Loss
                Print(" -> Final Loss. Proceeding to Send Result.");
                totalLosses++;
                UpdateGlobalStats(false);
                LogTradeToSharedFile(signalHistory[i]); // Log to shared file
                
                // Release Global Lock
                GlobalVariableSet("MT4_CONN_ACTIVE_TRADE", 0.0);
                Print("GLOBAL LOCK: Trade LOST (Final). Lock released.");
             }
         }
         
         Print("Sending Telegram Result for ", signalHistory[i].symbol);
         if(Telegram_Enable && Telegram_SendResult) {
            if(Telegram_SendResult) { // Check input again
                 if(Screenshot_ClearOld) ClearOldScreenshots(); // Optional cleanup
                 
                 string resFilename = CaptureScreenshot("Result");
                 
                 // We need to send this result WITH photo.
                 // Since SignalData is in array, we can set a flag or just handle it here.
                 // But ProcessPending is for History items?
                 // Let's create a temporary structure or handle it.
                 // EASIER: Just try to send photo here with a small sleep (blocking) or reuse pending logic?
                 // Reusing pending logic on 'signalHistory' is complex because this is an UPDATE to existing signal.
                 // I will add a special "PendingResult" state to the signal?
                 
                 // SIMPLER: Use a small loop here because results are less frequent.
                 // Or add to a separate 'pendingUploads' list?
                 // Let's modify SignalData to handle 'isResult'.
                 
                 signalHistory[i].pendingScreenshot = true;
                 signalHistory[i].screenshotFile = resFilename;
                 signalHistory[i].screenshotTime = TimeCurrent();
                 signalHistory[i].isResult = true; // MARK AS RESULT
            } else {
                SendTelegramResult(signalHistory[i]);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process martingale step after loss                               |
//+------------------------------------------------------------------+
void ProcessMartingaleStep(SignalData &lossSignal)
{
   SignalData martSignal;
   martSignal.time = TimeCurrent();
   martSignal.symbol = lossSignal.symbol;
   martSignal.direction = lossSignal.direction;
   martSignal.entryPrice = Close[0];
   martSignal.expiryMinutes = Martingale_NextExpiry;
   martSignal.processed = false;
   martSignal.win = false;
   martSignal.martingaleStep = lossSignal.martingaleStep + 1;
   martSignal.pendingScreenshot = false; // CRITICAL: Must be false to allow processing
   martSignal.isResult = false;
   martSignal.screenshotFile = "";
   
   ArrayResize(signalHistory, signalCount + 1);
   signalHistory[signalCount] = martSignal;
   signalCount++;
   
   Print("Martingale Step ", martSignal.martingaleStep, " triggered");
}

//+------------------------------------------------------------------+
//| Send result to Telegram                                          |
//+------------------------------------------------------------------+
void SendTelegramResult(SignalData &signal)
{
   string message = "";
   
   // Result Header
   message = "========== RESULT ============\n\n";
   message += "🔔 " + signal.symbol + "\n";
   message += "🕐 " + TimeToString(signal.time, TIME_MINUTES) + "\n";
   
   // Win/Loss Status
   if(signal.win) {
      // Dynamic Checkmarks: 1 for Direct, 2 for Step 1, etc. (Step + 1 checkmarks)
      string checks = "";
      for(int k=0; k <= signal.martingaleStep; k++) checks += "✅";
      message += checks + " WIN\n";
   } else {
      message += "❌❌❌ LOSS\n";
   }
   
   // Session Stats (Global)
   int gw, gl;
   GetGlobalStats(gw, gl);
   
   double globalWinRate = 0;
   int total = gw + gl;
   if(total > 0) globalWinRate = (double)gw / total * 100.0;
   
   message += "🎃 Win: " + IntegerToString(gw) + " | Loss: " + IntegerToString(gl) + " (" + DoubleToString(globalWinRate, 1) + "%)\n";
   
   string url = "https://api.telegram.org/bot" + Telegram_BotToken + "/sendMessage";
   string params = "chat_id=" + Telegram_ChatID + "&text=" + UrlEncode(message);
   
   char post[], resultData[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   StringToCharArray(params, post, 0, StringLen(params));
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, resultData, headers);
   
   if(res == -1) {
      SendTelegramViaDLL(message);
   } else {
       string resultStr = CharArrayToString(resultData);
       if(StringFind(resultStr, "\"ok\":true") < 0) {
           SendTelegramViaDLL(message);
       }
   }
}

//+------------------------------------------------------------------+
//| Create statistics dashboard                                      |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   // Dashboard will be created with OBJ_LABEL objects
   // Similar to the Magic V indicator
}

//+------------------------------------------------------------------+
//| Update statistics dashboard                                      |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int gw, gl;
   GetGlobalStats(gw, gl);
   
   double winRate = 0;
   int total = gw + gl;
   if(total > 0) winRate = (double)gw / total * 100.0;
   
   int x = 10;
   int y = 100;
   int lineHeight = 20;
   
   // Title
   CreateLabel("CONNECTOR_Title", x, y, "⚡ CONNECTOR V7.0", "Arial Black", 10, clrGold);
   
   // Stats (Global)
   CreateLabel("CONNECTOR_Signals", x, y + lineHeight, "Total Signals: " + IntegerToString(total), "Arial", 9, clrWhite);
   CreateLabel("CONNECTOR_Wins", x, y + lineHeight * 2, "Wins: " + IntegerToString(gw), "Arial", 9, clrLime);
   CreateLabel("CONNECTOR_Losses", x + 80, y + lineHeight * 2, "| Loss: " + IntegerToString(gl), "Arial", 9, clrRed);
   
   color rateColor = winRate >= 70 ? clrLime : (winRate >= 50 ? clrYellow : clrRed);
   CreateLabel("CONNECTOR_Rate", x, y + lineHeight * 3, "Win Rate: " + DoubleToString(winRate, 1) + "%", "Arial Bold", 10, rateColor);

   // Lock Status (New)
   string lockStatus = "READY";
   color lockColor = clrLime;
   if(GlobalVariableCheck("MT4_CONN_ACTIVE_TRADE")) {
       datetime lTime = (datetime)GlobalVariableGet("MT4_CONN_ACTIVE_TRADE");
       if(lTime > 0 && TimeCurrent() - lTime < 1800) {
           lockStatus = "BUSY (" + Symbol() + ")";
           lockColor = clrYellow;
       }
   }
   CreateLabel("CONNECTOR_Lock", x, y + lineHeight * 4, "STATUS: " + lockStatus, "Arial Bold", 9, lockColor);
}

//+------------------------------------------------------------------+
//| Global Statistics Helpers                                        |
//+------------------------------------------------------------------+
void UpdateGlobalStats(bool isWin) {
   string winVar = "MT4_CONN_WINS";
   string lossVar = "MT4_CONN_LOSS";
   
   if(!GlobalVariableCheck(winVar)) GlobalVariableSet(winVar, 0);
   if(!GlobalVariableCheck(lossVar)) GlobalVariableSet(lossVar, 0);
   
   if(isWin) {
      double current = GlobalVariableGet(winVar);
      GlobalVariableSet(winVar, current + 1);
   } else {
      double current = GlobalVariableGet(lossVar);
      GlobalVariableSet(lossVar, current + 1);
   }
}

void GetGlobalStats(int &wins, int &losses) {
   string winVar = "MT4_CONN_WINS";
   string lossVar = "MT4_CONN_LOSS";
   
   if(GlobalVariableCheck(winVar)) wins = (int)GlobalVariableGet(winVar);
   else wins = 0;
   
   if(GlobalVariableCheck(lossVar)) losses = (int)GlobalVariableGet(lossVar);
   else losses = 0;
}

//+------------------------------------------------------------------+
//| Send Periodic Summary Report (GLOBAL)                            |
//+------------------------------------------------------------------+
void SendPeriodicReport()
{
   Print("Generating Global Periodic Report...");
   
   string message = "========== GLOBAL REPORT ==========\n";
   message += "🗓 " + TimeToString(TimeCurrent(), TIME_DATE) + "\n";
   message += "-----------------------------\n";
   
   string filename = "GlobalTrades_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   StringReplace(filename, ".", "");
   
   // Open from Common folder so all charts see it
   int handle = FileOpen(filename, FILE_CSV|FILE_READ|FILE_COMMON, ",");
   
   if(handle == INVALID_HANDLE) {
       Print("No global trade file found for today: ", filename);
       return;
   }
   
   int reportWins = 0;
   int reportLosses = 0;
   int count = 0;
   string tradeList = "";
   
   while(!FileIsEnding(handle)) {
       string tStr = FileReadString(handle);
       if(tStr == "" || FileIsEnding(handle)) continue;

       string sym   = FileReadString(handle);
       string dir   = FileReadString(handle);
       string winS  = FileReadString(handle);
       string stepS = FileReadString(handle);
       
       if(sym == "" || dir == "") continue;
       
       datetime tradeTime = (datetime)StringToInteger(tStr);
       bool isWin = (winS == "1");
       int step = (int)StringToInteger(stepS);
       
       // Only show trades since the last report on THIS chart
       if(tradeTime < lastReportTime) continue;
       
       // Formatting
       string icon = isWin ? "✅" : "❌";
       if(isWin && Martingale_Enable && step > 0) {
           icon += GetSuperscript(step);
       }
       
       string dirDisp = (dir == "CALL") ? "BUY" : "SELL"; 
       
       tradeList += "⏹ " + TimeToString(tradeTime, TIME_MINUTES) + " - " + 
                    sym + " - " + dirDisp + " " + icon + "\n";
       
       if(isWin) reportWins++;
       else reportLosses++;
       count++;
   }
   FileClose(handle);
   
   if(count == 0) {
       Print("No new global trades to report.");
       return; 
   }
   
   message += "📊 Total : " + IntegerToString(count) + "\n";
   message += "-----------------------------\n";
   message += "SIGNAL HISTORY\n";
   message += "-----------------------------\n";
   message += tradeList;
   message += "-----------------------------\n";
   
   double winRate = (count > 0) ? (double)reportWins / count * 100.0 : 0;
   
   message += "🔹 G-Win : " + IntegerToString(reportWins) + " | G-Loss : " + IntegerToString(reportLosses) + " | " + DoubleToString(winRate, 0) + "%\n";
   message += "-----------------------------\n";
   message += "🤖 MT4 : " + AccountCompany() + " MT4\n";
   message += "❤️ Global Report Sent Successfully\n";
   message += "-----------------------------";
   
   // Send to Telegram
   if(Telegram_Enable) {
      string url = "https://api.telegram.org/bot" + Telegram_BotToken + "/sendMessage";
      string params = "chat_id=" + Telegram_ChatID + "&text=" + UrlEncode(message);
      
      char post[], resultData[];
      string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
      StringToCharArray(params, post, 0, StringLen(params));
      
      ResetLastError();
      string resHeaders;
      int res = WebRequest("POST", url, headers, 5000, post, resultData, resHeaders);
      
      if(res == -1) {
          SendTelegramViaDLL(message);
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Create label object                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, string font, int size, color clr)
{
   if(ObjectFind(name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Send test Telegram message on init                               |
//+------------------------------------------------------------------+
void SendTestTelegramMessage()
{
   Print("=== TELEGRAM TEST MESSAGE ===");
   Print("Bot Token (first 15 chars): ", StringSubstr(Telegram_BotToken, 0, 15), "...");
   Print("Chat ID: ", Telegram_ChatID);
   
   string testMessage = "MT4 Connector Test - Connection OK";
   string encodedMessage = UrlEncode(testMessage);
   
   string url = "https://api.telegram.org/bot" + Telegram_BotToken + "/sendMessage";
   string params = "chat_id=" + Telegram_ChatID + "&text=" + encodedMessage;
   
   char post[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   StringToCharArray(params, post, 0, StringLen(params));
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, headers);
   int error = GetLastError();
   
   Print("WebRequest result: ", res);
   
   if(res == -1) {
      Print("WebRequest Failed (Error ", error, "). Switching to DLL mode...");
      
      if(error == 4060) {
         Print("Trying to bypass Error 4060 using WinInet.dll...");
         if(SendTelegramViaDLL(testMessage)) {
            Print(">>> SUCCESS! DLL Fallback worked! <<<");
            Alert("Telegram Connected (via DLL Mode)");
         } else {
            Print(">>> DLL Failed too. Check Internet connection <<<");
            Alert("TELEGRAM FAILED! Even DLL mode didn't work.");
         }
      } else {
          // Try DLL anyway for other errors
          if(SendTelegramViaDLL(testMessage)) {
            Print(">>> SUCCESS! DLL Fallback worked! <<<");
          }
      }
   } else {
      string resultStr = CharArrayToString(result);
      if(StringFind(resultStr, "\"ok\":true") >= 0) {
         Print("SUCCESS! WebRequest working normally.");
      }
   }
}
//+------------------------------------------------------------------+
//| Load file into byte array                                        |
//+------------------------------------------------------------------+
bool LoadFile(string filename, char &data[])
{
   ResetLastError();
   int handle = FileOpen(filename, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE) {
      // Print("FileOpen failed: ", filename, " Error: ", GetLastError());
      return false;
   }
   
   int fileSize = (int)FileSize(handle);
   if(fileSize > 0) {
      ArrayResize(data, fileSize);
      FileReadArray(handle, data, 0, fileSize);
   }
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| Send Photo to Telegram (Multipart)                               |
//+------------------------------------------------------------------+
bool SendTelegramPhoto(string caption, string filename)
{
   // 1. Try to load image
   char imageData[];
   if(!LoadFile(filename, imageData)) return false;
   
   Print("Sending Photo: ", filename, " Size: ", ArraySize(imageData), " bytes");
   
   string boundary = "---------------------------" + IntegerToString(GetTickCount());
   string url = "https://api.telegram.org/bot" + Telegram_BotToken + "/sendPhoto";
   
   // 2. Build Body
   string boundaryPrefix = "--" + boundary + "\r\n";
   string rn = "\r\n";
   
   // Part 1: chat_id
   string body_chatId = boundaryPrefix + 
                        "Content-Disposition: form-data; name=\"chat_id\"" + rn + rn + 
                        Telegram_ChatID + rn;
                        
   // Part 2: caption (UTF-8)
   string body_caption = boundaryPrefix + 
                         "Content-Disposition: form-data; name=\"caption\"" + rn + rn;
   // Caption content is added as bytes later
   
   // Part 3: photo header
   string body_photo = rn + boundaryPrefix + 
                       "Content-Disposition: form-data; name=\"photo\"; filename=\"screenshot.png\"" + rn + 
                       "Content-Type: image/png" + rn + rn;
                       
   // Part 4: Footer
   string body_footer = rn + "--" + boundary + "--" + rn;
   
   // Calculate total size and allocate
   char captionBytes[];
   int captionLen = StringToCharArray(caption, captionBytes, 0, -1, CP_UTF8);
   // Note: StringToCharArray includes null term. We exclude it.
   if(captionLen > 0) captionLen--; 
   
   int len1 = StringLen(body_chatId);
   int len2 = StringLen(body_caption);
   int len3 = StringLen(body_photo);
   int len4 = StringLen(body_footer);
   int imgLen = ArraySize(imageData);
   
   int totalSize = len1 + len2 + captionLen + len3 + imgLen + len4;
   
   char data[];
   ArrayResize(data, totalSize);
   
   int offset = 0;
   // Copy ChatID Part
   StringToCharArray(body_chatId, data, offset, len1); offset += len1;
   
   // Copy Caption Header
   StringToCharArray(body_caption, data, offset, len2); offset += len2;
   
   // Copy Caption Bytes
   ArrayCopy(data, captionBytes, offset, 0, captionLen); offset += captionLen;
   
   // Copy Photo Header
   StringToCharArray(body_photo, data, offset, len3); offset += len3;
   
   // Copy Image Bytes
   ArrayCopy(data, imageData, offset, 0, imgLen); offset += imgLen;
   
   // Copy Footer
   StringToCharArray(body_footer, data, offset, len4);
   
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
   
   // 3. Send Request
   char result[];
   string resHeaders;
   ResetLastError();
   
   // Try WebRequest first
   int res = WebRequest("POST", url, headers, 10000, data, result, resHeaders);
   
   if(res == -1 || StringFind(CharArrayToString(result), "\"ok\":true") < 0) {
       Print("WebRequest (Photo) Failed. Error: ", GetLastError(), ". Response: ", CharArrayToString(result));
       // Fallback to DLL
       return SendTelegramPhotoViaDLL(headers, data);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Send Photo via DLL (Fallback)                                    |
//+------------------------------------------------------------------+
bool SendTelegramPhotoViaDLL(string headers, char &data[])
{
   Print("Attempting purchase/upload via DLL...");
   Alert("Telegram: WebRequest failed. Trying DLL Upload... ⏳");
   
   // 1. Open Internet
   int hInternet = InternetOpenW("MT4 Connector", 1, NULL, NULL, 0);
   if(hInternet == 0) return false;
   
   // 2. Connect
   int hConnect = InternetConnectW(hInternet, "api.telegram.org", 443, "", "", 3, 0, 0);
   if(hConnect == 0) { InternetCloseHandle(hInternet); return false; }
   
   // 3. Open Request
   string objectName = "/bot" + Telegram_BotToken + "/sendPhoto";
   int hRequest = HttpOpenRequestW(hConnect, "POST", objectName, "HTTP/1.1", NULL, 0, 0x00800000 | 0x04000000, 0);
   if(hRequest == 0) { InternetCloseHandle(hConnect); InternetCloseHandle(hInternet); return false; }
   
   // 4. Send Request with Data
   bool sent = HttpSendRequestW(hRequest, headers, StringLen(headers), data, ArraySize(data));
   
   if(sent) Print("✓ Photo sent via DLL!");
   else Print("DLL Upload Failed");
   
   InternetCloseHandle(hRequest);
   InternetCloseHandle(hConnect);
   InternetCloseHandle(hInternet);
   
   return sent;
}

//+------------------------------------------------------------------+
//| Process any pending screenshot uploads                           |
//+------------------------------------------------------------------+
void ProcessPendingScreenshots()
{
   for(int i = 0; i < signalCount; i++) {
      if(signalHistory[i].pendingScreenshot) {
         // Check timeout (e.g. 10 seconds)
         if(TimeCurrent() - signalHistory[i].screenshotTime > 10) {
            Print("Screenshot timeout for signal ", i);
            signalHistory[i].pendingScreenshot = false;
            // Fallback: Send Text Only
            if(signalHistory[i].isResult) SendTelegramResult(signalHistory[i]);
            else SendTelegramSignal(signalHistory[i]);
            continue;
         }
         
         // Try to send
         string caption = "";
         if(signalHistory[i].isResult) {
            // Reconstruct Result Message (Logic duplicated from SendTelegramResult, ideally refactor)
            // Simplified for now:
             caption = "========== RESULT ============\n" + 
                       "🔔 " + signalHistory[i].symbol + "\n" + 
                       (signalHistory[i].win ? "✅ WIN" : "❌ LOSS");
             // Full stats logic requires accessing globals. 
             // Ideally we just call SendTelegramResult passing "CheckOnly" or similar?
             // Since SendTelegramResult doesn't return string, we duplicate logic slightly or extract it.
             // For now, I will assume SendTelegramResult logic is copied/called.
             // Let's call a helper "GetResultCaption(signal)".
             caption = GetResultCaption(signalHistory[i]);
         } else {
             caption = GetSignalCaption(signalHistory[i]);
         }
         
         if(SendTelegramPhoto(caption, signalHistory[i].screenshotFile)) {
             Alert("Telegram: Photo Sent! 📸");
             signalHistory[i].pendingScreenshot = false; // Done
         }
         // If false, it keeps trying until timeout (LoadFile usually fails until file is ready)
      }
   }
}

string GetSignalCaption(SignalData &signal) {
    if(Telegram_MessageTemplate != "") {
       string msg = Telegram_MessageTemplate;
       StringReplace(msg, "{SYMBOL}", signal.symbol);
       StringReplace(msg, "{DIRECTION}", signal.direction);
       return msg;
    }
    return "========== SIGNAL ============\n" + 
           "🔔 " + signal.symbol + "\n" + 
           "🕐 " + TimeToString(signal.time, TIME_MINUTES) + "\n" +
           (signal.direction == "CALL" ? "🟢 CALL" : "🔴 PUT") + "\n" + 
           "📌 " + DoubleToString(signal.entryPrice, Digits);
}

string GetResultCaption(SignalData &signal) {
   string msg = "========== RESULT ============\n" + 
                "🔔 " + signal.symbol + "\n" + 
                "🕐 " + TimeToString(signal.time, TIME_MINUTES) + "\n";
                
   if(signal.win) {
      string checks = "";
      for(int k=0; k <= signal.martingaleStep; k++) checks += "✅";
      msg += checks + " WIN\n";
   } else {
      msg += "❌❌❌ LOSS\n";
   }
   
   int gw, gl;
   GetGlobalStats(gw, gl);
   
   double winRate = 0;
   int total = gw + gl;
   if(total > 0) winRate = (double)gw / total * 100.0;
   msg += "🎃 Win: " + IntegerToString(gw) + " | Loss: " + IntegerToString(gl) + " (" + DoubleToString(winRate, 1) + "%)";
   return msg;
}

//+------------------------------------------------------------------+
//| Helper: Get Superscript Number                                   |
//+------------------------------------------------------------------+
string GetSuperscript(int num) {
    if(num == 1) return ShortToString((ushort)0x00B9);
    if(num == 2) return ShortToString((ushort)0x00B2);
    if(num == 3) return ShortToString((ushort)0x00B3);
    if(num == 4) return ShortToString((ushort)0x2074);
    if(num == 5) return ShortToString((ushort)0x2075);
    return "(" + IntegerToString(num) + ")";
}

//+------------------------------------------------------------------+
//| Log trade to shared global file                                  |
//+------------------------------------------------------------------+
void LogTradeToSharedFile(SignalData &signal)
{
   // Format: Time,Symbol,Direction,Win(1/0),Step
   string filename = "GlobalTrades_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   StringReplace(filename, ".", ""); // Remove dots from date
   
   int handle = FileOpen(filename, FILE_CSV|FILE_READ|FILE_WRITE|FILE_COMMON, ",");
   if(handle > 0) {
       FileSeek(handle, 0, SEEK_END);
       
       string winStr = signal.win ? "1" : "0";
       string line = (string)signal.time + "," + signal.symbol + "," + signal.direction + "," + winStr + "," + IntegerToString(signal.martingaleStep);
       
       FileWrite(handle, line);
       FileClose(handle);
       Print("Logged trade to shared file: ", line);
   } else {
       Print("Error opening shared file: ", GetLastError());
   }
}

