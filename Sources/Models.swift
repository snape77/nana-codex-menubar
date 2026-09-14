import Cocoa
import Foundation

// MARK: - Data models

struct QuotaWindow {
    let remainingPercent: Double
    let resetsAt: Date?
}

struct QuotaSnapshot {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
}

struct ModelSnapshot: Equatable {
    let model: String?
    let effort: String?
}
