//==================================================================
// File: Include/Config.mqh
// Version: 6.0 (Production)
// Purpose : Global configuration for GoldEA
//==================================================================

#ifndef CONFIG_MQH
#define CONFIG_MQH

//==============================================================
// EA INFORMATION
//==============================================================

#define EA_NAME "GoldEA"

const bool ENABLE_LOGGING = true;
const bool DEBUG_MODE     = false;

//==============================================================
// ENUMERATIONS
//==============================================================

enum ENUM_TREND
{
   TREND_NONE = 0,
   TREND_BUY,
   TREND_SELL
};

//==============================================================
// RISK MANAGEMENT
//==============================================================

input group "===== Risk Management ====="

input double InpRiskPercent            = 2.0;      // Risk per trade (% of current account balance)
input double InpMinimumRR              = 2.0;      // Minimum acceptable Risk : Reward ratio

//==============================================================
// MARKET STRUCTURE
//==============================================================

input group "===== Market Structure ====="

input int    InpSwingStrength               = 3;        // Swing detection strength
input double InpBodyRatio                   = 0.70;     // Minimum candle body ratio
input double InpImpulseMultiplier           = 1.50;     // Strong impulse threshold

input double InpMinimumSwingDistancePoints  = 500.0;   // Minimum distance between qualified swings (Gold points)
input double InpSwingDuplicateTolerancePoints = 100.0; // Duplicate swing tolerance (Gold points)

//==============================================================
// VOLATILITY
//==============================================================

input group "===== Volatility ====="

input int    InpATRPeriod              = 14;       // ATR calculation period
input int    InpATRMovingAverage       = 50;       // ATR moving average period
input double InpExpansionATRMultiplier = 1.80;     // Impulse expansion threshold
input double InpSLBufferATR            = 0.25;     // Stop-loss buffer beyond swing (ATR multiplier)

//==============================================================
// EXECUTION FILTERS
//==============================================================

input group "===== Execution Filters ====="

input double InpMaxSpreadATR           = 0.15;     // Maximum spread as a fraction of ATR
input double InpMaxSlippageATR         = 0.05;     // Maximum slippage as a fraction of ATR

//==============================================================
// TRADE MANAGEMENT
//==============================================================

input group "===== Trade Management ====="

input int    InpMaxTradesPerSession    = 2;        // Maximum trades per trading session
input ulong  InpMagicNumber            = 2026080101;
input string InpTradeComment           = EA_NAME;

//==============================================================
// SESSION TIMES
// Broker Server Time
//==============================================================

const int ASIAN_START_MINUTES    = 0;     // 00:00
const int ASIAN_END_MINUTES      = 479;   // 07:59

const int LONDON_START_MINUTES   = 480;   // 08:00
const int LONDON_END_MINUTES     = 630;   // 10:30

const int NEWYORK_START_MINUTES  = 810;   // 13:30
const int NEWYORK_END_MINUTES    = 960;   // 16:00

//==============================================================
// TRADING SESSIONS
//==============================================================

input group "===== Trading Sessions ====="

input bool   InpTradeLondon            = true;
input bool   InpTradeNewYork           = true;
input bool   InpTradeAsian             = false;

//==============================================================
// LOCKED TIMEFRAMES
//==============================================================

const ENUM_TIMEFRAMES TF_TREND     = PERIOD_H1;
const ENUM_TIMEFRAMES TF_STRUCTURE = PERIOD_M15;
const ENUM_TIMEFRAMES TF_ENTRY     = PERIOD_M5;

#endif // CONFIG_MQH
