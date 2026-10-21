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
                telemetryDetail: "This build quarantines \(asset) from the active basket. The quarantine is a configuration choice, not a measured edge claim.",
                stakeGuidance: "No entry · switch to an active pair",
                isActionable: false
            )
        }

        let isSideActionable = side == "HIGH" || side == "LOW"
        // The commit score is side-neutral conviction (0...100). It is not a win probability.
        let conviction = score
        let dirLabel = side == "LOW" ? "PUT" : (side == "HIGH" ? "CALL" : "WAIT")

        // 3. Apex Prime Setup (A+)
        if isSideActionable && conviction >= 72 && edgeWindow.isPrime {
            return StalkingTelemetry(
                tier: .apexPrime,
                badgeLabel: "APEX A+ CONVICTION",
                telemetryHeadline: "\(dirLabel) Momentum Confirmed",
                telemetryDetail: "Engine score \(conviction) during \(edgeWindow.badgeTitle). Score is not a win probability.",
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
                telemetryDetail: "Moderate directional impulse detected (engine score \(conviction)). Market is outside peak liquidity overlap.",
                stakeGuidance: "Use your fixed risk limit",
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
                telemetryDetail: "\(evidence). Engine score \(conviction)/72 needed for the high-conviction tier. Monitoring compression.",
                stakeGuidance: "Stand by · awaiting a qualifying trigger",
                isActionable: false
            )
        }

        // 6. Capital Shield (Chop filtered)
        return StalkingTelemetry(
            tier: .capitalShield,
            badgeLabel: "CAPITAL SHIELD",
            telemetryHeadline: "Chop Filtered · No Trade",
            telemetryDetail: "No qualifying setup. Standing down preserves capital; this is not a probability claim.",
            stakeGuidance: "No action · radar scanning other pairs",
            isActionable: false
        )
    }
}
