// GoldEA non-trading SwingDetector v2.5 regression and timestamp diagnostics.
#property strict
#property version "1.21"
#include "Include/Config.mqh"
#include "Include/SwingDetector.mqh"
input group "===== Non-trading diagnostics ====="
input int InpTestSwingCount=12;
input bool InpTestWriteCSV=true;
input bool InpTestRebuildEveryBar=false; // Expensive full-source replay comparison.
int TestPasses=0,TestFailures=0,TestFile=INVALID_HANDLE;
datetime LastTestBar=0;
bool TestStopped=false;
SwingEvent PreviousEvents[];

void TestCheck(const bool ok,const string description)
{
   if(ok) TestPasses++; else TestFailures++;
   PrintFormat("SwingTest | %s | %s",ok ? "PASS" : "FAIL",description);
}

// FileWrite reports bytes, FileFlush reports errors through GetLastError.
// Latch failures: retrying an incomplete CSV snapshot would duplicate rows.
bool TestCSVWriteOK(const uint written,const string operation)
{
   int error=GetLastError();
   if(written>0 && error==0) return true;
   TestStopped=true;
   TestCheck(false,"CSV "+operation);
   PrintFormat("SwingTest | CSV ERROR | operation=%s error=%d bytes=%u",operation,error,written);
   return false;
}
bool TestCSVFlush()
{
   ResetLastError();
   FileFlush(TestFile);
   if(GetLastError()==0) return true;
   return TestCSVWriteOK(0,"flush");
}
string TestTime(const datetime time)
{
   return TimeToString(time,TIME_DATE|TIME_SECONDS);
}

// BEGIN PORTABLE REGRESSION FIXTURES: also executed by the adapted native probe.
bool TestSameEvent(const SwingEvent &a,const SwingEvent &b)
{
   return a.id==b.id && a.type==b.type && a.price==b.price &&
          a.pivotTime==b.pivotTime && a.confirmedAt==b.confirmedAt && a.finalizedAt==b.finalizedAt;
}
void TestRate(const double price,const datetime time,MqlRates &r)
{
   r.time=time; r.open=price; r.close=price; r.high=price+0.1; r.low=price-0.1;
}
bool TestBuild(const double &centers[],const int interpolation,MqlRates &rates[])
{
   int n=ArraySize(centers);
   if(n<=0 || interpolation<=0 || n-1>2147483646/interpolation) return false;
   int count=(n-1)*interpolation+1;
   if(ArrayResize(rates,count)!=count) return false;
   TestRate(centers[0],1000000000,rates[0]);
   int out=1;
   for(int i=1;i<n;i++)
      for(int j=1;j<=interpolation;j++)
      {
         double price=centers[i-1]+(centers[i]-centers[i-1])*j/interpolation;
         TestRate(price,1000000000+out*900,rates[out]); out++;
      }
   return true;
}
bool TestReplay(const MqlRates &rates[],const int strength,CSwingStream &stream)
{
   if(!stream.Configure(strength,500,100)) return false;
   SwingEvent previous[];
   for(int bar=0;bar<ArraySize(rates);bar++)
   {
      if(!stream.FeedClosed(rates[bar],rates[bar].time+900)) return false;
      // Every finalized event must survive unchanged until explicit event-count
      // retention (499 newer finalized events), including across window shifts.
      for(int old=0;old<ArraySize(previous);old++)
      {
         if(previous[old].id<=stream.totalEvents-MAX_SWING_LOOKBACK_BARS) continue;
         int index=(int)(previous[old].id-stream.events[0].id);
         if(index<0 || index>=stream.eventCount || !TestSameEvent(previous[old],stream.events[index]))
            return false;
      }
      if(ArrayResize(previous,stream.eventCount)!=stream.eventCount) return false;
      for(int i=0;i<stream.eventCount;i++)
      {
         SwingEvent e=stream.events[i];
         if(e.pivotTime>=e.confirmedAt || e.confirmedAt>=e.finalizedAt ||
            e.finalizedAt>rates[bar].time+900) return false;
         if(i>0 && (e.type==stream.events[i-1].type ||
                    e.pivotTime<=stream.events[i-1].pivotTime ||
                    e.finalizedAt<=stream.events[i-1].finalizedAt)) return false;
         previous[i]=e;
      }
   }
   return true;
}
void TestFixture(const double &centers[],const int interpolation,const int strength,const string label,const int direction=0)
{
   MqlRates rates[];
   if(!TestBuild(centers,interpolation,rates))
   { TestCheck(false,label+" fixture allocation"); return; }
   CSwingStream stream,rebuilt;
   bool ok=TestReplay(rates,strength,stream) && TestReplay(rates,strength,rebuilt);
   if(ok)
   {
      ok=stream.eventCount==rebuilt.eventCount && stream.totalEvents==rebuilt.totalEvents;
      for(int i=0;i<stream.eventCount && ok;i++) ok=TestSameEvent(stream.events[i],rebuilt.events[i]);
   }
   if(direction!=0 && ok)
   {
      double high=0,low=0;
      int highs=0,lows=0;
      for(int i=0;i<stream.eventCount;i++)
      {
         SwingEvent e=stream.events[i];
         if(e.type==SWING_HIGH)
         {
            if(highs>0 && (direction>0 ? e.price<=high : e.price>=high)) ok=false;
            high=e.price; highs++;
         }
         else
         {
            if(lows>0 && (direction>0 ? e.price<=low : e.price>=low)) ok=false;
            low=e.price; lows++;
         }
      }
      ok=ok && highs>=2 && lows>=2;
   }
   TestCheck(ok,label);
}
void RunSwingRegressionTests()
{
   TestCheck(GoldPointsToPrice(500)==5 && GoldPointsToPrice(100)==1,"Gold units");
   double up[]={100,90,120,100,130,110,140,120,150,130,160};
   double down[]={160,170,140,160,130,150,120,140,110,130,100};
   double range[]={100,110,100,110,100,109,108,110,100,110,100};
   double volatilePrices[]={100,101,130,90,140,105,102,150,80,160,90};
   double prefix[]={100,90,100,120,110,100,105,110,109};
   double extended[]={100,90,100,120,110,100,105,110,109,108,115,114};
   for(int strength=1;strength<=3;strength+=2)
   {
      int density=strength==1 ? 1 : 4;
      TestFixture(up,density,strength,"A HH/HL uptrend immutable replay/rebuild",1);
      TestFixture(down,density,strength,"B LH/LL downtrend immutable replay/rebuild",-1);
      TestFixture(range,density,strength,"C range/close pivots immutable replay");
      TestFixture(volatilePrices,density,strength,"D volatility immutable replay");
      MqlRates a[];
      MqlRates b[];
      if(!TestBuild(prefix,density,a) || !TestBuild(extended,density,b))
      { TestCheck(false,"fixture allocation"); return; }
      CSwingStream first,later;
      bool ok=TestReplay(a,strength,first) && TestReplay(b,strength,later);
      ok=ok && first.eventCount==3 && later.eventCount==3;
      for(int i=0;i<first.eventCount && ok;i++) ok=TestSameEvent(first.events[i],later.events[i]);
      TestCheck(ok,"E/F v2.4 counterexample: finalized identities survive appended bars");
      TestCheck(first.candidate.type==SWING_HIGH && MathAbs(first.candidate.price-110.1)<1e-9 &&
                later.candidate.type==SWING_HIGH && MathAbs(later.candidate.price-115.1)<1e-9,
                "E only unfinalized candidate replaces 110.1 with 115.1");
      TestCheck(later.events[0].type==SWING_LOW && MathAbs(later.events[0].price-89.9)<1e-9 &&
                later.events[1].type==SWING_HIGH && MathAbs(later.events[1].price-120.1)<1e-9 &&
                later.events[2].type==SWING_LOW && MathAbs(later.events[2].price-99.9)<1e-9,
                "E expected chronological finalized sequence");
      MqlRates longHistory[];
      if(ArrayResize(longHistory,2401)!=2401)
      { TestCheck(false,"long fixture allocation"); return; }
      for(int i=0;i<ArraySize(longHistory);i++)
      {
         int phase=i%8;
         double price=100+5*(phase<=4 ? phase : 8-phase);
         TestRate(price,1000000000+i*900,longHistory[i]);
      }
      CSwingStream retained;
      bool stable=TestReplay(longHistory,strength,retained);
      TestCheck(stable && retained.totalEvents>499 && retained.eventCount==499 &&
                retained.events[0].id==retained.totalEvents-498,
                "F/I 2401-bar replay: moving window, immutable IDs, explicit 499-event retention");
   }
   CSwingStream invalid;
   TestCheck(!invalid.Configure(0,500,100) && !invalid.Configure(2147483647,500,100) &&
             !invalid.Configure(3,0,100) && !invalid.Configure(3,500,-1),"H strength/distance bounds");
   double nan=MathArcsin(2.0);
   double infinity=DBL_MAX; infinity*=2.0;
   TestCheck(!invalid.Configure(3,nan,100) && !invalid.Configure(3,500,nan) &&
             !invalid.Configure(3,infinity,100) && !invalid.Configure(3,500,infinity) &&
             GoldPointsToPrice(nan)<0 && GoldPointsToPrice(infinity)<0 && GoldPointsToPrice(-1)<0,
             "H NaN/infinity/negative conversion rejected");
   TestCheck(IsDuplicateSwing(100,101) && !IsDuplicateSwing(100,101.001) &&
             HasMinimumSwingDistance(100,105) && !HasMinimumSwingDistance(100,104.999),
             "H exact default thresholds");
   invalid.Configure(1,500,100);
   MqlRates good,bad;
   TestRate(100,1000000000,good);
   bad=good; bad.high=0;
   bool rejected=!invalid.FeedClosed(bad,bad.time+900) && invalid.windowCount==0;
   bad=good; bad.low=0; rejected=rejected && !invalid.FeedClosed(bad,bad.time+900);
   bad=good; bad.open=200; rejected=rejected && !invalid.FeedClosed(bad,bad.time+900);
   bad=good; bad.close=nan; rejected=rejected && !invalid.FeedClosed(bad,bad.time+900);
   TestCheck(rejected && invalid.windowCount==0,"G invalid/missing OHLC never advances stream");
   TestCheck(invalid.FeedClosed(good,good.time+900) &&
             !invalid.FeedClosed(good,good.time+900) && invalid.windowCount==1,
             "G duplicate/out-of-order feed fails without mutation");
   double sentinel[];
   if(ArrayResize(sentinel,1)!=1)
   { TestCheck(false,"sentinel allocation"); return; }
   sentinel[0]=12345;
   TestCheck(!GetLastSwingHighs(_Symbol,PERIOD_M15,1,2147483647,sentinel) && ArraySize(sentinel)==0,
             "H INT_MAX count safely rejected before arithmetic/data access");
   if(ArrayResize(sentinel,1)!=1)
   { TestCheck(false,"sentinel allocation"); return; }
   sentinel[0]=12345;
   TestCheck(!GetLastSwingLows(_Symbol,PERIOD_M15,1,0,sentinel) && ArraySize(sentinel)==0,
             "H zero count clears output");
}
// END PORTABLE REGRESSION FIXTURES.

int OnInit()
{
   // MQL5 can reinitialize an EA without unloading its global variables.
   TestPasses=0; TestFailures=0; TestStopped=false; LastTestBar=0;
   TestFile=INVALID_HANDLE;
   if(ArrayResize(PreviousEvents,0)!=0)
   { TestCheck(false,"initial snapshot reset"); return INIT_FAILED; }
   ResetSwingDetectors();
   if(!IsSwingConfigurationValid() || InpTestSwingCount<=0 || InpTestSwingCount>MAX_SWING_LOOKBACK_BARS)
      return INIT_PARAMETERS_INCORRECT;
   RunSwingRegressionTests();
   ResetSwingDetectors(); // Synthetic streams never enter market-data contexts.
   if(TestFailures>0) return INIT_FAILED;
   if(InpTestWriteCSV)
   {
      ResetLastError();
      TestFile=FileOpen("GoldEA_SwingTest.csv",FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(TestFile==INVALID_HANDLE)
      { TestCSVWriteOK(0,"open"); return INIT_FAILED; }
      ResetLastError();
      if(!TestCSVWriteOK(FileWrite(TestFile,"evaluation_bar","id","type","price","pivot",
                                  "confirmed_at","finalized_at"),"header") || !TestCSVFlush())
         return INIT_FAILED;
   }
   Print("SwingTest v1.21, detector v2.5, NON-TRADING. CSV overwritten each initialization.");
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(TestStopped) return;
   datetime bar=iTime(_Symbol,PERIOD_M15,0);
   if(bar<=0 || bar==LastTestBar) return;
   SwingEvent current[];
   if(!GetFinalizedSwingEvents(_Symbol,PERIOD_M15,InpSwingStrength,InpTestSwingCount,current))
   {
      PrintFormat("SwingTest | WAIT/ERROR status=%d | history changes require explicit reset and fresh replay",
                  (int)GetSwingStatus());
      return;
   }
   bool stable=true;
   long newest=ArraySize(current)>0 ? current[0].id : 0;
   for(int old=0;old<ArraySize(PreviousEvents);old++)
   {
      // A rank limit retires exactly IDs older than the newest N-event suffix.
      if(PreviousEvents[old].id<=newest-InpTestSwingCount) continue;
      bool found=false;
      for(int i=0;i<ArraySize(current);i++)
         if(TestSameEvent(PreviousEvents[old],current[i])) found=true;
      if(!found) stable=false;
   }
   TestCheck(stable,"F live finalized identity/type/price/timestamps immutable (except count retirement)");
   if(InpTestRebuildEveryBar)
   {
      ResetSwingDetectors();
      SwingEvent rebuilt[];
      bool same=GetFinalizedSwingEvents(_Symbol,PERIOD_M15,InpSwingStrength,InpTestSwingCount,rebuilt);
      same=same && ArraySize(current)==ArraySize(rebuilt);
      for(int i=0;i<ArraySize(current) && same;i++) same=TestSameEvent(current[i],rebuilt[i]);
      TestCheck(same,"I reset and full closed-history replay matches incremental events");
      if(!same) return;
   }
   for(int i=0;i<ArraySize(current);i++)
   {
      SwingEvent e=current[i];
      TestCheck(e.pivotTime<e.confirmedAt && e.confirmedAt<e.finalizedAt && e.finalizedAt<=bar,
                "pivot/confirmation/finalization causality");
      PrintFormat("SwingTest | id=%I64d type=%d price=%s pivot=%s confirmed=%s finalized=%s",
                  e.id,(int)e.type,DoubleToString(e.price,_Digits),TestTime(e.pivotTime),
                  TestTime(e.confirmedAt),TestTime(e.finalizedAt));
      if(TestFile!=INVALID_HANDLE)
      {
         ResetLastError();
         if(!TestCSVWriteOK(FileWrite(TestFile,TestTime(bar),e.id,(int)e.type,DoubleToString(e.price,_Digits),
                                     TestTime(e.pivotTime),TestTime(e.confirmedAt),TestTime(e.finalizedAt)),"event"))
            return;
      }
   }
   if(TestFile!=INVALID_HANDLE && !TestCSVFlush()) return;
   if(ArrayResize(PreviousEvents,ArraySize(current))!=ArraySize(current))
   { TestCheck(false,"snapshot allocation"); TestStopped=true; return; }
   for(int i=0;i<ArraySize(current);i++) PreviousEvents[i]=current[i];
   LastTestBar=bar;
}
void OnDeinit(const int reason)
{
   if(TestFile!=INVALID_HANDLE) FileClose(TestFile);
   TestFile=INVALID_HANDLE;
   ResetSwingDetectors();
   PrintFormat("SwingTest | passes=%d failures=%d reason=%d",TestPasses,TestFailures,reason);
}
