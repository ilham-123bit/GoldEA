// GoldEA SwingDetector v2.5 — causal closed-bar stream and immutable events.
#ifndef SWINGDETECTOR_MQH
#define SWINGDETECTOR_MQH
#include "Config.mqh"

const double GOLD_POINTS_PER_PRICE_UNIT=100.0;
const int MAX_SWING_LOOKBACK_BARS=499;
const int MAX_SWING_CONTEXTS=8;

enum ENUM_SWING_TYPE { SWING_NONE=0, SWING_HIGH, SWING_LOW };
enum ENUM_SWING_STATUS
{
   SWING_OK=0, SWING_INVALID_INPUT, SWING_DATA_UNAVAILABLE,
   SWING_HISTORY_CHANGED, SWING_CAPACITY, SWING_OUTPUT_ERROR
};

struct SwingEvent
{
   long id;                    // Deterministic sequence within symbol/tf/strength stream.
   ENUM_SWING_TYPE type;
   double price;
   datetime pivotTime;         // Stable identity: stream key + pivotTime + type.
   datetime confirmedAt;       // First opening after all newer neighbors closed.
   datetime finalizedAt;       // Qualifying opposite pivot's confirmation time.
};

bool SwingStrengthValid(const int strength)
{
   return strength>0 && strength<=(MAX_SWING_LOOKBACK_BARS-1)/2;
}
bool SwingNumbersValid(const double minimum,const double tolerance)
{
   return MathIsValidNumber(minimum) && minimum>0.0 && minimum/GOLD_POINTS_PER_PRICE_UNIT>0.0 &&
          MathIsValidNumber(tolerance) && tolerance>=0.0 &&
          (tolerance==0.0 || tolerance/GOLD_POINTS_PER_PRICE_UNIT>0.0);
}
inline double GoldPointsToPrice(const double points)
{
   // -1 is an explicit invalid-distance sentinel. Zero distance is permitted.
   if(!MathIsValidNumber(points) || points<0.0) return -1.0;
   double price=points/GOLD_POINTS_PER_PRICE_UNIT;
   if(points>0.0 && price<=0.0) return -1.0; // Conversion underflow is invalid.
   return price;
}
inline bool IsSwingConfigurationValid()
{
   return SwingStrengthValid(InpSwingStrength) &&
          SwingNumbersValid(InpMinimumSwingDistancePoints,InpSwingDuplicateTolerancePoints);
}
bool SwingPriceValid(const double price)
{
   return MathIsValidNumber(price) && price>0.0;
}
inline bool IsDuplicateSwing(const double a,const double b)
{
   if(!IsSwingConfigurationValid() || !SwingPriceValid(a) || !SwingPriceValid(b)) return false;
   double distance=MathAbs(a-b);
   return MathIsValidNumber(distance) && distance<=GoldPointsToPrice(InpSwingDuplicateTolerancePoints);
}
inline bool HasMinimumSwingDistance(const double a,const double b)
{
   if(!IsSwingConfigurationValid() || !SwingPriceValid(a) || !SwingPriceValid(b)) return false;
   double distance=MathAbs(a-b);
   return MathIsValidNumber(distance) && distance>=GoldPointsToPrice(InpMinimumSwingDistancePoints);
}
bool SwingRateValid(const MqlRates &r)
{
   return r.time>0 && SwingPriceValid(r.open) && SwingPriceValid(r.high) &&
          SwingPriceValid(r.low) && SwingPriceValid(r.close) &&
          r.low<=r.open && r.open<=r.high && r.low<=r.close && r.close<=r.high;
}
bool SwingSameRate(const MqlRates &a,const MqlRates &b)
{
   // Volume/spread corrections do not affect this OHLC-only algorithm.
   return a.time==b.time && a.open==b.open && a.high==b.high &&
          a.low==b.low && a.close==b.close;
}

// All arrays use physical chronological order (ArraySetAsSeries(false)).
// A dual high/low outside candle is excluded, as in v2.4.
ENUM_SWING_TYPE SwingPivotType(const MqlRates &rates[],const int center,const int strength)
{
   int n=ArraySize(rates);
   if(!SwingStrengthValid(strength) || center<strength || center>=n-strength) return SWING_NONE;
   bool high=true,low=true;
   for(int i=center-strength;i<=center+strength;i++)
   {
      if(!SwingRateValid(rates[i]) || (i>center-strength && rates[i].time<=rates[i-1].time))
         return SWING_NONE;
      if(i==center) continue;
      if(rates[i].high>=rates[center].high) high=false;
      if(rates[i].low<=rates[center].low) low=false;
   }
   if(high==low) return SWING_NONE;
   return high ? SWING_HIGH : SWING_LOW;
}

// Standalone local-pivot checks validate the entire OHLC neighborhood atomically.
// Bounds are expressed by subtraction before any shift+strength arithmetic.
bool SwingReadLocal(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,
                    const int strength,const bool wantHigh)
{
   if(symbol=="" || !SwingStrengthValid(strength) || shift<=strength ||
      !SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED)) return false;
   int bars=Bars(symbol,tf);
   if(bars<=strength || shift>=bars-strength) return false;
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int count=2*strength+1;
   if(CopyRates(symbol,tf,shift-strength,count,rates)!=count) return false;
   // Local checks keep v2.4's high/low independence, including dual pivots.
   for(int i=0;i<count;i++)
      if(!SwingRateValid(rates[i]) || (i>0 && rates[i].time<=rates[i-1].time)) return false;
   for(int i=0;i<count;i++)
   {
      if(i==strength) continue;
      if(wantHigh && rates[i].high>=rates[strength].high) return false;
      if(!wantHigh && rates[i].low<=rates[strength].low) return false;
   }
   return true;
}
inline bool IsSwingHigh(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,const int strength)
{ return SwingReadLocal(symbol,tf,shift,strength,true); }
inline bool IsSwingLow(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,const int strength)
{ return SwingReadLocal(symbol,tf,shift,strength,false); }

class CSwingStream
{
public:
   string symbol;
   ENUM_TIMEFRAMES timeframe;
   int strength;
   double minimum,tolerance;
   datetime anchor;             // Earliest source bar; never silently moved.
   datetime lastTime,lastAvailable;
   MqlRates window[MAX_SWING_LOOKBACK_BARS];
   int windowCount;
   SwingEvent events[MAX_SWING_LOOKBACK_BARS];
   int eventCount;
   long totalEvents;             // Monotonic, does not reset when history retires.
   SwingEvent candidate;
   ENUM_SWING_STATUS status;

   CSwingStream() { Reset(); }
   void Reset()
   {
      symbol=""; timeframe=PERIOD_CURRENT; strength=0; minimum=0; tolerance=0;
      anchor=0; lastTime=0; lastAvailable=0; windowCount=0; eventCount=0; totalEvents=0;
      candidate.type=SWING_NONE; candidate.id=0; candidate.price=0;
      candidate.pivotTime=0; candidate.confirmedAt=0; candidate.finalizedAt=0;
      status=SWING_OK;
   }
   bool Configure(const int s,const double minPoints,const double duplicatePoints)
   {
      Reset();
      if(!SwingStrengthValid(s) || !SwingNumbersValid(minPoints,duplicatePoints))
      { status=SWING_INVALID_INPUT; return false; }
      strength=s; minimum=GoldPointsToPrice(minPoints); tolerance=GoldPointsToPrice(duplicatePoints);
      return true;
   }
   bool FeedClosed(const MqlRates &bar,const datetime availableAt)
   {
      // No mutation for a failed input. A missing bar is never skipped.
      if(!SwingStrengthValid(strength) || !SwingRateValid(bar) || availableAt<=bar.time ||
         (lastTime>0 && (bar.time<=lastTime || availableAt<=lastAvailable || bar.time!=lastAvailable)))
      { status=SWING_DATA_UNAVAILABLE; return false; }
      if(windowCount==MAX_SWING_LOOKBACK_BARS)
      {
         for(int i=1;i<windowCount;i++) window[i-1]=window[i];
         windowCount--;
      }
      window[windowCount]=bar; windowCount++;
      lastTime=bar.time; lastAvailable=availableAt;
      if(anchor==0) anchor=bar.time;
      status=SWING_OK;
      if(windowCount<2*strength+1) return true;
      int center=windowCount-1-strength;
      ENUM_SWING_TYPE type=SwingPivotType(window,center,strength);
      if(type==SWING_NONE) return true;
      double price=type==SWING_HIGH ? window[center].high : window[center].low;
      if(candidate.type!=SWING_NONE && type==candidate.type)
      {
         if((type==SWING_HIGH && price<=candidate.price) ||
            (type==SWING_LOW && price>=candidate.price)) return true;
      }
      else if(candidate.type!=SWING_NONE)
      {
         double distance=MathAbs(price-candidate.price);
         if(!MathIsValidNumber(distance) || distance<=tolerance || distance<minimum) return true;
         // Append a value copy; never revisit or replace a finalized event.
         if(eventCount==MAX_SWING_LOOKBACK_BARS)
         {
            for(int i=1;i<eventCount;i++) events[i-1]=events[i];
            eventCount--;
         }
         totalEvents++;
         candidate.id=totalEvents;
         candidate.finalizedAt=availableAt;
         events[eventCount]=candidate; eventCount++;
      }
      candidate.type=type; candidate.price=price; candidate.pivotTime=window[center].time;
      candidate.confirmedAt=availableAt; candidate.finalizedAt=0; candidate.id=0;
      return true;
   }
};

CSwingStream SwingContexts[MAX_SWING_CONTEXTS];
ENUM_SWING_STATUS SwingLastStatus=SWING_OK;

// Explicit lifecycle: call on EA initialization/deinitialization. No disk/global
// variable persistence, so each Strategy Tester run reconstructs independently.
// Reconstruction requires identical source OHLC and the same earliest source
// timestamp. Source extension/truncation or cached OHLC corrections return
// HISTORY_CHANGED until explicit reset; never merge generations of events.
// Corrections older than the cached 499 rates cannot be detected automatically.
void ResetSwingDetectors()
{
   for(int i=0;i<MAX_SWING_CONTEXTS;i++) SwingContexts[i].Reset();
   SwingLastStatus=SWING_OK;
}
ENUM_SWING_STATUS GetSwingStatus() { return SwingLastStatus; }

int SwingContext(const string symbol,const ENUM_TIMEFRAMES tf,const int strength)
{
   int empty=-1;
   for(int i=0;i<MAX_SWING_CONTEXTS;i++)
   {
      if(SwingContexts[i].symbol==symbol && SwingContexts[i].timeframe==tf &&
         SwingContexts[i].strength==strength) return i;
      if(SwingContexts[i].symbol=="") empty=i;
   }
   if(empty<0) { SwingLastStatus=SWING_CAPACITY; return -1; }
   if(!SwingContexts[empty].Configure(strength,InpMinimumSwingDistancePoints,InpSwingDuplicateTolerancePoints))
   { SwingLastStatus=SWING_INVALID_INPUT; return -1; }
   SwingContexts[empty].symbol=symbol; SwingContexts[empty].timeframe=tf;
   return empty;
}

bool SwingUpdate(CSwingStream &state)
{
   string symbol=state.symbol;
   ENUM_TIMEFRAMES tf=state.timeframe;
   if(!SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED))
   { SwingLastStatus=SWING_DATA_UNAVAILABLE; return false; }
   int bars=Bars(symbol,tf);
   datetime active=iTime(symbol,tf,0);
   datetime first=(datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE);
   if(bars<2 || active<=0 || first<=0)
   { SwingLastStatus=SWING_DATA_UNAVAILABLE; return false; }
   if(state.anchor!=0 && state.anchor!=first)
   { SwingLastStatus=SWING_HISTORY_CHANGED; return false; }
   if(state.minimum!=GoldPointsToPrice(InpMinimumSwingDistancePoints) ||
      state.tolerance!=GoldPointsToPrice(InpSwingDuplicateTolerancePoints))
   { SwingLastStatus=SWING_INVALID_INPUT; return false; }
   int remaining=bars-1;
   if(state.lastTime>0)
   {
      int lastShift=iBarShift(symbol,tf,state.lastTime,true);
      MqlRates overlap[];
      ArraySetAsSeries(overlap,false);
      if(lastShift<1 || CopyRates(symbol,tf,lastShift,state.windowCount,overlap)!=state.windowCount)
      { SwingLastStatus=SWING_HISTORY_CHANGED; return false; }
      for(int i=0;i<state.windowCount;i++)
         if(!SwingSameRate(overlap[i],state.window[i]))
         { SwingLastStatus=SWING_HISTORY_CHANGED; return false; }
      remaining=lastShift-1;
   }
   // Initial bootstrap replays ALL available closed history from a fixed first
   // bar in bounded 499-rate chunks. Starting a rolling 499-bar rescan would
   // lose the incoming candidate and cannot preserve finalized history.
   while(remaining>0)
   {
      int count=(int)MathMin(remaining,MAX_SWING_LOOKBACK_BARS);
      int shift=remaining-count+1;
      MqlRates rates[];
      ArraySetAsSeries(rates,false);
      if(CopyRates(symbol,tf,shift,count,rates)!=count)
      { SwingLastStatus=SWING_DATA_UNAVAILABLE; return false; }
      datetime next=iTime(symbol,tf,shift-1);
      if(next<=0 || iTime(symbol,tf,0)!=active || Bars(symbol,tf)!=bars ||
         (datetime)SeriesInfoInteger(symbol,tf,SERIES_FIRSTDATE)!=first)
      { SwingLastStatus=SWING_DATA_UNAVAILABLE; return false; }
      // Validate whole chunk before advancing state. Failed chunks are retried.
      for(int i=0;i<count;i++)
      {
         datetime available=i+1<count ? rates[i+1].time : next;
         if(!SwingRateValid(rates[i]) || available<=rates[i].time || available>active ||
            (i==0 && ((state.lastTime==0 && rates[0].time!=first) ||
             (state.lastTime>0 && rates[0].time!=state.lastAvailable))))
         { SwingLastStatus=SWING_DATA_UNAVAILABLE; return false; }
      }
      for(int i=0;i<count;i++)
      {
         datetime available=i+1<count ? rates[i+1].time : next;
         if(!state.FeedClosed(rates[i],available))
         { SwingLastStatus=state.status; return false; }
      }
      remaining-=count;
   }
   SwingLastStatus=SWING_OK;
   return true;
}

// New identity-aware API: returns false on errors, true on valid empty history.
// Caller must supply resizable dynamic arrays (not static/indicator buffers).
// Events are newest first; only the oldest retained events retire after 499
// FINALIZATIONS. This is count retention, not a sliding pivot-age cutoff.
bool GetFinalizedSwingEvents(const string symbol,const ENUM_TIMEFRAMES tf,const int strength,
                             const int maximumSwings,SwingEvent &out[])
{
   SwingLastStatus=SWING_INVALID_INPUT;
   if(!ArrayIsDynamic(out)) return false;
   ArrayResize(out,0);
   if(ArraySize(out)!=0) return false; // Non-resizable buffers are unsupported outputs.
   if(symbol=="" || !IsSwingConfigurationValid() || !SwingStrengthValid(strength) ||
      maximumSwings<=0 || maximumSwings>MAX_SWING_LOOKBACK_BARS) return false;
   int index=SwingContext(symbol,tf,strength);
   if(index<0 || !SwingUpdate(SwingContexts[index])) return false;
   int count=(int)MathMin(maximumSwings,SwingContexts[index].eventCount);
   if(ArrayResize(out,count)!=count)
   { ArrayResize(out,0); SwingLastStatus=SWING_OUTPUT_ERROR; return false; }
   for(int i=0;i<count;i++) out[i]=SwingContexts[index].events[SwingContexts[index].eventCount-1-i];
   return true;
}
inline int CollectQualifiedSwings(const string symbol,const ENUM_TIMEFRAMES tf,const int strength,
                                 const int maximumSwings,double &prices[],ENUM_SWING_TYPE &types[])
{
   SwingLastStatus=SWING_INVALID_INPUT;
   bool dynamic=ArrayIsDynamic(prices) && ArrayIsDynamic(types);
   if(ArrayIsDynamic(prices)) ArrayResize(prices,0);
   if(ArrayIsDynamic(types)) ArrayResize(types,0);
   if(!dynamic || ArraySize(prices)!=0 || ArraySize(types)!=0) return 0;
   SwingEvent events[];
   if(!GetFinalizedSwingEvents(symbol,tf,strength,maximumSwings,events)) return 0;
   int count=ArraySize(events);
   if(ArrayResize(prices,count)!=count || ArrayResize(types,count)!=count)
   {
      ArrayResize(prices,0); ArrayResize(types,0); SwingLastStatus=SWING_OUTPUT_ERROR; return 0;
   }
   for(int i=0;i<count;i++) { prices[i]=events[i].price; types[i]=events[i].type; }
   return count;
}
bool SwingGetByType(const string symbol,const ENUM_TIMEFRAMES tf,const int strength,const int count,
                    const ENUM_SWING_TYPE type,double &out[])
{
   SwingLastStatus=SWING_INVALID_INPUT;
   if(!ArrayIsDynamic(out)) return false;
   ArrayResize(out,0);
   if(ArraySize(out)!=0) return false;
   // No count multiplication. At most ceil(499/2) of one type can be retained.
   if(count<=0 || count>(MAX_SWING_LOOKBACK_BARS+1)/2) return false;
   SwingEvent events[];
   if(!GetFinalizedSwingEvents(symbol,tf,strength,MAX_SWING_LOOKBACK_BARS,events)) return false;
   int found=0;
   for(int i=0;i<ArraySize(events);i++) if(events[i].type==type) found++;
   if(found<count) return false;
   if(ArrayResize(out,count)!=count)
   { ArrayResize(out,0); SwingLastStatus=SWING_OUTPUT_ERROR; return false; }
   found=0;
   for(int i=0;i<ArraySize(events) && found<count;i++)
      if(events[i].type==type) { out[found]=events[i].price; found++; }
   return true;
}
inline bool GetLastSwingHighs(const string symbol,const ENUM_TIMEFRAMES tf,const int strength,
                              const int count,double &highs[])
{ return SwingGetByType(symbol,tf,strength,count,SWING_HIGH,highs); }
inline bool GetLastSwingLows(const string symbol,const ENUM_TIMEFRAMES tf,const int strength,
                             const int count,double &lows[])
{ return SwingGetByType(symbol,tf,strength,count,SWING_LOW,lows); }
#endif
