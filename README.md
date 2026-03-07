# MSNR — Malaysian SNR BPE indicator
### MetaTrader 5 | MQL5 

---

## Overview

MSNR is a MetaTrader 5 indicator that automatically identifies and marks high-probability **EG zones** based on a double breakout of fresh swing levels. The core logic mirrors how MSNR A V levels work  with double breakout (BPE)— a zone is **only drawn after a confirmed double breakout MSNR — Malaysian SNR BPE Indicator
### MetaTrader 5 | MQL5 
---

## How It Works

### Swing Points
The indicator reads swing highs and lows from the MQL5 stock ZigZag indicator:
- **A level** — a swing HIGH (top of a zigzag leg)
- **V level** — a swing LOW (bottom of a zigzag leg)

### Fresh Level Definition
A level is considered **fresh** if no candle has touched it since it formed. The moment any bar's wick or body reaches that level, it is no longer fresh and is removed from consideration.

### Zone Detection 
Detection flows **forward in time**

**SELL Zone:**
1. Scan forward tracking all fresh V levels (swing lows)
2. When a single bar breaks **two fresh V levels** downward (wick or close) → double BO down confirmed
3. Look **back** from that bar to find the last A-level pivot before the move
4. Draw a SELL zone rectangle at that A-level candle — this is the origin of the move

**BUY Zone:**
1. Scan forward tracking all fresh A levels (swing highs)
2. When a single bar breaks **two fresh A levels** upward (wick or close) → double BO up confirmed
3. Look **back** from that bar to find the last V-level pivot before the move
4. Draw a BUY zone rectangle at that V level candle — this is the origin of the move

---

## Inputs

| Parameter | Default | Description |
|---|---|---|
| `InpZZPeriod` | 10 | ZigZag period — controls swing point sensitivity |
| `InpLookback` | 500 | Number of bars to scan back |
| `InpBoxExtend` | 50 | Bars to extend the zone rectangle to the right |
| `InpAColor` | DodgerBlue | Color for A level lines |
| `InpVColor` | OrangeRed | Color for V level lines |
| `InpLineWidth` | 1 | Level line thickness |
| `InpLineStyle` | Solid | Level line style |
| `InpSellColor` | FireBrick | SELL zone box color |
| `InpBuyColor` | ForestGreen | BUY zone box color |
| `InpBoxAlpha` | 60 | Zone fill transparency (0–255) |

---

## Dependencies

- `iHighLowZigZag.ex5` — must be compiled and placed in `MQL5/Indicators/`
- MetaTrader 5 build 2000 or later

---

## Installation

1. Copy `iHighLowZigZag.mq5` to `MQL5/Indicators/` and compile
2. Copy `MSNR_Levels.mq5` to `MQL5/Indicators/` and compile
3. Attach `MSNR_Levels` to any chart
4. Adjust `InpZZPeriod` to match your preferred swing sensitivity


*Built for traders who want structure-confirmed zones, not noise.*
