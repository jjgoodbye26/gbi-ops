//+------------------------------------------------------------------+
//| NDR_Type1Zones.mq5  v1.0                                         |
//| Marks the FIRST H4 candle of every Type-1 daily candle as a      |
//| zone (body + wicks) and tracks what price does when it returns   |
//| to that area days or weeks later.                                |
//|                                                                  |
//| Type-1 day  = daily candle that ENGULFS the prior day's body     |
//|               (opposite colour) and/or CLOSES past daily          |
//|               structure (the high/low of the last N days —       |
//|               N=1 is a single-candle market structure break).    |
//| Zone        = first H4 candle of that day (wick-to-wick range,   |
//|               body drawn darker inside).                         |
//| Touch       = first H4 bar AFTER the zone day that trades back   |
//|               into the zone. Outcome is measured over the next   |
//|               InpReactBars H4 bars: HELD (+max favourable move   |
//|               in points) or BROKE (closed through the far side). |
//+------------------------------------------------------------------+
#property copyright   "NDR Trading System"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define ZPFX "NDRT1Z_"
#define MAXZONES 120

// ── INPUTS ────────────────────────────────────────────────────────
input group "== Scan =="
input int  InpLookbackDays = 90;     // Days of history to scan for Type-1 days
input int  InpStructDays   = 1;      // Structure lookback: close past the N-day high/low (1 = prior day)

input group "== Type-1 qualification =="
input bool InpNeedEngulf   = false;  // Require engulf (opposite-colour body close-through)
input bool InpNeedSMSB     = false;  // Require structure break (close past N-day high/low)
//        both false = engulf OR structure break qualifies (default)
//        both true  = only the strongest days: engulf AND structure break

input group "== Zone =="
input bool InpZoneWicks    = true;   // Zone = full first-H4 range (false = body only)
input int  InpReactBars    = 18;     // H4 bars after a touch to judge the reaction (18 = 3 days)
input bool InpShowTouched  = true;   // Keep touched zones on chart with their outcome label
input bool InpShowBroken   = true;   // Keep zones that broke (false = hide them)

input group "== Alerts =="
input bool InpAlertTouch   = true;   // Pop an MT5 alert when live price re-enters a zone

input group "== Colours =="
input color InpCBullZone   = C'18,60,100';    // bullish zone fill (demand)
input color InpCBearZone   = C'100,30,30';    // bearish zone fill (supply)
input color InpCBullStrong = C'20,90,150';    // engulf + structure break (strongest)
input color InpCBearStrong = C'150,40,40';
input color InpCText       = clrWhite;

// ── GLOBALS ───────────────────────────────────────────────────────
datetime g_lastH4   = 0;
bool     g_alerted[MAXZONES];
datetime g_zoneT[MAXZONES];
int      g_zoneN    = 0;

//═══════════════════════════════════════════════════════════════════
int OnInit()
{
   ArrayInitialize(g_alerted, false);
   g_lastH4 = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   ObjectsDeleteAll(0, ZPFX);
   ChartRedraw();
}

int OnCalculate(const int rt,const int pc,const datetime &t[],
                const double &o[],const double &h[],const double &l[],const double &c[],
                const long &tv[],const long &v[],const int &s[])
{
   // Rebuild once per new H4 bar (first run included)
   datetime h4 = iTime(_Symbol, PERIOD_H4, 0);
   if(h4 != 0 && h4 != g_lastH4)
   {
      g_lastH4 = h4;
      ScanAndDraw();
   }
   if(InpAlertTouch) LiveTouchCheck();
   return rt;
}

//═══════════════════════════════════════════════════════════════════
bool Is24_7()
{
   string sym=_Symbol;
   return (StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
           StringFind(sym,"DE40")>=0 || StringFind(sym,"US30")>=0 ||
           StringFind(sym,"USTECH")>=0 || StringFind(sym,"XTIUSD")>=0 ||
           StringFind(sym,"XAUUSD")>=0 || StringFind(sym,"XAGUSD")>=0);
}

// Is daily bar index d a valid (non-weekend, non-doji) day?
bool ValidDay(int d, bool is247)
{
   datetime tt=iTime(_Symbol,PERIOD_D1,d); if(tt==0) return false;
   if(!is247)
   {
      MqlDateTime dt; TimeToStruct(tt,dt);
      if(dt.day_of_week==0||dt.day_of_week==6) return false;
   }
   double o=iOpen(_Symbol,PERIOD_D1,d), cc=iClose(_Symbol,PERIOD_D1,d);
   if(o==0||cc==0||o==cc) return false;
   return true;
}

// Next valid trading day at or after index d (searching older), -1 if none
int NextValidDay(int d, bool is247)
{
   for(int k=d;k<=d+7;k++)
   {
      if(iTime(_Symbol,PERIOD_D1,k)==0) return -1;
      if(!is247)
      {
         MqlDateTime dt; TimeToStruct(iTime(_Symbol,PERIOD_D1,k),dt);
         if(dt.day_of_week==0||dt.day_of_week==6) continue;
      }
      if(iOpen(_Symbol,PERIOD_D1,k)==0) continue;
      return k;
   }
   return -1;
}

//═══════════════════════════════════════════════════════════════════
void ScanAndDraw()
{
   ObjectsDeleteAll(0, ZPFX);
   g_zoneN = 0;

   bool is247 = Is24_7();
   int  maxD  = MathMin(InpLookbackDays, iBars(_Symbol,PERIOD_D1)-2);
   int  ab    = iBars(_Symbol,PERIOD_H4);
   if(ab < 12) return;

   // Scan from oldest to newest so newer zones draw on top
   for(int d=maxD; d>=1; d--)
   {
      if(g_zoneN >= MAXZONES) break;
      if(!ValidDay(d, is247)) continue;

      double o=iOpen(_Symbol,PERIOD_D1,d), cc=iClose(_Symbol,PERIOD_D1,d);
      bool   bull=(cc>o);

      // Prior valid day (for the engulf test)
      int p2 = NextValidDay(d+1, is247);
      if(p2<0) continue;
      double o2=iOpen(_Symbol,PERIOD_D1,p2), c2=iClose(_Symbol,PERIOD_D1,p2);
      double bodyHi2=MathMax(o2,c2), bodyLo2=MathMin(o2,c2);

      bool engulf = bull ? ((c2<o2)&&(cc>bodyHi2))
                         : ((c2>o2)&&(cc<bodyLo2));

      // Structure break: close past the extreme of the last N valid days
      double structLv = 0; int found=0, k=d+1;
      while(found<MathMax(1,InpStructDays) && k<=d+InpStructDays+10)
      {
         int vd = NextValidDay(k, is247); if(vd<0) break;
         double ext = bull ? iHigh(_Symbol,PERIOD_D1,vd) : iLow(_Symbol,PERIOD_D1,vd);
         if(found==0) structLv=ext;
         else structLv = bull ? MathMax(structLv,ext) : MathMin(structLv,ext);
         found++; k=vd+1;
      }
      bool smsb = (found>0) && (bull ? (cc>structLv) : (cc<structLv));

      bool type1;
      if(InpNeedEngulf && InpNeedSMSB)      type1 = engulf && smsb;
      else if(InpNeedEngulf)                type1 = engulf;
      else if(InpNeedSMSB)                  type1 = smsb;
      else                                  type1 = engulf || smsb;
      if(!type1) continue;

      // ── First H4 candle of day d ──────────────────────────────
      datetime dS=iTime(_Symbol,PERIOD_D1,d);
      datetime dE=(d>=1)?iTime(_Symbol,PERIOD_D1,d-1):TimeCurrent();
      if(dE==0) dE=dS+86400;
      int aF=-1;
      for(int b=ab-1;b>=0;b--)
      { datetime tb=iTime(_Symbol,PERIOD_H4,b); if(tb==0||tb<dS) continue; if(tb>=dE) break; aF=b; break; }
      if(aF<0) continue;

      double zh=iHigh(_Symbol,PERIOD_H4,aF), zl=iLow(_Symbol,PERIOD_H4,aF);
      double zo=iOpen(_Symbol,PERIOD_H4,aF), zc=iClose(_Symbol,PERIOD_H4,aF);
      double top = InpZoneWicks ? zh : MathMax(zo,zc);
      double bot = InpZoneWicks ? zl : MathMin(zo,zc);
      if(top<=bot) continue;
      datetime zt=iTime(_Symbol,PERIOD_H4,aF);

      // ── Find the first H4 touch AFTER the zone day ends ───────
      int touchBar=-1;
      for(int b=ab-1;b>=0;b--)
      {
         datetime tb=iTime(_Symbol,PERIOD_H4,b);
         if(tb==0||tb<dE) continue;              // skip the zone's own day
         if(iLow(_Symbol,PERIOD_H4,b)<=top && iHigh(_Symbol,PERIOD_H4,b)>=bot)
         { touchBar=b; break; }
      }

      // ── Judge the reaction over the next InpReactBars H4 bars ─
      // HELD  = never closed through the far side; report max favourable move
      // BROKE = an H4 close beyond the far side of the zone
      string outcome=""; double favPts=0; bool broke=false;
      if(touchBar>=0)
      {
         double pt=SymbolInfoDouble(_Symbol,SYMBOL_POINT); if(pt<=0) pt=1;
         int from=touchBar, to=MathMax(0,touchBar-InpReactBars);
         double fav=0;
         for(int b=from;b>=to;b--)
         {
            double bc=iClose(_Symbol,PERIOD_H4,b);
            if(bull){ if(bc<bot){ broke=true; break; } fav=MathMax(fav,iHigh(_Symbol,PERIOD_H4,b)-top); }
            else    { if(bc>top){ broke=true; break; } fav=MathMax(fav,bot-iLow(_Symbol,PERIOD_H4,b)); }
         }
         favPts=fav/pt;
         outcome = broke ? "BROKE" : ("HELD +"+DoubleToString(favPts,0)+"pts");
      }

      if(touchBar>=0 && !InpShowTouched) continue;
      if(broke && !InpShowBroken)        continue;

      // ── Draw ──────────────────────────────────────────────────
      bool  strong = (engulf && smsb);
      color zc1 = bull ? (strong?InpCBullStrong:InpCBullZone)
                       : (strong?InpCBearStrong:InpCBearZone);
      datetime rightT = (touchBar>=0)
         ? iTime(_Symbol,PERIOD_H4,MathMax(0,touchBar-InpReactBars))
         : TimeCurrent()+PeriodSeconds(PERIOD_H4)*6;

      string id=IntegerToString(g_zoneN);
      string rn=ZPFX+"R"+id;
      ObjectCreate(0,rn,OBJ_RECTANGLE,0,zt,top,rightT,bot);
      ObjectSetInteger(0,rn,OBJPROP_COLOR,zc1);
      ObjectSetInteger(0,rn,OBJPROP_FILL,true);
      ObjectSetInteger(0,rn,OBJPROP_BACK,true);
      ObjectSetInteger(0,rn,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,rn,OBJPROP_HIDDEN,true);

      string tag = bull ? "T1 DEMAND" : "T1 SUPPLY";
      if(strong) tag += " *";                       // engulf + structure break
      if(touchBar<0) tag += "  [untouched]";
      else           tag += "  ["+outcome+"]";
      string tn=ZPFX+"T"+id;
      ObjectCreate(0,tn,OBJ_TEXT,0,zt,top);
      ObjectSetString (0,tn,OBJPROP_TEXT," "+tag);
      ObjectSetInteger(0,tn,OBJPROP_COLOR,InpCText);
      ObjectSetString (0,tn,OBJPROP_FONT,"Arial Bold");
      ObjectSetInteger(0,tn,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,tn,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0,tn,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,tn,OBJPROP_HIDDEN,true);

      // Remember untouched zones for live alerts
      if(touchBar<0 && g_zoneN<MAXZONES)
      {
         g_zoneT[g_zoneN]=zt;
         // store levels in object as tooltip for the alert check
         ObjectSetString(0,rn,OBJPROP_TOOLTIP,DoubleToString(top,_Digits)+"|"+DoubleToString(bot,_Digits));
      }
      g_zoneN++;
   }
   ChartRedraw();
}

//═══════════════════════════════════════════════════════════════════
// Live alert: current price entering a still-untouched zone
void LiveTouchCheck()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0) return;
   for(int i=0;i<g_zoneN && i<MAXZONES;i++)
   {
      if(g_alerted[i]) continue;
      string rn=ZPFX+"R"+IntegerToString(i);
      if(ObjectFind(0,rn)<0) continue;
      string tip=ObjectGetString(0,rn,OBJPROP_TOOLTIP);
      if(tip=="") continue;                      // touched historically, no alert needed
      int sep=StringFind(tip,"|"); if(sep<0) continue;
      double top=StringToDouble(StringSubstr(tip,0,sep));
      double bot=StringToDouble(StringSubstr(tip,sep+1));
      if(bid<=top && bid>=bot)
      {
         g_alerted[i]=true;
         Alert("NDR Type-1 zone touched: ",_Symbol," ",
               DoubleToString(bot,_Digits),"-",DoubleToString(top,_Digits));
      }
   }
}
