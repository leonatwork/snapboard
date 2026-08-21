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
                    Text("Snapboard")
                        .font(.title2.bold())
                    Text("Greenshot-Alternative für macOS & Windows")
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
                            Text("Direkt in Zwischenablage:")
                                .fontWeight(.medium)
                            Text("Bereich wählen → 0 Klicks sofort im Clipboard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("⌘ ⇧ 1")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.quaternaryLabelColor))
                            .cornerRadius(6)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Aufnehmen & Bearbeiten:")
                                .fontWeight(.medium)
                            Text("Bereich wählen → Öffnet Editor (Pfeile, Blur, Badges)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("⌘ ⇧ 2")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.quaternaryLabelColor))
                            .cornerRadius(6)
                    }
                } header: {
                    Text("Globale Tastaturkürzel")
                }

                Section {
                    Toggle("Ton bei Aufnahme abspielen", isOn: $appState.playSound)

                    Toggle("Mitteilung nach Aufnahme anzeigen", isOn: $appState.showNotification)

                    Toggle("Beim Anmelden automatisch starten", isOn: $appState.launchAtLogin)
                } header: {
                    Text("Benachrichtigungen & Start")
                }
            }
            .formStyle(.grouped)
            .padding(.top, 10)

            Divider()

            // Footer
            HStack {
                Button("Direkt testen (⌘⇧1)") {
                    CaptureService.shared.captureDirect()
                }

                Button("Editor testen (⌘⇧2)") {
                    CaptureService.shared.captureForEdit()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Schließen") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 490, height: 460)
        .onAppear {
            appState.checkLaunchAtLoginStatus()
        }
    }
}
