# XM MT5 Algo Setup

This project now contains two different runtime paths:

- `main.py`: the older BingX/crypto-oriented runtime.
- `main_mt5.py`: the MetaTrader 5 runtime for broker terminals such as XM/XMGlobal.
- `pure_mql5/UltimateSMCTraderEA.mq5`: a standalone pure-MQL5 EA with multi-strategy scoring, SMC filters, risk management, and Telegram trade snapshots.

If your goal is to run this on your XM trading server, use the MT5 path.

## What this setup gives you

- Python-driven MT5 trading runtime for XM.
- MT5 execution through the locally installed XM MetaTrader 5 terminal.
- XMTrading-side MQL5 execution mode through an EA attached to the XM charts.
- Smart-money / confluence engine using OB, FVG, BOS, CHOCH, liquidity sweeps, session flow, VWAP, and regime filters.
- Adaptive memory that learns from closed trades by reducing confidence in repeated losing contexts.
- Session memory that tracks high-volume periods and statistical golden-zone behavior.
- Scheduled news blackout using ForexFactory weekly exports plus local override files.
- Telegram operator controls for status, scans, pause/resume, news, close, and walk-forward checks.
- Walk-forward evaluation CLI using the same hybrid strategy stack as live trading.

## XM deployment architecture

For XM, the intended flow is:

1. XM MetaTrader 5 terminal stays installed and logged in on the Windows VPS.
2. `UltimateBridgeEA.mq5` is attached inside the XMTrading MT5 app on each symbol chart you want to trade.
3. Python connects to that terminal through the `MetaTrader5` package for market/account reads.
4. `main_mt5.py` scores the setup and writes command files for the MQL5 EA.
5. The MQL5 EA inside XM MT5 executes the order from the chart side and writes the result back.
6. Telegram is used for monitoring and operator actions.

This is the recommended XM setup mode for this project.

## Main files to use

- `main_mt5.py`: live XM/MT5 runtime.
- `main_mt5_backtest.py`: walk-forward evaluator for MT5 symbols.
- `config.py`: runtime configuration and local `.env` loading.
- `.env.example`: template for production variables.
- `MT5_HYBRID_GUIDE.md`: shorter architecture note.
- `mql5/UltimateBridgeEA.mq5`: optional chart-side helper EA.
- `pure_mql5/UltimateSMCTraderEA.mq5`: pure-MQL5 trading EA if you want the strategy to run entirely inside MT5 instead of Python.
- `execution/mql5_file_bridge.py`: Python-to-MQL5 command/result bridge.
- `execution/mt5_executor.py`: MT5 data/order adapter.
- `execution/backtester.py`: walk-forward engine.

## Pure MQL5 path

If you do not want Python running continuously on the VPS, you can use `pure_mql5/UltimateSMCTraderEA.mq5` instead of `main_mt5.py`.

That EA includes:

- MACD, MAMA-style adaptive signal scoring, PSAR, CCI, MFI, RSI, and Stochastic filters.
- Candlestick pattern logic such as engulfing, harami, piercing line, dark cloud, hammer, morning star, three white soldiers, and three black crows.
- SMC-style bias, BOS, liquidity sweep, FVG, order-block style confirmation, and Fibonacci premium/discount checks.
- ATR-based SL/TP, risk-based lot sizing, break-even, ATR trailing, and partial profit handling.
- Telegram text and chart screenshot delivery for trade entries.
- Built-in economic-calendar blackout using the MT5 calendar feed.

For Telegram from the pure-MQL5 EA, add `https://api.telegram.org` to `Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL`.

## Prerequisites

You need all of the following on your Windows VPS:

1. XM MetaTrader 5 terminal installed.
2. XM trading account credentials.
3. Python 3.10+.
4. Your VPS user session kept alive after RDP disconnect.
5. Telegram bot token and Telegram chat ID.

## Step 1: Install and prepare XM MetaTrader 5

1. Install the XM or XMGlobal MT5 terminal on the VPS.
2. Open MT5 and log in to your trading account.
3. Confirm the terminal shows live prices.
4. Turn on the global `Algo Trading` button in MT5 so it is enabled.
5. Go to `Tools -> Options -> Expert Advisors` and make sure algorithmic trading is allowed.
6. Keep MT5 logged in under the same Windows user account that will run Python.

Important:

- Do not rely on a local desktop PC for this. The Python runtime and XM MT5 must be on the same VPS.
- Disconnect RDP when finished; do not log off the Windows user session unless you want the trading stack to stop.

## Step 2: Find the correct XM terminal path

The runtime needs the path to the XM `terminal64.exe` file.

Typical examples:

- `C:\Program Files\XM MT5\terminal64.exe`
- `C:\Program Files\MetaTrader 5\terminal64.exe`
- `C:\Users\<your-user>\AppData\Roaming\MetaQuotes\Terminal\...\terminal64.exe`

If you are not sure:

1. Right-click the MT5 shortcut.
2. Open `Properties`.
3. Copy the `Target` path.

Put that exact path into `MT5_PATH` in `.env`.

## Step 3: Python environment setup

From the project folder:

```powershell
cd C:\Users\syedmuqt\Downloads\smc_bot_v3_unzipped\smc_bot_v3
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If Python is already installed in your current VPS environment, just activate the right virtual environment and run the install command.

## Step 4: Configure the local `.env`

This project now auto-loads a local `.env` file from the project root through `config.py`.

The local Telegram values have already been integrated into `.env` on this machine.

You still need to fill in the MT5/XM values before running live:

```env
MT5_ENABLED=true
MT5_PATH=C:\Program Files\XM MT5\terminal64.exe
MT5_LOGIN=YOUR_XM_ACCOUNT_NUMBER
MT5_PASSWORD=YOUR_XM_PASSWORD
MT5_SERVER=YOUR_XM_SERVER_NAME
MT5_EXECUTION_MODE=mql5_bridge
MT5_BRIDGE_FOLDER=UltimateHybrid
MT5_COMMON_FILES_DIR=
MT5_BRIDGE_TIMEOUT_SECONDS=12
MT5_BRIDGE_POLL_INTERVAL_MS=200
MT5_SYMBOLS=EURUSD,GBPUSD,USDJPY,XAUUSD,BTCUSD,ETHUSD,USOIL
MT5_TIMEFRAMES=5m,15m,1h,4h
MT5_SCAN_INTERVAL_SECONDS=20
MT5_BAR_COUNT=500

WALKFORWARD_BAR_COUNT=2500
WALKFORWARD_TRAIN_BARS=288
WALKFORWARD_TEST_BARS=96
WALKFORWARD_STEP_BARS=96
WALKFORWARD_MAX_HOLD_BARS=96

MT5_MAGIC=3133701
MT5_DEVIATION_POINTS=20

NEWS_EVENTS_FILE=data/news_events.json
NEWS_CACHE_FILE=data/news_events_cache.json
NEWS_AUTO_SYNC=true
NEWS_REFRESH_MINUTES=30
NEWS_PROVIDER_URLS=https://nfs.faireconomy.media/ff_calendar_thisweek.json,https://nfs.faireconomy.media/ff_calendar_thisweek.csv

RUNTIME_STATE_DIR=data/runtime
TRADE_JOURNAL_FILE=data/runtime/trade_journal.json
```

Notes:

- `MT5_LOGIN` should be your XM account login number.
- `MT5_SERVER` must match the server shown by XM in the MT5 login dialog.
- `MT5_SYMBOLS` should match the exact symbols your XM terminal exposes.
- `MT5_EXECUTION_MODE=mql5_bridge` tells Python to send orders to the MQL5 EA running inside XMTrading MT5.
- `MT5_COMMON_FILES_DIR` can stay empty in most Windows MT5 installs because the default common-files path is auto-detected.
- The runtime now auto-applies different profiles for FX, Gold, BTC, ETH, and Oil so risk, stop sizing, spread tolerance, and exit sensitivity are not identical across all instruments.

## Step 4B: XMTrading MQL5 bridge mode

This is the missing XM-specific part and should be treated as required when `MT5_EXECUTION_MODE=mql5_bridge` is used.

You must attach the MQL5 bridge EA inside the XMTrading terminal itself.

How it works:

1. Python writes `command_<symbol>.csv` into the MT5 common-files bridge folder.
2. `UltimateBridgeEA.mq5` running on the XM chart reads that command.
3. The EA executes the trade from inside XMTrading MT5.
4. The EA writes `result_<request_id>.csv` back for Python to consume.
5. The EA also writes `heartbeat_<symbol>.csv` so Python knows the chart-side bridge is alive.

If the EA is not attached to a symbol chart, Python will reject that symbol with a `bridge_not_ready` reason.

## Step 5: Configure symbols for XM correctly

Do not assume XM uses the same symbol names as another broker.

Examples:

- Some brokers expose gold as `XAUUSD`, others as `GOLD`.
- Some brokers expose crypto CFDs with suffixes.
- Some brokers append account-type suffixes to FX pairs.

Before running live:

1. Open the XM MT5 terminal.
2. Open `Market Watch`.
3. Copy the exact symbol names from XM.
4. Update `MT5_SYMBOLS` in `.env`.

## Step 6: News configuration

There are two supported news sources in this setup:

1. Remote ForexFactory weekly feeds.
2. Local manual override file at `data/news_events.json`.

The runtime automatically syncs remote scheduled events from:

- `https://nfs.faireconomy.media/ff_calendar_thisweek.json`
- `https://nfs.faireconomy.media/ff_calendar_thisweek.csv`

If you want to add your own manual high-impact events:

1. Copy `data/news_events.example.json` to `data/news_events.json`.
2. Add the events you care about.

Example:

```json
{
  "events": [
    {
      "id": "fed-rate-decision",
      "timestamp": "2026-05-22T18:00:00+00:00",
      "currency": "USD",
      "title": "Fed Rate Decision",
      "impact": "high",
      "source": "manual"
    }
  ]
}
```

## Step 7: MQL5 bridge EA setup inside XMTrading MT5

If you are using `MT5_EXECUTION_MODE=mql5_bridge`, this step is required.

Do this inside the XMTrading MT5 application:

1. Open MT5.
2. Click `File -> Open Data Folder`.
3. Open `MQL5\Experts`.
4. Copy `mql5\UltimateBridgeEA.mq5` into that folder.
5. Open MetaEditor.
6. Compile `UltimateBridgeEA.mq5`.
7. Open one chart for each symbol in `MT5_SYMBOLS`.
8. Attach `UltimateBridgeEA` to each of those charts.
9. Make sure the EA input `BridgeFolder` matches `MT5_BRIDGE_FOLDER` from `.env`.
10. Keep those charts open while the runtime is active.

Recommended XM chart attachments:

- Attach one EA to `EURUSD` chart.
- Attach one EA to `XAUUSD` chart.
- Attach one EA to each additional traded symbol chart.

You do not need to load the full strategy inside MQL5. The EA is the XM-side execution and control bridge, while Python remains the strategy brain.

## Step 8: Run a walk-forward evaluation first

Before live trading on XM, run the walk-forward evaluator.

Example:

```powershell
cd C:\Users\syedmuqt\Downloads\smc_bot_v3_unzipped\smc_bot_v3
.\.venv\Scripts\Activate.ps1
python main_mt5_backtest.py EURUSD --bar-count 2500 --train-bars 288 --test-bars 96 --step-bars 96
```

Recommended first tests:

1. `EURUSD`
2. `XAUUSD`
3. `GBPUSD`

Do not move to live just because the backtest runs. Use it to confirm:

- Symbol connectivity works.
- XM history is available.
- The strategy actually generates trades on the symbol.
- The walk-forward stats are acceptable.

## Step 9: Start the live MT5 runtime

Once the XM terminal is logged in and `.env` is filled correctly:

```powershell
cd C:\Users\syedmuqt\Downloads\smc_bot_v3_unzipped\smc_bot_v3
.\.venv\Scripts\Activate.ps1
python main_mt5.py
```

On startup, the runtime will:

1. Connect to the XM MT5 terminal.
2. Read account/equity state.
3. Sync scheduled news.
4. Check whether the MQL5 bridge heartbeat exists for each traded symbol if bridge mode is enabled.
5. Start scanning configured symbols.
6. Start Telegram operator polling if token/chat settings are present.

## Telegram commands available in live mode

Once `main_mt5.py` is running, your Telegram bot can control the runtime.

Available commands:

- `/status`
- `/positions`
- `/scan`
- `/pause`
- `/resume`
- `/news [EURUSD]`
- `/syncnews`
- `/rejections`
- `/close EURUSD`
- `/close 12345678`
- `/closeall`
- `/walkforward EURUSD`

Use `/status` first to confirm the Telegram integration is working.

## Recommended first live rollout on XM

Use a strict rollout instead of jumping straight to full automation.

Phase 1:

1. Run on demo account.
2. Use only 1 or 2 symbols.
3. Keep scan interval and defaults as-is.
4. Check Telegram responses.
5. Let it run for several sessions.

Phase 2:

1. Run on small live size.
2. Keep `risk_per_trade_pct` conservative.
3. Monitor guard rejections and trade quality.
4. Review `data/runtime/trade_journal.json`.

Phase 3:

1. Expand symbol list carefully.
2. Tune risk and walk-forward windows based on actual performance.

## Auto-start on Windows VPS

For a real VPS setup, do not rely on manually starting the bot after every reboot.

Use Windows Task Scheduler:

1. Open `Task Scheduler`.
2. Create a new task.
3. Trigger: `At log on` of your trading user.
4. Action:

```text
Program/script:
powershell.exe

Arguments:
-ExecutionPolicy Bypass -File "C:\Users\syedmuqt\Downloads\smc_bot_v3_unzipped\smc_bot_v3\start_mt5_runtime.ps1"
```

Then create a simple launcher script like this:

```powershell
Set-Location "C:\Users\syedmuqt\Downloads\smc_bot_v3_unzipped\smc_bot_v3"
& ".\.venv\Scripts\Activate.ps1"
python main_mt5.py
```

You can also use NSSM if you prefer running it as a service, but Task Scheduler is usually simpler on a Windows trading VPS.

## Files and data created during runtime

Expect these files to be used or generated:

- `.env`: local secrets and runtime config.
- `logs\mt5_hybrid.log`: runtime logs.
- `data\runtime\trade_journal.json`: tracked trades and outcomes.
- `data\runtime\adaptive_memory.json`: expectancy memory.
- `data\runtime\session_memory.json`: session/golden-zone memory.
- `data\news_events_cache.json`: remote news cache.
- `data\news_events.json`: your local manual event overrides.
- `%APPDATA%\MetaQuotes\Terminal\Common\Files\UltimateHybrid\heartbeat_<symbol>.csv`: bridge heartbeat from XM MT5.
- `%APPDATA%\MetaQuotes\Terminal\Common\Files\UltimateHybrid\command_<symbol>.csv`: order instruction sent from Python to the chart EA.
- `%APPDATA%\MetaQuotes\Terminal\Common\Files\UltimateHybrid\result_<request_id>.csv`: execution response from the MQL5 EA.

## Troubleshooting

### MT5 connection fails

Check:

1. MT5 terminal is open.
2. MT5 is logged in.
3. `MT5_PATH` points to the correct XM terminal.
4. `MT5_LOGIN`, `MT5_PASSWORD`, and `MT5_SERVER` are correct.

### No trades are placed

Check:

1. `Algo Trading` is enabled in MT5.
2. The symbols in `.env` exactly match XM symbols.
3. `UltimateBridgeEA` is attached to each traded XM chart.
4. The bridge folder name in the EA matches `MT5_BRIDGE_FOLDER` in `.env`.
5. News blackout is not active.
6. Portfolio guard is not rejecting setups due to spread, margin, or correlated exposure.
7. The strategy is actually generating signals for that symbol and timeframe.

Use:

- `/status`
- `/rejections`
- `/news EURUSD`
- `/walkforward EURUSD`

### Telegram is not responding

Check:

1. `main_mt5.py` is running.
2. The bot token is valid.
3. The chat ID is correct.
4. The bot has already been started at least once from Telegram.

### Bridge not ready

If `/rejections` shows `bridge_not_ready:*`, check:

1. The MQL5 EA is attached to the correct XM symbol chart.
2. The chart is still open.
3. The EA input `BridgeFolder` matches `.env`.
4. The MT5 user session is still active on the VPS.
5. The common-files path has not been overridden incorrectly.

### Walk-forward returns zero trades

That does not automatically mean the code is broken.

Possible causes:

1. The symbol history is too short.
2. The strategy filters are too strict for the selected symbol.
3. XM symbol naming or bar history is inconsistent.
4. The market regime in the tested window did not satisfy the confluence rules.

## Security note

Your Telegram settings are stored locally in `.env`, and `.env` is now ignored by `.gitignore`.

Because the bot token was shared in chat, rotating that Telegram token after setup would be prudent if you want to treat it as uncompromised.

## Live-trading note

This project is designed to give you a structured MT5/XM automation stack, not guaranteed outcomes.

Use demo first, then small live size, then scale only after the walk-forward and live monitoring results justify it.