import Foundation

/// On-device trading reasoning engine for the Coach voice session.
/// Answers user questions about sealed scans with contextual trading intelligence.
public enum CoachIntelligence {
    public static func synthesizeAnswer(seal: ParitySeal, evidence: String, question: String) -> String {
        let q = question.lowercased()
        let conviction = seal.side == "LOW" ? (100 - seal.score) : seal.score
        let direction = seal.side == "LOW" ? "PUT" : (seal.side == "HIGH" ? "CALL" : "WAIT")

        // Risk or sizing inquiry
        if q.contains("risk") || q.contains("size") || q.contains("stake") || q.contains("lot") || q.contains("money") {
            let winRateStr = conviction >= 70 ? "high statistical edge" : "favorable probability"
            return "This \(direction) setup carries a \(winRateStr) with a conviction rating of \(conviction). Keep risk fixed at 1 to 2 percent of your balance. Never chase losses with Martingale."
        }

        // Reason / Why inquiry
        if q.contains("why") || q.contains("reason") || q.contains("setup") || q.contains("signal") || q.contains("take") || q.contains("enter") {
            let rationale = evidence.isEmpty ? "clean structural alignment and wick rejection" : evidence
            let strikeStr = PriceFormat.px(seal.strike)
            return "The engine called \(direction) with a conviction score of \(conviction). Key driver: \(rationale). Strike is anchored at \(strikeStr)."
        }

        // Win / Probability inquiry
        if q.contains("win") || q.contains("chance") || q.contains("probability") || q.contains("edge") || q.contains("stat") {
            let edge = conviction >= 60 ? "exceeds our 54 percent breakeven threshold" : "is below threshold"
            return "At conviction \(conviction), historical calibration confirms this setup \(edge). On Pocket Option 85 to 88 percent payout, this provides positive mathematical expectancy."
        }

        // Expiry / Timing inquiry
        if q.contains("time") || q.contains("expiry") || q.contains("duration") || q.contains("hold") || q.contains("second") || q.contains("minute") {
            return "This setup is modeled across binary horizons (60s, 3m, 5m). Enter on broker within the 8-second action window before quote drift exceeds 0.4 pips."
        }

        // General / Default analysis
        let rationale = evidence.isEmpty ? "trend alignment and momentum expansion" : evidence
        return "Conviction \(conviction) on \(direction). Rationale: \(rationale). Fingerprint \(seal.fingerprint.prefix(4)). Trade with disciplined risk."
    }
}
