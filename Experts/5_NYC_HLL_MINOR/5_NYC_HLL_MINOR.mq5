#include <Trade/Trade.mqh>
CTrade Trade;

#define MagicNumber 555555

int barsTotal;

input double risk2reward = 8;
input double accountRisk = 50; // Risk in dollars
input int START_HOUR = 16; // 16: 30
input int END_HOUR = 18; // 18: 00  

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
    STATE_SELL_SETUP = 2,    // Sell Setup
    STATE_BUY_SETUP = 3,    // Buy Setup
    STATE_NOTHING = 4             // No significant market action detected
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
        case STATE_SELL_SETUP:
            stateText = "Sell Setup";
            break;
        case STATE_BUY_SETUP:
            stateText = "Buy Setup";
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

// Lines Values
double highLineValue;
double lowLineValue;

// Swings
double Highs[];
double Lows[];
datetime HighsTime[];
datetime LowsTime[];

double A_value = 2;
double B_value = 0;
datetime A_time;
datetime B_time;

double bullishOrderBlockHigh[];
double bullishOrderBlockLow[];
datetime bullishOrderBlockTime[];

double bearishOrderBlockHigh[];
double bearishOrderBlockLow[];
datetime bearishOrderBlockTime[];

double untouchedHighs[];
double untouchedLows[];

datetime startTime = 0;
datetime endTime = 0;

void createObj(datetime time, double price, int arrowCode, int direction, color clr) {
    string objName ="Signal@" + TimeToString(time) + "at" + DoubleToString(price, _Digits) + "(" + IntegerToString(arrowCode) + ")";

    double ask=SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid=SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spread=ask-bid;

    if(direction > 0)
        price += 2*spread * _Point;
    else if(direction < 0)
        price -= 2*spread * _Point;

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

    ArraySetAsSeries(untouchedHighs, true);
    ArraySetAsSeries(untouchedLows, true);

    return(INIT_SUCCEEDED);
}

void StoreUntouchedHighLowLines(MqlDateTime &currentDateStruct) {
    datetime finishTime = TimeCurrent() + 86400; // Add 24 hours (86400 seconds) to get the time of tomorrow
    
    MqlRates dailyRates[];
    ArraySetAsSeries(dailyRates, true);
    CopyRates(_Symbol, PERIOD_D1, 0, 30, dailyRates);

    datetime targetTime;
    MqlDateTime targetDateTime = currentDateStruct;
    targetDateTime.hour = START_HOUR;
    targetDateTime.min = 30;
    targetDateTime.sec = 0;
    targetTime = StructToTime(targetDateTime);

    double priceAtStart = iOpen(_Symbol, PERIOD_CURRENT, iBarShift(_Symbol, PERIOD_CURRENT, targetTime, true));

    ArrayResize(untouchedHighs, 0);
    ArrayResize(untouchedLows, 0);

    for(int i = 1; i < ArraySize(dailyRates); i++) {
        bool highTouched = false;
        bool lowTouched = false;
        for(int j = 0; j <= ArraySize(dailyRates); j++) {
            if(j >= i) break; // Only check new candles after the day of interest
            double dayHigh = iHigh(_Symbol, PERIOD_D1, j);
            double dayLow = iLow(_Symbol, PERIOD_D1, j);
            if(dayHigh >= dailyRates[i].high) highTouched = true;
            if(dayLow <= dailyRates[i].low) lowTouched = true;
        }
        if(!highTouched) {
            string highLineName = "HighLine_" + IntegerToString(i);
            ObjectCreate(0, highLineName, OBJ_TREND, 0, dailyRates[i].time, dailyRates[i].high, finishTime, dailyRates[i].high);
            ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrRed);
            ArrayResize(untouchedHighs, ArraySize(untouchedHighs) + 1);
            untouchedHighs[ArraySize(untouchedHighs) - 1] = dailyRates[i].high;
        }
        if(!lowTouched) {
            string lowLineName = "LowLine_" + IntegerToString(i);
            ObjectCreate(0, lowLineName, OBJ_TREND, 0, dailyRates[i].time, dailyRates[i].low, finishTime, dailyRates[i].low);
            ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrBlue);
            ArrayResize(untouchedLows, ArraySize(untouchedLows) + 1);
            untouchedLows[ArraySize(untouchedLows) - 1] = dailyRates[i].low;
        }
    }

    for(int i = 0; i < ArraySize(untouchedHighs); i++) {
        if(untouchedHighs[i] > priceAtStart) {
            highLineValue = untouchedHighs[i];
            break;
        }
    }

    for(int i = 0; i < ArraySize(untouchedLows); i++) {
        if(untouchedLows[i] < priceAtStart) {
            lowLineValue = untouchedLows[i];
            break;
        }
    }
}

void ChangeTimeState(){
    if(TimeCurrent() >= startTime && TimeCurrent() <= endTime)
        currentTimeState = STATE_IN_TIME;
    else
        currentTimeState = STATE_OUTSIDE_TIME;
}

void PlotLineRange(MqlDateTime &currentDateStruct) {
    MqlDateTime tempTime = currentDateStruct;
    tempTime.hour = START_HOUR;
    tempTime.min = 30;
    tempTime.sec = 0;
    startTime = StructToTime(tempTime);
    
    tempTime.hour = END_HOUR;
    tempTime.min = 0;
    endTime = StructToTime(tempTime);

    string highlightName = "TimeHighlight_main";
    ObjectCreate(0, highlightName, OBJ_VLINE, 0, startTime, 0);
    ObjectSetInteger(0, highlightName, OBJPROP_COLOR, clrBlue);
    ObjectCreate(0, highlightName + "_end", OBJ_VLINE, 0, endTime, 0);
    ObjectSetInteger(0, highlightName + "_end", OBJPROP_COLOR, clrBlue);

    StoreUntouchedHighLowLines(currentDateStruct);
    
    // Create high line
    string highObjName = "DailyHigh ";
    string highObjNameDesc = highObjName + "txt";
    if(ObjectCreate(0, highObjName, OBJ_TREND, 0, startTime, highLineValue, endTime, highLineValue)) {
        ObjectSetInteger(0, highObjName, OBJPROP_COLOR, clrBlack);
        if(ObjectCreate(0, highObjNameDesc, OBJ_TEXT, 0, startTime, highLineValue)){
            ObjectSetString(0, highObjNameDesc, OBJPROP_TEXT, "Daily High");
            ObjectSetInteger(0, highObjNameDesc, OBJPROP_COLOR, clrBlack);
        }
    }
    
    // Create low line
    string lowObjName = "DailyLow ";
    string lowObjNameDesc = lowObjName + "txt";
    if(ObjectCreate(0, lowObjName, OBJ_TREND, 0, startTime, lowLineValue, endTime, lowLineValue)) {
        ObjectSetInteger(0, lowObjName, OBJPROP_COLOR, clrBlack);
        if(ObjectCreate(0, lowObjNameDesc, OBJ_TEXT, 0, startTime, lowLineValue)){
            ObjectSetString(0, lowObjNameDesc, OBJPROP_TEXT, "Daily Low");
            ObjectSetInteger(0, lowObjNameDesc, OBJPROP_COLOR, clrBlack);
        }
    }    
}

void HighlightCurrentState(const MqlRates &rates[]) {
    string timeStateText = GetTimeStateText(currentTimeState);
    string marketStateText = GetMarketActionStateText(currentState);
    
    // Create labels for current state if they don't exist
    if(ObjectFind(0, "TimeStateLabel") < 0) {
        ObjectCreate(0, "TimeStateLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_XDISTANCE, 1000);
        ObjectSetInteger(0, "TimeStateLabel", OBJPROP_YDISTANCE, 20);
    }
    
    if(ObjectFind(0, "MarketStateLabel") < 0) {
        ObjectCreate(0, "MarketStateLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_XDISTANCE, 1000);
        ObjectSetInteger(0, "MarketStateLabel", OBJPROP_YDISTANCE, 40);
    }
    if(ObjectFind(0, "ModeLabel") < 0) {
        ObjectCreate(0, "ModeLabel", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_XDISTANCE, 1000);
        ObjectSetInteger(0, "ModeLabel", OBJPROP_YDISTANCE, 60);
    }
    
    ObjectSetString(0, "ModeLabel", OBJPROP_TEXT, "Mode: " + Mode);
    ObjectSetInteger(0, "ModeLabel", OBJPROP_COLOR, (Mode == "BUY") ? clrGreen : (Mode == "SELL") ? clrRed : clrGray);
    
    // Update label text and appearance
    ObjectSetString(0, "TimeStateLabel", OBJPROP_TEXT, "Time State: " + timeStateText);
    ObjectSetString(0, "MarketStateLabel", OBJPROP_TEXT, "Market State: " + marketStateText);
    
    // Set colors based on state
    color timeColor = (currentTimeState == STATE_TRADE_TIME) ? clrGreen : (currentTimeState == STATE_IN_TIME) ? clrBlue : clrRed;
    color textMarketColor = (currentState == STATE_BUY_SETUP || currentState == STATE_SELL_SETUP) ? clrGreen : (currentState == STATE_NOTHING) ? clrGray : clrOrange;
    
    ObjectSetInteger(0, "TimeStateLabel", OBJPROP_COLOR, timeColor);
    ObjectSetInteger(0, "MarketStateLabel", OBJPROP_COLOR, textMarketColor);
    
    // // Draw rectangle between current and previous bar
    string rectName = "StateRect" + TimeToString(rates[0].time);
    color marketColor = (currentState == STATE_BUY_SETUP || currentState == STATE_SELL_SETUP) ? C'162,235,162' : (currentState == STATE_NOTHING) ? C'198,197,197' : C'244,198,112';
    
    ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, rates[1].time, 0.5, rates[0].time, 2);
    ObjectSetInteger(0, rectName, OBJPROP_COLOR, marketColor);
    ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
    ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
}

void PlotAB(MqlRates &rates[]) {
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
}

void TradeExec() {
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double spread = ask - bid;
    double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); // Get pip value
    // Set magic number for trade operations
    Trade.SetExpertMagicNumber(MagicNumber);

    if (Mode == "SELL") {
        double entryprice = bid;
        entryprice = NormalizeDouble(entryprice, _Digits);

        double stoploss = bearishOrderBlockHigh[0] + spread;
        stoploss = NormalizeDouble(stoploss, _Digits);

        double riskvalue = stoploss - entryprice;
        riskvalue = NormalizeDouble(riskvalue, _Digits);

        double takeprofit = entryprice - (risk2reward * riskvalue);
        takeprofit = NormalizeDouble(takeprofit, _Digits);

        double pipsRisk = riskvalue / _Point;  // Risk in pips
        double lots = accountRisk / (pipsRisk * pipValue); // Calculate lot size
        lots = NormalizeDouble(lots, 2); // Round to 2 decimal places

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lots, entryprice, stoploss, takeprofit, "Sell Test"))
            currentState = STATE_TAKE_LIQUIDITY_B;
        else
            Print("Failed to open position. Error code: ", GetLastError());
    }
    if (Mode == "BUY") {
        double entryprice = ask;
        entryprice = NormalizeDouble(entryprice, _Digits);

        double stoploss = bullishOrderBlockLow[0] - spread;
        stoploss = NormalizeDouble(stoploss, _Digits);

        double riskvalue = entryprice - stoploss;
        riskvalue = NormalizeDouble(riskvalue, _Digits);

        double takeprofit = entryprice + (risk2reward * riskvalue);
        takeprofit = NormalizeDouble(takeprofit, _Digits);
        
        double pipsRisk = riskvalue / _Point;  // Risk in pips
        double lots = accountRisk / (pipsRisk * pipValue); // Calculate lot size
        lots = NormalizeDouble(lots, 2); // Round to 2 decimal places

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lots, entryprice, stoploss, takeprofit, "Buy Test"))
            currentState = STATE_TAKE_LIQUIDITY_A;
        else
            Print("Failed to open position. Error code: ", GetLastError());
    }
}

void OnTick() {
    int bars = iBars(_Symbol, PERIOD_CURRENT);
    if(barsTotal == bars) return;
    else   barsTotal = bars;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, PERIOD_CURRENT, 0, 50, rates);

    datetime currentTime = TimeCurrent();
    MqlDateTime currentDateStruct;
    TimeToStruct(currentTime, currentDateStruct);

    if(currentDateStruct.hour == START_HOUR && currentDateStruct.min == 30 && currentDateStruct.sec == 0)
        PlotLineRange(currentDateStruct);

    ChangeTimeState();

    swingPoints(rates);
    int isOrderBlock = orderBlock(rates);

    if(currentTimeState == STATE_OUTSIDE_TIME) {
        Mode = "None";
        currentState = STATE_NOTHING;
        PlotAB(rates);
        HighlightCurrentState(rates);
        return;
    }

    if (ArraySize(Highs) > 1 && ArraySize(Lows) > 1 && ArraySize(bullishOrderBlockTime) > 0 && ArraySize(bearishOrderBlockTime) > 0) {
        if (Mode != "BUY") {
            if (Highs[0] > MathMax(highLineValue, B_value)){
                currentState = STATE_TAKE_LIQUIDITY_B;
                Mode = "SELL";
                B_time = HighsTime[0];
                B_value = Highs[0];
            }
            if (currentState == STATE_TAKE_LIQUIDITY_B && Highs[1] < Highs[0] && Highs[0] < B_value)
                currentState = STATE_SELL_SETUP;
        }

        if (Mode != "SELL") {
            if (Lows[0] < MathMin(lowLineValue, A_value)){
                currentState = STATE_TAKE_LIQUIDITY_A;
                Mode = "BUY";
                A_time = LowsTime[0];
                A_value = Lows[0];  
            }
            if (currentState == STATE_TAKE_LIQUIDITY_A && Lows[1] > Lows[0] && Lows[0] > A_value)
                currentState = STATE_BUY_SETUP;
        }

        if ((Mode == "SELL" && MathAbs(rates[0].low - B_value) > 0.0040) || (Mode == "BUY" && MathAbs(rates[0].high - A_value) > 0.0040))
            currentState = STATE_NOTHING;

        if (PositionsTotal() > 0) {
            for (int i = PositionsTotal() - 1; i >= 0; i--) {
                if (PositionSelectByTicket(PositionGetTicket(i)) && PositionGetString(POSITION_SYMBOL) == Symbol()){
                    PlotAB(rates);
                    HighlightCurrentState(rates);
                    return;
                }             
            }
        }

        if (Mode == "SELL" && currentState == STATE_SELL_SETUP && bearishOrderBlockTime[0] - HighsTime[0] <= 120 && bearishOrderBlockTime[0] >= HighsTime[0] && isOrderBlock == -1)
            TradeExec();
        if (Mode == "BUY" && currentState == STATE_BUY_SETUP && bullishOrderBlockTime[0] - LowsTime[0] <= 120 && bullishOrderBlockTime[0] >= LowsTime[0] && isOrderBlock == 1)
            TradeExec();
    }

    PlotAB(rates);
    HighlightCurrentState(rates);
}

void swingPoints(MqlRates &rates[]) {
    //SwingHigh
    if(rates[2].high >= rates[3].high && rates[2].high >= rates[1].high) {
        ArrayResize(Highs, MathMin(ArraySize(Highs) + 1, 10));
        for(int i = ArraySize(Highs) - 1;i > 0;--i)
            Highs[i] = Highs[i - 1];
        Highs[0] = rates[2].high;

        ArrayResize(HighsTime, MathMin(ArraySize(HighsTime) + 1, 10));
        for(int i= ArraySize(HighsTime) - 1;i>0;--i)
            HighsTime[i] = HighsTime[i - 1];
        HighsTime[0] = rates[2].time;

        createObj(rates[2].time, rates[2].high, 234, -1, clrOrangeRed);
    }
    //SwingLow
    if(rates[2].low <= rates[3].low && rates[2].low <= rates[1].low) {
        ArrayResize(Lows, MathMin(ArraySize(Lows) + 1, 10));
        for(int i= ArraySize(Lows) - 1;i>0;--i)
            Lows[i] = Lows[i - 1];
        Lows[0] = rates[2].low;

        ArrayResize(LowsTime, MathMin(ArraySize(LowsTime) + 1, 10));
        for(int i= ArraySize(LowsTime) - 1;i>0;--i)
            LowsTime[i] = LowsTime[i - 1];
        LowsTime[0] = rates[2].time;

        createObj(rates[2].time, rates[2].low, 233, 1, clrGreen);
    }
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

int orderBlock(MqlRates &rates[]) {
   int direction = 0;

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
    return direction;
}
