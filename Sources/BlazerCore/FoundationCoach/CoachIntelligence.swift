import Foundation

/// On-device trading reasoning engine for the Coach voice session.
/// Answers user questions about sealed scans with contextual trading intelligence.
public enum CoachIntelligence {
    public static func synthesizeAnswer(seal: ParitySeal, evidence: String, question: String) -> String {
        let q = question.lowercased()
        let conviction = seal.score
        let direction = seal.side.contains("LOW") ? "PUT" : (seal.side.contains("HIGH") ? "CALL" : "WAIT")

        // Math / Expectancy / Edge inquiry
        if q.contains("math") || q.contains("expectancy") || q.contains("formula") || q.contains("equation") || q.contains("fail") || q.contains("90") {
            return "Trading is basic math: Expectancy = (Probability * Payout) - (Risk * (1 - Probability)). Chasing win rate without positive expectancy is why 90% of traders fail. At an 88% payout, break-even is 53.2%."
        }

        // Flat is a position / Chop inquiry
        if q.contains("flat") || q.contains("chop") || q.contains("pass") || q.contains("skip") || q.contains("patience") {
            return "Flat is a position. When market structure lacks clean momentum or mathematical expectancy is unproven, capital preservation is the highest expected value decision."
        }

        // Risk or sizing inquiry
        if q.contains("risk") || q.contains("size") || q.contains("stake") || q.contains("lot") || q.contains("money") || q.contains("kelly") {
            return "Directional conviction \(conviction) is not a win probability. Risk math mandates a fixed 1 to 2 percent account ceiling independent of conviction. If expectancy is non-positive, stake is zero."
        }

        // Reason / Why inquiry
        if q.contains("why") || q.contains("reason") || q.contains("setup") || q.contains("signal") || q.contains("take") || q.contains("enter") {
            let rationale = evidence.isEmpty ? "clean structural alignment and wick rejection" : evidence
            let strikeStr = PriceFormat.px(seal.strike)
            return "The engine called \(direction) with a conviction score of \(conviction). Key driver: \(rationale). Strike is anchored at \(strikeStr)."
        }

        // Win / Probability inquiry
        if q.contains("win") || q.contains("chance") || q.contains("probability") || q.contains("edge") || q.contains("stat") {
            return "A conviction score of \(conviction) does not establish a win rate or positive expectancy. At an assumed 88 percent net payout, break-even is 53.2 percent verified wins; this setup needs separate outcome evidence."
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
