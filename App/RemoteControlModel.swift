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
  case drag = "Drag"
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
  var hostAddress: String = UserDefaults.standard.string(forKey: "hostAddress") ?? "" {
    didSet { UserDefaults.standard.set(hostAddress, forKey: "hostAddress") }
  }
  var hostPort: String = UserDefaults.standard.string(forKey: "hostPort") ?? "8765" {
    didSet { UserDefaults.standard.set(hostPort, forKey: "hostPort") }
  }
  var sensitivity: Double = 2.0
  var scrollSensitivity: Double = 1.0

  // Keyboard state
  var activeModifiers: Set<ModifierKey> = []
  var showFnKeys: Bool = false
  var capsLock: Bool = false

  @ObservationIgnored
  private var shiftResetWorkItem: DispatchWorkItem?

  @ObservationIgnored
  private var trackpadFlushWorkItem: DispatchWorkItem?
  @ObservationIgnored
  private var pendingMoveDX: CGFloat = 0
  @ObservationIgnored
  private var pendingMoveDY: CGFloat = 0
  @ObservationIgnored
  private var pendingScrollDX: CGFloat = 0
  @ObservationIgnored
  private var pendingScrollDY: CGFloat = 0
  @ObservationIgnored
  private var pendingDragDX: CGFloat = 0
  @ObservationIgnored
  private var pendingDragDY: CGFloat = 0
  @ObservationIgnored
  private let trackpadFlushInterval: TimeInterval = 0.005

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
    send(["type": "key", "key": key.lowercased(), "modifiers": mods])

    // Shift behaves as one-shot: clear immediately after any key dispatch.
    clearShiftState()
  }

  func sendMouseMove(dx: CGFloat, dy: CGFloat) {
    pendingMoveDX += dx * sensitivity
    pendingMoveDY += dy * sensitivity
    scheduleTrackpadFlush()
  }

  func sendScroll(dx: CGFloat, dy: CGFloat) {
    pendingScrollDX += dx * scrollSensitivity
    pendingScrollDY += dy * scrollSensitivity
    scheduleTrackpadFlush()
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

  func sendMouseDrag(dx: CGFloat, dy: CGFloat) {
    pendingDragDX += dx * sensitivity
    pendingDragDY += dy * sensitivity
    scheduleTrackpadFlush()
  }

  func sendMouseDragEnd() {
    flushTrackpadDeltas()
    send(["type": "drop", "button": "left"])
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
      if key == .shift {
        scheduleShiftReset()
      }
    }
  }

  private func send(_ payload: [String: Any]) {
    manager?.send(payload)
  }

  private func clearShiftState() {
    shiftResetWorkItem?.cancel()
    shiftResetWorkItem = nil
    activeModifiers.remove(.shift)
  }

  private func scheduleTrackpadFlush() {
    guard trackpadFlushWorkItem == nil else { return }
    let workItem = DispatchWorkItem { [weak self] in
      self?.flushTrackpadDeltas()
    }
    trackpadFlushWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + trackpadFlushInterval, execute: workItem)
  }

  private func flushTrackpadDeltas() {
    trackpadFlushWorkItem?.cancel()
    trackpadFlushWorkItem = nil

    if pendingMoveDX != 0 || pendingMoveDY != 0 {
      send(["type": "move", "dx": pendingMoveDX, "dy": pendingMoveDY])
      pendingMoveDX = 0
      pendingMoveDY = 0
    }

    if pendingScrollDX != 0 || pendingScrollDY != 0 {
      send(["type": "scroll", "dx": pendingScrollDX, "dy": pendingScrollDY])
      pendingScrollDX = 0
      pendingScrollDY = 0
    }

    if pendingDragDX != 0 || pendingDragDY != 0 {
      send(["type": "drag", "dx": pendingDragDX, "dy": pendingDragDY])
      pendingDragDX = 0
      pendingDragDY = 0
    }

    if pendingMoveDX != 0 || pendingMoveDY != 0 || pendingScrollDX != 0 || pendingScrollDY != 0 || pendingDragDX != 0 || pendingDragDY != 0 {
      scheduleTrackpadFlush()
    }
  }

  private func scheduleShiftReset() {
    shiftResetWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      DispatchQueue.main.async {
        self?.activeModifiers.remove(.shift)
      }
    }
    shiftResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
  }

  private func applyDeviceInfo(_ info: [String: Any]) {
    if let name = (info["name"] as? String) ?? (info["mac_name"] as? String) {
      macName = name
    }

    if let battery = (info["battery"] as? Double) ?? (info["battery_percentage"] as? Double) {
      batteryLevel = battery > 1.0 ? battery / 100.0 : battery
    }

    if let cpu = (info["cpu"] as? Double) ?? (info["cpu_usage"] as? Double) {
      cpuUsage = cpu > 1.0 ? cpu / 100.0 : cpu
    }
  }
}

struct TerminalLine: Identifiable {
  let id = UUID()
  var text: String
  var isOutput: Bool
}
