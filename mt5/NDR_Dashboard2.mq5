//+------------------------------------------------------------------+
//| NDR_Dashboard2.mq5  v5                                          |
//+------------------------------------------------------------------+
#property copyright   "NDR Trading System"
#property version     "5.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#define PFX   "NDR5_"     // panel objects — wiped on every Draw()
#define APFX  "NDR5A_"   // arrow objects — persistent, only wiped on new day/invalidation
#define PCNT  42

// ── INPUTS ────────────────────────────────────────────────────────
input group "== Panel position =="
input int  InpX    = 10;
input int  InpY    = 30;

input group "== Row & column sizing =="
input int  InpRowH  = 20;   // px between rows — increase if rows still touch
input int  InpColW  = 320;  // px between left col and right col
//   Sub-column offsets WITHIN each column:
input int  InpXSym  = 5;    // PAIR  label x-offset from column start
input int  InpXDir  = 110;  // DIR   label x-offset from column start
input int  InpXLvl  = 220;  // LEVEL label x-offset from column start

input group "== Font =="
input int  InpFontSz = 9;

input group "== Chart line =="
input bool InpDrawLine = true;
input int  InpLineW    = 2;

input group "== Filter =="
input bool InpValidOnly = false;

input group "== Sensitivity =="
input int  InpTolPts = 0;

input group "== Telegram alerts =="
input bool   InpTgEnabled  = true;                                          // Enable Telegram alerts
input string InpTgToken    = "";              // Bot token (set in indicator inputs — do not commit)
input string InpTgChatID   = "";              // Your chat ID (set in indicator inputs)

input group "== WhatsApp alerts (CallMeBot) =="
input bool   InpWaEnabled  = false;           // Enable WhatsApp alerts
input string InpWaPhone    = "";              // Phone with country code e.g. 447911123456
input string InpWaApiKey   = "";             // API key from CallMeBot

input group "== Colours =="
input color InpCBuy     = clrDodgerBlue;
input color InpCSell    = clrRed;
input color InpCWas     = clrGray;
input color InpCInv     = C'120,120,120';
input color InpCTitle   = clrWhite;
input color InpCBg      = C'10,10,22';
input color InpCBorder  = C'60,60,90';
input color InpCInvLine = clrOrange;   // Invalidation level line colour

// ── TYPES ─────────────────────────────────────────────────────────
enum ENDR { EBUY, ESELL, EWBUY, EWSELL, EINV };

struct SPair { string sym; ENDR st; double lvl; datetime h4t; double pdcH; double pdcL; double refH; double refL; };

// ── GLOBALS ───────────────────────────────────────────────────────
string g_sym[PCNT] =
{
   "AUDCAD","AUDCHF","AUDJPY","AUDNZD","AUDUSD",
   "CADCHF","CADJPY","CHFJPY",
   "EURAUD","EURCAD","EURCHF","EURGBP","EURJPY","EURNZD","EURUSD","EURSGD",
   "GBPAUD","GBPCAD","GBPCHF","GBPJPY","GBPNZD","GBPUSD","GBPSGD",
   "NZDCAD","NZDCHF","NZDJPY","NZDUSD",
   "USDCAD","USDCHF","USDJPY","USDMXN","USDSGD","USDZAR","USDTHB",
   "XAUUSD","XAGUSD","ETHUSD","BTCUSD",
   "DE40","US30","USTECH","XTIUSD"
};

SPair    g_p[PCNT];
datetime g_day        = 0;
bool     g_dirty      = true;
ENDR     g_prevSt[PCNT];

// M30 entry arrow tracking for current chart symbol
datetime g_lastM30    = 0;
bool     g_prevM30Bull= false;
bool     g_prevM30Set = false;
int      g_arrowSeq   = 0;

// ═══════════════════════════════════════════════════════════════════
int OnInit()
{
   for(int i=0;i<PCNT;i++)
   {
      g_p[i].sym=g_sym[i]; g_p[i].st=EINV;
      g_p[i].lvl=0; g_p[i].h4t=0;
      g_p[i].pdcH=0; g_p[i].pdcL=0;
      g_prevSt[i]=EINV;
   }
   Evaluate();
   Draw();
   DrawLine();
   SendDailySummary();   // send real live list on load
   g_dirty = false;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, APFX);
   ChartRedraw();
}

int OnCalculate(const int rt,const int pc,const datetime &t[],
                const double &o[],const double &h[],const double &l[],const double &c[],
                const long &tv[],const long &v[],const int &s[])
{
   datetime d = iTime(_Symbol,PERIOD_D1,0);
   if(d!=0 && d!=g_day)
   {
      g_day=d;
      ObjectsDeleteAll(0, APFX);   // clear previous day's arrows
      g_arrowSeq = 0;
      Evaluate();
      SendDailySummary();
      g_dirty=true;
      // Reset M30 tracking for new day
      g_lastM30    = 0;
      g_prevM30Set = false;
      g_prevM30Bull= false;
   }
   else
   {
      LiveCheck();
      CheckAlerts();        // alert: invalidations and new setups intraday
   }

   if(g_dirty){ Draw(); DrawLine(); g_dirty=false; }

   // Check M30 manipulation for entry arrow on current chart symbol
   CheckM30Entry();

   return rt;
}

// ═══════════════════════════════════════════════════════════════════
// EVALUATION
// ═══════════════════════════════════════════════════════════════════
void Evaluate(){ for(int i=0;i<PCNT;i++) EvalPair(i); g_dirty=true; }

void EvalPair(int idx)
{
   string sym=g_sym[idx];
   g_p[idx].st=EINV; g_p[idx].lvl=0; g_p[idx].h4t=0; g_p[idx].pdcH=0; g_p[idx].pdcL=0; g_p[idx].refH=0; g_p[idx].refL=0;
   if(!SymbolSelect(sym,true)) return;
   datetime tmp[1];
   CopyTime(sym,PERIOD_D1,0,1,tmp);
   CopyTime(sym,PERIOD_H12,0,1,tmp);
   CopyTime(sym,PERIOD_H4,0,1,tmp);
   if(iBars(sym,PERIOD_D1)<5) return;

   // PDC
   // For 24/7 symbols (crypto, indices) every day is valid — don't skip weekends
   bool is24_7 = (StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
                  StringFind(sym,"DE40")>=0 || StringFind(sym,"US30")>=0 ||
                  StringFind(sym,"USTECH")>=0 || StringFind(sym,"XTIUSD")>=0 ||
                  StringFind(sym,"XAUUSD")>=0 || StringFind(sym,"XAGUSD")>=0);
   int ps=-1;
   for(int d=1;d<=7;d++)
   {
      datetime t=iTime(sym,PERIOD_D1,d); if(t==0) continue;
      if(!is24_7)
      {
         MqlDateTime dt; TimeToStruct(t,dt);
         if(dt.day_of_week==0||dt.day_of_week==6) continue;
      }
      double o=iOpen(sym,PERIOD_D1,d),cc=iClose(sym,PERIOD_D1,d);
      if(o==0||cc==0||o==cc) continue;
      ps=d; break;
   }
   if(ps<0) return;
   double pO=iOpen(sym,PERIOD_D1,ps),pC=iClose(sym,PERIOD_D1,ps);
   double pH=iHigh(sym,PERIOD_D1,ps),pL=iLow(sym,PERIOD_D1,ps);
   if(pC==pO) return;
   bool bull=(pC>pO);
   datetime pS=iTime(sym,PERIOD_D1,ps),pE=iTime(sym,PERIOD_D1,ps-1);
   if(pS==0||pE==0) return;

   // H12
   int hb=iBars(sym,PERIOD_H12); if(hb<4) return;
   int hF=-1,hS=-1,hC=0;
   for(int b=0;b<hb;b++)
   {
      datetime t=iTime(sym,PERIOD_H12,b);
      if(t==0||t<pS) break;
      if(t<pE){ hC++; if(hC==1)hS=b; else if(hC==2)hF=b; else return; }
   }
   if(hC!=2||hF<0||hS<0) return;
   double fO=iOpen(sym,PERIOD_H12,hF),fC=iClose(sym,PERIOD_H12,hF);
   double sO=iOpen(sym,PERIOD_H12,hS),sC=iClose(sym,PERIOD_H12,hS);
   if(fO==0||fC==0||sO==0||sC==0) return;
   bool oA=bull?((fC>fO)&&(sC>sO)):((fC<fO)&&(sC<sO));
   bool oB=bull?(sC>fC):(sC<fC);
   if(!oA&&!oB) return;

   // Asian H4
   int ab=iBars(sym,PERIOD_H4); if(ab<8) return;
   int aF=-1;
   for(int b=ab-1;b>=0;b--)
   { datetime t=iTime(sym,PERIOD_H4,b); if(t==0||t>=pE||t<pS) continue; aF=b; break; }
   if(aF<0) return;
   double tol=InpTolPts*SymbolInfoDouble(sym,SYMBOL_POINT);
   if(bull){ if(MathAbs(iLow(sym,PERIOD_H4,aF)-pL)>tol)  return; }
   else    { if(MathAbs(iHigh(sym,PERIOD_H4,aF)-pH)>tol) return; }

   // Last H4 of PDC
   int lF=-1;
   for(int b=0;b<ab;b++)
   { datetime t=iTime(sym,PERIOD_H4,b); if(t==0)break; if(t>=pE)continue; if(t<pS)break; lF=b; break; }
   if(lF<0) return;

   g_p[idx].lvl  = bull?iLow(sym,PERIOD_H4,lF):iHigh(sym,PERIOD_H4,lF);
   g_p[idx].h4t  = iTime(sym,PERIOD_H4,lF);
   g_p[idx].pdcH = pH;
   g_p[idx].pdcL = pL;
   g_p[idx].refH = iHigh(sym,PERIOD_H4,lF);   // reference H4 range for M30 close-back
   g_p[idx].refL = iLow (sym,PERIOD_H4,lF);
   g_p[idx].st   = bull?EBUY:ESELL;
}

void LiveCheck()
{
   for(int i=0;i<PCNT;i++)
   {
      if(g_p[i].st!=EBUY&&g_p[i].st!=ESELL) continue;

      // Ensure symbol is subscribed so data stays fresh
      SymbolSelect(g_sym[i], true);

      // Use stored PDC levels — reliable, already in memory, never returns 0
      double pdcL = g_p[i].pdcL;
      double pdcH = g_p[i].pdcH;
      if(pdcL==0 || pdcH==0) continue;

      // ── KEY FIX ──────────────────────────────────────────────────
      // Check TODAY's session LOW and HIGH — not just the current bid.
      // If price dipped below pdcL and then recovered, the current bid
      // would be above pdcL and LiveCheck would miss the invalidation.
      // Using the day's candle captures any touch during the entire session.
      double todayL = iLow (g_sym[i], PERIOD_D1, 0);
      double todayH = iHigh(g_sym[i], PERIOD_D1, 0);

      // Fallback: if D1[0] not yet available, use current bid as secondary
      if(todayL == 0 || todayH == 0)
      {
         todayL = SymbolInfoDouble(g_sym[i], SYMBOL_BID);
         if(todayL==0) todayL = SymbolInfoDouble(g_sym[i], SYMBOL_LAST);
         todayH = todayL;
      }
      if(todayL==0) continue;

      if(g_p[i].st==EBUY  && todayL < pdcL){ g_p[i].st=EWBUY;  g_dirty=true; }
      if(g_p[i].st==ESELL && todayH > pdcH){ g_p[i].st=EWSELL; g_dirty=true; }
   }
}

// ═══════════════════════════════════════════════════════════════════
// ALERTS
// ═══════════════════════════════════════════════════════════════════

// Send a message via Telegram bot API
void SendTelegram(string msg)
{
   if(!InpTgEnabled || InpTgToken=="" || InpTgChatID=="") return;

   // Escape special chars for plain text (no HTML parse mode)
   string safe = msg;
   StringReplace(safe, "\"", "'");

   string url  = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "{\"chat_id\":\"" + InpTgChatID + "\",\"text\":\"" + safe + "\"}";
   char   req[];  char res[];  string hdrs;

   // Use CP_UTF8 for proper encoding
   int len = StringToCharArray(body, req, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(len <= 0) { Print("NDR: failed to encode message"); return; }
   ArrayResize(req, len);

   Print("NDR: sending to Telegram, body length=", len);

   int rc = WebRequest("POST", url,
                       "Content-Type: application/json\r\n",
                       10000, req, res, hdrs);

   Print("NDR: WebRequest rc=", rc, " lastError=", GetLastError());

   if(rc == 200)
      Print("NDR: Telegram message sent OK");
   else if(rc < 0)
      Print("NDR: WebRequest FAILED — error ", GetLastError(),
            " — go to MT5 Tools > Options > Expert Advisors > Allow WebRequest > add https://api.telegram.org");
   else
      Print("NDR: HTTP error code=", rc, " response=", CharArrayToString(res));
}

// Send a message via CallMeBot WhatsApp API
void SendWhatsApp(string msg)
{
   if(!InpWaEnabled || InpWaPhone=="" || InpWaApiKey=="") return;

   // URL-encode spaces and basic chars
   string enc = msg;
   StringReplace(enc, " ", "%20");
   StringReplace(enc, "\n", "%0A");

   string url = "https://api.callmebot.com/whatsapp.php?phone=" + InpWaPhone +
                "&text=" + enc + "&apikey=" + InpWaApiKey;
   char req[]; char res[]; string hdrs;

   int rc = WebRequest("GET", url, "", 5000, req, res, hdrs);
   if(rc < 0)
      Print("WhatsApp WebRequest error: ", GetLastError(),
            " — add https://api.callmebot.com to MT5 allowed URLs");
}

// Send to both channels
void SendAlert(string msg)
{
   SendTelegram(msg);
   SendWhatsApp(msg);
   Print("NDR Alert: ", msg);
}

// Day-open summary of all valid BUY/SELL pairs
void SendDailySummary()
{
   if(!InpTgEnabled && !InpWaEnabled) return;

   string buys="", sells="";
   for(int i=0;i<PCNT;i++)
   {
      if(g_p[i].st==EBUY)
      {
         int dg=(int)SymbolInfoInteger(g_p[i].sym,SYMBOL_DIGITS);
         buys += "  " + g_p[i].sym + " @ " + DoubleToString(g_p[i].lvl,dg) + "\n";
      }
      else if(g_p[i].st==ESELL)
      {
         int dg=(int)SymbolInfoInteger(g_p[i].sym,SYMBOL_DIGITS);
         sells += "  " + g_p[i].sym + " @ " + DoubleToString(g_p[i].lvl,dg) + "\n";
      }
      g_prevSt[i] = g_p[i].st;   // sync prev state after summary
   }

   string msg = "NDR SCANNER — Daily Setup\n";
   msg += TimeToString(TimeCurrent(), TIME_DATE) + "\n\n";
   msg += buys==""  ? "BUYS:  none\n"  : "BUYS:\n"  + buys;
   msg += sells=="" ? "SELLS: none\n"  : "SELLS:\n" + sells;

   SendAlert(msg);
}

// Intraday: alert only when a pair's status changes
void CheckAlerts()
{
   if(!InpTgEnabled && !InpWaEnabled) return;

   for(int i=0;i<PCNT;i++)
   {
      if(g_p[i].st == g_prevSt[i]) continue;   // no change

      string msg = "";
      int dg = (int)SymbolInfoInteger(g_p[i].sym, SYMBOL_DIGITS);

      if((g_prevSt[i]==EINV || g_prevSt[i]==EWBUY || g_prevSt[i]==EWSELL)
          && g_p[i].st==EBUY)
         msg = "NEW BUY SETUP\n" + g_p[i].sym +
               "\nLevel: " + DoubleToString(g_p[i].lvl,dg);

      else if((g_prevSt[i]==EINV || g_prevSt[i]==EWBUY || g_prevSt[i]==EWSELL)
               && g_p[i].st==ESELL)
         msg = "NEW SELL SETUP\n" + g_p[i].sym +
               "\nLevel: " + DoubleToString(g_p[i].lvl,dg);

      else if(g_p[i].st==EWBUY)
         msg = "BUY INVALIDATED\n" + g_p[i].sym + " — PDC Low broken";

      else if(g_p[i].st==EWSELL)
         msg = "SELL INVALIDATED\n" + g_p[i].sym + " — PDC High broken";

      if(msg != "") SendAlert(msg);

      g_prevSt[i] = g_p[i].st;
   }
}

// ═══════════════════════════════════════════════════════════════════
// M30 ENTRY ARROW
// Fires when: prev M30 opposite direction + current M30 pierces the
// Setup 1 level AND closes back inside the reference H4 range
// BUY:  bearish M30 → bullish M30 low < level, close inside ref range
// SELL: bullish M30 → bearish M30 high > level, close inside ref range
// ═══════════════════════════════════════════════════════════════════
void CheckM30Entry()
{
   // Only check for current chart symbol
   int symIdx = -1;
   for(int i=0;i<PCNT;i++)
   {
      if(g_p[i].sym == _Symbol) { symIdx=i; break; }
   }
   if(symIdx < 0) return;
   if(g_p[symIdx].st != EBUY && g_p[symIdx].st != ESELL) return;
   if(g_p[symIdx].lvl == 0) return;

   // Check if a new M30 candle has closed
   datetime m30Time = iTime(_Symbol, PERIOD_M30, 1);
   if(m30Time == 0 || m30Time == g_lastM30) return;
   g_lastM30 = m30Time;

   double m30O = iOpen (_Symbol, PERIOD_M30, 1);
   double m30H = iHigh (_Symbol, PERIOD_M30, 1);
   double m30L = iLow  (_Symbol, PERIOD_M30, 1);
   double m30C = iClose(_Symbol, PERIOD_M30, 1);
   if(m30O==0||m30H==0||m30L==0||m30C==0) return;

   bool curBull = (m30C > m30O);
   bool curBear = (m30C < m30O);

   if(g_prevM30Set)
   {
      double lvl  = g_p[symIdx].lvl;
      double refH = g_p[symIdx].refH;
      double refL = g_p[symIdx].refL;
      bool   bull = (g_p[symIdx].st == EBUY);
      bool   fire = false;

      if(bull && !g_prevM30Bull && curBull)
      {
         // BUY: prev bearish → cur bullish, wick below level, close back inside ref
         if(m30L < lvl && m30C >= refL && m30C <= refH) fire = true;
      }
      else if(!bull && g_prevM30Bull && curBear)
      {
         // SELL: prev bullish → cur bearish, wick above level, close back inside ref
         if(m30H > lvl && m30C >= refL && m30C <= refH) fire = true;
      }

      if(fire)
      {
         g_arrowSeq++;
         color  clr = bull ? InpCBuy : InpCSell;

         // Arrow — use APFX so Draw() never wipes it
         string nm  = APFX + "ARW" + IntegerToString(g_arrowSeq);
         double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double gap = (m30H - m30L) > 0 ? (m30H - m30L) : pt * 50;

         // BUY: arrow below candle low  | SELL: arrow above candle high
         double anchor = bull ? m30L - gap : m30H + gap;
         ENUM_OBJECT arw = bull ? OBJ_ARROW_UP : OBJ_ARROW_DOWN;

         ObjectCreate(0, nm, arw, 0, m30Time, anchor);
         ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH,      4);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     false);
         ObjectSetInteger(0, nm, OBJPROP_ZORDER,     100);

         // Label
         string lnm = APFX + "ARWTXT" + IntegerToString(g_arrowSeq);
         string lbl = bull ? "▲ BUY" : "▼ SELL";
         ObjectCreate(0, lnm, OBJ_TEXT, 0, m30Time, anchor);
         ObjectSetString (0, lnm, OBJPROP_TEXT,       lbl);
         ObjectSetInteger(0, lnm, OBJPROP_COLOR,      clr);
         ObjectSetString (0, lnm, OBJPROP_FONT,       "Arial Bold");
         ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,   10);
         ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lnm, OBJPROP_ZORDER,     100);

         // Send Telegram alert
         int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         string dir = bull ? "BUY" : "SELL";
         string alertMsg = "ENTRY SIGNAL\n" + _Symbol + " " + dir +
                           "\nLevel: " + DoubleToString(lvl, dg) +
                           "\nM30 manipulation confirmed";
         SendAlert(alertMsg);

         ChartRedraw();
      }
   }

   // Roll forward M30 state
   if(curBull || curBear)
   {
      g_prevM30Bull = curBull;
      g_prevM30Set  = true;
   }
}

// ═══════════════════════════════════════════════════════════════════
// DRAW PANEL
//
// Layout (all values in pixels from top-left of panel):
//
//   InpX, InpY ┌─────────────────────────────────────────────────┐
//              │  [PAIR col]  [DIR col]    [LEVEL col]           │  ← left col
//              │  [PAIR col]  [DIR col]    [LEVEL col]           │  ← right col
//              │  ...                                            │
//              └─────────────────────────────────────────────────┘
//
//   Left  col x  = InpX + InpXSym          (pair labels)
//   Right col x  = InpX + InpColW + InpXSym
//
//   Within each column:
//     PAIR  at col_x + InpXSym  (= col_x, since InpXSym is the base)
//     DIR   at col_x + InpXDir
//     LEVEL at col_x + InpXLvl
//
//   Each of the 3 fields is a SEPARATE OBJ_LABEL so they can never
//   touch each other — their x positions are explicit and independent.
// ═══════════════════════════════════════════════════════════════════
void Draw()
{
   ObjectsDeleteAll(0, PFX);

   string font  = "Arial Bold";
   int    rh    = InpRowH;
   int    half  = PCNT/2;      // 21 rows per column
   int    pad   = 8;

   // Left column base x,  right column base x
   int lx = InpX;
   int rx = InpX + InpColW;

   // Panel dimensions
   int panW = InpColW * 2 + pad;
   int panH = (half + 3) * rh + pad * 2;   // title + header + divider + 21 rows

   // ── Background ───────────────────────────────────────────────
   MkBox("BG", InpX - pad, InpY - pad, panW + pad*2, panH + pad*2);

   int y0 = InpY;

   // ── Titles ───────────────────────────────────────────────────
   MkLbl("TL", "NDR SCANNER", lx + InpXSym, y0, InpCTitle, font, InpFontSz+1);
   MkLbl("TR", "NDR SCANNER", rx + InpXSym, y0, InpCTitle, font, InpFontSz+1);

   // ── Column headers ───────────────────────────────────────────
   int yH = y0 + rh;
   MkLbl("HL_S", "PAIR",  lx+InpXSym, yH, InpCTitle, font, InpFontSz);
   MkLbl("HL_D", "DIR",   lx+InpXDir, yH, InpCTitle, font, InpFontSz);
   MkLbl("HL_L", "LEVEL", lx+InpXLvl, yH, InpCTitle, font, InpFontSz);
   MkLbl("HR_S", "PAIR",  rx+InpXSym, yH, InpCTitle, font, InpFontSz);
   MkLbl("HR_D", "DIR",   rx+InpXDir, yH, InpCTitle, font, InpFontSz);
   MkLbl("HR_L", "LEVEL", rx+InpXLvl, yH, InpCTitle, font, InpFontSz);

   // ── Dividers ─────────────────────────────────────────────────
   int yD = y0 + rh * 2;
   MkLbl("DL", "──────────────────────────", lx+InpXSym, yD, InpCTitle, font, InpFontSz-2);
   MkLbl("DR", "──────────────────────────", rx+InpXSym, yD, InpCTitle, font, InpFontSz-2);

   // ── Data rows ────────────────────────────────────────────────
   for(int i = 0; i < PCNT; i++)
   {
      if(InpValidOnly && g_p[i].st==EINV) continue;

      bool  right = (i >= half);
      int   slot  = right ? (i - half) : i;
      int   cx    = right ? rx : lx;              // this row's column base x
      int   ry    = y0 + (slot + 3) * rh;         // +3 = title + header + divider rows

      // Determine colour and direction text
      color  cl;
      string ds;
      switch(g_p[i].st)
      {
         case EBUY:   cl=InpCBuy;  ds="BUY";      break;
         case ESELL:  cl=InpCSell; ds="SELL";     break;
         case EWBUY:  cl=InpCWas;  ds="BUY-INV";  break;
         case EWSELL: cl=InpCWas;  ds="SELL-INV"; break;
         default:     cl=InpCInv;  ds="--";        break;
      }

      // Level — only show for active BUY / SELL
      string lv = " ";
      if(g_p[i].lvl > 0.0 && (g_p[i].st==EBUY || g_p[i].st==ESELL))
      {
         int dg = (int)SymbolInfoInteger(g_p[i].sym, SYMBOL_DIGITS);
         lv = DoubleToString(g_p[i].lvl, dg);
      }

      // Three labels, each at its own explicit x — they are physically
      // independent and cannot touch each other
      string id = IntegerToString(i);
      MkLbl("S"+id, g_p[i].sym, cx + InpXSym, ry, cl, font, InpFontSz);
      MkLbl("D"+id, ds,          cx + InpXDir, ry, cl, font, InpFontSz);
      MkLbl("L"+id, lv,          cx + InpXLvl, ry, cl, font, InpFontSz);
   }

   ChartRedraw();
}

// ═══════════════════════════════════════════════════════════════════
// CHART LINES — Setup 1 level + Invalidation level
//
// Setup 1 line  : blue/red dashed  — where price must manipulate
// Invalidation  : orange solid     — if price CROSSES this, setup is dead
//   Bullish PDC → invalidation line at PREVIOUS DAY LOW
//   Bearish PDC → invalidation line at PREVIOUS DAY HIGH
// ═══════════════════════════════════════════════════════════════════
void DrawLine()
{
   // Remove both lines first
   ObjectDelete(0, PFX+"LINE");
   ObjectDelete(0, PFX+"LINETXT");
   ObjectDelete(0, PFX+"INVLINE");
   ObjectDelete(0, PFX+"INVTXT");
   if(!InpDrawLine) return;

   for(int i=0; i<PCNT; i++)
   {
      if(g_p[i].sym != _Symbol)               continue;
      if(g_p[i].st!=EBUY && g_p[i].st!=ESELL) return;
      if(g_p[i].lvl == 0)                      return;

      bool     bull = (g_p[i].st == EBUY);
      color    cl   = bull ? InpCBuy : InpCSell;
      double   lv   = g_p[i].lvl;
      datetime dS   = iTime(_Symbol,PERIOD_D1,0);
      datetime dE   = dS + 86400;
      int      dg   = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

      // ── Setup 1 manipulation level line (dashed, blue/red) ────
      DrawBoundedLine(PFX+"LINE", dS, dE, lv, cl, STYLE_DASH, InpLineW);

      string dir = bull ? "BUY" : "SELL";
      DrawTextLabel(PFX+"LINETXT", dS, lv,
                    " S1 " + dir + "  " + DoubleToString(lv,dg),
                    cl);

      // ── Invalidation level line (solid orange) ────────────────
      // Bullish: line at PDC low  — cross below = invalid
      // Bearish: line at PDC high — cross above = invalid
      double invLv = bull ? g_p[i].pdcL : g_p[i].pdcH;
      if(invLv > 0)
      {
         DrawBoundedLine(PFX+"INVLINE", dS, dE, invLv, InpCInvLine, STYLE_SOLID, 2);

         string invLbl = bull
            ? " PDC LOW  — cross below = BUYS INVALID"
            : " PDC HIGH — cross above = SELLS INVALID";
         DrawTextLabel(PFX+"INVTXT", dS, invLv, invLbl, InpCInvLine);
      }

      ChartRedraw();
      return;
   }
}

// Draw a bounded horizontal segment (no rays, today only)
void DrawBoundedLine(string nm, datetime t1, datetime t2,
                     double price, color cl, ENUM_LINE_STYLE sty, int wid)
{
   ObjectDelete(0, nm);
   ObjectCreate(0,nm,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,nm,OBJPROP_TIME,  0,t1);
   ObjectSetDouble (0,nm,OBJPROP_PRICE, 0,price);
   ObjectSetInteger(0,nm,OBJPROP_TIME,  1,t2);
   ObjectSetDouble (0,nm,OBJPROP_PRICE, 1,price);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0,nm,OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,     cl);
   ObjectSetInteger(0,nm,OBJPROP_STYLE,     sty);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,     wid);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,    true);
}

void DrawTextLabel(string nm, datetime t, double price, string txt, color cl)
{
   ObjectDelete(0, nm);
   ObjectCreate(0,nm,OBJ_TEXT,0,t,price);
   ObjectSetString (0,nm,OBJPROP_TEXT,       txt);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,      cl);
   ObjectSetString (0,nm,OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,     true);
}

// ═══════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════
void MkBox(string id,int x,int y,int w,int h)
{
   string nm=PFX+id;
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0,nm,OBJPROP_XSIZE,       w);
   ObjectSetInteger(0,nm,OBJPROP_YSIZE,       h);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,     InpCBg);
   ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,       InpCBorder);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,      0);
}

void MkLbl(string id,string txt,int x,int y,color cl,string font,int fs)
{
   string nm=PFX+id;
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetString (0,nm,OBJPROP_TEXT,        txt);
   ObjectSetString (0,nm,OBJPROP_FONT,        font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,    fs);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,       cl);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0,nm,OBJPROP_HIDDEN,      true);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,      10);
}
