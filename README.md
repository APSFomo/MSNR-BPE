# MSNR — Malaysian SNR Double Breakout Zone Indicator
### MetaTrader 5 | MQL5 | Price Action | Swing Structure

---

## Overview

MSNR is a MetaTrader 5 indicator that automatically identifies and marks high-probability **Supply and Demand zones** based on a double breakout of fresh swing levels. The core logic mirrors how SMC (Smart Money Concepts) order block indicators work — a zone is **only drawn after a confirmed structural break**, never speculatively. This eliminates the majority of false signals that appear in conventional SNR (Support and Resistance) indicators.

The indicator depends on an external ZigZag indicator (`iHighLowZigZag`) to supply swing point data and does all structural analysis internally.

---

## How It Works

### Swing Points
The indicator reads swing highs and lows from the ZigZag indicator:
- **A level** — a swing HIGH (top of a zigzag leg)
- **V level** — a swing LOW (bottom of a zigzag leg)

### Fresh Level Definition
A level is considered **fresh** if no candle has touched it since it formed. The moment any bar's wick or body reaches that level, it is no longer fresh and is removed from consideration.

### Zone Detection — SMC Order Block Style
Detection flows **forward in time**, exactly like an SMC order block indicator marks zones only after a BOS (Break of Structure):

**SELL Zone:**
1. Scan forward tracking all fresh V levels (swing lows)
2. When a single bar breaks **two fresh V levels** downward (wick or close) → double BOS down confirmed
3. Look **back** from that bar to find the last A level pivot before the move
4. Draw a SELL zone rectangle at that A level candle — this is the origin of the move

**BUY Zone:**
1. Scan forward tracking all fresh A levels (swing highs)
2. When a single bar breaks **two fresh A levels** upward (wick or close) → double BOS up confirmed
3. Look **back** from that bar to find the last V level pivot before the move
4. Draw a BUY zone rectangle at that V level candle — this is the origin of the move

### Critical Rule
> A zone is **never drawn** unless both breakouts are fully confirmed. If only one fresh level is broken, nothing is marked. This is the core filter that keeps the chart clean.

---

## Visual Output

| Object | Description |
|---|---|
| Blue horizontal lines | Fresh A levels (swing highs) still unbroken |
| Orange horizontal lines | Fresh V levels (swing lows) still unbroken |
| Red rectangle | SELL zone — A level that preceded a double downward BOS |
| Green rectangle | BUY zone — V level that preceded a double upward BOS |

Zones extend a configurable number of bars to the right so entry opportunities remain visible after the zone forms.

---

## Why This Approach

Most SNR indicators mark every support and resistance level they find, producing a cluttered chart full of levels of varying quality. MSNR takes the opposite approach — it marks **nothing** until the market structure proves a zone was significant enough to produce a double structural break.

The two-breakout requirement means:
- A single fake-out does not trigger a zone
- Both breaks must come from **fresh** levels — levels that have not been touched since they formed
- The zone is placed at the **origin candle** of the move, not at the break point, making it actionable when price returns

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

---

## Roadmap

- [ ] Zone invalidation — remove zone when price closes back through it
- [ ] ISL (Internal Structure Level) marking inside each zone
- [ ] EA integration — automated entries on zone touch with SL/TP
- [ ] Multi-timeframe zone display
- [ ] Alerts on zone touch

---

## License

MIT License — free to use, modify, and distribute.

---

*Built for traders who want structure-confirmed zones, not noise.*
