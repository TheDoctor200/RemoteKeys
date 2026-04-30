import SwiftUI

// MARK: - Enums

enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
}

enum ConnectionType {
  case wifi, bluetooth, none

  var icon: String {
    switch self {
    case .wifi: return "wifi"
    case .bluetooth: return "dot.radiowaves.left.and.right"
    case .none: return "wifi.slash"
    }
  }

  var label: String {
    switch self {
    case .wifi: return "Wi-Fi"
    case .bluetooth: return "Bluetooth"
    case .none: return "Not Connected"
    }
  }
}

enum ModifierKey: String, CaseIterable, Hashable {
  case command, option, control, shift

  var symbol: String {
    switch self {
    case .command: return "⌘"
    case .option: return "⌥"
    case .control: return "⌃"
    case .shift: return "⇧"
    }
  }

  var shortLabel: String {
    switch self {
    case .command: return "CMD"
    case .option: return "OPT"
    case .control: return "CTL"
    case .shift: return "⇧"
    }
  }
}

enum TrackpadMode: String, CaseIterable {
  case cursor = "Cursor"
  case scroll = "Scroll"
}

// MARK: - Model

@Observable
class RemoteControlModel {
  // Connection
  var connectionState: ConnectionState = .disconnected
  var connectionType: ConnectionType = .none
  var latency: Int = 0

  // Device info
  var macName: String = "MacBook"
  var batteryLevel: Double = 0.0
  var cpuUsage: Double = 0.0

  // Settings
  var hostAddress: String = ""
  var hostPort: String = "8765"
  var sensitivity: Double = 2.0
  var scrollSensitivity: Double = 1.0

  // Keyboard state
  var activeModifiers: Set<ModifierKey> = []
  var showFnKeys: Bool = false
  var capsLock: Bool = false

  // Trackpad
  var trackpadMode: TrackpadMode = .cursor

  // Terminal
  var showTerminal: Bool = false
  var terminalOutput: [TerminalLine] = []

  private var manager: ConnectionManager?

  func connect() {
    guard !hostAddress.isEmpty, let port = Int(hostPort) else { return }
    connectionState = .connecting
    manager = ConnectionManager(host: hostAddress, port: port)
    manager?.onConnected = { [weak self] in
      DispatchQueue.main.async {
        self?.connectionState = .connected
        self?.connectionType = .wifi
      }
    }
    manager?.onDisconnected = { [weak self] in
      DispatchQueue.main.async {
        self?.connectionState = .disconnected
        self?.connectionType = .none
        self?.latency = 0
      }
    }
    manager?.onLatencyUpdate = { [weak self] ms in
      DispatchQueue.main.async { self?.latency = ms }
    }
    manager?.onDeviceInfo = { [weak self] info in
      DispatchQueue.main.async { self?.applyDeviceInfo(info) }
    }
    manager?.onTerminalOutput = { [weak self] line in
      DispatchQueue.main.async {
        self?.terminalOutput.append(TerminalLine(text: line, isOutput: true))
        if (self?.terminalOutput.count ?? 0) > 200 {
          self?.terminalOutput.removeFirst()
        }
      }
    }
    manager?.connect()
  }

  func disconnect() {
    manager?.disconnect()
    manager = nil
    connectionState = .disconnected
    connectionType = .none
    latency = 0
  }

  func sendKey(_ key: String) {
    let mods = activeModifiers.map { $0.rawValue }
    send(["type": "key", "key": key, "modifiers": mods])
    withAnimation(.snappy(duration: 0.15)) {
      activeModifiers.removeAll()
    }
  }

  func sendMouseMove(dx: CGFloat, dy: CGFloat) {
    send(["type": "move", "dx": dx * sensitivity, "dy": dy * sensitivity])
  }

  func sendScroll(dx: CGFloat, dy: CGFloat) {
    send(["type": "scroll", "dx": dx * scrollSensitivity, "dy": dy * scrollSensitivity])
  }

  func sendClick(button: String = "left") {
    send(["type": "click", "button": button])
  }

  func sendDoubleClick() {
    send(["type": "dblclick", "button": "left"])
  }

  func sendZoom(scale: CGFloat) {
    send(["type": "zoom", "scale": scale])
  }

  func sendTerminalCommand(_ command: String) {
    send(["type": "terminal", "command": command])
    terminalOutput.append(TerminalLine(text: "$ " + command, isOutput: false))
  }

  func toggleModifier(_ key: ModifierKey) {
    if activeModifiers.contains(key) {
      activeModifiers.remove(key)
    } else {
      activeModifiers.insert(key)
    }
  }

  private func send(_ payload: [String: Any]) {
    manager?.send(payload)
  }

  private func applyDeviceInfo(_ info: [String: Any]) {
    if let name = info["name"] as? String { macName = name }
    if let battery = info["battery"] as? Double { batteryLevel = battery }
    if let cpu = info["cpu"] as? Double { cpuUsage = cpu }
  }
}

struct TerminalLine: Identifiable {
  let id = UUID()
  var text: String
  var isOutput: Bool
}
