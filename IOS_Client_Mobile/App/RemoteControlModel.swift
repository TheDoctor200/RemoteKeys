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

struct KeyboardLayoutRow: Equatable, Identifiable {
  var name: String
  var keys: [String]

  var id: String { name }
}

struct KeyboardLayoutProfile: Equatable {
  var identifier: String
  var displayName: String
  var rows: [KeyboardLayoutRow]

  static let standard = KeyboardLayoutProfile(
    identifier: "us",
    displayName: "US / QWERTY",
    rows: [
      KeyboardLayoutRow(name: "numberRow", keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
      KeyboardLayoutRow(name: "row1", keys: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]),
      KeyboardLayoutRow(name: "row2", keys: ["a", "s", "d", "f", "g", "h", "j", "k", "l"]),
      KeyboardLayoutRow(name: "row3", keys: ["z", "x", "c", "v", "b", "n", "m"]),
    ]
  )

  static func fromInfo(_ info: [String: Any]) -> KeyboardLayoutProfile? {
    guard let layout = info["keyboard_layout"] as? [String: Any] else { return nil }
    guard let rows = layout["rows"] as? [String: Any] else { return nil }

    let identifier = (layout["identifier"] as? String) ?? "detected"
    let displayName = (layout["name"] as? String) ?? "Detected Keyboard Layout"

    let orderedRowNames = layoutRowOrder(from: layout, rows: rows)
    let keyboardRows = orderedRowNames.compactMap { rowName -> KeyboardLayoutRow? in
      guard let keys = rows[rowName] as? [String] else { return nil }
      return KeyboardLayoutRow(name: rowName, keys: keys)
    }

    guard !keyboardRows.isEmpty else { return nil }

    return KeyboardLayoutProfile(
      identifier: identifier,
      displayName: displayName,
      rows: keyboardRows
    )
  }

  private static func layoutRowOrder(from layout: [String: Any], rows: [String: Any]) -> [String] {
    if let order = (layout["row_order"] as? [String]) ?? (layout["rowOrder"] as? [String]) ?? (layout["rows_order"] as? [String]) {
      return order
    }

    let preferred = ["numberRow", "row1", "row2", "row3"]
    let remaining = rows.keys.filter { !preferred.contains($0) }.sorted()
    return preferred.filter { rows[$0] != nil } + remaining
  }
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
  var keyboardLayout: KeyboardLayoutProfile = .standard

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
    manager?.onStatusUpdate = { [weak self] status in
      DispatchQueue.main.async { self?.applyStatus(status) }
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

  func toggleConnection() {
    if isConnectionActive {
      disconnect()
    } else {
      connect()
    }
  }

  func applyConnectionString(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    let candidates = [trimmed, trimmed.replacingOccurrences(of: "ws://", with: "http://"), trimmed.replacingOccurrences(of: "wss://", with: "https://")]

    for candidate in candidates {
      let prefixed = candidate.contains("://") ? candidate : "ws://\(candidate)"
      guard let components = URLComponents(string: prefixed), let host = components.host, let port = components.port else { continue }
      hostAddress = host
      hostPort = String(port)
      return true
    }

    let hostPortValue = trimmed
      .replacingOccurrences(of: "ws://", with: "")
      .replacingOccurrences(of: "wss://", with: "")
      .replacingOccurrences(of: "/remote", with: "")

    let parts = hostPortValue.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, !parts[0].isEmpty, Int(parts[1]) != nil else { return false }

    hostAddress = parts[0]
    hostPort = parts[1]
    return true
  }

  var canConnect: Bool {
    !hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Int(hostPort) != nil
  }

  var isConnectionActive: Bool {
    connectionState == .connected || connectionState == .connecting
  }

  var connectionActionLabel: String {
    isConnectionActive ? "Disconnect" : "Connect"
  }

  var connectionActionSystemImage: String {
    isConnectionActive ? "cable.connector.slash" : "cable.connector"
  }

  var connectionActionDisabled: Bool {
    connectionState == .disconnected && !canConnect
  }

  func sendKey(_ key: String) {
    let mods = activeModifiers.map { $0.rawValue }
    send(["type": "key", "key": key, "modifiers": mods])

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

  private func applyDeviceInfo(_ info: [String: Any]) {
    if let name = (info["name"] as? String) ?? (info["mac_name"] as? String) {
      macName = name
    }

    if let layout = KeyboardLayoutProfile.fromInfo(info) {
      keyboardLayout = layout
    }

    if let battery = (info["battery"] as? Double) ?? (info["battery_percentage"] as? Double) {
      batteryLevel = battery > 1.0 ? battery / 100.0 : battery
    }

    if let cpu = (info["cpu"] as? Double) ?? (info["cpu_usage"] as? Double) {
      cpuUsage = cpu > 1.0 ? cpu / 100.0 : cpu
    }
  }

  private func applyStatus(_ status: [String: Any]) {
    if let caps = status["caps_lock"] as? Bool {
      capsLock = caps
    }
  }
}
