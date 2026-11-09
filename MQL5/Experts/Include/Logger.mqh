//==================================================================
// File: Include/Logger.mqh
// Purpose : Centralized logging utilities
// Version : 1.2
//==================================================================

#ifndef LOGGER_MQH
#define LOGGER_MQH

#include "Config.mqh"

//------------------------------------------------------------
// Internal log printer
//------------------------------------------------------------
inline void LogMessage(const string level,const string message)
{
   if(!ENABLE_LOGGING)
      return;

   PrintFormat("[%s][%s][%s] %s",
               EA_NAME,
               level,
               TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),
               message);
}

//------------------------------------------------------------
// EA Status
//------------------------------------------------------------
inline void LogStatus(const string status)
{
   LogMessage("STATUS",status);
}

//------------------------------------------------------------
// Information
//------------------------------------------------------------
inline void LogInfo(const string message)
{
   LogMessage("INFO",message);
}

//------------------------------------------------------------
// Warning
//------------------------------------------------------------
inline void LogWarning(const string message)
{
   LogMessage("WARNING",message);
}

//------------------------------------------------------------
// Error
//------------------------------------------------------------
inline void LogError(const string message)
{
   LogMessage("ERROR",message);
}

//------------------------------------------------------------
// Trade Events
//------------------------------------------------------------
inline void LogTrade(const string message)
{
   LogMessage("TRADE",message);
}

//------------------------------------------------------------
// Debug Messages
//------------------------------------------------------------
inline void LogDebug(const string message)
{
   if(!DEBUG_MODE)
      return;

   LogMessage("DEBUG",message);
}

#endif // LOGGER_MQH
