import Foundation

// MARK: - CTAssets
// Crypto watchlist, pip scales, and spread gates for blazerCT.
//
// EXPANSION POLICY:
//   Phase 1 (now):       BTC/USDT only — single asset for clean calibration.
//   Phase 2 (≥ 100 BTC signals, WR ≥ 55%): Add ETH/USDT.
//   Phase 3 (≥ 100 ETH signals, WR ≥ 55%): Add XAU/USDT if Binance spread is acceptable.
//
// Never add a pair to watchlist without a data-backed reason.

public enum CTAssets {

    // MARK: - Active Watchlist

    /// Phase 1: BTC/USDT only.
    /// Update this array only after forward-test data justifies expansion.
    public static let watchlist: [String] = [
        "BTC/USDT",
    ]

    // MARK: - Pip Scales
    // Defines what 1 "pip" means for each asset in absolute price terms.
    // Used to convert raw price drift to a human-readable pip count.
    //
    // BTC/USDT: 1 pip = $1.00  (matches common binary-contract pip conventions for BTC)
    // ETH/USDT: 1 pip = $0.10
    // XAU/USDT: 1 pip = $0.10  (identical to BlazerOS XAU/USD — keeps metrics comparable)

    public static func pipScale(for asset: String) -> Double {
        switch asset {
        case "BTC/USDT": return 1.00
        case "ETH/USDT": return 0.10
        case "XAU/USDT": return 0.10
        default:          return 1.00
        }
    }

    // MARK: - Maximum Spread Gates (in pips)
    // Signals are suppressed when the live bid/ask spread exceeds this threshold.
    // This is the primary anti-chop filter for crypto (replaces the time-of-day
    // prime window gate that cannot yet be backed by data).
    //
    // BTC/USDT: 20 pip ($20) max — tight during liquid hours (~$5–15),
    //           wide during low-volume periods ($25–$50) → those periods auto-suppressed.
    // ETH/USDT: 5 pip ($0.50) max
    // XAU/USDT: 35 pip ($3.50) max — same as BlazerOS XAU gate

    public static func maxSpreadPips(for asset: String) -> Double {
        switch asset {
        case "BTC/USDT": return 20.0
        case "ETH/USDT": return 5.0
        case "XAU/USDT": return 35.0
        default:          return 10.0
        }
    }

    // MARK: - ATR Gate (in pips)
    // Rejects signals when the 14-period Average True Range exceeds the threshold.
    // Protects against news spikes and liquidation cascades where the engine
    // cannot reliably read candle structure.
    //
    // BTC/USDT: 300 pip ($300) max ATR — extreme volatility beyond this is ungradeable.
    // ETH/USDT: 30 pip ($3) max ATR
    // XAU/USDT: 50 pip ($5) max ATR

    public static func maxATRPips(for asset: String) -> Double {
        switch asset {
        case "BTC/USDT": return 300.0
        case "ETH/USDT": return 30.0
        case "XAU/USDT": return 50.0
        default:          return 100.0
        }
    }

    // MARK: - Minimum Conviction Threshold
    // Current fixed gate is 75. This score is not a calibrated probability.
    // Any threshold change requires separate prospective validation, version review
    // and explicit authorization; nominal win-rate counts do not authorize a change.

    public static let minConviction: Int = 75
}
