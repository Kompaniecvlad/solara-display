import SwiftUI

struct MenuPopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.hasXDR {
                presetRow
            }
            if model.displays.count > 1 {
                Toggle(isOn: $model.syncDisplays) {
                    Text(model.language.localized("settings.sync"))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            if model.displays.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(model.displays) { display in
                        DisplayCardView(display: display)
                    }
                }
            }
            if model.isAtPeak {
                Text(model.language.localized("warning.peak"))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.35)
            footer
        }
        .padding(14)
        .frame(width: 348)
        .solaraPanel()
        .sheet(isPresented: $model.showingAbout) {
            AboutView()
                .environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(SolaraTheme.sunGradient)
                    .frame(width: 32, height: 32)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SolaraTheme.dusk)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(SolaraBrand.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(model.language.localized("popover.subtitle"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            languageSwitcher
        }
    }

    private var languageSwitcher: some View {
        HStack(spacing: 1) {
            ForEach(AppLanguage.allCases) { language in
                let selected = model.language == language
                Button {
                    model.language = language
                } label: {
                    Text(language.badge)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? SolaraTheme.dusk : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background {
                            if selected {
                                Capsule().fill(SolaraTheme.sunGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.accessibilityName)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .fixedSize()
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(BrightnessPreset.allCases) { preset in
                Button {
                    model.applyPreset(preset)
                } label: {
                    Text(preset.title(in: model.language))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .disabled(preset == .restore && !model.canRestore)
                .opacity(preset == .restore && !model.canRestore ? 0.4 : 1)
            }
        }
    }

    private var emptyState: some View {
        Text(model.language.localized("empty.no_displays"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $model.showMenuPercent) {
                Text(model.language.localized("settings.menu_percent"))
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: launchBinding) {
                Text(model.language.localized("settings.launch_at_login"))
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Button(model.language.localized("about.title")) { model.showingAbout = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.language.localized("settings.quit")) { model.quit() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(.top, 2)
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { _ in model.toggleLaunchAtLogin() }
        )
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 36))
                .foregroundStyle(SolaraTheme.sunGradient)
            Text(SolaraBrand.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(model.language.localized("about.version \(version)"))
                .foregroundStyle(.secondary)
            Text(model.language.localized("about.body"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Text(model.language.localized("about.requires"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button(action: model.openWebsite) {
                VStack(spacing: 2) {
                    Text(model.language.localized("about.developed"))
                    Text(SolaraBrand.websiteHost)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SolaraTheme.amber)
                }
            }
            .buttonStyle(.plain)
            Button(model.language.localized("about.close"), action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 300)
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3"
        return "\(short) (\(build))"
    }
}
