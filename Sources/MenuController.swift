import Cocoa
import Foundation

// MARK: - Menu bar controller

final class NanaMenuController: NSObject {
    private let quotaReader = CodexQuotaReader()
    private let modelReader = CodexModelReader()

    private let quotaWorker = DispatchQueue(label: "nana.menubar.quota", qos: .utility)
    private let modelWorker = DispatchQueue(label: "nana.menubar.model", qos: .utility)

    private var statusItem: NSStatusItem!
    private var modelItem: NSMenuItem!
    private var quotaDetailItem: NSMenuItem!
    private var updatedItem: NSMenuItem!

    private var fiveHour: QuotaWindow?
    private var weekly: QuotaWindow?
    private var model = ModelSnapshot(model: nil, effort: nil)

    private var lastSuccessfulQuotaUpdate: Date?
    private var quotaRefreshInFlight = false
    private var modelRefreshInFlight = false

    private var quotaTimer: Timer?
    private var displayTimer: Timer?
    private var modelTimer: Timer?

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "nana · Codex quota"
        }

        buildMenu()
        renderStatusImage()
        refreshEverything()

        quotaTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshQuota()
        }
        displayTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.renderStatusImage()
        }
        modelTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshModel()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        modelItem = NSMenuItem(title: "Model: —", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)

        quotaDetailItem = NSMenuItem(title: "Waiting for Codex quota…", action: nil, keyEquivalent: "")
        quotaDetailItem.isEnabled = false
        menu.addItem(quotaDetailItem)

        updatedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        updatedItem.isEnabled = false
        menu.addItem(updatedItem)

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit nana", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func refreshEverything() {
        refreshQuota()
        refreshModel()
    }

    @objc private func refreshNow() { refreshEverything() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func refreshQuota() {
        guard !quotaRefreshInFlight else { return }
        quotaRefreshInFlight = true

        quotaWorker.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.quotaReader.fetch()
                DispatchQueue.main.async {
                    self.fiveHour = snapshot.fiveHour
                    self.weekly = snapshot.weekly
                    self.lastSuccessfulQuotaUpdate = Date()
                    self.quotaRefreshInFlight = false
                    self.renderStatusImage()
                    self.updateMenu()
                }
            } catch {
                DispatchQueue.main.async {
                    self.quotaRefreshInFlight = false
                    self.renderStatusImage()
                    self.updateMenu()
                }
            }
        }
    }

    private func refreshModel() {
        guard !modelRefreshInFlight else { return }
        modelRefreshInFlight = true

        modelWorker.async { [weak self] in
            guard let self else { return }
            let snapshot = self.modelReader.currentModel()
            DispatchQueue.main.async {
                self.model = snapshot
                self.modelRefreshInFlight = false
                self.updateMenu()
            }
        }
    }

    private func renderStatusImage() {
        let row1 = statusRow(prefix: "5h", quota: fiveHour)
        let row2 = statusRow(prefix: "1w", quota: weekly)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.8, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let row1Size = (row1 as NSString).size(withAttributes: attrs)
        let row2Size = (row2 as NSString).size(withAttributes: attrs)
        let width = ceil(max(row1Size.width, row2Size.width)) + 4
        let height: CGFloat = 22

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        (row1 as NSString).draw(at: NSPoint(x: 2, y: 11.1), withAttributes: attrs)
        (row2 as NSString).draw(at: NSPoint(x: 2, y: 0.2), withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = true

        statusItem.length = width + 5
        statusItem.button?.image = image
        statusItem.button?.toolTip = tooltipText()
    }

    private func statusRow(prefix: String, quota: QuotaWindow?) -> String {
        guard let quota else { return "\(prefix) --%  --" }
        let percent = Int(quota.remainingPercent.rounded())
        let reset = compactReset(to: quota.resetsAt, prefix: prefix)
        return "\(prefix) \(percent)%  \(reset)"
    }

    private func compactReset(to date: Date?, prefix: String) -> String {
        guard let date else { return "--" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))

        if prefix.lowercased() == "5h" {
            let hours = seconds / 3_600
            let minutes = (seconds % 3_600) / 60
            if hours > 0 { return "\(hours)h\(minutes)m" }
            return "\(minutes)m"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        if days > 0 { return "\(days)d\(hours)h" }
        return "\(hours)h"
    }

    private func tooltipText() -> String {
        let five = detailLine(name: "5-hour", quota: fiveHour)
        let week = detailLine(name: "1-week", quota: weekly)
        return "nana · Codex quota\n\(five)\n\(week)"
    }

    private func detailLine(name: String, quota: QuotaWindow?) -> String {
        guard let quota else { return "\(name): unavailable" }
        let pct = Int(quota.remainingPercent.rounded())
        let reset = exactReset(to: quota.resetsAt)
        return "\(name): \(pct)% · reset \(reset)"
    }

    private func exactReset(to date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func updateMenu() {
        modelItem.title = "Model: \(friendlyModel(model))"
        let five = detailLine(name: "5h", quota: fiveHour)
        let week = detailLine(name: "1w", quota: weekly)
        quotaDetailItem.title = "\(five)   |   \(week)"

        if let lastSuccessfulQuotaUpdate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            updatedItem.title = "Updated \(formatter.string(from: lastSuccessfulQuotaUpdate))"
        } else {
            updatedItem.title = "Quota data unavailable"
        }
    }

    private func friendlyModel(_ snapshot: ModelSnapshot) -> String {
        let modelName: String
        switch snapshot.model?.lowercased() {
        case "gpt-6-astra": modelName = "GPT-6 Astra"
        case "gpt-5.6-sol": modelName = "GPT-5.6 Sol"
        case "gpt-5.6-terra": modelName = "GPT-5.6 Terra"
        case "gpt-5.6-luna": modelName = "GPT-5.6 Luna"
        case .some(let raw): modelName = raw
        case .none: modelName = "—"
        }

        let effortName: String?
        switch snapshot.effort?.lowercased() {
        case "minimal": effortName = "minimal"
        case "low": effortName = "low"
        case "medium", "med": effortName = "medium"
        case "high": effortName = "high"
        case "xhigh", "extra_high": effortName = "extra high"
        case .some(let raw) where !raw.isEmpty: effortName = raw
        default: effortName = nil
        }

        if let effortName { return "\(modelName) · \(effortName)" }
        return modelName
    }
}
