"use strict";
var BlazerScan = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // src/lib/mac-scan-bridge.ts
  var mac_scan_bridge_exports = {};
  __export(mac_scan_bridge_exports, {
    evaluatePair: () => evaluatePair,
    evaluatePairJson: () => evaluatePairJson,
    pickDesk: () => pickDesk,
    pickDeskJson: () => pickDeskJson,
    slippageGateJson: () => slippageGateJson
  });

  // src/lib/constants.ts
  var IDEAL_WIN_RATE_BUFFER = 0.05;
  var PAIR_HEAT_MIN_N = 8;
  var PAIR_DESK_FACT_CAP = 5;
  var PRINT_STALE_MS = 20 * 60 * 1e3;

  // src/lib/math.ts
  function payoutAsDecimal(payoutPercent) {
    return payoutPercent / 100;
  }
  function breakEvenWinRate(payoutPercent) {
    const r = payoutAsDecimal(payoutPercent);
    if (r <= 0) {
      return 1;
    }
    return 1 / (1 + r);
  }
  function expectedValuePerStake(winRate, payoutPercent) {
    const r = payoutAsDecimal(payoutPercent);
    return winRate * r - (1 - winRate);
  }

  // src/lib/pair-desk.ts
  function pairDeskVerdict(n, winRate, be) {
    if (n < PAIR_HEAT_MIN_N || winRate === null) {
      return "thin";
    }
    if (winRate < be - IDEAL_WIN_RATE_BUFFER) {
      return "skip";
    }
    if (winRate >= be + IDEAL_WIN_RATE_BUFFER) {
      return "keep";
    }
    return "thin";
  }
  function computePairHeat(trades, payoutPercent) {
    const be = breakEvenWinRate(payoutPercent);
    const byAsset = /* @__PURE__ */ new Map();
    for (const trade of trades) {
      switch (trade.outcome) {
        case "WIN":
        case "LOSS":
          break;
        case "TIE":
        case "PENDING":
          continue;
        default: {
          const exhaustive = trade.outcome;
          return exhaustive;
        }
      }
      const row = byAsset.get(trade.asset) ?? { hits: 0, misses: 0 };
      if (trade.outcome === "WIN") {
        row.hits += 1;
      } else {
        row.misses += 1;
      }
      byAsset.set(trade.asset, row);
    }
    return [...byAsset.entries()].map(([asset, row]) => {
      const n = row.hits + row.misses;
      const winRate = n > 0 ? row.hits / n : null;
      return {
        asset,
        n,
        hits: row.hits,
        misses: row.misses,
        winRate,
        breakEvenWinRate: be,
        evPerStake: winRate === null ? null : expectedValuePerStake(winRate, payoutPercent),
        verdict: pairDeskVerdict(n, winRate, be)
      };
    }).sort((a, b) => {
      const rank = verdictRank(a.verdict) - verdictRank(b.verdict);
      if (rank !== 0) {
        return rank;
      }
      if (b.n !== a.n) {
        return b.n - a.n;
      }
      return a.asset.localeCompare(b.asset);
    });
  }
  function pairHeatMap(trades, payoutPercent) {
    return new Map(
      computePairHeat(trades, payoutPercent).map((row) => [row.asset, row])
    );
  }
  function formatDeskFacts(heat, cap = PAIR_DESK_FACT_CAP) {
    return heat.slice(0, cap).map((row) => {
      switch (row.verdict) {
        case "keep":
          return `${row.asset} ${row.hits}/${row.n} HIT \u2014 keep`;
        case "skip":
          return `${row.asset} ${row.hits}/${row.n} \u2014 skip`;
        case "thin":
          return `${row.asset} ${row.hits}/${row.n}`;
        default: {
          const exhaustive = row.verdict;
          return exhaustive;
        }
      }
    }).join(" \xB7 ");
  }
  function pickBestDeskRow(rows, trades, payoutPercent, nowMs = Date.now(), preferAsset) {
    if (rows.length === 0) {
      return null;
    }
    const heat = pairHeatMap(trades, payoutPercent);
    const skipped = (row) => heat.get(row.asset)?.verdict === "skip";
    const preferred = (row) => heat.get(row.asset)?.verdict === "keep";
    const blocked = (row) => skipped(row) || printLooksStale(row, nowMs);
    if (preferAsset) {
      const stay = rows.find((row) => row.asset === preferAsset);
      if (stay && stay.live && !blocked(stay)) {
        return stay;
      }
    }
    const live = rows.filter((row) => row.live);
    const eligibleLive = live.filter((row) => !blocked(row));
    const pool = eligibleLive.length > 0 ? eligibleLive : rows.filter((row) => !row.live || !blocked(row));
    if (pool.length === 0) {
      return null;
    }
    return [...pool].sort((a, b) => {
      const pref = Number(preferred(b)) - Number(preferred(a));
      if (pref !== 0) {
        return pref;
      }
      const age = quoteAgeMs(a, nowMs) - quoteAgeMs(b, nowMs);
      if (age !== 0) {
        return age;
      }
      return b.confidence - a.confidence;
    })[0] ?? null;
  }
  function pickBestSignalWithDesk(signals, trades, payoutPercent, nowMs = Date.now(), preferAsset) {
    const picked = pickBestDeskRow(
      signals.map((signal) => ({
        signal,
        asset: signal.asset,
        live: signal.side !== "WAIT",
        confidence: signal.confidence,
        asOfMs: signalPrintMs(signal)
      })),
      trades,
      payoutPercent,
      nowMs,
      preferAsset
    );
    return picked?.signal ?? null;
  }
  function signalPrintMs(signal) {
    if (typeof signal.printMs === "number" && Number.isFinite(signal.printMs) && signal.printMs > 0) {
      return signal.printMs;
    }
    if (Number.isFinite(signal.asOfMs) && signal.asOfMs > 0) {
      return signal.asOfMs;
    }
    return void 0;
  }
  function printLooksStale(row, nowMs) {
    const age = knownQuoteAgeMs(row, nowMs);
    return age !== null && age > PRINT_STALE_MS;
  }
  function quoteAgeMs(row, nowMs) {
    return knownQuoteAgeMs(row, nowMs) ?? Number.POSITIVE_INFINITY;
  }
  function knownQuoteAgeMs(row, nowMs) {
    if (row.asOfMs == null || !Number.isFinite(row.asOfMs) || row.asOfMs <= 0) {
      return null;
    }
    return Math.max(0, nowMs - row.asOfMs);
  }
  function verdictRank(verdict) {
    switch (verdict) {
      case "skip":
        return 0;
      case "keep":
        return 1;
      case "thin":
        return 2;
      default: {
        const exhaustive = verdict;
        return exhaustive;
      }
    }
  }

  // src/lib/indicators.ts
  function closes(candles) {
    return candles.map((candle) => candle.close);
  }
  function ema(values, period) {
    if (values.length === 0) {
      return [];
    }
    const k = 2 / (period + 1);
    const out = [];
    let prev = values[0];
    for (let i = 0; i < values.length; i += 1) {
      prev = i === 0 ? values[0] : values[i] * k + prev * (1 - k);
      out.push(prev);
    }
    return out;
  }
  function rsi(values, period = 7) {
    const out = new Array(values.length).fill(50);
    if (values.length <= period) {
      return out;
    }
    let gain = 0;
    let loss = 0;
    for (let i = 1; i <= period; i += 1) {
      const delta = values[i] - values[i - 1];
      if (delta >= 0) {
        gain += delta;
      } else {
        loss -= delta;
      }
    }
    let avgGain = gain / period;
    let avgLoss = loss / period;
    out[period] = avgLoss === 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
    for (let i = period + 1; i < values.length; i += 1) {
      const delta = values[i] - values[i - 1];
      const curGain = delta > 0 ? delta : 0;
      const curLoss = delta < 0 ? -delta : 0;
      avgGain = (avgGain * (period - 1) + curGain) / period;
      avgLoss = (avgLoss * (period - 1) + curLoss) / period;
      out[i] = avgLoss === 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
    }
    return out;
  }
  function atr(candles, period = 14) {
    const out = [];
    let prevClose = candles[0]?.close ?? 0;
    const trs = [];
    for (const candle of candles) {
      const range = Math.max(
        candle.high - candle.low,
        Math.abs(candle.high - prevClose),
        Math.abs(candle.low - prevClose)
      );
      trs.push(range);
      prevClose = candle.close;
    }
    let avg = trs.slice(0, period).reduce((sum, value) => sum + value, 0) / period;
    for (let i = 0; i < trs.length; i += 1) {
      if (i < period) {
        out.push(avg);
      } else {
        avg = (avg * (period - 1) + trs[i]) / period;
        out.push(avg);
      }
    }
    return out;
  }
  function lastSwing(candles, lookback = 5) {
    const window = candles.slice(-Math.max(lookback * 4, 20));
    let support = window[0]?.low ?? 0;
    let resistance = window[0]?.high ?? 0;
    for (const candle of window) {
      support = Math.min(support, candle.low);
      resistance = Math.max(resistance, candle.high);
    }
    return { support, resistance };
  }
  function bodyDirection(candle) {
    const body = candle.close - candle.open;
    if (Math.abs(body) < candle.close * 2e-5) {
      return "FLAT";
    }
    return body > 0 ? "UP" : "DOWN";
  }

  // src/lib/strategy-engine.ts
  function last(values) {
    return values[values.length - 1];
  }
  function toCabinet(side) {
    switch (side) {
      case "CALL":
        return "HIGH";
      case "PUT":
        return "LOW";
      case "WAIT":
        return "WAIT";
      default: {
        const exhaustive = side;
        return exhaustive;
      }
    }
  }
  function toCall(side) {
    switch (side) {
      case "CALL":
        return "TAP HIGH";
      case "PUT":
        return "TAP LOW";
      case "WAIT":
        return "WAIT";
      default: {
        const exhaustive = side;
        return exhaustive;
      }
    }
  }
  function expiryWords(seconds) {
    if (seconds >= 60) {
      const minutes = seconds / 60;
      return minutes === 1 ? "1 minute" : `${minutes} minutes`;
    }
    return `${seconds} seconds`;
  }
  function pipSize(asset) {
    return /JPY/i.test(asset) ? 0.01 : 1e-4;
  }
  function isSpreadOk(asset, spread, lastBar) {
    if (!Number.isFinite(spread)) {
      return false;
    }
    const rawRange = lastBar ? lastBar.high - lastBar.low : 0;
    const barRange = Number.isFinite(rawRange) ? rawRange : 0;
    const pip = pipSize(asset);
    return !(spread > Math.max(3 * pip, 0.5 * barRange));
  }
  function runStrategyEngine(bundle, expirySeconds) {
    const candles = bundle.candles5m.length >= 30 ? bundle.candles5m : bundle.candles1m;
    const tap = bundle.candles1m;
    const prices = closes(candles);
    const tapPrices = closes(tap);
    const emaFastSeries = ema(prices, 21);
    const emaSlowSeries = ema(prices, 55);
    const rsiSeries = rsi(tapPrices.length >= 20 ? tapPrices : prices, 7);
    const atrSeries = atr(candles, 14);
    const emaFast = last(emaFastSeries);
    const emaSlow = last(emaSlowSeries);
    const currentRsi = last(rsiSeries);
    const currentAtr = last(atrSeries);
    const { support, resistance } = lastSwing(candles);
    const tape = tap.length ? tap : candles;
    const lastCandle = last(tape);
    const priorCandle = tape.slice(-2)[0] ?? lastCandle;
    const printMs = lastCandle.time;
    const lastPrice = bundle.lastPrice;
    const spread = bundle.spread;
    const spreadOk = isSpreadOk(bundle.asset, spread, lastCandle);
    const reasons = [];
    const blockers = [];
    const tags = [];
    const lastDir = bodyDirection(lastCandle);
    const priorDir = bodyDirection(priorCandle);
    const bounce = lastDir === "UP" && priorDir === "DOWN";
    const reject = lastDir === "DOWN" && priorDir === "UP";
    const nearSupport = lastPrice - support <= currentAtr * 1.1 && lastPrice >= support - currentAtr * 0.15;
    const nearResistance = resistance - lastPrice <= currentAtr * 1.1 && lastPrice <= resistance + currentAtr * 0.15;
    const share = rangeShare(lastPrice, support, resistance);
    const extendedUp = share >= 0.72 && lastDir === "UP" && currentRsi > 55;
    const extendedDown = share <= 0.28 && lastDir === "DOWN" && currentRsi < 45;
    const pinnedToMid = Math.abs(lastPrice - emaSlow) < currentAtr * 0.12;
    let trend = "CHOP";
    if (lastPrice > emaSlow && !pinnedToMid) {
      trend = "UP";
    } else if (lastPrice < emaSlow && !pinnedToMid) {
      trend = "DOWN";
    }
    const sweep = liquiditySweep(tape);
    const tight = rangeIsTight(tape, currentAtr);
    const bos = tight ? null : breakOfStructure(tape);
    const evidenceLines = [];
    let score = 50;
    const addEvidence = (points, title) => {
      score += points;
      const sign = points > 0 ? "+" : "";
      evidenceLines.push(`${title} (${sign}${points})`);
    };
    if (trend === "UP") {
      addEvidence(18, "Trend is up");
    } else if (trend === "DOWN") {
      addEvidence(-18, "Trend is down");
    }
    if (bos === "up") {
      addEvidence(16, "Broke the prior high");
    } else if (bos === "down") {
      addEvidence(-16, "Broke the prior low");
    }
    if (sweep === "low") {
      addEvidence(22, "Swept the low and reclaimed");
    } else if (sweep === "high") {
      addEvidence(-22, "Swept the high and reclaimed");
    }
    if (extendedUp) {
      addEvidence(12, "Climb is extended");
    }
    if (extendedDown) {
      addEvidence(-12, "Fall is extended");
    }
    if (bounce && trend === "UP") {
      addEvidence(14, "Dip then bounce");
    }
    if (reject && trend === "DOWN") {
      addEvidence(-14, "Pop then reject");
    }
    if (tight && sweep === null) {
      score = 50 + (score - 50) * 0.35;
      evidenceLines.push("Range is tight");
    }
    score = Math.max(0, Math.min(100, Math.round(score)));
    let side = "WAIT";
    let confidence = score;
    let getIn = "NOW";
    let why = "Not enough edge.";
    const countertrend = bounce && trend === "DOWN" || reject && trend === "UP";
    if (countertrend) {
      side = "WAIT";
      getIn = "WAIT_TOUCH";
      why = bounce ? "Bounce against the fall. Wait for a clean High." : "Reject against the climb. Wait for a clean Low.";
      blockers.push(why);
    } else if (score >= 72) {
      side = "CALL";
      getIn = "NOW";
      if (sweep === "low") {
        why = "Price swept the low and reclaimed. High from here.";
        tags.push("Sweep");
      } else if (bounce && trend === "UP") {
        why = "Price dipped and is bouncing. High from here.";
        tags.push("Bounce");
      } else if (extendedUp) {
        why = "The climb is still going. High from here.";
        tags.push("Climb");
      } else if (bos === "up") {
        why = "Price broke the prior high. High from here.";
        tags.push("Break");
      } else if (nearSupport) {
        why = "Price held the floor and turned up. High from here.";
        tags.push("Climb");
      } else {
        why = "The climb is still going. High from here.";
        tags.push("Climb");
      }
      reasons.push(why);
    } else if (score <= 28) {
      side = "PUT";
      getIn = "NOW";
      if (sweep === "high") {
        why = "Price swept the high and reclaimed. Low from here.";
        tags.push("Sweep");
      } else if (reject && trend === "DOWN") {
        why = "Price popped and got rejected. Low from here.";
        tags.push("Reject");
      } else if (extendedDown) {
        why = "The fall is still going. Low from here.";
        tags.push("Fall");
      } else if (bos === "down") {
        why = "Price broke the prior low. Low from here.";
        tags.push("Break");
      } else if (nearResistance) {
        why = "Price failed the ceiling. Low from here.";
        tags.push("Fall");
      } else {
        why = "The fall is still going. Low from here.";
        tags.push("Fall");
      }
      reasons.push(why);
    } else if (trend === "UP") {
      why = "Climbing but not near the floor. Wait for a bounce.";
      blockers.push(why);
      getIn = "WAIT_TOUCH";
    } else if (trend === "DOWN") {
      why = "Falling but not near the ceiling. Wait for a reject.";
      blockers.push(why);
      getIn = "WAIT_TOUCH";
    } else {
      why = "Not enough edge.";
      blockers.push(why);
      getIn = "WAIT_TOUCH";
    }
    const evidence = evidenceLines.join(" \xB7 ");
    if (!spreadOk) {
      side = "WAIT";
      confidence = 0;
      getIn = "WAIT_TOUCH";
      why = "Spread too wide.";
      reasons.length = 0;
      blockers.length = 0;
      blockers.push(why);
      tags.length = 0;
    }
    const entryPrice = lastPrice;
    const buffer = Math.max(currentAtr * 0.15, lastPrice * 4e-5);
    let entryLow = entryPrice - buffer;
    let entryHigh = entryPrice + buffer;
    let exitTarget = entryPrice;
    let invalidation = entryPrice;
    let getInLabel = why;
    let getOutLabel = "Nothing to exit.";
    switch (side) {
      case "CALL":
        entryLow = Math.min(support, entryPrice - buffer);
        entryHigh = entryPrice + buffer * 0.4;
        exitTarget = Math.min(resistance, entryPrice + currentAtr * 0.35);
        invalidation = support - buffer;
        getInLabel = `Press green High on Pocket Option now. Not a buy.`;
        getOutLabel = `When the ${expiryWords(expirySeconds)} timer ends. Skip if it already dumped.`;
        break;
      case "PUT":
        entryHigh = Math.max(resistance, entryPrice + buffer);
        entryLow = entryPrice - buffer * 0.4;
        exitTarget = Math.max(support, entryPrice - currentAtr * 0.35);
        invalidation = resistance + buffer;
        getInLabel = `Press red Low on Pocket Option now. Not a sell.`;
        getOutLabel = `When the ${expiryWords(expirySeconds)} timer ends. Skip if it already bounced.`;
        break;
      case "WAIT":
        getInLabel = why;
        getOutLabel = "No High or Low to exit.";
        break;
      default: {
        const exhaustive = side;
        return exhaustive;
      }
    }
    const cabinetSide = toCabinet(side);
    const call = toCall(side);
    const narrative = side === "WAIT" ? why : `${call} \xB7 ${getInLabel}. ${getOutLabel}`;
    return {
      asset: bundle.asset,
      side,
      cabinetSide,
      call,
      confidence,
      price: lastPrice,
      bid: bundle.bid,
      ask: bundle.ask,
      spread,
      spreadOk,
      source: bundle.source,
      reasons: reasons.length ? reasons : [why],
      blockers,
      tags: [...new Set(tags)],
      why,
      narrative,
      rsi: currentRsi,
      emaFast,
      emaSlow,
      trend,
      support,
      resistance,
      expirySeconds,
      getIn: side === "WAIT" ? "WAIT_TOUCH" : "NOW",
      asOfMs: Date.now(),
      printMs,
      opportunity: confidence,
      evidence,
      getInLabel,
      entryPrice,
      entryLow,
      entryHigh,
      exitTarget,
      invalidation,
      getOutLabel
    };
  }
  function priorBars(bars) {
    return bars.slice(-11, -1);
  }
  function liquiditySweep(bars) {
    if (bars.length < 12) {
      return null;
    }
    const last2 = bars[bars.length - 1];
    const prior = priorBars(bars);
    if (prior.length < 8) {
      return null;
    }
    const priorLow = Math.min(...prior.map((bar) => bar.low));
    const priorHigh = Math.max(...prior.map((bar) => bar.high));
    if (last2.low < priorLow && last2.close > priorLow) {
      return "low";
    }
    if (last2.high > priorHigh && last2.close < priorHigh) {
      return "high";
    }
    return null;
  }
  function breakOfStructure(bars) {
    if (bars.length < 12) {
      return null;
    }
    const last2 = bars[bars.length - 1];
    const prior = priorBars(bars);
    const priorLow = Math.min(...prior.map((bar) => bar.low));
    const priorHigh = Math.max(...prior.map((bar) => bar.high));
    if (last2.close > priorHigh) {
      return "up";
    }
    if (last2.close < priorLow) {
      return "down";
    }
    return null;
  }
  function rangeIsTight(bars, atrValue) {
    const window = bars.slice(-8);
    if (window.length < 8 || !(atrValue > 0)) {
      return false;
    }
    const hi = Math.max(...window.map((bar) => bar.high));
    const lo = Math.min(...window.map((bar) => bar.low));
    return hi - lo < atrValue * 1.25;
  }
  function rangeShare(price, support, resistance) {
    const range = resistance - support;
    if (!(range > 0) || !Number.isFinite(price)) {
      return 0.5;
    }
    return (price - support) / range;
  }

  // src/lib/slippage-gate.ts
  function pipSize2(asset) {
    return asset.toUpperCase().includes("JPY") ? 0.01 : 1e-4;
  }
  function slippageGate(input) {
    const pip = pipSize2(input.asset);
    const idle = {
      veto: false,
      adverseDriftPips: 0,
      thresholdPips: 1
    };
    if (input.side !== "HIGH" && input.side !== "LOW") return idle;
    const { strike, bid, ask } = input;
    if (![strike, bid, ask, pip].every((n) => Number.isFinite(n)) || pip <= 0) {
      return idle;
    }
    const liveSpreadPips = Math.max(0, ask - bid) / pip;
    const threshold = Math.max(liveSpreadPips, 1);
    const adverseDrift = input.side === "HIGH" ? (strike - bid) / pip : (ask - strike) / pip;
    return {
      veto: adverseDrift > threshold,
      adverseDriftPips: adverseDrift,
      thresholdPips: threshold
    };
  }

  // src/lib/mac-scan-bridge.ts
  function slimSignal(signal) {
    return {
      asset: signal.asset,
      cabinetSide: signal.cabinetSide,
      call: signal.call,
      why: signal.why,
      price: signal.price,
      entryPrice: signal.entryPrice,
      invalidation: signal.invalidation,
      confidence: signal.confidence,
      opportunity: signal.opportunity,
      evidence: signal.evidence,
      asOfMs: signal.asOfMs,
      printMs: signal.printMs,
      source: signal.source
    };
  }
  function evaluatePair(input) {
    const bid = input.bid ?? input.lastPrice;
    const ask = input.ask ?? input.lastPrice;
    const spread = input.spread ?? Math.max(0, ask - bid);
    const bundle = {
      asset: input.asset,
      source: input.source ?? "oanda",
      candles1m: input.candles1m,
      candles5m: input.candles5m,
      lastPrice: input.lastPrice,
      bid,
      ask,
      spread
    };
    const signal = runStrategyEngine(bundle, input.expirySeconds ?? 60);
    return {
      signal: slimSignal(signal),
      candles: bundle.candles5m.slice(-80),
      source: bundle.source
    };
  }
  function pickDesk(input) {
    const nowMs = input.nowMs ?? Date.now();
    const heat = computePairHeat(input.trades, input.payoutPercent);
    const picked = pickBestSignalWithDesk(
      input.signals,
      input.trades,
      input.payoutPercent,
      nowMs,
      input.preferAsset
    );
    return {
      asset: picked?.asset ?? null,
      deskFact: formatDeskFacts(heat),
      heat,
      signal: picked ? slimSignal(picked) : null
    };
  }
  function evaluatePairJson(raw) {
    return JSON.stringify(evaluatePair(JSON.parse(raw)));
  }
  function pickDeskJson(raw) {
    return JSON.stringify(pickDesk(JSON.parse(raw)));
  }
  function slippageGateJson(raw) {
    return JSON.stringify(slippageGate(JSON.parse(raw)));
  }
  return __toCommonJS(mac_scan_bridge_exports);
})();
