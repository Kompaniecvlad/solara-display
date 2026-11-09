import AppKit
import SwiftUI

@main
struct SolaraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(model)
        } label: {
            MenuBarGlyph(percent: model.menuPercent, boosting: model.isBoosting, showPercent: model.showMenuPercent)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        promptIfRunningOutsideApplications()
        AppModel.shared.start()
    }

    private func promptIfRunningOutsideApplications() {
        let path = Bundle.main.bundlePath
        let fromImage = path.hasPrefix("/Volumes/") || path.contains("AppTranslocation")
        guard fromImage else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let language = AppLanguage.current
        alert.messageText = language.localized("install.move_title")
        alert.informativeText = language.localized("install.move_body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: language.localized("install.move_ok"))
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.teardown()
    }
}

private struct MenuBarGlyph: View {
    let percent: Int
    let boosting: Bool
    let showPercent: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: boosting ? "sun.max.fill" : "sun.max")
                .font(.system(size: 13, weight: .semibold))
            if showPercent {
                Text("\(percent)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .help("Solara Display")
    }
}
