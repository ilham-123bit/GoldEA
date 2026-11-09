//==================================================================
// File: Include/SessionFilter.mqh
// Purpose : Trading session filter
// Version : 1.3
//==================================================================

#ifndef SESSIONFILTER_MQH
#define SESSIONFILTER_MQH

#include "Config.mqh"

//------------------------------------------------------------
// Returns true when trading is allowed during the configured
// trading sessions (broker server time).
//------------------------------------------------------------
inline bool SessionAllowed()
{
   MqlDateTime tm;
   TimeToStruct(TimeTradeServer(), tm);

   const int minutes = tm.hour * 60 + tm.min;

   if(InpTradeAsian &&
      minutes >= ASIAN_START_MINUTES &&
      minutes <= ASIAN_END_MINUTES)
   {
      return true;
   }

   if(InpTradeLondon &&
      minutes >= LONDON_START_MINUTES &&
      minutes <= LONDON_END_MINUTES)
   {
      return true;
   }

   if(InpTradeNewYork &&
      minutes >= NEWYORK_START_MINUTES &&
      minutes <= NEWYORK_END_MINUTES)
   {
      return true;
   }

   return false;
}

#endif // SESSIONFILTER_MQH
