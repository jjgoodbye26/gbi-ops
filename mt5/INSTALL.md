# NDR Dashboard — MT5 Install & Default Template Setup

This gets `NDR_Dashboard2.mq5` compiled, on your chart, and loading automatically
on every new chart you open (the "default template").

## 1. Put the file into MT5

1. Open MetaTrader 5.
2. Go to **File → Open Data Folder**. A Windows Explorer window opens.
3. Navigate into **MQL5 → Indicators**.
4. Copy `NDR_Dashboard2.mq5` into that folder.

## 2. Compile it

1. Back in MT5, press **F4** (or Tools → MetaQuotes Language Editor) to open MetaEditor.
2. In the Navigator panel on the left, find **Indicators → NDR_Dashboard2.mq5** and double-click it.
3. Press **F7** (Compile). The log at the bottom should say **0 errors, 0 warnings**
   and produce `NDR_Dashboard2.ex5`.

## 3. Allow the alert URLs (Telegram / WhatsApp)

The indicator sends alerts via WebRequest, which MT5 blocks by default:

1. In MT5: **Tools → Options → Expert Advisors** tab.
2. Tick **"Allow WebRequest for listed URL"** and add:
   - `https://api.telegram.org`
   - `https://api.callmebot.com` (only if you use WhatsApp alerts)
3. Click OK.

## 4. Attach it to a chart and enter your keys

1. Open the chart you trade from (e.g. your main pair, M30 is what the entry
   arrows are built around).
2. In the MT5 Navigator (Ctrl+N), under **Indicators → Custom**, drag
   **NDR_Dashboard2** onto the chart.
3. In the inputs dialog that pops up, under **Telegram alerts**, enter your
   **Bot token** and **Chat ID**. (They are intentionally NOT stored in this
   file — never commit live tokens to git.)
4. Adjust panel position/colors if you like, then OK. The NDR SCANNER panel
   should appear.

## 5. Save it as your DEFAULT template

A "template" in MT5 is the saved chart setup (indicators + settings + colors).
Naming it `Default` makes every **new** chart open with it automatically:

1. With the chart set up exactly how you want, right-click the chart →
   **Templates → Save Template…**
2. Name it exactly: **`Default`** (so it saves as `Default.tpl`) and save.
3. Done — every new chart you open now loads the NDR Dashboard automatically.

To apply it to charts that are already open: right-click each chart →
**Templates → Default**.

## Notes

- The dashboard scans all 42 symbols in its list regardless of which chart it's
  on, but the **chart line, invalidation line, and M30 entry arrows only draw
  for the chart's own symbol** — so keep it on the symbol(s) you actually trade.
- Your broker's symbol names must match the list in the file (e.g. some brokers
  use `US30.cash` or `GER40` instead of `US30` / `DE40`). Symbols that don't
  match simply show `--` on the panel; edit the `g_sym` list in the .mq5 and
  recompile if needed.
- If Telegram alerts don't arrive, check the **Experts** tab in the MT5 Toolbox —
  the indicator prints the WebRequest result codes there.
