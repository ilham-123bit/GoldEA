//==================================================================
// File: Include/SpreadFilter.mqh
// Purpose : ATR-based spread filter
// Version : 3.1 (Production)
//==================================================================

#ifndef SPREADFILTER_MQH
#define SPREADFILTER_MQH

#include "Config.mqh"
#include "Logger.mqh"

//------------------------------------------------------------
// Returns the current spread in price units.
//
// Example:
// Ask = 3500.35
// Bid = 3500.10
// Spread = 0.25
//
// Returns -1.0 if market data is unavailable.
//------------------------------------------------------------
inline double CurrentSpread()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return -1.0;

   if(tick.ask <= 0.0 || tick.bid <= 0.0)
      return -1.0;

   return (tick.ask - tick.bid);
}

//------------------------------------------------------------
// Returns true when the current spread is less than or equal
// to the configured fraction of the current ATR.
//
// Maximum allowed spread:
// ATR × InpMaxSpreadATR
//------------------------------------------------------------
inline bool SpreadAllowed(const double atr)
{
   // Validate ATR
   if(atr <= 0.0)
   {
      LogWarning("Spread Filter | Invalid ATR.");
      return false;
   }

   // Obtain current spread
   const double spread = CurrentSpread();

   if(spread < 0.0)
   {
      LogWarning("Spread Filter | Unable to obtain current spread.");
      return false;
   }

   // Calculate maximum allowed spread
   const double maxSpread = atr * InpMaxSpreadATR;

   // Reject excessive spread
   if(spread > maxSpread)
   {
      LogWarning(
         StringFormat(
            "Spread Filter | Spread too high. Spread=%s Max=%s",
            DoubleToString(spread, _Digits),
            DoubleToString(maxSpread, _Digits)
         )
      );

      return false;
   }

   return true;
}

#endif // SPREADFILTER_MQH
