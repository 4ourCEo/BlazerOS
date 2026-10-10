import Foundation

/// Quantitative telemetry and opportunity grading for active desk setups.
/// Replaces static "WAIT" with active stalking metrics while strictly protecting capital.
public struct StalkingTelemetry: Sendable, Equatable {
    public enum Tier: Sendable, Equatable {
        case apexPrime         // Score >= 72 + Prime window + Actionable -> Apex A+
        case tacticalProbe     // Score >= 65 + Actionable -> B-Tier
        case stalkingSetup     // Score 50..64 or developing breakout -> Hunting
        case capitalShield     // Chop, flat range, or unconfirmed -> Capital Preserved
        case safetyBrake       // Veto active -> Safety brake
        case pairWarning       // Chronic chop pair (USD/CAD)
    }

    public let tier: Tier
    public let badgeLabel: String
    public let telemetryHeadline: String
    public let telemetryDetail: String
    public let stakeGuidance: String
    public let isActionable: Bool

    public static func evaluate(
        asset: String,
        score: Int,
        side: String,
        evidence: String,
        veto: String?,
        edgeWindow: MarketEdgeWindow = MarketEdgeWindow.current()
    ) -> StalkingTelemetry {
        // 1. Safety Brake (Veto)
        if let veto, !veto.isEmpty {
            return StalkingTelemetry(
                tier: .safetyBrake,
                badgeLabel: "SAFETY BRAKE",
                telemetryHeadline: "Brake Engaged · \(veto)",
                telemetryDetail: "Adverse price expansion or slippage detected. Trade blocked to protect capital.",
                stakeGuidance: "$0 · Rescan for fresh level",
                isActionable: false
            )
        }

        // 2. Chronic Chop Pair Check
        if case .chopRisk = MarketEdgeWindow.conviction(for: asset), side != "WAIT" {
            return StalkingTelemetry(
                tier: .pairWarning,
                badgeLabel: "CHOP RISK",
                telemetryHeadline: "\(asset) Quarantined",
                telemetryDetail: "Empirical forward testing confirms sub-breakeven performance on \(asset). Quarantined from active basket.",
                stakeGuidance: "$0 · Switch to active basket",
                isActionable: false
            )
        }

        let isSideActionable = side == "HIGH" || side == "LOW"
        let conviction = score
        let dirLabel = side == "LOW" ? "PUT" : (side == "HIGH" ? "CALL" : "WAIT")

        // 3. Apex Prime Setup (A+)
        if isSideActionable && conviction >= 72 && edgeWindow.isPrime {
            return StalkingTelemetry(
                tier: .apexPrime,
                badgeLabel: "APEX A+ CONVICTION",
                telemetryHeadline: "\(dirLabel) Momentum Confirmed",
                telemetryDetail: "Directional conviction \(conviction) during \(edgeWindow.badgeTitle). Score is not a win probability.",
                stakeGuidance: "Use your fixed risk limit",
                isActionable: true
            )
        }

        // 4. Tactical Probe (B-Tier)
        if isSideActionable && conviction >= 65 {
            return StalkingTelemetry(
                tier: .tacticalProbe,
                badgeLabel: "TACTICAL PROBE",
                telemetryHeadline: "\(dirLabel) Micro-Breakout",
                telemetryDetail: "Moderate directional impulse detected (Conviction \(conviction)). Market is outside peak liquidity overlap.",
                stakeGuidance: "Light Stake ($10–$15) · Secondary Edge",
                isActionable: true
            )
        }

        // 5. Stalking Setup (Developing pressure)
        if conviction >= 50 && conviction < 65 {
            let direction = side == "LOW" ? "PUT" : (side == "HIGH" ? "CALL" : (evidence.lowercased().contains("down") ? "PUT" : "CALL"))
            return StalkingTelemetry(
                tier: .stalkingSetup,
                badgeLabel: "STALKING SETUP",
                telemetryHeadline: "Stalking \(direction) Pressure",
                telemetryDetail: "\(evidence). Conviction \(conviction)/72 needed for high-conviction trigger. Monitoring compression.",
                stakeGuidance: "Stand By · Awaiting Trigger Spike",
                isActionable: false
            )
        }

        // 6. Capital Shield (Chop filtered)
        return StalkingTelemetry(
            tier: .capitalShield,
            badgeLabel: "CAPITAL SHIELD",
            telemetryHeadline: "Chop Filtered · No Trade",
            telemetryDetail: "Market noise below statistical edge. Skipping low-probability consolidation preserves your bankroll.",
            stakeGuidance: "No Action · Radar Scanning Other Pairs",
            isActionable: false
        )
    }
}
