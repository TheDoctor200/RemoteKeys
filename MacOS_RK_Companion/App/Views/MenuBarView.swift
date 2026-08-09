import SwiftUI

struct MenuBarView: View {
  @Environment(AppSettings.self) private var settings
  @Environment(\.openWindow) private var openWindow
  private let server = WebSocketServer.shared
  @State private var localIP = NetworkInfo.localIPAddress()

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

  private var serverIsOn: Bool {
    server.status != .stopped
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("RemoteKeys Companion", systemImage: "keyboard.fill")
        .font(.headline)

      HStack(spacing: 6) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
        Text(statusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if server.isRunning, let localIP {
        LabeledContent("Address", value: "\(localIP):\(settings.port)")
          .font(.system(.body, design: .monospaced))
      }

      Toggle(
        "Server Enabled",
        isOn: Binding(
          get: { serverIsOn },
          set: { isOn in
            if isOn {
              server.start(port: UInt16(settings.port))
            } else {
              server.stop()
            }
          }
        )
      )
      .toggleStyle(.button)

      Divider()

      Button("Open Settings…") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }

      Button("Quit RemoteKeys Companion") {
        NSApp.terminate(nil)
      }
    }
    .padding()
    .frame(width: 240)
    .onAppear { localIP = NetworkInfo.localIPAddress() }
  }
}
