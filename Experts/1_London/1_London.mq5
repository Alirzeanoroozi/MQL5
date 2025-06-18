#include <Trade\Trade.mqh>
CTrade Trade;

#define MagicNumber 888888

int bigBarsTotal;

input double pipSize = 0.0020;
input double risk2reward = 8;
input double accountRisk = 50; // Risk in dollars
input bool doubleTime = false;
input int NYC_START_HOUR = 16; // 16: 30
input int NYC_END_HOUR = 18; // 18: 00  
input int LONDON_START_HOUR = 9; // 9: 22
input int LONDON_END_HOUR = 11; // 11: 37
input ENUM_TIMEFRAMES bigSwingPeriod = PERIOD_M15; // 15 minutes
input int ORDER_BLOCK_TIME_LIMIT = 45;
input bool verbose = false;
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

// Lines Values
double highLineValue = 10;
double lowLineValue = -10;

// Swings
double Highs[];
double Lows[];
datetime HighsTime[];
datetime LowsTime[];

double Big_Highs[];
double Big_Lows[];
datetime Big_HighsTime[];
datetime Big_LowsTime[];

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

bool is20PipHigh[];
bool is20PipLow[];

datetime lastBarTime = 0;
double open, high, low, close;
MqlRates rates15[];  // Array to store the rates
bool isFirstBar = true;

MqlDateTime lastDateStruct;

void createObj(datetime time, double price, int arrowCode, int direction, color clr) {
    string objName ="Signal@" + TimeToString(time) + "at" + DoubleToString(price, _Digits) + "(" + IntegerToString(arrowCode) + ")";

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

    ArraySetAsSeries(bullishOrderBlockHigh, true);
    ArraySetAsSeries(bullishOrderBlockLow, true);
    ArraySetAsSeries(bullishOrderBlockTime, true);

    ArraySetAsSeries(bearishOrderBlockHigh, true);
    ArraySetAsSeries(bearishOrderBlockLow, true);
    ArraySetAsSeries(bearishOrderBlockTime, true);

    ArraySetAsSeries(Big_Highs, true);
    ArraySetAsSeries(Big_Lows, true);
    ArraySetAsSeries(Big_HighsTime, true);
    ArraySetAsSeries(Big_LowsTime, true);

    ArraySetAsSeries(is20PipHigh, true);
    ArraySetAsSeries(is20PipLow, true);

    ArraySetAsSeries(rates15, true);

    return(INIT_SUCCEEDED);
}

void removeAllLines() {
    if(ArraySize(Big_Highs) > 0) {
        for(int i = ArraySize(Big_Highs) - 1; i >= 0; i--) {
            if(ObjectFind(0, "MidHighLine" + TimeToString(Big_HighsTime[i])) >= 0)
                ObjectDelete(0, "MidHighLine" + TimeToString(Big_HighsTime[i]));
        }
    }

    //Swing Low +20pip
    if(ArraySize(Big_Lows) > 0) {
        for(int i = ArraySize(Big_Lows) - 1; i >= 0; i--) {
            if(ObjectFind(0, "MidLowLine" + TimeToString(Big_LowsTime[i])) >= 0)
                ObjectDelete(0, "MidLowLine" + TimeToString(Big_LowsTime[i]));
        }   
    }
}

void OnTick() {
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
        if (verbose)
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

    if (currentDateStruct.day != lastDateStruct.day) {
        removeAllLines();

        ArrayResize(Highs, 0);
        ArrayResize(Lows, 0);
        ArrayResize(HighsTime, 0);
        ArrayResize(LowsTime, 0);

        ArrayResize(Big_Highs, 0);
        ArrayResize(Big_Lows, 0);
        ArrayResize(Big_HighsTime, 0);
        ArrayResize(Big_LowsTime, 0);

        ArrayResize(is20PipHigh, 0);
        ArrayResize(is20PipLow, 0);

        highLineValue = 2;
        lowLineValue = -2;
        A_value = 2;
        B_value = 0;
        A_time = 0;
        B_time = 0;
        lastBuTime = 0;
        lastBeTime = 0;

        lastDateStruct = currentDateStruct;
    }

    PlotLineRange(currentDateStruct);

    swingPoints(rates15);
    int isOrderBlock = orderBlock(rates15);

    int bigBars = iBars(_Symbol, bigSwingPeriod);
    if (bigBarsTotal != bigBars) {
        bigBarsTotal = bigBars;
        MqlRates bigRates[];
        ArraySetAsSeries(bigRates, true);
        CopyRates(_Symbol, bigSwingPeriod, 0, 5, bigRates);
        bigSwingPoints(bigRates);
        Mid20Pip();
    }

    if (currentTimeState == STATE_OUTSIDE_TIME) {
        Mode = "None";
        currentState = STATE_NOTHING;
        A_value = 2;
        B_value = 0;
        A_time = 0;
        B_time = 0;
        lastBuTime = 0;
        lastBeTime = 0;
        PlotABChochs(rates);
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

        if (Mode == "SELL" && currentState == STATE_CHOCH_BULLISH  && bullishOrderBlockTime[0] - B_time <= ORDER_BLOCK_TIME_LIMIT && bullishOrderBlockTime[0] >= B_time && isOrderBlock == 1)
            TradeExec(rates15);
        if (Mode == "BUY" && currentState == STATE_CHOCH_BEARISH && bearishOrderBlockTime[0] - A_time <= ORDER_BLOCK_TIME_LIMIT && bearishOrderBlockTime[0] >= A_time && isOrderBlock == -1)
            TradeExec(rates15);
    }

    PlotABChochs(rates);
    HighlightCurrentState(rates);
}

void PlotLineRange(MqlDateTime &currentDateStruct) {
    MqlDateTime tempTime = currentDateStruct;
    tempTime.hour = LONDON_START_HOUR;
    tempTime.min = 22;
    tempTime.sec = 0;
    datetime LondonStartTime = StructToTime(tempTime);
    
    tempTime.hour = LONDON_END_HOUR;
    tempTime.min = 37;
    datetime LondonEndTime = StructToTime(tempTime);

    tempTime.hour = NYC_START_HOUR;
    tempTime.min = 30;
    datetime NYCStartTime = StructToTime(tempTime);

    tempTime.hour = NYC_END_HOUR;
    tempTime.min = 0;
    datetime NYCEndTime = StructToTime(tempTime);

    if(doubleTime) {
        ObjectCreate(0, "LondonLine", OBJ_VLINE, 0, LondonStartTime, 0);
        ObjectSetInteger(0, "LondonLine", OBJPROP_COLOR, clrBlue);
        ObjectCreate(0, "LondonLine_end", OBJ_VLINE, 0, LondonEndTime, 0);
        ObjectSetInteger(0, "LondonLine_end", OBJPROP_COLOR, clrBlue);
    }
    ObjectCreate(0, "NYCLine", OBJ_VLINE, 0, NYCStartTime, 0);
    ObjectSetInteger(0, "NYCLine", OBJPROP_COLOR, clrBlue);
    ObjectCreate(0, "NYCLine_end", OBJ_VLINE, 0, NYCEndTime, 0);
    ObjectSetInteger(0, "NYCLine_end", OBJPROP_COLOR, clrBlue);

    datetime startLine = 0;
    datetime endLine = 0;
    if (doubleTime && TimeCurrent() >= LondonStartTime && TimeCurrent() <= LondonEndTime){
        currentTimeState = STATE_IN_TIME;
        startLine = LondonStartTime;
        endLine = LondonEndTime;
    }
    else if (TimeCurrent() >= NYCStartTime && TimeCurrent() <= NYCEndTime){
        currentTimeState = STATE_IN_TIME;
        startLine = NYCStartTime;
        endLine = NYCEndTime;
    }
    else
        currentTimeState = STATE_OUTSIDE_TIME;

    // Create high line
    string highObjName = "HLL";
    string highObjNameDesc = highObjName + "txt";
    if(ObjectCreate(0, highObjName, OBJ_TREND, 0, startLine, highLineValue, endLine, highLineValue)) {
        ObjectSetInteger(0, highObjName, OBJPROP_COLOR, clrBlack);
        if(ObjectCreate(0, highObjNameDesc, OBJ_TEXT, 0, startLine, highLineValue)){
            ObjectSetString(0, highObjNameDesc, OBJPROP_TEXT, "HLL");
            ObjectSetInteger(0, highObjNameDesc, OBJPROP_COLOR, clrBlack);
        }
    }
    
    // Create low line
    string lowObjName = "LLL";
    string lowObjNameDesc = lowObjName + "txt";
    if(ObjectCreate(0, lowObjName, OBJ_TREND, 0, startLine, lowLineValue, endLine, lowLineValue)) {
        ObjectSetInteger(0, lowObjName, OBJPROP_COLOR, clrBlack);
        if(ObjectCreate(0, lowObjNameDesc, OBJ_TEXT, 0, startLine, lowLineValue)){
            ObjectSetString(0, lowObjNameDesc, OBJPROP_TEXT, "LLL");
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

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, lots, entryprice, stoploss, takeprofit, "Sell Test"))
            currentState = STATE_TAKE_LIQUIDITY_B;
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

        if (Trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, lots, entryprice, stoploss, takeprofit, "Buy Test"))
            currentState = STATE_TAKE_LIQUIDITY_A;
        else
            Print("Failed to open position. Error code: ", GetLastError());
    }
}

void Mid20Pip() {
    double tempHighLineValue = 10;
    double tempLowLineValue = -10;

    int sizeRate = 500;
    if (ArraySize(Big_Highs) > 0 && ArraySize(Big_Lows) > 0)
        sizeRate = MathMax(iBarShift(_Symbol, _Period, Big_HighsTime[ArraySize(Big_HighsTime) - 1]), iBarShift(_Symbol, _Period, Big_LowsTime[ArraySize(Big_LowsTime) - 1])) + 1;

    MqlRates completeRates[];
    ArraySetAsSeries(completeRates, true);
    CopyRates(_Symbol, _Period, 0, sizeRate, completeRates);

    // Swing High +20pip
    if(ArraySize(Big_Highs) > 0) {
        for(int i = ArraySize(Big_Highs) - 1; i >= 0; i--) {
            bool highTouched = false;
            for(int j = 0; j < iBarShift(_Symbol, _Period, Big_HighsTime[i]); j++) {
                if(completeRates[j].high > Big_Highs[i])
                    highTouched = true;
                if(Big_Highs[i] - completeRates[j].low > pipSize)
                    is20PipHigh[i] = true;  
            }

            if (!highTouched && is20PipHigh[i]) {
                tempHighLineValue = Big_Highs[i]; 
                ObjectCreate(0, "MidHighLine" + TimeToString(Big_HighsTime[i]), OBJ_TREND, 0, Big_HighsTime[i], Big_Highs[i], completeRates[0].time + 15 * 60, Big_Highs[i]);
                ObjectSetInteger(0, "MidHighLine" + TimeToString(Big_HighsTime[i]), OBJPROP_COLOR, clrRed);
            }
            else if(ObjectFind(0, "MidHighLine" + TimeToString(Big_HighsTime[i])) >= 0)
                ObjectDelete(0, "MidHighLine" + TimeToString(Big_HighsTime[i]));
        }
        highLineValue = tempHighLineValue;
    }

    //Swing Low +20pip
    if(ArraySize(Big_Lows) > 0) {
        for(int i = ArraySize(Big_Lows) - 1; i >= 0; i--) {
            bool lowTouched = false;
            for(int j = 0; j < iBarShift(_Symbol, _Period, Big_LowsTime[i]); j++) {
                if(completeRates[j].low < Big_Lows[i])
                    lowTouched = true;
                if(completeRates[j].high - Big_Lows[i] > pipSize)
                    is20PipLow[i] = true;
            }
            if (!lowTouched && is20PipLow[i]) {
                tempLowLineValue = Big_Lows[i];

                ObjectCreate(0, "MidLowLine" + TimeToString(Big_LowsTime[i]), OBJ_TREND, 0, Big_LowsTime[i], Big_Lows[i], completeRates[0].time + 15 * 60, Big_Lows[i]);
                ObjectSetInteger(0, "MidLowLine" + TimeToString(Big_LowsTime[i]), OBJPROP_COLOR, clrBlue);
            }
            else if(ObjectFind(0, "MidLowLine" + TimeToString(Big_LowsTime[i])) >= 0)
                ObjectDelete(0, "MidLowLine" + TimeToString(Big_LowsTime[i]));
        }   
        lowLineValue = tempLowLineValue;    
    }
}

void bigSwingPoints(MqlRates &bigRates[]) {
    //SwingHigh
    if(bigRates[2].high >= bigRates[3].high && bigRates[2].high >= bigRates[1].high) {
        ArrayResize(Big_Highs, MathMin(ArraySize(Big_Highs) + 1, 10));
        for(int i = ArraySize(Big_Highs) - 1;i > 0;--i)
            Big_Highs[i] = Big_Highs[i - 1];
        Big_Highs[0] = bigRates[2].high;

        ArrayResize(Big_HighsTime, MathMin(ArraySize(Big_HighsTime) + 1, 10));
        for(int i= ArraySize(Big_HighsTime) - 1;i>0;--i)
            Big_HighsTime[i] = Big_HighsTime[i - 1];
        Big_HighsTime[0] = bigRates[2].time;

        ArrayResize(is20PipHigh, MathMin(ArraySize(is20PipHigh) + 1, 10));
        for(int i = ArraySize(is20PipHigh) - 1; i > 0; --i)
            is20PipHigh[i] = is20PipHigh[i - 1];
        is20PipHigh[0] = false;

        createObj(bigRates[2].time, bigRates[2].high, 234, -1, clrOrangeRed);
    }
    //SwingLow
    if(bigRates[2].low <= bigRates[3].low && bigRates[2].low <= bigRates[1].low) {
        ArrayResize(Big_Lows, MathMin(ArraySize(Big_Lows) + 1, 10));
        for(int i= ArraySize(Big_Lows) - 1;i>0;--i)
            Big_Lows[i] = Big_Lows[i - 1];
        Big_Lows[0] = bigRates[2].low;

        ArrayResize(Big_LowsTime, MathMin(ArraySize(Big_LowsTime) + 1, 10));
        for(int i= ArraySize(Big_LowsTime) - 1;i>0;--i)
            Big_LowsTime[i] = Big_LowsTime[i - 1];
        Big_LowsTime[0] = bigRates[2].time;

        ArrayResize(is20PipLow, MathMin(ArraySize(is20PipLow) + 1, 10));
        for(int i = ArraySize(is20PipLow) - 1; i > 0; --i)
            is20PipLow[i] = is20PipLow[i - 1];
        is20PipLow[0] = false;

        createObj(bigRates[2].time, bigRates[2].low, 233, 1, clrGreen);
    }
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
        // Print("Highs: ", Highs[0],"HighsTime: ", HighsTime[0]);
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
        // Print("Lows: ", Lows[0],"LowsTime: ", LowsTime[0]);
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

    // Bearish Order Block lvl 1 SELL
    if (rates[2].close > rates[2].open && rates[1].close < rates[2].low) {
        createOrderBlock(2, C'223,134,32', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }
    // Bearish Order Block lvl 2 SELL
    // else 
    if (rates[3].close > rates[3].open && rates[1].close < rates[3].low && rates[1].close < rates[2].low) {
        createOrderBlock(3, C'233,43,43', rates, bearishOrderBlockHigh, bearishOrderBlockLow, bearishOrderBlockTime);
        direction = -1;
    }

    // Bullish Order Block lvl 1 BUY
    if (rates[2].close < rates[2].open && rates[1].close > rates[2].high) {
            createOrderBlock(2, C'0,65,139', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
            direction = 1;
        }
    // Bullish Order Block lvl 2 BUY
    // else 
    if (rates[3].close < rates[3].open && rates[1].close > rates[3].high && rates[1].close > rates[2].high) {
        createOrderBlock(3, C'0,139,65', rates, bullishOrderBlockHigh, bullishOrderBlockLow, bullishOrderBlockTime);
        direction = 1;
    }

    lastProcessedTimeOrderBlock = rates[2].time;
    lastProcessedTimeOrderBlockDirection = direction;
    return direction;
}