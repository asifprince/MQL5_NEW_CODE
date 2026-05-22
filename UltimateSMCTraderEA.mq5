#property strict

#include <Trade/Trade.mqh>

enum SignalDirection
{
   DIR_NONE = 0,
   DIR_LONG = 1,
   DIR_SHORT = -1
};

input ulong MagicNumber = 2026052201;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES BiasTimeframe = PERIOD_H1;
input ENUM_TIMEFRAMES MacroTimeframe = PERIOD_H4;
input bool EnableLongTrades = true;
input bool EnableShortTrades = true;
input bool RestrictSessions = true;
input int LondonSessionStart = 7;
input int LondonSessionEnd = 16;
input int NewYorkSessionStart = 12;
input int NewYorkSessionEnd = 21;
input int MaxManagedPositions = 3;
input double RiskPerTradePercent = 0.75;
input double MaxDailyLossPercent = 3.0;
input double MaxSpreadPoints = 350.0;
input int SlippagePoints = 30;
input int ATRPeriod = 14;
input double MAMAFastLimit = 0.5;
input double MAMASlowLimit = 0.05;
input bool UseExactMAMAFilter = true;
input double StopATRMultiplier = 1.8;
input double TakeATRMultiplier = 3.8;
input double RewardToRisk = 2.2;
input double TrailATRMultiplier = 1.2;
input double BreakEvenAtRR = 1.0;
input double PartialAtRR = 1.5;
input double PartialClosePercent = 0.50;
input int StructureLookback = 20;
input int LiquidityLookback = 40;
input int FibonacciLookback = 80;
input int SignalThreshold = 8;
input bool EnableNewsBlackout = true;
input bool BlockHighImpactNews = true;
input bool BlockModerateImpactNews = false;
input int NewsBlockBeforeMinutes = 25;
input int NewsBlockAfterMinutes = 20;
input string ExtraBlockedCurrencies = "";
input int ScreenshotWidth = 1440;
input int ScreenshotHeight = 900;
input string TelegramBotToken = "";
input string TelegramChatId = "";
input bool TelegramSendText = true;
input bool TelegramSendPhotoAlerts = true;
input bool TelegramSendStartupPing = true;
input bool TelegramEnableInbound = true;
input int TelegramInboundPollSeconds = 10;
input string TelegramInboundChatId = "";
input string TelegramInboundOwnerId = "";
input bool PrintVerboseReasons = true;

CTrade trade;

int macd_handle = INVALID_HANDLE;
int ama_handle = INVALID_HANDLE;
int sar_handle = INVALID_HANDLE;
int cci_handle = INVALID_HANDLE;
int mfi_handle = INVALID_HANDLE;
int rsi_handle = INVALID_HANDLE;
int stoch_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int adx_handle = INVALID_HANDLE;

datetime last_bar_time = 0;
string trade_object_prefix = "USMC_";
string last_gate_reason = "";
bool manual_trading_pause = false;
long telegram_last_update_id = 0;
string last_telegram_command = "";
datetime last_telegram_command_time = 0;

struct IndicatorSnapshot
{
   double macd_main;
   double macd_signal;
   double macd_hist;
   double mama;
   double fama;
   double mama_prev;
   double fama_prev;
   double adaptive_ma;
   double adaptive_ma_prev;
   double sar;
   double cci;
   double mfi;
   double rsi;
   double stoch_main;
   double stoch_signal;
   double atr;
   double adx;
   double plus_di;
   double minus_di;
};

struct PatternSnapshot
{
   bool bullish_engulfing;
   bool bearish_engulfing;
   bool bullish_harami;
   bool bearish_harami;
   bool piercing_line;
   bool dark_cloud_cover;
   bool hammer;
   bool hanging_man;
   bool morning_star;
   bool evening_star;
   bool doji;
   bool three_white_soldiers;
   bool three_black_crows;
};

struct SMCContext
{
   int bias;
   bool bullish_bos;
   bool bearish_bos;
   bool sweep_low;
   bool sweep_high;
   bool bullish_fvg;
   bool bearish_fvg;
   bool bullish_order_block;
   bool bearish_order_block;
   bool discount_zone;
   bool premium_zone;
   double swing_high;
   double swing_low;
   double fib_50;
   double fib_618_long;
   double fib_618_short;
};

struct TradePlan
{
   bool valid;
   int direction;
   int long_score;
   int short_score;
   double entry;
   double stop_loss;
   double take_profit;
   double volume;
   double fib_reference;
   string label;
   string reasons;
};

void AppendReason(string &reasons, const string item)
{
   if(item == "")
      return;
   if(reasons == "")
      reasons = item;
   else
      reasons += " | " + item;
}

string DirectionText(const int direction)
{
   if(direction == DIR_LONG)
      return "LONG";
   if(direction == DIR_SHORT)
      return "SHORT";
   return "NONE";
}

bool TelegramConfigured()
{
   return (TelegramBotToken != "" && TelegramChatId != "");
}

bool IsAsciiSpace(const ushort ch)
{
   return (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r');
}

string TrimText(const string text)
{
   int start = 0;
   int end = StringLen(text) - 1;
   while(start <= end && IsAsciiSpace((ushort)StringGetCharacter(text, start)))
      start++;
   while(end >= start && IsAsciiSpace((ushort)StringGetCharacter(text, end)))
      end--;
   if(start > end)
      return "";
   return StringSubstr(text, start, end - start + 1);
}

string ToLowerAscii(const string text)
{
   string result = "";
   for(int i = 0; i < StringLen(text); i++)
   {
      ushort ch = (ushort)StringGetCharacter(text, i);
      if(ch >= 'A' && ch <= 'Z')
         result += CharToString((uchar)(ch + 32));
      else
         result += StringSubstr(text, i, 1);
   }
   return result;
}

string TelegramCommandToken(const string text)
{
   string token = ToLowerAscii(TrimText(text));
   int newline_pos = StringFind(token, "\n");
   if(newline_pos >= 0)
      token = StringSubstr(token, 0, newline_pos);
   int space_pos = StringFind(token, " ");
   if(space_pos >= 0)
      token = StringSubstr(token, 0, space_pos);
   int mention_pos = StringFind(token, "@");
   if(mention_pos > 0)
      token = StringSubstr(token, 0, mention_pos);
   return token;
}

double CandleBody(const MqlRates &bar)
{
   return MathAbs(bar.close - bar.open);
}

double CandleRange(const MqlRates &bar)
{
   return MathMax(bar.high - bar.low, _Point);
}

double UpperWick(const MqlRates &bar)
{
   return bar.high - MathMax(bar.open, bar.close);
}

double LowerWick(const MqlRates &bar)
{
   return MathMin(bar.open, bar.close) - bar.low;
}

bool IsBullish(const MqlRates &bar)
{
   return bar.close > bar.open;
}

bool IsBearish(const MqlRates &bar)
{
   return bar.close < bar.open;
}

bool IsDojiBar(const MqlRates &bar)
{
   return CandleBody(bar) <= CandleRange(bar) * 0.12;
}

double HighestHigh(MqlRates &rates[], const int start_index, const int count)
{
   double highest = -DBL_MAX;
   int end_index = MathMin(ArraySize(rates) - 1, start_index + count - 1);
   for(int i = start_index; i <= end_index; i++)
      highest = MathMax(highest, rates[i].high);
   return highest;
}

double LowestLow(MqlRates &rates[], const int start_index, const int count)
{
   double lowest = DBL_MAX;
   int end_index = MathMin(ArraySize(rates) - 1, start_index + count - 1);
   for(int i = start_index; i <= end_index; i++)
      lowest = MathMin(lowest, rates[i].low);
   return lowest;
}

double AverageClose(MqlRates &rates[], const int start_index, const int count)
{
   double total = 0.0;
   int used = 0;
   int end_index = MathMin(ArraySize(rates) - 1, start_index + count - 1);
   for(int i = start_index; i <= end_index; i++)
   {
      total += rates[i].close;
      used++;
   }
   if(used == 0)
      return 0.0;
   return total / used;
}

bool LoadRates(const ENUM_TIMEFRAMES timeframe, const int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, timeframe, 0, count, rates);
   return (copied >= count);
}

bool CopyBufferValues(const int handle, const int buffer_index, const int start_shift, const int count, double &output[])
{
   ArraySetAsSeries(output, true);
   int copied = CopyBuffer(handle, buffer_index, start_shift, count, output);
   return (copied >= count);
}

double RadToDeg(const double value)
{
   return value * 180.0 / 3.14159265358979323846;
}

double SelectMAMAPrice(const MqlRates &bar)
{
   return (bar.high + bar.low + bar.close) / 3.0;
}

bool ComputeMAMASnapshot(MqlRates &rates[], double &mama, double &fama, double &mama_prev, double &fama_prev)
{
   int total = ArraySize(rates);
   if(total < 60)
      return false;

   double price[], smooth[], detrender[], q1[], i1[], ji[], jq[], i2[], q2[], re[], im[], period[], phase[], alpha[], mama_values[], fama_values[];
   ArrayResize(price, total);
   ArrayResize(smooth, total);
   ArrayResize(detrender, total);
   ArrayResize(q1, total);
   ArrayResize(i1, total);
   ArrayResize(ji, total);
   ArrayResize(jq, total);
   ArrayResize(i2, total);
   ArrayResize(q2, total);
   ArrayResize(re, total);
   ArrayResize(im, total);
   ArrayResize(period, total);
   ArrayResize(phase, total);
   ArrayResize(alpha, total);
   ArrayResize(mama_values, total);
   ArrayResize(fama_values, total);

   for(int i = 0; i < total; i++)
   {
      MqlRates bar = rates[total - 1 - i];
      price[i] = SelectMAMAPrice(bar);
      smooth[i] = price[i];
      detrender[i] = 0.0;
      q1[i] = 0.0;
      i1[i] = 0.0;
      ji[i] = 0.0;
      jq[i] = 0.0;
      i2[i] = 0.0;
      q2[i] = 0.0;
      re[i] = 0.0;
      im[i] = 0.0;
      period[i] = 0.0;
      phase[i] = 0.0;
      alpha[i] = MAMAFastLimit;
      mama_values[i] = price[i];
      fama_values[i] = price[i];
   }

   for(int i = 0; i < total; i++)
   {
      if(i >= 3)
         smooth[i] = (4.0 * price[i] + 3.0 * price[i - 1] + 2.0 * price[i - 2] + price[i - 3]) / 10.0;

      double previous_period = (i > 0 && period[i - 1] > 0.0) ? period[i - 1] : 10.0;
      double adjust = 0.075 * previous_period + 0.54;

      if(i >= 6)
      {
         detrender[i] = (0.0962 * smooth[i] + 0.5769 * smooth[i - 2] - 0.5769 * smooth[i - 4] - 0.0962 * smooth[i - 6]) * adjust;
         q1[i] = (0.0962 * detrender[i] + 0.5769 * detrender[i - 2] - 0.5769 * detrender[i - 4] - 0.0962 * detrender[i - 6]) * adjust;
      }

      if(i >= 3)
         i1[i] = detrender[i - 3];

      if(i >= 6)
      {
         ji[i] = (0.0962 * i1[i] + 0.5769 * i1[i - 2] - 0.5769 * i1[i - 4] - 0.0962 * i1[i - 6]) * adjust;
         jq[i] = (0.0962 * q1[i] + 0.5769 * q1[i - 2] - 0.5769 * q1[i - 4] - 0.0962 * q1[i - 6]) * adjust;
      }

      i2[i] = i1[i] - jq[i];
      q2[i] = q1[i] + ji[i];

      if(i > 0)
      {
         i2[i] = 0.2 * i2[i] + 0.8 * i2[i - 1];
         q2[i] = 0.2 * q2[i] + 0.8 * q2[i - 1];

         double re_raw = i2[i] * i2[i - 1] + q2[i] * q2[i - 1];
         double im_raw = i2[i] * q2[i - 1] - q2[i] * i2[i - 1];
         re[i] = 0.2 * re_raw + 0.8 * re[i - 1];
         im[i] = 0.2 * im_raw + 0.8 * im[i - 1];
      }

      double current_period = previous_period;
      if(MathAbs(re[i]) > 1e-8 && MathAbs(im[i]) > 1e-8)
      {
         double angle = RadToDeg(MathArctan(im[i] / re[i]));
         if(MathAbs(angle) > 1e-6)
            current_period = 360.0 / MathAbs(angle);
      }

      if(i > 0 && period[i - 1] > 0.0)
      {
         current_period = MathMin(current_period, 1.5 * period[i - 1]);
         current_period = MathMax(current_period, 0.67 * period[i - 1]);
      }
      current_period = MathMax(6.0, MathMin(50.0, current_period));
      if(i > 0)
         current_period = 0.2 * current_period + 0.8 * period[i - 1];
      period[i] = current_period;

      double current_phase = (i > 0) ? phase[i - 1] : 0.0;
      if(MathAbs(i1[i]) > 1e-8)
         current_phase = RadToDeg(MathArctan(q1[i] / i1[i]));
      phase[i] = current_phase;

      double delta_phase = (i > 0) ? phase[i - 1] - current_phase : 1.0;
      if(delta_phase < 1.0)
         delta_phase = 1.0;

      double current_alpha = MAMAFastLimit / delta_phase;
      if(current_alpha < MAMASlowLimit)
         current_alpha = MAMASlowLimit;
      if(current_alpha > MAMAFastLimit)
         current_alpha = MAMAFastLimit;
      alpha[i] = current_alpha;

      if(i > 0)
      {
         mama_values[i] = current_alpha * price[i] + (1.0 - current_alpha) * mama_values[i - 1];
         fama_values[i] = 0.5 * current_alpha * mama_values[i] + (1.0 - 0.5 * current_alpha) * fama_values[i - 1];
      }
   }

   int closed_index = total - 2;
   int previous_index = total - 3;
   if(previous_index < 0)
      return false;

   mama = mama_values[closed_index];
   fama = fama_values[closed_index];
   mama_prev = mama_values[previous_index];
   fama_prev = fama_values[previous_index];
   return true;
}

int AddCurrencyToken(string &currencies[], const string token)
{
   if(StringLen(token) != 3)
      return ArraySize(currencies);

   for(int i = 0; i < ArraySize(currencies); i++)
   {
      if(currencies[i] == token)
         return ArraySize(currencies);
   }

   int size = ArraySize(currencies);
   ArrayResize(currencies, size + 1);
   currencies[size] = token;
   return size + 1;
}

void CollectRelevantCurrencies(string &currencies[])
{
   ArrayResize(currencies, 0);
   string symbol = _Symbol;
   string majors[] = {"USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD"};
   for(int i = 0; i < ArraySize(majors); i++)
   {
      if(StringFind(symbol, majors[i]) >= 0)
         AddCurrencyToken(currencies, majors[i]);
   }

   if(StringFind(symbol, "OIL") >= 0 || StringFind(symbol, "WTI") >= 0 || StringFind(symbol, "BRENT") >= 0 || StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "XAG") >= 0)
      AddCurrencyToken(currencies, "USD");

   string manual = ExtraBlockedCurrencies;
   int start = 0;
   while(start < StringLen(manual))
   {
      int comma = StringFind(manual, ",", start);
      string part = (comma == -1) ? StringSubstr(manual, start) : StringSubstr(manual, start, comma - start);
      while(StringLen(part) > 0 && StringGetCharacter(part, 0) == ' ')
         part = StringSubstr(part, 1);
      while(StringLen(part) > 0 && StringGetCharacter(part, StringLen(part) - 1) == ' ')
         part = StringSubstr(part, 0, StringLen(part) - 1);
      if(StringLen(part) == 3)
         AddCurrencyToken(currencies, part);
      if(comma == -1)
         break;
      start = comma + 1;
   }
}

bool CalendarImportanceBlocked(const ENUM_CALENDAR_EVENT_IMPORTANCE importance)
{
   if(importance == CALENDAR_IMPORTANCE_HIGH)
      return BlockHighImpactNews;
   if(importance == CALENDAR_IMPORTANCE_MODERATE)
      return BlockModerateImpactNews;
   return false;
}

bool CalendarNewsBlocked(string &reason)
{
   reason = "";
   if(!EnableNewsBlackout)
      return false;

   string currencies[];
   CollectRelevantCurrencies(currencies);
   if(ArraySize(currencies) == 0)
      return false;

   datetime now = TimeTradeServer();
   datetime from = now - NewsBlockAfterMinutes * 60;
   datetime to = now + NewsBlockBeforeMinutes * 60;

   for(int currency_index = 0; currency_index < ArraySize(currencies); currency_index++)
   {
      MqlCalendarValue values[];
      ResetLastError();
      int count = CalendarValueHistory(values, from, to, "", currencies[currency_index]);
      if(count <= 0)
         continue;

      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;
         if(event.type == CALENDAR_TYPE_HOLIDAY)
            continue;
         if(!CalendarImportanceBlocked(event.importance))
            continue;

         if(values[i].time >= from && values[i].time <= to)
         {
            reason = StringFormat("news blackout %s: %s", currencies[currency_index], event.name);
            return true;
         }
      }
   }
   return false;
}

bool LoadIndicators(IndicatorSnapshot &snapshot)
{
   double macd_main_values[2], macd_signal_values[2], ama_values[2], sar_values[1], cci_values[1], mfi_values[1];
   double rsi_values[1], stoch_main_values[1], stoch_signal_values[1], atr_values[1], adx_values[1], plus_di_values[1], minus_di_values[1];

   if(!CopyBufferValues(macd_handle, 0, 1, 2, macd_main_values))
      return false;
   if(!CopyBufferValues(macd_handle, 1, 1, 2, macd_signal_values))
      return false;
   if(!CopyBufferValues(ama_handle, 0, 1, 2, ama_values))
      return false;
   if(!CopyBufferValues(sar_handle, 0, 1, 1, sar_values))
      return false;
   if(!CopyBufferValues(cci_handle, 0, 1, 1, cci_values))
      return false;
   if(!CopyBufferValues(mfi_handle, 0, 1, 1, mfi_values))
      return false;
   if(!CopyBufferValues(rsi_handle, 0, 1, 1, rsi_values))
      return false;
   if(!CopyBufferValues(stoch_handle, 0, 1, 1, stoch_main_values))
      return false;
   if(!CopyBufferValues(stoch_handle, 1, 1, 1, stoch_signal_values))
      return false;
   if(!CopyBufferValues(atr_handle, 0, 1, 1, atr_values))
      return false;
   if(!CopyBufferValues(adx_handle, 0, 1, 1, adx_values))
      return false;
   if(!CopyBufferValues(adx_handle, 1, 1, 1, plus_di_values))
      return false;
   if(!CopyBufferValues(adx_handle, 2, 1, 1, minus_di_values))
      return false;

   snapshot.macd_main = macd_main_values[0];
   snapshot.macd_signal = macd_signal_values[0];
   snapshot.macd_hist = snapshot.macd_main - snapshot.macd_signal;
   snapshot.mama = 0.0;
   snapshot.fama = 0.0;
   snapshot.mama_prev = 0.0;
   snapshot.fama_prev = 0.0;
   snapshot.adaptive_ma = ama_values[0];
   snapshot.adaptive_ma_prev = ama_values[1];
   snapshot.sar = sar_values[0];
   snapshot.cci = cci_values[0];
   snapshot.mfi = mfi_values[0];
   snapshot.rsi = rsi_values[0];
   snapshot.stoch_main = stoch_main_values[0];
   snapshot.stoch_signal = stoch_signal_values[0];
   snapshot.atr = atr_values[0];
   snapshot.adx = adx_values[0];
   snapshot.plus_di = plus_di_values[0];
   snapshot.minus_di = minus_di_values[0];
   return true;
}

void ResetPatterns(PatternSnapshot &patterns)
{
   patterns.bullish_engulfing = false;
   patterns.bearish_engulfing = false;
   patterns.bullish_harami = false;
   patterns.bearish_harami = false;
   patterns.piercing_line = false;
   patterns.dark_cloud_cover = false;
   patterns.hammer = false;
   patterns.hanging_man = false;
   patterns.morning_star = false;
   patterns.evening_star = false;
   patterns.doji = false;
   patterns.three_white_soldiers = false;
   patterns.three_black_crows = false;
}

void DetectPatterns(MqlRates &rates[], PatternSnapshot &patterns)
{
   ResetPatterns(patterns);
   if(ArraySize(rates) < 6)
      return;

   MqlRates b1 = rates[1];
   MqlRates b2 = rates[2];
   MqlRates b3 = rates[3];

   patterns.doji = IsDojiBar(b1);

   patterns.bullish_engulfing = IsBearish(b2) && IsBullish(b1) && b1.open <= b2.close && b1.close >= b2.open;
   patterns.bearish_engulfing = IsBullish(b2) && IsBearish(b1) && b1.open >= b2.close && b1.close <= b2.open;

   patterns.bullish_harami = IsBearish(b2) && IsBullish(b1) && b1.open > b2.close && b1.close < b2.open;
   patterns.bearish_harami = IsBullish(b2) && IsBearish(b1) && b1.open < b2.close && b1.close > b2.open;

   double midpoint_b2 = (b2.open + b2.close) * 0.5;
   patterns.piercing_line = IsBearish(b2) && IsBullish(b1) && b1.close > midpoint_b2 && b1.close < b2.open;
   patterns.dark_cloud_cover = IsBullish(b2) && IsBearish(b1) && b1.close < midpoint_b2 && b1.close > b2.open;

   patterns.hammer = LowerWick(b1) > CandleBody(b1) * 2.0 && UpperWick(b1) < CandleBody(b1) * 0.8;
   patterns.hanging_man = patterns.hammer && IsBearish(b1);

   patterns.morning_star = IsBearish(b3) && CandleBody(b3) > CandleRange(b3) * 0.45 && IsDojiBar(b2) && IsBullish(b1) && b1.close > (b3.open + b3.close) * 0.5;
   patterns.evening_star = IsBullish(b3) && CandleBody(b3) > CandleRange(b3) * 0.45 && IsDojiBar(b2) && IsBearish(b1) && b1.close < (b3.open + b3.close) * 0.5;

   patterns.three_white_soldiers = IsBullish(rates[3]) && IsBullish(rates[2]) && IsBullish(rates[1])
      && rates[2].close > rates[3].close && rates[1].close > rates[2].close;
   patterns.three_black_crows = IsBearish(rates[3]) && IsBearish(rates[2]) && IsBearish(rates[1])
      && rates[2].close < rates[3].close && rates[1].close < rates[2].close;
}

int SimpleTrendBias(MqlRates &rates[])
{
   if(ArraySize(rates) < 40)
      return DIR_NONE;

   double fast = AverageClose(rates, 1, 8);
   double slow = AverageClose(rates, 1, 21);
   double latest_close = rates[1].close;

   if(fast > slow && latest_close > fast)
      return DIR_LONG;
   if(fast < slow && latest_close < fast)
      return DIR_SHORT;
   return DIR_NONE;
}

void BuildSMCContext(MqlRates &signal_rates[], MqlRates &bias_rates[], MqlRates &macro_rates[], SMCContext &context)
{
   context.bias = DIR_NONE;
   context.bullish_bos = false;
   context.bearish_bos = false;
   context.sweep_low = false;
   context.sweep_high = false;
   context.bullish_fvg = false;
   context.bearish_fvg = false;
   context.bullish_order_block = false;
   context.bearish_order_block = false;
   context.discount_zone = false;
   context.premium_zone = false;
   context.swing_high = 0.0;
   context.swing_low = 0.0;
   context.fib_50 = 0.0;
   context.fib_618_long = 0.0;
   context.fib_618_short = 0.0;

   int bias_tf = SimpleTrendBias(bias_rates);
   int macro_tf = SimpleTrendBias(macro_rates);
   if(bias_tf == macro_tf)
      context.bias = bias_tf;

   double prior_high = HighestHigh(signal_rates, 2, StructureLookback);
   double prior_low = LowestLow(signal_rates, 2, StructureLookback);
   context.bullish_bos = signal_rates[1].close > prior_high;
   context.bearish_bos = signal_rates[1].close < prior_low;

   double liquidity_high = HighestHigh(signal_rates, 2, LiquidityLookback);
   double liquidity_low = LowestLow(signal_rates, 2, LiquidityLookback);
   context.sweep_high = signal_rates[1].high > liquidity_high && signal_rates[1].close < liquidity_high;
   context.sweep_low = signal_rates[1].low < liquidity_low && signal_rates[1].close > liquidity_low;

   context.bullish_fvg = (signal_rates[3].high < signal_rates[1].low);
   context.bearish_fvg = (signal_rates[3].low > signal_rates[1].high);

   context.bullish_order_block = IsBearish(signal_rates[2]) && signal_rates[1].close > signal_rates[2].high;
   context.bearish_order_block = IsBullish(signal_rates[2]) && signal_rates[1].close < signal_rates[2].low;

   context.swing_high = HighestHigh(signal_rates, 1, FibonacciLookback);
   context.swing_low = LowestLow(signal_rates, 1, FibonacciLookback);
   double range = context.swing_high - context.swing_low;
   if(range > _Point)
   {
      context.fib_50 = context.swing_low + range * 0.5;
      context.fib_618_long = context.swing_high - range * 0.618;
      context.fib_618_short = context.swing_low + range * 0.618;
      context.discount_zone = signal_rates[1].close <= context.fib_50;
      context.premium_zone = signal_rates[1].close >= context.fib_50;
   }
}

double CurrentSpreadPoints()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid) / _Point;
}

bool SessionAllowed()
{
   if(!RestrictSessions)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   bool london = (dt.hour >= LondonSessionStart && dt.hour < LondonSessionEnd);
   bool new_york = (dt.hour >= NewYorkSessionStart && dt.hour < NewYorkSessionEnd);
   return (london || new_york);
}

double TodayClosedPnl()
{
   datetime day_start = StringToTime(TimeToString(TimeTradeServer(), TIME_DATE));
   if(!HistorySelect(day_start, TimeTradeServer()))
      return 0.0;

   double pnl = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != MagicNumber)
         continue;

      long entry_type = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_OUT_BY)
         continue;

      pnl += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      pnl += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      pnl += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   }
   return pnl;
}

int CountManagedPositions()
{
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         total++;
   }
   return total;
}

bool SelectManagedPositionBySymbol(ulong &ticket)
{
   ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong pos_ticket = PositionGetTicket(i);
      if(pos_ticket == 0)
         continue;
      if(!PositionSelectByTicket(pos_ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ticket = pos_ticket;
      return true;
   }
   return false;
}

double NormalizeVolume(const double volume)
{
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   double bounded = MathMax(min_volume, MathMin(max_volume, volume));
   double normalized = MathFloor(bounded / step) * step;
   int digits = 2;
   if(step < 0.1)
      digits = 3;
   if(step < 0.01)
      digits = 4;
   return NormalizeDouble(normalized, digits);
}

double CalculatePositionSize(const double entry, const double stop_loss)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double stop_distance = MathAbs(entry - stop_loss);
   if(tick_size <= 0.0 || tick_value <= 0.0 || stop_distance <= _Point)
      return 0.0;

   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPerTradePercent / 100.0;
   double loss_per_lot = (stop_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;
   return NormalizeVolume(risk_money / loss_per_lot);
}

void EnforceStopDistance(const int direction, const double entry, double &stop_loss, double &take_profit)
{
   double min_distance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(min_distance <= 0.0)
      min_distance = _Point * 10.0;

   if(direction == DIR_LONG)
   {
      if(entry - stop_loss < min_distance)
         stop_loss = entry - min_distance * 1.2;
      if(take_profit - entry < min_distance)
         take_profit = entry + min_distance * 1.2;
   }
   else if(direction == DIR_SHORT)
   {
      if(stop_loss - entry < min_distance)
         stop_loss = entry + min_distance * 1.2;
      if(entry - take_profit < min_distance)
         take_profit = entry - min_distance * 1.2;
   }

   stop_loss = NormalizeDouble(stop_loss, _Digits);
   take_profit = NormalizeDouble(take_profit, _Digits);
}

bool TradingAllowedNow()
{
   last_gate_reason = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      last_gate_reason = "algo trading disabled";
      Print("UltimateSMCTraderEA: algo trading is disabled in terminal or EA settings.");
      return false;
   }
   if(CurrentSpreadPoints() > MaxSpreadPoints)
   {
      last_gate_reason = "spread too wide";
      return false;
   }
   if(!SessionAllowed())
   {
      last_gate_reason = "outside session window";
      return false;
   }
   if(CountManagedPositions() >= MaxManagedPositions)
   {
      last_gate_reason = "max managed positions reached";
      return false;
   }

   double daily_loss_limit = AccountInfoDouble(ACCOUNT_BALANCE) * MaxDailyLossPercent / 100.0;
   if(TodayClosedPnl() <= -daily_loss_limit)
   {
      last_gate_reason = "daily loss limit reached";
      return false;
   }

   string news_reason = "";
   if(CalendarNewsBlocked(news_reason))
   {
      last_gate_reason = news_reason;
      if(PrintVerboseReasons)
         Print("UltimateSMCTraderEA: trade blocked by ", news_reason);
      return false;
   }
   return true;
}

void ScoreIndicators(const double close_price, const IndicatorSnapshot &indicators, int &long_score, int &short_score, string &reasons)
{
   if(indicators.macd_main > indicators.macd_signal && indicators.macd_hist > 0.0)
   {
      long_score += 2;
      AppendReason(reasons, "MACD bull");
   }
   else if(indicators.macd_main < indicators.macd_signal && indicators.macd_hist < 0.0)
   {
      short_score += 2;
      AppendReason(reasons, "MACD bear");
   }

   if(UseExactMAMAFilter)
   {
      if(indicators.mama > indicators.fama && indicators.mama > indicators.mama_prev)
      {
         long_score += 2;
         AppendReason(reasons, "MAMA bull");
      }
      else if(indicators.mama < indicators.fama && indicators.mama < indicators.mama_prev)
      {
         short_score += 2;
         AppendReason(reasons, "MAMA bear");
      }

      if(indicators.mama_prev <= indicators.fama_prev && indicators.mama > indicators.fama)
         long_score += 1;
      else if(indicators.mama_prev >= indicators.fama_prev && indicators.mama < indicators.fama)
         short_score += 1;
   }

   if(indicators.adaptive_ma > indicators.adaptive_ma_prev && close_price > indicators.adaptive_ma)
   {
      long_score += 2;
      AppendReason(reasons, "adaptive MA up");
   }
   else if(indicators.adaptive_ma < indicators.adaptive_ma_prev && close_price < indicators.adaptive_ma)
   {
      short_score += 2;
      AppendReason(reasons, "adaptive MA down");
   }

   if(indicators.sar < close_price)
   {
      long_score += 1;
      AppendReason(reasons, "PSAR support");
   }
   else if(indicators.sar > close_price)
   {
      short_score += 1;
      AppendReason(reasons, "PSAR resistance");
   }

   if(indicators.cci > 50.0)
      long_score += 1;
   else if(indicators.cci < -50.0)
      short_score += 1;

   if(indicators.mfi > 52.0)
      long_score += 1;
   else if(indicators.mfi < 48.0)
      short_score += 1;

   if(indicators.rsi > 52.0)
      long_score += 1;
   else if(indicators.rsi < 48.0)
      short_score += 1;

   if(indicators.stoch_main > indicators.stoch_signal && indicators.stoch_main < 82.0)
      long_score += 1;
   else if(indicators.stoch_main < indicators.stoch_signal && indicators.stoch_main > 18.0)
      short_score += 1;

   if(indicators.adx > 18.0)
   {
      if(indicators.plus_di > indicators.minus_di)
         long_score += 1;
      else if(indicators.minus_di > indicators.plus_di)
         short_score += 1;
   }
}

void ScorePatterns(const PatternSnapshot &patterns, const IndicatorSnapshot &indicators, int &long_score, int &short_score, string &reasons)
{
   if(patterns.bullish_engulfing)
   {
      long_score += 2;
      AppendReason(reasons, "bull engulfing");
   }
   if(patterns.bearish_engulfing)
   {
      short_score += 2;
      AppendReason(reasons, "bear engulfing");
   }
   if(patterns.bullish_harami)
      long_score += 1;
   if(patterns.bearish_harami)
      short_score += 1;
   if(patterns.piercing_line)
   {
      long_score += 2;
      AppendReason(reasons, "piercing line");
   }
   if(patterns.dark_cloud_cover)
   {
      short_score += 2;
      AppendReason(reasons, "dark cloud cover");
   }
   if(patterns.hammer)
      long_score += 1;
   if(patterns.hanging_man)
      short_score += 1;
   if(patterns.morning_star)
   {
      long_score += 2;
      AppendReason(reasons, "morning star");
   }
   if(patterns.evening_star)
      short_score += 2;
   if(patterns.three_white_soldiers)
   {
      long_score += 2;
      AppendReason(reasons, "three white soldiers");
   }
   if(patterns.three_black_crows)
   {
      short_score += 2;
      AppendReason(reasons, "three black crows");
   }

   if(patterns.doji)
   {
      if(indicators.rsi > 50.0 && indicators.mfi > 50.0)
         long_score += 1;
      else if(indicators.rsi < 50.0 && indicators.mfi < 50.0)
         short_score += 1;
   }
}

void ScoreSMC(const MqlRates &closed_bar, const IndicatorSnapshot &indicators, const SMCContext &context, int &long_score, int &short_score, string &reasons)
{
   if(context.bias == DIR_LONG)
   {
      long_score += 2;
      AppendReason(reasons, "HTF bull bias");
   }
   else if(context.bias == DIR_SHORT)
   {
      short_score += 2;
      AppendReason(reasons, "HTF bear bias");
   }

   if(context.bullish_bos)
   {
      long_score += 2;
      AppendReason(reasons, "bull BOS");
   }
   if(context.bearish_bos)
   {
      short_score += 2;
      AppendReason(reasons, "bear BOS");
   }

   if(context.sweep_low)
   {
      long_score += 2;
      AppendReason(reasons, "liquidity sweep low");
   }
   if(context.sweep_high)
   {
      short_score += 2;
      AppendReason(reasons, "liquidity sweep high");
   }

   if(context.bullish_fvg)
      long_score += 1;
   if(context.bearish_fvg)
      short_score += 1;

   if(context.bullish_order_block)
      long_score += 1;
   if(context.bearish_order_block)
      short_score += 1;

   if(context.discount_zone && closed_bar.close >= context.fib_618_long - indicators.atr * 0.3)
   {
      long_score += 1;
      AppendReason(reasons, "fib discount");
   }
   if(context.premium_zone && closed_bar.close <= context.fib_618_short + indicators.atr * 0.3)
   {
      short_score += 1;
      AppendReason(reasons, "fib premium");
   }
}

void ResetPlan(TradePlan &plan)
{
   plan.valid = false;
   plan.direction = DIR_NONE;
   plan.long_score = 0;
   plan.short_score = 0;
   plan.entry = 0.0;
   plan.stop_loss = 0.0;
   plan.take_profit = 0.0;
   plan.volume = 0.0;
   plan.fib_reference = 0.0;
   plan.label = "";
   plan.reasons = "";
}

bool BuildTradePlan(TradePlan &plan)
{
   ResetPlan(plan);

   MqlRates signal_rates[];
   MqlRates bias_rates[];
   MqlRates macro_rates[];
   if(!LoadRates(SignalTimeframe, 160, signal_rates))
      return false;
   if(!LoadRates(BiasTimeframe, 120, bias_rates))
      return false;
   if(!LoadRates(MacroTimeframe, 120, macro_rates))
      return false;
   if(ArraySize(signal_rates) < 10)
      return false;

   IndicatorSnapshot indicators;
   if(!LoadIndicators(indicators))
      return false;
   if(UseExactMAMAFilter && !ComputeMAMASnapshot(signal_rates, indicators.mama, indicators.fama, indicators.mama_prev, indicators.fama_prev))
      return false;

   PatternSnapshot patterns;
   DetectPatterns(signal_rates, patterns);

   SMCContext smc;
   BuildSMCContext(signal_rates, bias_rates, macro_rates, smc);

   MqlRates closed_bar = signal_rates[1];
   int long_score = 0;
   int short_score = 0;
   string reasons = "";

   ScoreIndicators(closed_bar.close, indicators, long_score, short_score, reasons);
   ScorePatterns(patterns, indicators, long_score, short_score, reasons);
   ScoreSMC(closed_bar, indicators, smc, long_score, short_score, reasons);

   if(PrintVerboseReasons)
      Print("UltimateSMCTraderEA: long_score=", long_score, " short_score=", short_score, " reasons=", reasons);

   int direction = DIR_NONE;
   if(long_score >= SignalThreshold && long_score >= short_score + 2 && EnableLongTrades)
      direction = DIR_LONG;
   else if(short_score >= SignalThreshold && short_score >= long_score + 2 && EnableShortTrades)
      direction = DIR_SHORT;
   else
      return false;

   double entry = (direction == DIR_LONG) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_loss = 0.0;
   double take_profit = 0.0;

   if(direction == DIR_LONG)
   {
      double structure_stop = smc.swing_low - indicators.atr * 0.2;
      double atr_stop = entry - indicators.atr * StopATRMultiplier;
      stop_loss = MathMin(structure_stop, atr_stop);
      double risk_distance = MathMax(entry - stop_loss, indicators.atr * 0.8);
      double rr_target = entry + risk_distance * RewardToRisk;
      double atr_target = entry + indicators.atr * TakeATRMultiplier;
      take_profit = MathMax(rr_target, atr_target);
      plan.fib_reference = smc.fib_618_long;
   }
   else
   {
      double structure_stop = smc.swing_high + indicators.atr * 0.2;
      double atr_stop = entry + indicators.atr * StopATRMultiplier;
      stop_loss = MathMax(structure_stop, atr_stop);
      double risk_distance = MathMax(stop_loss - entry, indicators.atr * 0.8);
      double rr_target = entry - risk_distance * RewardToRisk;
      double atr_target = entry - indicators.atr * TakeATRMultiplier;
      take_profit = MathMin(rr_target, atr_target);
      plan.fib_reference = smc.fib_618_short;
   }

   EnforceStopDistance(direction, entry, stop_loss, take_profit);
   double volume = CalculatePositionSize(entry, stop_loss);
   if(volume <= 0.0)
      return false;

   plan.valid = true;
   plan.direction = direction;
   plan.long_score = long_score;
   plan.short_score = short_score;
   plan.entry = NormalizeDouble(entry, _Digits);
   plan.stop_loss = NormalizeDouble(stop_loss, _Digits);
   plan.take_profit = NormalizeDouble(take_profit, _Digits);
   plan.volume = volume;
   plan.label = StringFormat("USMC_%s_%s", _Symbol, DirectionText(direction));
   plan.reasons = reasons;
   return true;
}

void RemoveTradeObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, trade_object_prefix) == 0)
         ObjectDelete(0, name);
   }
}

void CreateHLine(const string name, const double price, const color line_color, const ENUM_LINE_STYLE line_style)
{
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, line_color);
   ObjectSetInteger(0, name, OBJPROP_STYLE, line_style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void DrawTradeLevels(const TradePlan &plan)
{
   RemoveTradeObjects();
   CreateHLine(trade_object_prefix + "ENTRY", plan.entry, clrDodgerBlue, STYLE_SOLID);
   CreateHLine(trade_object_prefix + "SL", plan.stop_loss, clrTomato, STYLE_DASH);
   CreateHLine(trade_object_prefix + "TP", plan.take_profit, clrLimeGreen, STYLE_DASH);
   if(plan.fib_reference > 0.0)
      CreateHLine(trade_object_prefix + "FIB618", plan.fib_reference, clrGoldenrod, STYLE_DOT);
   ChartRedraw();
}

string PartialCloseKey(const ulong ticket)
{
   return StringFormat("USMC_PARTIAL_%I64u", ticket);
}

bool ModifyPositionLevels(const double new_stop_loss, const double take_profit)
{
   return trade.PositionModify(_Symbol, NormalizeDouble(new_stop_loss, _Digits), NormalizeDouble(take_profit, _Digits));
}
bool CloseManagedPositionBySymbol()
{
   ulong ticket;
   if(!SelectManagedPositionBySymbol(ticket))
      return false;
   return trade.PositionClose(_Symbol);
}

void ManageOpenPosition()
{
   ulong ticket;
   if(!SelectManagedPositionBySymbol(ticket))
      return;

   long position_type = PositionGetInteger(POSITION_TYPE);
   if(manual_trading_pause)
   {
      last_gate_reason = "manual pause";
      return false;
   }
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double stop_loss = PositionGetDouble(POSITION_SL);
   double take_profit = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double current_price = (position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double atr_values[1];
   if(!CopyBufferValues(atr_handle, 0, 1, 1, atr_values))
      return;
   double atr = atr_values[0];
   double risk = MathAbs(entry - stop_loss);
   if(risk <= _Point || atr <= _Point)
      return;

   double rr = (position_type == POSITION_TYPE_BUY) ? (current_price - entry) / risk : (entry - current_price) / risk;
   double break_even_sl = (position_type == POSITION_TYPE_BUY) ? entry + _Point * 5.0 : entry - _Point * 5.0;

   if(rr >= BreakEvenAtRR)
   {
      if(position_type == POSITION_TYPE_BUY && (stop_loss < break_even_sl || stop_loss == 0.0))
         ModifyPositionLevels(break_even_sl, take_profit);
      else if(position_type == POSITION_TYPE_SELL && (stop_loss > break_even_sl || stop_loss == 0.0))
         ModifyPositionLevels(break_even_sl, take_profit);
   }

   double trail_stop = (position_type == POSITION_TYPE_BUY) ? current_price - atr * TrailATRMultiplier : current_price + atr * TrailATRMultiplier;
   if(rr > BreakEvenAtRR)
   {
      if(position_type == POSITION_TYPE_BUY && trail_stop > stop_loss)
         ModifyPositionLevels(trail_stop, take_profit);
      else if(position_type == POSITION_TYPE_SELL && trail_stop < stop_loss)
         ModifyPositionLevels(trail_stop, take_profit);
   }

   string partial_key = PartialCloseKey(ticket);
   if(rr >= PartialAtRR && !GlobalVariableCheck(partial_key) && PartialClosePercent > 0.0 && PartialClosePercent < 1.0)
   {
      double close_volume = NormalizeVolume(volume * PartialClosePercent);
      double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(close_volume >= min_volume && close_volume < volume)
      {
         if(trade.PositionClosePartial(_Symbol, close_volume))
            GlobalVariableSet(partial_key, TimeTradeServer());
      }
   }
}

bool IsNewSignalBar()
{
   datetime times[];
   ArraySetAsSeries(times, true);
   if(CopyTime(_Symbol, SignalTimeframe, 0, 1, times) < 1)
      return false;
   if(times[0] == last_bar_time)
      return false;
   last_bar_time = times[0];
   return true;
}

bool ReadFileBytes(const string file_name, uchar &bytes[])
{
   int handle = FileOpen(file_name, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
      return false;
   int size = (int)FileSize(handle);
   if(size <= 0)
   {
      FileClose(handle);
      return false;
   }
   ArrayResize(bytes, size);
   int read = FileReadArray(handle, bytes, 0, size);
   FileClose(handle);
   return (read == size);
}

void AppendStringBytes(char &target[], const string text)
{
   char chunk[];
   int copied = StringToCharArray(text, chunk, 0, -1, CP_UTF8);
   if(copied <= 0)
      return;
   int payload_size = copied - 1;
   int current_size = ArraySize(target);
   ArrayResize(target, current_size + payload_size);
   for(int i = 0; i < payload_size; i++)
      target[current_size + i] = chunk[i];
}

void AppendBinaryBytes(char &target[], const uchar &source[])
{
   int current_size = ArraySize(target);
   int add_size = ArraySize(source);
   ArrayResize(target, current_size + add_size);
   for(int i = 0; i < add_size; i++)
      target[current_size + i] = (char)source[i];
}

string UrlEncode(const string text)
{
   string encoded = "";
   for(int i = 0; i < StringLen(text); i++)
   {
      ushort ch = (ushort)StringGetCharacter(text, i);
      bool is_alpha = (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
      bool is_digit = (ch >= '0' && ch <= '9');
      if(is_alpha || is_digit || ch == '-' || ch == '_' || ch == '.' )
         encoded += CharToString((uchar)ch);
      else if(ch == ' ')
         encoded += "%20";
      else if(ch == '\n' || ch == '\r')
         encoded += "%0A";
      else
         encoded += StringFormat("%%%02X", (int)ch);
   }
   return encoded;
}

bool TelegramGetResponse(const string url, string &body_text, int &status_code)
{
   char request[];
   char response[];
   string response_headers;
   ArrayResize(request, 0);
   ResetLastError();
   status_code = WebRequest("GET", url, "", 15000, request, response, response_headers);
   if(status_code == -1)
   {
      Print("UltimateSMCTraderEA: Telegram GET failed err=", GetLastError(), ". Add https://api.telegram.org to WebRequest allowed URLs.");
      body_text = "";
      return false;
   }
   body_text = CharArrayToString(response, 0, ArraySize(response), CP_UTF8);
   return true;
}

bool TelegramGet(const string url)
{
   string body_text;
   int status_code = 0;
   if(!TelegramGetResponse(url, body_text, status_code))
      return false;
   return (status_code >= 200 && status_code < 300);
}

bool TelegramSendMessageToChat(const string chat_id, const string message)
{
   if(!TelegramConfigured() || !TelegramSendText || chat_id == "")
      return false;
   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage?chat_id=" + UrlEncode(chat_id) + "&text=" + UrlEncode(message);
   return TelegramGet(url);
}

bool TelegramSendMessage(const string message)
{
   return TelegramSendMessageToChat(TelegramChatId, message);
}

bool ExtractJsonLong(const string source, const string needle, long &value, const int start_index)
{
   int pos = StringFind(source, needle, start_index);
   if(pos < 0)
      return false;
   pos += StringLen(needle);
   int end = pos;
   while(end < StringLen(source))
   {
      ushort ch = (ushort)StringGetCharacter(source, end);
      if((ch >= '0' && ch <= '9') || ch == '-')
         end++;
      else
         break;
   }
   if(end <= pos)
      return false;
   value = (long)StringToInteger(StringSubstr(source, pos, end - pos));
   return true;
}

bool ExtractJsonString(const string source, const string needle, string &value, const int start_index)
{
   int pos = StringFind(source, needle, start_index);
   if(pos < 0)
      return false;
   pos += StringLen(needle);
   string result = "";
   for(int i = pos; i < StringLen(source); i++)
   {
      ushort ch = (ushort)StringGetCharacter(source, i);
      if(ch == '\\')
      {
         i++;
         if(i >= StringLen(source))
            break;
         ushort escaped = (ushort)StringGetCharacter(source, i);
         if(escaped == 'n' || escaped == 'r' || escaped == 't')
            result += " ";
         else
            result += StringSubstr(source, i, 1);
         continue;
      }
      if(ch == '"')
      {
         value = result;
         return true;
      }
      result += StringSubstr(source, i, 1);
   }
   return false;
}

bool ExtractTelegramUpdate(const string body_text, const int start_index, int &next_index, long &update_id, long &chat_id, long &user_id, string &message_text)
{
   int update_pos = StringFind(body_text, "\"update_id\":", start_index);
   if(update_pos < 0)
   {
      next_index = -1;
      return false;
   }

   int next_update_pos = StringFind(body_text, "\"update_id\":", update_pos + 1);
   string chunk = (next_update_pos < 0) ? StringSubstr(body_text, update_pos) : StringSubstr(body_text, update_pos, next_update_pos - update_pos);
   next_index = (next_update_pos < 0) ? StringLen(body_text) : next_update_pos;

   chat_id = 0;
   user_id = 0;
   message_text = "";
   if(!ExtractJsonLong(chunk, "\"update_id\":", update_id, 0))
      return false;

   ExtractJsonLong(chunk, "\"chat\":{\"id\":", chat_id, 0);
   ExtractJsonLong(chunk, "\"from\":{\"id\":", user_id, 0);
   ExtractJsonString(chunk, "\"text\":\"", message_text, 0);
   return true;
}

bool TelegramCommandAuthorized(const long chat_id, const long user_id)
{
   string effective_chat_id = (TelegramInboundChatId != "") ? TelegramInboundChatId : TelegramChatId;
   string chat_id_text = StringFormat("%I64d", chat_id);
   string user_id_text = StringFormat("%I64d", user_id);
   bool chat_allowed = (effective_chat_id != "" && chat_id_text == effective_chat_id);
   bool user_allowed = (TelegramInboundOwnerId != "" && user_id_text == TelegramInboundOwnerId);
   if(TelegramInboundOwnerId != "")
      return (chat_allowed || user_allowed);
   return chat_allowed;
}

string BuildTelegramStatusMessage()
{
   string state = manual_trading_pause ? "paused" : "active";
   string gate = "ready";
   if(manual_trading_pause)
      gate = "manual pause";
   else if(!TradingAllowedNow())
      gate = last_gate_reason;

   ulong ticket = 0;
   string position_line = "Position: none";
   if(SelectManagedPositionBySymbol(ticket))
   {
      string side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      position_line = StringFormat("Position: %s %.2f ticket %I64u", side, PositionGetDouble(POSITION_VOLUME), ticket);
   }

   string last_command = (last_telegram_command == "") ? "none" : last_telegram_command;
   if(last_telegram_command_time > 0)
      last_command += " @ " + TimeToString(last_telegram_command_time, TIME_DATE | TIME_SECONDS);

   return StringFormat(
      "Ultimate SMC status\nSymbol: %s\nState: %s\nGate: %s\nSpread: %.1f\nToday PnL: %.2f\n%s\nLast command: %s",
      _Symbol,
      state,
      gate,
      CurrentSpreadPoints(),
      TodayClosedPnl(),
      position_line,
      last_command
   );
}

void HandleTelegramCommand(const long chat_id, const long user_id, const string raw_text)
{
   string command = TelegramCommandToken(raw_text);
   if(command == "")
      return;

   if(!TelegramCommandAuthorized(chat_id, user_id))
   {
      Print("UltimateSMCTraderEA: ignoring unauthorized Telegram command from chat ", StringFormat("%I64d", chat_id));
      return;
   }

   string reply_chat_id = StringFormat("%I64d", chat_id);
   last_telegram_command = command;
   last_telegram_command_time = TimeTradeServer();

   if(command == "/status" || command == "status")
   {
      TelegramSendMessageToChat(reply_chat_id, BuildTelegramStatusMessage());
      return;
   }

   if(command == "/pause" || command == "pause")
   {
      manual_trading_pause = true;
      last_gate_reason = "manual pause";
      TelegramSendMessageToChat(reply_chat_id, "Trading paused for " + _Symbol + ". Existing positions remain managed.");
      return;
   }

   if(command == "/resume" || command == "resume")
   {
      manual_trading_pause = false;
      last_gate_reason = "";
      TelegramSendMessageToChat(reply_chat_id, "Trading resumed for " + _Symbol + ".");
      return;
   }

   if(command == "/close" || command == "close")
   {
      ulong ticket = 0;
      if(!SelectManagedPositionBySymbol(ticket))
      {
         TelegramSendMessageToChat(reply_chat_id, "No managed position is open for " + _Symbol + ".");
         return;
      }

      if(CloseManagedPositionBySymbol())
         TelegramSendMessageToChat(reply_chat_id, StringFormat("Close requested for %s ticket %I64u.", _Symbol, ticket));
      else
         TelegramSendMessageToChat(reply_chat_id, "Close failed: " + trade.ResultRetcodeDescription());
      return;
   }

   if(command == "/help" || command == "help" || command == "/start" || command == "start")
   {
      TelegramSendMessageToChat(reply_chat_id, "Commands: /status, /pause, /resume, /close");
      return;
   }
}

void PollTelegramCommands(const bool process_updates)
{
   if(!TelegramConfigured() || !TelegramEnableInbound)
      return;

   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/getUpdates?limit=5";
   if(telegram_last_update_id > 0)
      url += "&offset=" + UrlEncode(StringFormat("%I64d", telegram_last_update_id + 1));

   string body_text;
   int status_code = 0;
   if(!TelegramGetResponse(url, body_text, status_code))
      return;
   if(status_code < 200 || status_code >= 300)
   {
      Print("UltimateSMCTraderEA: Telegram getUpdates returned HTTP ", status_code);
      return;
   }

   int cursor = 0;
   long max_update_id = telegram_last_update_id;
   while(true)
   {
      int next_index = -1;
      long update_id = 0;
      long chat_id = 0;
      long user_id = 0;
      string message_text = "";
      if(!ExtractTelegramUpdate(body_text, cursor, next_index, update_id, chat_id, user_id, message_text))
         break;

      cursor = next_index;
      if(update_id > max_update_id)
         max_update_id = update_id;

      if(process_updates && update_id > telegram_last_update_id && message_text != "")
         HandleTelegramCommand(chat_id, user_id, message_text);
   }

   telegram_last_update_id = max_update_id;
}

bool TelegramSendPhoto(const string file_name, const string caption)
{
   if(!TelegramConfigured() || !TelegramSendPhotoAlerts)
      return false;

   uchar raw_bytes[];
   if(!ReadFileBytes(file_name, raw_bytes))
      return false;

   string boundary = StringFormat("----USMCBoundary_%I64d", (long)TimeTradeServer());
   char body[];
   ArrayResize(body, 0);

   AppendStringBytes(body, "--" + boundary + "\r\n");
   AppendStringBytes(body, "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n");
   AppendStringBytes(body, TelegramChatId + "\r\n");
   AppendStringBytes(body, "--" + boundary + "\r\n");
   AppendStringBytes(body, "Content-Disposition: form-data; name=\"caption\"\r\n\r\n");
   AppendStringBytes(body, caption + "\r\n");
   AppendStringBytes(body, "--" + boundary + "\r\n");
   AppendStringBytes(body, "Content-Disposition: form-data; name=\"photo\"; filename=\"" + file_name + "\"\r\n");
   AppendStringBytes(body, "Content-Type: image/png\r\n\r\n");
   AppendBinaryBytes(body, raw_bytes);
   AppendStringBytes(body, "\r\n--" + boundary + "--\r\n");

   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendPhoto";
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
   char response[];
   string response_headers;
   ResetLastError();
   int code = WebRequest("POST", url, headers, 20000, body, response, response_headers);
   if(code == -1)
   {
      Print("UltimateSMCTraderEA: Telegram photo failed err=", GetLastError(), ". Add https://api.telegram.org to WebRequest allowed URLs.");
      return false;
   }
   return (code >= 200 && code < 300);
}

void SendStartupTelegramPing()
{
   if(!TelegramConfigured())
   {
      Print("UltimateSMCTraderEA: Telegram disabled. Set TelegramBotToken and TelegramChatId in EA inputs.");
      return;
   }

   if(!TelegramSendStartupPing || !TelegramSendText)
      return;

   string message = StringFormat(
      "Ultimate SMC EA attached\nSymbol: %s\nTimeframe: %d\nServer time: %s",
      _Symbol,
      (int)SignalTimeframe,
      TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS)
   );

   if(TelegramSendMessage(message))
      Print("UltimateSMCTraderEA: startup Telegram ping sent.");
   else
      Print("UltimateSMCTraderEA: startup Telegram ping failed. Check MT5 WebRequest allowed URLs and Telegram inputs.");
 }

string CaptureTradeImage(const TradePlan &plan)
{
   DrawTradeLevels(plan);
   string filename = StringFormat("USMC_%s_%I64d.png", _Symbol, TimeTradeServer());
   if(!ChartScreenShot(0, filename, ScreenshotWidth, ScreenshotHeight, ALIGN_RIGHT))
      return "";
   return filename;
}

void NotifyTrade(const TradePlan &plan, const ulong order_ticket, const double fill_price)
{
   if(!TelegramConfigured())
      return;

   string message = StringFormat(
      "Ultimate SMC %s\nSymbol: %s\nEntry: %s\nSL: %s\nTP: %s\nVolume: %.2f\nOrder: %I64u\nScores L/S: %d/%d\nReasons: %s",
      DirectionText(plan.direction),
      _Symbol,
      DoubleToString(fill_price, _Digits),
      DoubleToString(plan.stop_loss, _Digits),
      DoubleToString(plan.take_profit, _Digits),
      plan.volume,
      order_ticket,
      plan.long_score,
      plan.short_score,
      plan.reasons
   );

   TelegramSendMessage(message);
   string screenshot = CaptureTradeImage(plan);
   if(screenshot != "")
   {
      TelegramSendPhoto(screenshot, StringFormat("%s %s TP/SL map", _Symbol, DirectionText(plan.direction)));
      FileDelete(screenshot);
   }
}

bool ExecuteTrade(const TradePlan &plan)
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   bool result = false;
   if(plan.direction == DIR_LONG)
      result = trade.Buy(plan.volume, _Symbol, 0.0, plan.stop_loss, plan.take_profit, plan.label);
   else if(plan.direction == DIR_SHORT)
      result = trade.Sell(plan.volume, _Symbol, 0.0, plan.stop_loss, plan.take_profit, plan.label);

   if(!result)
   {
      Print("UltimateSMCTraderEA: trade send failed retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
      return false;
   }

   double fill_price = trade.ResultPrice();
   Print("UltimateSMCTraderEA: ", DirectionText(plan.direction), " trade placed at ", DoubleToString(fill_price, _Digits), " reasons=", plan.reasons);
   NotifyTrade(plan, trade.ResultOrder(), fill_price);
   return true;
}

int OnInit()
{
   macd_handle = iMACD(_Symbol, SignalTimeframe, 12, 26, 9, PRICE_CLOSE);
   ama_handle = iAMA(_Symbol, SignalTimeframe, 10, 2, 30, 0, PRICE_MEDIAN);
   sar_handle = iSAR(_Symbol, SignalTimeframe, 0.02, 0.2);
   cci_handle = iCCI(_Symbol, SignalTimeframe, 20, PRICE_TYPICAL);
   mfi_handle = iMFI(_Symbol, SignalTimeframe, 14, VOLUME_TICK);
   rsi_handle = iRSI(_Symbol, SignalTimeframe, 14, PRICE_CLOSE);
   stoch_handle = iStochastic(_Symbol, SignalTimeframe, 8, 3, 3, MODE_SMA, STO_LOWHIGH);
   atr_handle = iATR(_Symbol, SignalTimeframe, ATRPeriod);
   adx_handle = iADX(_Symbol, SignalTimeframe, 14);

   if(macd_handle == INVALID_HANDLE || ama_handle == INVALID_HANDLE || sar_handle == INVALID_HANDLE || cci_handle == INVALID_HANDLE
      || mfi_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE || stoch_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE
      || adx_handle == INVALID_HANDLE)
   {
      Print("UltimateSMCTraderEA: failed to create indicator handles.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   if(TelegramConfigured() && TelegramEnableInbound)
   {
      PollTelegramCommands(false);
      EventSetTimer(MathMax(1, TelegramInboundPollSeconds));
      Print("UltimateSMCTraderEA: Telegram inbound polling enabled.");
   }
   SendStartupTelegramPing();
   Print("UltimateSMCTraderEA initialized. Allow Algo Trading, whitelist https://api.telegram.org for Telegram alerts, and enable the MT5 Economic Calendar if news blackout is used.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(macd_handle != INVALID_HANDLE)
      IndicatorRelease(macd_handle);
   if(ama_handle != INVALID_HANDLE)
      IndicatorRelease(ama_handle);
   if(sar_handle != INVALID_HANDLE)
      IndicatorRelease(sar_handle);
   if(cci_handle != INVALID_HANDLE)
      IndicatorRelease(cci_handle);
   if(mfi_handle != INVALID_HANDLE)
      IndicatorRelease(mfi_handle);
   if(rsi_handle != INVALID_HANDLE)
      IndicatorRelease(rsi_handle);
   if(stoch_handle != INVALID_HANDLE)
      IndicatorRelease(stoch_handle);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
   if(adx_handle != INVALID_HANDLE)
      IndicatorRelease(adx_handle);

   RemoveTradeObjects();
}

void OnTimer()
{
   PollTelegramCommands(true);
}

void OnTick()
{
   ManageOpenPosition();

   if(!IsNewSignalBar())
      return;
   if(!TradingAllowedNow())
      return;

   ulong existing_ticket;
   if(SelectManagedPositionBySymbol(existing_ticket))
      return;

   TradePlan plan;
   if(!BuildTradePlan(plan))
      return;

   ExecuteTrade(plan);
}