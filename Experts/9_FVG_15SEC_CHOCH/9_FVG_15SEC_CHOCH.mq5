#include <Trade/Trade.mqh>
CTrade Trade;

#define MagicNumber 999999

input double pipSize = 0.0020;
input double risk2reward = 6;
input double accountRisk = 50; // Risk in dollars
input int START_HOUR = 9;
input int END_HOUR = 18; 
input ENUM_TIMEFRAMES FVG_TIMEFRAME = PERIOD_M15;  // Timeframe
input int ORDER_BLOCK_TIME_LIMIT = 45;
input bool verbose = false;
input int dailyLimit = 3;
input int WeeklyLimit = 5;
#define INPUT_PERIOD 15

void SetChartAppearance() {
    ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrWhite);     // Background
    ChartSetInteger(0, CHART_COLOR_FOREGROUND, clrBlack);     // Text & scales
    ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, clrWhite); // Bullish candles
    ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, clrBlack); // Bearish candles
    ChartSetInteger(0, CHART_COLOR_CHART_UP, clrBlack);         // Bar up color
    ChartSetInteger(0, CHART_COLOR_CHART_DOWN, clrBlack);     // Bar down color
    ChartSetInteger(0, CHART_SHOW_GRID, false);                     // Hide grid
    ChartSetInteger(0, CHART_MODE, CHART_CANDLES);                 // Candlestick mode
    ChartSetInteger(0, CHART_COLOR_CHART_LINE, clrBlack);           // Line chart color
}

enum TimeState {
    STATE_OUTSIDE_TIME = 0,     // Outside trading time window
    STATE_IN_TIME = 1,          // Within trading time window
    STATE_TRADE_TIME = 2        // Within trade execution time window
};

enum MarketActionState {
    STATE_TAKE_LIQUIDITY_A = 0, // Taking liquidity at level A
    STATE_TAKE_LIQUIDITY_B = 1, // Taking liquidity at level B 
    STATE_CHOCH_BULLISH = 2,    // Bullish Change of Character detected
    STATE_CHOCH_BEARISH = 3,    // Bearish Change of Character detected
    STATE_ORDERBLOCK_BULLISH = 4, // Bullish Order Block detected
    STATE_ORDERBLOCK_BEARISH = 5,  // Bearish Order Block detected
    STATE_NOTHING = 6             // No significant market action detected
};

string GetTimeStateText(TimeState state) {
    string stateText;
    switch(state) {
        case STATE_IN_TIME:
            stateText = "Scanning for Setup";
            break;
        case STATE_OUTSIDE_TIME:
            stateText = "Outside Trading Window"; 
            break;
        case STATE_TRADE_TIME:
            stateText = "Ready to Execute";
            break;
        default:
            stateText = "Unknown Time State";
    }
    return stateText;
}

string GetMarketActionStateText(MarketActionState state) {
    string stateText;
    switch(state) {
        case STATE_TAKE_LIQUIDITY_A:
            stateText = "Taking Liquidity at Level A";
            break;
        case STATE_TAKE_LIQUIDITY_B:
            stateText = "Taking Liquidity at Level B";
            break;            
        case STATE_CHOCH_BULLISH:
            stateText = "Bullish CHoCH Detected";
            break;
        case STATE_CHOCH_BEARISH:
            stateText = "Bearish CHoCH Detected";
            break;
        case STATE_ORDERBLOCK_BULLISH:
            stateText = "Bullish OB Detected";
            break;
        case STATE_ORDERBLOCK_BEARISH:
            stateText = "Bearish OB Detected";
            break;
        default:
            stateText = "Unknown Market Action State";
    }
    return stateText;
}

// Current time state
TimeState currentTimeState = STATE_OUTSIDE_TIME;
// Current market action state
MarketActionState currentState = STATE_NOTHING;
// Current Position Method
string Mode = "None";

datetime lastFVGTime = 0;

// Lines Values
double highLineValue = 10;
double lowLineValue = -10;

// Swings
double Highs[];
double Lows[];
datetime HighsTime[];
datetime LowsTime[];

double A_value = 2;
double B_value = 0;
datetime A_time;
datetime B_time;

datetime lastBuTime = 0;
datetime lastBeTime = 0;

double bullishOrderBlockHigh[];
double bullishOrderBlockLow[];
datetime bullishOrderBlockTime[];

double bearishOrderBlockHigh[];
double bearishOrderBlockLow[];
datetime bearishOrderBlockTime[];

double bullishFVGHigh[];
double bullishFVGLow[];
datetime bullishFVGTime[];

double bearishFVGHigh[];
double bearishFVGLow[];
datetime bearishFVGTime[];

int dailyCount = 0;
int weeklyCount = 0;
int weekDay = 0;

datetime lastBarTime = 0;
double open, high, low, close;
MqlRates rates15[];  // Array to store the rates
bool isFirstBar = true;

MqlDateTime lastDateStruct;

void createObj(datetime time, double price, int arrowCode, int direction, color clr) {
    MqlDateTime timeStruct;
    TimeToStruct(time, timeStruct);
    string objName ="Signal@" + TimeToString(time) + ":" + IntegerToString(timeStruct.sec) + "at" + DoubleToString(price, _Digits) + "(" + IntegerToString(arrowCode) + ")";

    if(ObjectCreate(0, objName, OBJ_ARROW, 0, time, price)) {
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        if(direction > 0)
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_TOP);
        if(direction < 0)
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    }
}

int OnInit() {
    SetChartAppearance();

    ArraySetAsSeries(Highs, true);
    ArraySetAsSeries(Lows, true);
    ArraySetAsSeries(HighsTime, true);
    ArraySetAsSeries(LowsTime, true);

    ArraySetAsSeries(bullishOrderBlockHigh,true);
    ArraySetAsSeries(bullishOrderBlockLow,true);
    ArraySetAsSeries(bullishOrderBlockTime,true);

    ArraySetAsSeries(bearishOrderBlockHigh,true);
    ArraySetAsSeries(bearishOrderBlockLow,true);
    ArraySetAsSeries(bearishOrderBlockTime,true);

    ArraySetAsSeries(bullishFVGHigh, true);
    ArraySetAsSeries(bullishFVGLow, true);
    ArraySetAsSeries(bullishFVGTime, true);
    
    ArraySetAsSeries(bearishFVGHigh, true);
    ArraySetAsSeries(bearishFVGLow, true);
    ArraySetAsSeries(bearishFVGTime, true);

    ArraySetAsSeries(rates15, true);

    return(INIT_SUCCEEDED);
}

void OnTick() {
    if(DrawDayLine() == -1)
        return;
    
    datetime currentTime = TimeCurrent();
    MqlDateTime currentDateStruct;
    TimeToStruct(currentTime, currentDateStruct);

    if (lastBarTime == 0) {
        // Set initial time to the nearest 15-second mark
        lastBarTime = currentTime - (currentTime % 15);
        isFirstBar = true;
    }

    if (currentTime - lastBarTime >= INPUT_PERIOD) {
        // Create new MqlRates structure for the completed candle
        MqlRates new_rate;
        new_rate.time = lastBarTime;
        new_rate.open = open;
        new_rate.high = high;
        new_rate.low = low;
        new_rate.close = close;

        // Add the new rate to the array
        ArrayResize(rates15, ArraySize(rates15) + 1);
        for(int i = ArraySize(rates15) - 1;i > 0;--i)
            rates15[i] = rates15[i - 1];
        rates15[0] = new_rate;

        string candleType = (close > open) ? "Bullish" : "Bearish";
        if(verbose)
            Print(lastBarTime, " 15s Candle - Open: ", open, " High: ", high, " Low: ", low, " Close: ", close, " Type: ", candleType);
        lastBarTime = lastBarTime + 15;
        isFirstBar = true;
    }

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    // double value = (bid + ask) / 2;
    double value = bid;

    if (isFirstBar) {
        open = value;
        high = value;
        low = value;
    } else {
        high = MathMax(high, value);
        low = MathMin(low, value);
    }
    close = value;
    isFirstBar = false;

    if (ArraySize(rates15) < 15)
        return;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, 0, 50, rates);

    HandleTime(currentDateStruct);

    if (currentDateStruct.day != lastDateStruct.day) {
        lastDateStruct = currentDateStruct;
        highLineValue = 10;
        lowLineValue = -10;
    }

    swingPoints(rates15);
    int isOrderBlock = orderBlock(rates15);
    int fvgHappen = detectFairValueGaps();

    if (fvgHappen == 1) {
        if(verbose)
            Print("fvgHappen: ", fvgHappen, " Time: ", TimeToString(TimeCurrent()));
        currentState = STATE_NOTHING;
        Mode = "None";
        A_value = DBL_MAX;
        B_value = 0;
    }

    if(currentTimeState == STATE_OUTSIDE_TIME) {
        Mode = "None";
        currentState = STATE_NOTHING;
        A_value = DBL_MAX;
        B_value = 0;
        PlotABChochs(rates15);
        HighlightCurrentState(rates);
        return;
    }

    // SELL and BUY position Set
    if(currentState == STATE_NOTHING) {
        if (A_value < lowLineValue){
            currentState = STATE_TAKE_LIQUIDITY_A;
            Mode = "BUY";
        }
        if (B_value > highLineValue){
            currentState = STATE_TAKE_LIQUIDITY_B;
            Mode = "SELL";
        }
    }

    if (ArraySize(Highs) > 0 && ArraySize(Lows) > 0 && ArraySize(bullishOrderBlockTime) > 0 && ArraySize(bearishOrderBlockTime) > 0) {
        if (Mode != "BUY") {
            //CHoch Bullish
            if(rates15[1].high > B_value && rates15[2].close < B_value && B_time != lastBuTime) {
                if (currentState == STATE_CHOCH_BEARISH)
                    currentState = STATE_CHOCH_BULLISH;
                lastBuTime = B_time;
            }
            //CHoch Bearish     
            if(rates15[1].low < A_value && rates15[2].close > A_value && A_time != lastBeTime) {
                if (currentState == STATE_TAKE_LIQUIDITY_B || currentState == STATE_CHOCH_BULLISH)
                    currentState = STATE_CHOCH_BEARISH;
                lastBeTime = A_time;
            }

            if (Highs[0] > B_value) {
                A_time = LowsTime[0];
                A_value = Lows[0];
                B_time = HighsTime[0];
                B_value = Highs[0];
            }
        }

        if (Mode != "SELL") {
            //CHoch Bullish
            if(rates15[1].high > B_value && rates15[2].close < B_value && B_time != lastBuTime) {
                if (currentState == STATE_TAKE_LIQUIDITY_A || currentState == STATE_CHOCH_BEARISH)
                    currentState = STATE_CHOCH_BULLISH;
                lastBuTime = B_time;
            }
            //CHoch Bearish  
            if(rates15[1].low < A_value && rates15[2].close > A_value && A_time != lastBeTime) {
                if (currentState == STATE_CHOCH_BULLISH)
                    currentState = STATE_CHOCH_BEARISH;
                lastBeTime = A_time;
            }

            if (Lows[0] < A_value) {
                B_time = HighsTime[0];
                B_value = Highs[0];
                A_time = LowsTime[0];
                A_value = Lows[0];
            }
        }

        if ((Mode == "SELL" && MathAbs(rates[0].low - B_value) > pipSize) || (Mode == "BUY" && MathAbs(rates[0].high - A_value) > pipSize)){
            currentState = STATE_NOTHING;
            Mode = "None";
        }

        if (currentTimeState == STATE_TRADE_TIME) {
            if (Mode == "SELL" && currentState == STATE_CHOCH_BULLISH  && bearishOrderBlockTime[0] - B_time <= ORDER_BLOCK_TIME_LIMIT && bearishOrderBlockTime[0] >= B_time && isOrderBlock == 1)
                TradeExec(rates15);
            if (Mode == "BUY" && currentState == STATE_CHOCH_BEARISH && bullishOrderBlockTime[0] - A_time <= ORDER_BLOCK_TIME_LIMIT && bullishOrderBlockTime[0] >= A_time && isOrderBlock == -1)
                TradeExec(rates15);
        }
        
        ManageBreakeven();
    }
    
    PlotABChochs(rates15);
    HighlightCurrentState(rates);
}

void ManageBreakeven() {
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        if(!PositionSelectByTicket(PositionGetTicket(i)) || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;

        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

        double R = (type==POSITION_TYPE_BUY) ? (entry - sl) : (sl - entry);

        if (type==POSITION_TYPE_BUY && bid - entry >= 3 * R && sl < entry){
            Trade.PositionModify(_Symbol, entry + 0.5 * R, tp);
            Print("BUY Breakeven: ", TimeToString(TimeCurrent()), " SL: ", entry + 0.5 * R, " TP: ", tp);
        }
        if (type==POSITION_TYPE_SELL && entry - ask >= 3 * R && sl > entry){
            Trade.PositionModify(_Symbol, entry - 0.5 * R, tp);
            Print("SELL Breakeven: ", TimeToString(TimeCurrent()), " SL: ", entry - 0.5 * R, " TP: ", tp);
        }
    }
}

void HandleTime(MqlDateTime &currentTime) {
    currentTime.hour = START_HOUR; //9:00
    currentTime.min = 0;
    currentTime.sec = 0;
    datetime startTime = StructToTime(currentTime);

    currentTime.hour = 16; // 16:30
    currentTime.min = 30;
    datetime start1Time = StructToTime(currentTime);

    currentTime.hour = 18; // 18:00
    currentTime.min = 0;
    datetime end1Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 2; // 9:22
    // currentTime.min = 22;
    // datetime start2Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 3; // 10:07
    // currentTime.min = 7;
    // datetime end2Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 3; // 10:52
    // currentTime.min = 52;
    // datetime start3Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 4; // 11:37
    // currentTime.min = 37;
    // datetime end3Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 5; // 12:22
    // currentTime.min = 22;
    // datetime start4Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 6; // 13:07
    // currentTime.min = 7;
    // datetime end4Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 6; // 13:52
    // currentTime.min = 52;
    // datetime start5Time = StructToTime(currentTime);

    // currentTime.hour = START_HOUR + 7; // 14:37
    // currentTime.min = 37;
    // datetime end5Time = StructToTime(currentTime);

    currentTime.hour = END_HOUR; //18:00
    currentTime.min = 0;
    datetime endTime = StructToTime(currentTime);

    if(TimeCurrent() >= start1Time && TimeCurrent() <= end1Time)
        currentTimeState = STATE_TRADE_TIME;
    // else if(TimeCurrent() >= start2Time && TimeCurrent() <= end2Time)
    //     currentTimeState = STATE_TRADE_TIME;
    // else if(TimeCurrent() >= start3Time && TimeCurrent() <= end3Time)
    //     currentTimeState = STATE_TRADE_TIME;
    // else if(TimeCurrent() >= start4Time && TimeCurrent() <= end4Time)
    //     currentTimeState = STATE_TRADE_TIME;
    // else if(TimeCurrent() >= start5Time && TimeCurrent() <= end5Time)
    //     currentTimeState = STATE_TRADE_TIME;
    else if(TimeCurrent() >= startTime && TimeCurrent() <= endTime)
        currentTimeState = STATE_IN_TIME;
    else
        currentTimeState = STATE_OUTSIDE_TIME;

    string highlightName = "TimeHighlight_main";
    ObjectCreate(0, highlightName, OBJ_VLINE, 0, startTime, 0);
    ObjectSetInteger(0, highlightName, OBJPROP_COLOR, clrBlue);
    ObjectCreate(0, highlightName + "_end", OBJ_VLINE, 0, endTime, 0);
    ObjectSetInteger(0, highlightName + "_end", OBJPROP_COLOR, clrBlue);

    string highlightName1 = "TimeHighlight_1_start";
    ObjectCreate(0, highlightName1, OBJ_VLINE, 0, start1Time, 0);
    ObjectSetInteger(0, highlightName1, OBJPROP_COLOR, clrGreen);
    ObjectCreate(0, highlightName1 + "_end", OBJ_VLINE, 0, end1Time, 0);
    ObjectSetInteger(0, highlightName1 + "_end", OBJPROP_COLOR, clrRed);

    // string highlightName2 = "TimeHighlight_2_start";
    // ObjectCreate(0, highlightName2, OBJ_VLINE, 0, start2Time, 0);
    // ObjectSetInteger(0, highlightName2, OBJPROP_COLOR, clrGreen);
    // ObjectCreate(0, highlightName2 + "_end", OBJ_VLINE, 0, end2Time, 0);
    // ObjectSetInteger(0, highlightName2 + "_end", OBJPROP_COLOR, clrRed);

    // string highlightName3 = "TimeHighlight_3_start";
    // ObjectCreate(0, highlightName3, OBJ_VLINE, 0, start3Time, 0);
    // ObjectSetInteger(0, highlightName3, OBJPROP_COLOR, clrGreen);
    // ObjectCreate(0, highlightName3 + "_end", OBJ_VLINE, 0, end3Time, 0);
    // ObjectSetInteger(0, highlightName3 + "_end", OBJPROP_COLOR, clrRed);

    // string highlightName4 = "TimeHighlight_4_start";
    // ObjectCreate(0, highlightName4, OBJ_VLINE, 0, start4Time, 0);
    // ObjectSetInteger(0, highlightName4, OBJPROP_COLOR, clrGreen);
    // ObjectCreate(0, highlightName4 + "_end", OBJ_VLINE, 0, end4Time, 0);
    // ObjectSetInteger(0, highlightName4 + "_end", OBJPROP_COLOR, clrRed);

    // string highlightName5 = "TimeHighlight_5_start";
    // ObjectCreate(0, highlightName5, OBJ_VLINE, 0, start5Time, 0);
    // ObjectSetInteger(0, highlightName5, OBJPROP_COLOR, clrGreen);
    // ObjectCreate(0, highlightName5 + "_end", OBJ_VLINE, 0, end5Time, 0);
    // ObjectSetInteger(0, highlightName5 + "_end", OBJPROP_COLOR, clrRed);
}

int DrawDayLine() {
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    if(now.day_of_week == 0)
        return 0;

    if(now.day_of_week == 1)
        weeklyCount = 0;

    if(now.day_of_week != weekDay){
        weekDay = now.day_of_week;
        dailyCount = 0;
    }

    if(dailyCount >= dailyLimit || weeklyCount >= WeeklyLimit)
        return - 1;
    else
        return 1;
}

void PlotABChochs(MqlRates &rates[]) {
    string BObjName = "B";
    if(ObjectCreate(0, BObjName, OBJ_TEXT, 0, B_time, B_value)) {
        ObjectSetString(0, BObjName, OBJPROP_TEXT, BObjName);
        ObjectSetInteger(0, BObjName, OBJPROP_COLOR, C'64,0,255');
    }
    string AObjName = "A";
    if(ObjectCreate(0, AObjName, OBJ_TEXT, 0, A_time, A_value)) {
        ObjectSetString(0, AObjName, OBJPROP_TEXT, AObjName);
        ObjectSetInteger(0, AObjName, OBJPROP_COLOR, C'64,0,255');
    }
    string bChoch = "B choch" + TimeToString(rates[0].time);
    if(ObjectCreate(0, bChoch, OBJ_TREND, 0, B_time, B_value, rates[0].time, B_value)) {
        ObjectSetInteger(0, bChoch, OBJPROP_COLOR, clrGreen);
        ObjectSetInteger(0, bChoch, OBJPROP_WIDTH, 4);
    }

    string achoch = "A choch" + TimeToString(rates[0].time);
    if(ObjectCreate(0, achoch, OBJ_TREND, 0, A_time, A_value, rates[0].time, A_value)) {
        ObjectSetInteger(0, achoch, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, achoch, OBJPROP_WIDTH, 4);
    }

    MqlDateTime tempTime;
    TimeToStruct(TimeCurrent(), tempTime);

    tempTime.hour = START_HOUR; //7:00
    tempTime.min = 0;
    tempTime.sec = 0;
    datetime startTime_ = StructToTime(tempTime);

    if (ObjectCreate(0, "HLL", OBJ_TREND, 0, startTime_, highLineValue, rates[0].time, highLineValue)){
        ObjectSetInteger(0, "HLL", OBJPROP_COLOR, clrBlack);
        ObjectSetInteger(0, "HLL", OBJPROP_WIDTH, 4);
    }

    if(ObjectCreate(0, "HLLName", OBJ_TEXT, 0, rates[0].time, highLineValue)){
        ObjectSetString(0, "HLLName", OBJPROP_TEXT, "HLL");
        ObjectSetInteger(0, "HLLName", OBJPROP_COLOR, clrBlack);
    }

    if (ObjectCreate(0, "LLL", OBJ_TREND, 0, startTime_, lowLineValue, rates[0].time, lowLineValue)){
        ObjectSetInteger(0, "LLL", OBJPROP_COLOR, clrBlack);
        ObjectSetInteger(0, "LLL", OBJPROP_WIDTH, 4);
    }

    if(ObjectCreate(0, "LLLName", OBJ_TEXT, 0, rates[0].time, lowLineValue)){
        ObjectSetString(0, "LLLName", OBJPROP_TEXT, "LLL");
        ObjectSetInteger(0, "LLLName", OBJPROP_COLOR, clrBlack);
    }
}

void TradeExec(MqlRates &rates[]) {
    Print("TradeExec");
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spread = ask - bid;
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // Get pip value
    // Set magic number for trade operations
    Trade.SetExpertMagicNumber(MagicNumber);

    if (Mode == "SELL") {
        double entryprice = bid;
        entryprice = NormalizeDouble(entryprice, _Digits);

        double stoploss = 0;
        for(int i = 0; i < MathMin(ArraySize(rates), 3); i++) {
            stoploss = MathMax(rates[i].high + spread, stoploss);
        }
        stoploss = NormalizeDouble(stoploss, _Digits);

        double riskvalue = stoploss - entryprice;
        riskvalue = NormalizeDouble(riskvalue, _Digits);

        double takeprofit = entryprice - (risk2reward * riskvalue);
        takeprofit = NormalizeDouble(takeprofit, _Digits);

        double pipsRisk = riskvalue / _Point;  // Risk in pips
        double lots = accountRisk / (pipsRisk * pipValue); // Calculate lot size
        lots = NormalizeDouble(lots, 2); // Round to 2 decimal places

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lots, entryprice, stoploss, takeprofit, "Sell Test")){
            dailyCount++;
            weeklyCount++;
            currentState = STATE_TAKE_LIQUIDITY_B;
        }
        else
            Print("Failed to open position. Error code: ", GetLastError());
    }
    if (Mode == "BUY") {
        double entryprice = ask;
        entryprice = NormalizeDouble(entryprice, _Digits);

        double stoploss = 10;
        for(int i = 0; i < MathMin(ArraySize(rates), 3); i++) {
            stoploss = MathMin(rates[i].low - spread, stoploss);
        }
        stoploss = NormalizeDouble(stoploss, _Digits);

        double riskvalue = entryprice - stoploss;
        riskvalue = NormalizeDouble(riskvalue, _Digits);

        double takeprofit = entryprice + (risk2reward * riskvalue);
        takeprofit = NormalizeDouble(takeprofit, _Digits);
        
        double pipsRisk = riskvalue / _Point;  // Risk in pips
        double lots = accountRisk / (pipsRisk * pipValue); // Calculate lot size
        lots = NormalizeDouble(lots, 2); // Round to 2 decimal places

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lots, entryprice, stoploss, takeprofit, "Buy Test")){
            dailyCount++;
            weeklyCount++;
            currentState = STATE_TAKE_LIQUIDITY_A;
        }
        else
            Print("Failed to open position. Error code: ", GetLastError());
    }
}

void HighlightCurrentState(const MqlRates &rates[]) {
    string timeStateText = GetTimeStateText(currentTimeState);
    string marketStateText = GetMarketActionStateText(currentState);
    
    // Create labels for current state if they don't exist
    if(ObjectFind(0, "TimeStateLabel") < 0) {
        ObjectCreate(0, "TimeStateLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_XDISTANCE, 600);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_YDISTANCE, 20);
    }
    
    if(ObjectFind(0, "MarketStateLabel") < 0) {
        ObjectCreate(0, "MarketStateLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_XDISTANCE, 600);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_YDISTANCE, 50);
    }

    if(ObjectFind(0, "ModeLabel") < 0) {
        ObjectCreate(0, "ModeLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_XDISTANCE, 600);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_YDISTANCE, 80);
    }
    
    // Update label text and appearance
    ObjectSetString(0, "TimeStateLabel", OBJPROP_TEXT, "Time State: " + timeStateText);
    ObjectSetString(0, "MarketStateLabel", OBJPROP_TEXT, "Market State: " + marketStateText);
    ObjectSetString(0, "ModeLabel", OBJPROP_TEXT, "Mode: " + Mode);
    
    // Set colors based on state
    color timeColor = (currentTimeState == STATE_TRADE_TIME) ? clrGreen : (currentTimeState == STATE_IN_TIME) ? clrBlue : clrRed;
    color textMarketColor = (currentState == STATE_CHOCH_BEARISH ) ? clrGreen : 
                        (currentState == STATE_CHOCH_BULLISH) ? clrRed :
                       (currentState == STATE_NOTHING) ? clrBlack : 
                       (currentState == STATE_TAKE_LIQUIDITY_A || currentState == STATE_TAKE_LIQUIDITY_B) ? clrOrange : clrBlack;
    color modeColor = (Mode == "BUY") ? clrGreen : (Mode == "SELL") ? clrRed : clrBlack;
    
    ObjectSetInteger(0, "TimeStateLabel", OBJPROP_COLOR, timeColor);
    ObjectSetInteger(0, "MarketStateLabel", OBJPROP_COLOR, textMarketColor);
    ObjectSetInteger(0, "ModeLabel", OBJPROP_COLOR, modeColor);

    // // Draw rectangle between current and previous bar
    string rectName = "StateRect" + TimeToString(rates[0].time);
    color marketColor = (currentState == STATE_CHOCH_BEARISH ) ? C'145,218,145' : 
                        (currentState == STATE_CHOCH_BULLISH) ? C'225,155,155' :
                       (currentState == STATE_NOTHING) ? C'181,177,177' : 
                       (currentState == STATE_TAKE_LIQUIDITY_A || currentState == STATE_TAKE_LIQUIDITY_B) ? C'230,200,146' : clrWhite;
    
    ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, rates[1].time, 0.5, rates[0].time, 2);
    ObjectSetInteger(0, rectName, OBJPROP_COLOR, marketColor);
    ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
    ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
}

datetime lastProcessedTime = 0;

void swingPoints(MqlRates &ratesNew[]) {    
    // Check if rates have changed by comparing the time of the current candle
    if(ratesNew[2].time == lastProcessedTime)
        return;
    
    //SwingHigh
    if(ratesNew[2].high >= ratesNew[3].high && ratesNew[2].high >= ratesNew[1].high) {
        ArrayResize(Highs, MathMin(ArraySize(Highs) + 1, 10));
        for(int i = ArraySize(Highs) - 1;i > 0;--i)
            Highs[i] = Highs[i - 1];
        Highs[0] = ratesNew[2].high;

        ArrayResize(HighsTime, MathMin(ArraySize(HighsTime) + 1, 10));
        for(int i= ArraySize(HighsTime) - 1;i>0;--i)
            HighsTime[i] = HighsTime[i - 1];
        HighsTime[0] = ratesNew[2].time;

        string objName ="Signal@" + TimeToString(ratesNew[2].time) + "at" + DoubleToString(ratesNew[2].high, _Digits) + "(" + IntegerToString(234) + ")";
        if(ObjectCreate(0, objName, OBJ_ARROW, 0, ratesNew[2].time, ratesNew[2].high)) {
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 234);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrOrangeRed);
        }
    }
    //SwingLow
    if(ratesNew[2].low <= ratesNew[3].low && ratesNew[2].low <= ratesNew[1].low) {
        ArrayResize(Lows, MathMin(ArraySize(Lows) + 1, 10));
        for(int i= ArraySize(Lows) - 1;i>0;--i)
            Lows[i] = Lows[i - 1];
        Lows[0] = ratesNew[2].low;

        ArrayResize(LowsTime, MathMin(ArraySize(LowsTime) + 1, 10));
        for(int i= ArraySize(LowsTime) - 1;i>0;--i)
            LowsTime[i] = LowsTime[i - 1];
        LowsTime[0] = ratesNew[2].time;

        string objName ="Signal@" + TimeToString(ratesNew[2].time) + "at" + DoubleToString(ratesNew[2].low, _Digits) + "(" + IntegerToString(233) + ")";
        if(ObjectCreate(0, objName, OBJ_ARROW, 0, ratesNew[2].time, ratesNew[2].low)) {
            ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 233);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGreen);
        }
    }

    lastProcessedTime = ratesNew[2].time; // Update the last processed time
}

void createOrderBlock(int index, color clr, MqlRates &rates[], double &blockHigh[], double &blockLow[], datetime &blockTime[]) {
    double blockHighValue = 0;
    double blockLowValue = 0;
    datetime blockTimeValue = 0;
    if(index == 2) {
        blockHighValue = MathMax(rates[1].high, rates[2].high);
        blockLowValue = MathMin(rates[1].low, rates[2].low);
        blockTimeValue = rates[1].time;
    }
    else {
        blockHighValue = MathMax(MathMax(rates[1].high, rates[2].high), rates[3].high);
        blockLowValue = MathMin(MathMin(rates[1].low, rates[2].low), rates[3].low);
        blockTimeValue = rates[1].time;
    }

    // Shift existing elements in blockHigh[] to make space for the new value
    ArrayResize(blockHigh, ArraySize(blockHigh) + 1);
    for(int i = ArraySize(blockHigh) - 1; i > 0; --i)
        blockHigh[i] = blockHigh[i - 1];
    blockHigh[0] = blockHighValue;

    // Shift existing elements in blockLow[] to make space for the new value
    ArrayResize(blockLow, ArraySize(blockLow) + 1);
    for(int i = ArraySize(blockLow) - 1; i > 0; --i)
        blockLow[i] = blockLow[i - 1];
    blockLow[0] = blockLowValue;

    // Shift existing elements in blockTime[] to make space for the new value
    ArrayResize(blockTime, ArraySize(blockTime) + 1);
    for(int i = ArraySize(blockTime) - 1; i > 0; --i)
        blockTime[i] = blockTime[i - 1];
    blockTime[0] = blockTimeValue;

    createObj(rates[1].time, rates[1].close, 203, 1, clr);
}

datetime lastProcessedTimeOrderBlock = 0;
int lastProcessedTimeOrderBlockDirection = 0;

int orderBlock(MqlRates &rates[]) {
   int direction = 0;

    if(rates[2].time == lastProcessedTimeOrderBlock)
        return lastProcessedTimeOrderBlockDirection;

    // Bearish Order Block lvl 2 SELL
    if (rates[3].close > rates[3].open && rates[1].close < rates[3].low && rates[1].close < rates[2].low) {
        createOrderBlock(3, C'233,43,43', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }

    // Bullish Order Block lvl 2 BUY
    if (rates[3].close < rates[3].open && rates[1].close > rates[3].high && rates[1].close > rates[2].high) {
        createOrderBlock(3, C'0,139,65', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
        direction = 1;
    }

    // Bearish Order Block lvl 1 SELL
    if (rates[2].close > rates[2].open && rates[1].close < rates[2].low) {
        createOrderBlock(2, C'223,134,32', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }

    // Bullish Order Block lvl 1 BUY
    if (rates[2].close < rates[2].open && rates[1].close > rates[2].high) {
        createOrderBlock(2, C'0,65,139', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
        direction = 1;
    }
    
    lastProcessedTimeOrderBlock = rates[2].time;
    lastProcessedTimeOrderBlockDirection = direction;
    return direction;
}

int detectFairValueGaps() {
    int happen = 0;

    MqlRates FVG_rates[];
    ArraySetAsSeries(FVG_rates, true);
    CopyRates(_Symbol, FVG_TIMEFRAME, 0, 50, FVG_rates);

    if(FVG_rates[1].time != lastFVGTime) {
        if(FVG_rates[1].low > FVG_rates[3].high) {
            // Plot on current timeframe chart
            string objName = "BullishFVG_" + TimeToString(FVG_rates[1].time);
            if(ObjectCreate(0, objName, OBJ_RECTANGLE, 0, FVG_rates[3].time, FVG_rates[3].high, FVG_rates[0].time, FVG_rates[1].low)) {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, C'0,255,127');
                ObjectSetInteger(0, objName, OBJPROP_FILL, true);
                ObjectSetInteger(0, objName, OBJPROP_BACK, true);
            }

            // Plot on FVG timeframe chart
            string objNameFVG = "BullishFVG_FVG_" + TimeToString(FVG_rates[1].time); 
            if(ObjectCreate(0, objNameFVG, OBJ_RECTANGLE, FVG_TIMEFRAME, FVG_rates[3].time, FVG_rates[3].high, FVG_rates[0].time, FVG_rates[1].low)) {
                ObjectSetInteger(0, objNameFVG, OBJPROP_COLOR, C'0,255,127');
                ObjectSetInteger(0, objNameFVG, OBJPROP_FILL, true);
                ObjectSetInteger(0, objNameFVG, OBJPROP_BACK, true);
            }

            lowLineValue = FVG_rates[1].low;
            highLineValue = 2;
            happen = 1;
        }

        if(FVG_rates[1].high < FVG_rates[3].low) {
            // Plot on current timeframe chart
            string objName = "BearishFVG_" + TimeToString(FVG_rates[1].time);
            if(ObjectCreate(0, objName, OBJ_RECTANGLE, 0, FVG_rates[3].time, FVG_rates[3].low, FVG_rates[0].time, FVG_rates[1].high)) {
                ObjectSetInteger(0, objName, OBJPROP_COLOR, C'255,99,71');
                ObjectSetInteger(0, objName, OBJPROP_FILL, true);
                ObjectSetInteger(0, objName, OBJPROP_BACK, true);
            }

            // Plot on FVG timeframe chart
            string objNameFVG = "BearishFVG_FVG_" + TimeToString(FVG_rates[1].time);
            if(ObjectCreate(0, objNameFVG, OBJ_RECTANGLE, FVG_TIMEFRAME, FVG_rates[3].time, FVG_rates[3].low, FVG_rates[0].time, FVG_rates[1].high)) {
                ObjectSetInteger(0, objNameFVG, OBJPROP_COLOR, C'255,99,71');
                ObjectSetInteger(0, objNameFVG, OBJPROP_FILL, true);
                ObjectSetInteger(0, objNameFVG, OBJPROP_BACK, true);
            }

            highLineValue = FVG_rates[1].high;
            lowLineValue = 0;
            happen = 1;
        }
        lastFVGTime = FVG_rates[1].time;
    }
    return happen;
}
