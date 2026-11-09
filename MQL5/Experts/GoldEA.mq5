//==================================================================
// File: GoldEA.mq5
// Purpose : Main EA Controller
// Version : 1.1
//==================================================================

#property copyright "GoldEA"
#property version   "1.10"
#property strict

#include <Trade/Trade.mqh>

#include "Include/Config.mqh"
#include "Include/Logger.mqh"
#include "Include/SessionFilter.mqh"
#include "Include/SwingDetector.mqh"
#include "Include/TrendDetector.mqh"
#include "Include/ImpulseDetector.mqh"
#include "Include/ExpansionFilter.mqh"

CTrade trade;

datetime LastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   LastBarTime = 0;

   LogInfo("Initialized Successfully");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime CurrentBarTime = iTime(_Symbol, TF_STRUCTURE, 0);

   if(CurrentBarTime == LastBarTime)
      return;

   LastBarTime = CurrentBarTime;

   if(!SessionAllowed())
   {
      LogStatus("SESSION CLOSED");
      return;
   }

   ENUM_TREND H1Trend  = GetTrend(TF_TREND);
   ENUM_TREND M15Trend = GetTrend(TF_STRUCTURE);

   if(IsExpansion())
   {
      LogStatus("EXPANSION");
      return;
   }

   bool HasImpulse = false;

   if(H1Trend != TREND_NONE)
      HasImpulse = ValidImpulse(H1Trend);

   if(H1Trend == TREND_BUY &&
      M15Trend == TREND_BUY &&
      HasImpulse)
   {
      LogStatus("BUY READY");
      return;
   }

   if(H1Trend == TREND_SELL &&
      M15Trend == TREND_SELL &&
      HasImpulse)
   {
      LogStatus("SELL READY");
      return;
   }

   LogStatus("NO TRADE");
}
