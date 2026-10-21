import Foundation

/// On-device trading reasoning engine for the Coach voice session.
/// Answers user questions about sealed scans with contextual trading intelligence.
public enum CoachIntelligence {
    public static func synthesizeAnswer(seal: ParitySeal, evidence: String, question: String) -> String {
        let q = question.lowercased()
        let score = seal.score
        let direction = seal.side.contains("LOW") ? "PUT" : (seal.side.contains("HIGH") ? "CALL" : "WAIT")
        let recorded = evidence.trimmingCharacters(in: .whitespacesAndNewlines)

        // Math / Expectancy / Edge inquiry
        if q.contains("math") || q.contains("expectancy") || q.contains("formula") || q.contains("equation") {
            return "Expectancy = (win rate × payout) − (loss rate × risk). At the assumed 88% payout, break-even is 53.2% verified wins. This desk does not claim a verified edge."
        }

        // Flat is a position / Chop inquiry
        if q.contains("flat") || q.contains("chop") || q.contains("pass") || q.contains("skip") || q.contains("patience") {
            return "Flat is a position. When market structure lacks a qualifying setup, capital preservation is the default decision."
        }

        // Risk or sizing inquiry
        if q.contains("risk") || q.contains("size") || q.contains("stake") || q.contains("lot") || q.contains("money") || q.contains("kelly") {
            return "Engine score \(score) is not a win probability. Use a fixed risk limit you can afford to lose; this app does not size stakes and does not claim positive expectancy."
        }

        // Reason / Why inquiry
        if q.contains("why") || q.contains("reason") || q.contains("setup") || q.contains("signal") || q.contains("take") || q.contains("enter") {
            let strikeStr = PriceFormat.px(seal.strike)
            guard !recorded.isEmpty else {
                return "The engine called \(direction) with an engine score of \(score). No supporting evidence was recorded for this seal, so no rationale can be stated. Strike is anchored at \(strikeStr)."
            }
            return "The engine called \(direction) with an engine score of \(score). Recorded driver: \(recorded). Strike is anchored at \(strikeStr)."
        }

        // Win / Probability inquiry
        if q.contains("win") || q.contains("chance") || q.contains("probability") || q.contains("edge") || q.contains("stat") {
            return "An engine score of \(score) does not establish a win rate or positive expectancy. At an assumed 88% payout, break-even is 53.2% verified wins; this setup needs separate outcome evidence."
        }

        // Expiry / Timing inquiry
        if q.contains("time") || q.contains("expiry") || q.contains("duration") || q.contains("hold") || q.contains("second") || q.contains("minute") {
            let seconds = Int(Timing.liveMs / 1000)
            return "This setup is modeled across binary horizons (60s, 3m, 5m). Enter on the venue within the \(seconds)-second action window before quote drift invalidates the entry."
        }

        // General / Default analysis
        guard !recorded.isEmpty else {
            return "Engine score \(score) on \(direction). No supporting evidence was recorded for this seal. Fingerprint \(seal.fingerprint.prefix(4))."
        }
        return "Engine score \(score) on \(direction). Recorded driver: \(recorded). Fingerprint \(seal.fingerprint.prefix(4))."
    }
}
