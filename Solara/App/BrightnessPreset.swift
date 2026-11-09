import Foundation

@MainActor
enum BrightnessPreset: String, CaseIterable, Identifiable {
    case sdr
    case nits1000
    case peak
    case restore

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .sdr: language.localized("preset.sdr")
        case .nits1000: language.localized("preset.1000")
        case .peak: language.localized("preset.1600")
        case .restore: language.localized("preset.restore")
        }
    }

    func percent(for session: DisplaySession) -> Double {
        switch self {
        case .sdr:
            return session.sdrPercent
        case .nits1000:
            guard session.supportsXDR, session.peakNits > 0 else { return 100 }
            return min(100, 1000.0 / Double(session.peakNits) * 100)
        case .peak:
            return 100
        case .restore:
            return session.percent
        }
    }
}
