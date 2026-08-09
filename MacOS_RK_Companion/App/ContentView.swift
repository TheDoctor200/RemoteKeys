import SwiftUI

struct ContentView: View {
  @Environment(AppSettings.self) private var settings
  private let server = WebSocketServer.shared
  @State private var keyboardLayoutName = KeyboardLayoutInfo.currentLayoutName()
  @State private var localIP = NetworkInfo.localIPAddress()

  private var connectionString: String {
    "\(localIP ?? "0.0.0.0"):\(settings.port)"
  }

  private var statusColor: Color {
    switch server.status {
    case .running: .green
    case .starting: .yellow
    case .stopped: .secondary
    case .failed: .red
    }
  }

  private var statusText: String {
    switch server.status {
    case .running:
      "Running · \(server.connectedClientCount) connected"
    case .starting:
      "Starting…"
    case .stopped:
      "Stopped"
    case .failed(let message):
      "Error: \(message)"
    }
  }

  var body: some View {
    @Bindable var settings = settings

    Form {
      Section("Connection") {
        LabeledContent("Server Status") {
          HStack(spacing: 6) {
            Circle()
              .fill(statusColor)
              .frame(width: 8, height: 8)
            Text(statusText)
          }
        }

        Toggle(
          "Server Enabled",
          isOn: Binding(
            get: { server.status != .stopped },
            set: { isOn in
              if isOn {
                server.start(port: UInt16(settings.port))
              } else {
                server.stop()
              }
            }
          )
        )
        .toggleStyle(.switch)

        LabeledContent("Network Address") {
          Text(localIP ?? "Unavailable")
            .monospaced()
            .foregroundStyle(localIP == nil ? .secondary : .primary)
        }

        Stepper(value: $settings.port, in: 1024...65535, step: 1) {
          LabeledContent("Port", value: "\(settings.port)")
        }
      }

      Section("Scan to Connect") {
        VStack(spacing: 8) {
          QRCodeView(content: "ws://\(connectionString)")
            .frame(width: 180, height: 180)
          Text(connectionString)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
          Text("Scan this code in the RemoteKeys app to connect automatically.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }

      Section("Keyboard Layout") {
        LabeledContent("Current Layout", value: keyboardLayoutName)
      }

      Section("Startup & Visibility") {
        Toggle("Launch at Login", isOn: $settings.launchAtLogin)
        Toggle("Run Silently in Background", isOn: $settings.runSilentlyInBackground)
        Toggle("Show in Menu Bar", isOn: $settings.showInMenuBar)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: 620)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      keyboardLayoutName = KeyboardLayoutInfo.currentLayoutName()
      localIP = NetworkInfo.localIPAddress()
    }
  }
}
