//+------------------------------------------------------------------+
//|                                                 initial_data.mq5 |
//|                                         Copyright 2025, YourName |
//|                                                 https://mql5.com |
//| 21.06.2025 - Initial release                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, YourName"
#property link      "https://mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+

#include <Math\Stat\Math.mqh>
//+------------------------------------------------------------------+
//| Script Parameters |
//+------------------------------------------------------------------+
input datetime Start = D'2023.01.01 00:00:00'; // Period Start
input datetime End = D'2024.12.31 23:59:00'; // Period End

void Correlation(double &target1[], double &target2[], double &indicator[], string name, int handle) {
//---
   double correlation=0;
   string message="";

   if(MathCorrelationPearson(target1,indicator,correlation))
      message=StringFormat("%s\t%.5f",name,correlation);
   if(MathCorrelationPearson(target2,indicator,correlation))
      message=StringFormat("%s\t%.5f",message,correlation);
   if(handle!=INVALID_HANDLE)
      FileWrite(handle,message);
}

void OnStart() {
//---
   int h_ZZ=iCustom(_Symbol,PERIOD_M5,"Examples\\ZigZag.ex5",48,1,47);
   int h_CCI=iCCI(_Symbol,PERIOD_M5,12,PRICE_TYPICAL);
   int h_RSI=iRSI(_Symbol,PERIOD_M5,12,PRICE_TYPICAL);
   int h_Stoh=iStochastic(_Symbol,PERIOD_M5,12,8,3,MODE_LWMA,STO_LOWHIGH);
   int h_MACD=iMACD(_Symbol,PERIOD_M5,12,48,12,PRICE_TYPICAL);
   int h_ATR=iATR(_Symbol,PERIOD_M5,12);
   int h_BB=iBands(_Symbol,PERIOD_M5,48,0,3,PRICE_TYPICAL);
   int h_SAR=iSAR(_Symbol,PERIOD_M5,0.02,0.2);
   int h_MFI=iMFI(_Symbol,PERIOD_M5,12,VOLUME_TICK);

   double close[], open[],high[],low[];
   if
   (
      CopyClose(_Symbol,PERIOD_M5,Start,End,close)<=0 ||
      CopyOpen(_Symbol,PERIOD_M5,Start,End,open)<=0 ||
      CopyHigh(_Symbol,PERIOD_M5,Start,End,high)<=0 ||
      CopyLow(_Symbol,PERIOD_M5,Start,End,low)<=0
   )
      return;

   double zz[], cci[], macd_main[], macd_signal[],rsi[],atr[], bands_medium[];
   double bands_up[], bands_low[], sar[],stoch[],ssig[],mfi[];
   datetime end_zz=End+PeriodSeconds(PERIOD_M5)*(12*24*5);
   if
   (
      CopyBuffer(h_ZZ,0,Start,end_zz,zz)<=0 ||
      CopyBuffer(h_CCI,0,Start,End,cci)<=0 ||
      CopyBuffer(h_RSI,0,Start,End,rsi)<=0 ||
      CopyBuffer(h_MACD,MAIN_LINE,Start,End,macd_main)<=0 ||
      CopyBuffer(h_MACD,SIGNAL_LINE,Start,End,macd_signal)<=0 ||
      CopyBuffer(h_ATR,0,Start,End,atr)<=0 ||
      CopyBuffer(h_BB,BASE_LINE,Start,End,bands_medium)<=0 ||
      CopyBuffer(h_BB,UPPER_BAND,Start,End,bands_up)<=0 ||
      CopyBuffer(h_BB,LOWER_BAND,Start,End,bands_low)<=0 ||
      CopyBuffer(h_SAR,0,Start,End,sar)<=0 ||
      CopyBuffer(h_Stoh,MAIN_LINE,Start,End,stoch)<=0 ||
      CopyBuffer(h_Stoh,SIGNAL_LINE,Start,End,ssig)<=0 ||
      CopyBuffer(h_MFI,0,Start,End,mfi)<=0
   )
      return;

   int total = ArraySize(close);
   double target1[], target2[], oc[], bmc[], buc[], blc[], macd_delta[];
   // resize arrays
   if(ArrayResize(target1, total) <= 0 || ArrayResize(target2, total) <= 0 ||
   ArrayResize(oc, total) <= 0 || ArrayResize(bmc, total) <= 0 ||
   ArrayResize(buc, total) <= 0 || ArrayResize(blc, total) <= 0 ||
   ArrayResize(macd_delta, total) <= 0)
   return;

   double extremum = -1;
   for(int i = ArraySize(zz) - 2; i >= 0; i--) {
      if(zz[i + 1] > 0 && zz[i + 1] != EMPTY_VALUE)
         extremum = zz[i + 1];
      if(i >= total)
         continue;

      target2[i] = extremum - close[i];
      target1[i] = (target2[i] >= 0);
      oc[i] = close[i] - open[i];
      sar[i] -= close[i];
      bands_low[i] = close[i] - bands_low[i];
      bands_up[i] -= close[i];
      bands_medium[i] -= close[i];
      macd_delta[i] = macd_main[i] - macd_signal[i];
   }

   int handle = FileOpen("correlation.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, "\t", CP_UTF8);
   string message = "Indicator\tTarget 1\tTarget 2";
   if(handle != INVALID_HANDLE)
      return;
   FileWrite(handle, message);
   //---
   Correlation(target1, target2, oc, "Close - Open", handle);
   Correlation(target1, target2, hc, "High - Close %.5f", handle);
   Correlation(target1, target2, lc, "Close - Low", handle);
   Correlation(target1, target2, cci, "CCI %.5f", handle);
   Correlation(target1, target2, rsi, "RSI", handle);
   Correlation(target1, target2, atr, "ATR", handle);
   Correlation(target1, target2, sar, "SAR", handle);
   Correlation(target1, target2, macd_main, "MACD Main", handle);
   Correlation(target1, target2, macd_signal, "MACD Signal", handle);
   Correlation(target1, target2, macd_delta, "MACD Main-Signal", handle);

   Correlation(target1, target2, bands_medium, "BB Main", handle);
   Correlation(target1, target2, bands_low, "BB Low", handle);
   Correlation(target1, target2, bands_up, "BB Up", handle);
   Correlation(target1, target2, stoch, "Stochastic Main", handle);
   Correlation(target1, target2, ssig, "Stochastic Signal", handle);
   Correlation(target1, target2, mfi, "MFI", handle);
   //---
   FileFlush(handle);
   FileClose(handle);
}

//+------------------------------------------------------------------+
