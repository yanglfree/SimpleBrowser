import Foundation

struct TelemetryContext: Equatable {
    let consentAccepted: Bool
    let enabled: Bool
    let isPrivate: Bool
}

enum TelemetryPolicy {
    static func allowsWrite(_ context: TelemetryContext) -> Bool {
        context.consentAccepted && context.enabled && !context.isPrivate
    }

    static func clampedMilliseconds(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return min(86_400_000, Int(value.rounded()))
    }

    static func sanitizedAction(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return String(trimmed.prefix(40))
    }
}
