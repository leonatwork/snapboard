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
                    Text("Screenie")
                        .font(.title2.bold())
                    Text("Greenshot-Alternative für macOS")
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
                        Text("Globaler Shortcut:")
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
                        Text("Aktion:")
                        Spacer()
                        Text("Bereich auswählen → Zwischenablage")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Speicherort:")
                        Spacer()
                        Text("Keine (nur Zwischenablage)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Tastaturkürzel & Verhalten")
                }

                Section {
                    Toggle("Ton bei erfolgreicher Aufnahme abspielen", isOn: $appState.playSound)

                    Toggle("Mitteilung nach Aufnahme anzeigen", isOn: $appState.showNotification)

                    Toggle("Beim Anmelden automatisch starten", isOn: $appState.launchAtLogin)
                } header: {
                    Text("Benachrichtigungen & Start")
                }
            }
            .formStyle(.grouped)
            .padding(.top, 10)

            Divider()

            // Footer actions
            HStack {
                Button("Screenshot jetzt testen") {
                    CaptureService.shared.captureArea()
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
        .frame(width: 440, height: 420)
        .onAppear {
            appState.checkLaunchAtLoginStatus()
        }
    }
}
