import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var appState = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Snapboard")
                        .font(.title2.bold())
                    Text(L10n.tr("settings.subtitle"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Form
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.direct.title"))
                                .fontWeight(.medium)
                            Text(L10n.tr("settings.direct.detail"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "⌘ ⇧ 1")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.quaternaryLabelColor))
                            .cornerRadius(6)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.edit.title"))
                                .fontWeight(.medium)
                            Text(L10n.tr("settings.edit.detail"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "⌘ ⇧ 2")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.quaternaryLabelColor))
                            .cornerRadius(6)
                    }
                } header: {
                    Text(L10n.tr("settings.section.shortcuts"))
                }

                Section {
                    Toggle(L10n.tr("settings.playSound"), isOn: $appState.playSound)

                    Toggle(L10n.tr("settings.showNotification"), isOn: $appState.showNotification)

                    Toggle(L10n.tr("settings.launchAtLogin"), isOn: $appState.launchAtLogin)
                } header: {
                    Text(L10n.tr("settings.section.notifications"))
                }
            }
            .formStyle(.grouped)
            .padding(.top, 10)

            Divider()

            // Footer
            HStack {
                Button(L10n.tr("settings.testDirect")) {
                    CaptureService.shared.captureDirect()
                }

                Button(L10n.tr("settings.testEditor")) {
                    CaptureService.shared.captureForEdit()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(L10n.tr("common.close")) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 460)
        .onAppear {
            appState.checkLaunchAtLoginStatus()
        }
    }
}
