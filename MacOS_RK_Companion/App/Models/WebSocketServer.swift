import CoreGraphics
import Foundation
import Network

/// A minimal WebSocket server accepting the same JSON command protocol as the
/// RemoteKeys Python companion server, so the iPhone app can drive this Mac directly.
///
/// All listener/connection state is only ever touched on `queue`; the public
/// start/stop/restart entry points hop onto it so they never race with the
/// accept/receive callbacks (which Network.framework also runs on `queue`).
@Observable
final class WebSocketServer {
  enum Status: Equatable {
    case stopped
    case starting
    case running(port: UInt16)
    case failed(String)
  }

  static let shared = WebSocketServer()

  private(set) var status: Status = .stopped
  private(set) var connectedClientCount = 0

  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private var infoState: [ObjectIdentifier: (sent: Bool, lastSentAt: Date)] = [:]
  private var generation = 0
  private let queue = DispatchQueue(label: "app.remotekeys.websocket-server")
  private let infoThrottleInterval: TimeInterval = 20

  var isRunning: Bool {
    if case .running = status { return true }
    return false
  }

  private init() {}

  func start(port: UInt16) {
    queue.async { self.startOnQueue(port: port) }
  }

  func stop() {
    queue.async { self.stopOnQueue() }
  }

  func restart(port: UInt16) {
    queue.async {
      self.stopOnQueue()
      self.startOnQueue(port: port)
    }
  }

  private func startOnQueue(port: UInt16) {
    guard listener == nil else { return }
    guard let nwPort = NWEndpoint.Port(rawValue: port) else {
      setStatus(.failed("Invalid port"))
      return
    }
    setStatus(.starting)
    generation += 1
    let currentGeneration = generation

    let websocketOptions = NWProtocolWebSocket.Options()
    websocketOptions.autoReplyPing = true
    websocketOptions.setClientRequestHandler(queue) { _, _ in
      NWProtocolWebSocket.Response(status: .accept, subprotocol: nil, additionalHeaders: nil)
    }

    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)

    let newListener: NWListener
    do {
      newListener = try NWListener(using: parameters, on: nwPort)
    } catch {
      setStatus(.failed(error.localizedDescription))
      return
    }

    newListener.stateUpdateHandler = { [weak self] state in
      self?.queue.async {
        guard let self, self.generation == currentGeneration else { return }
        switch state {
        case .ready:
          self.setStatus(.running(port: port))
        case .failed(let error):
          self.setStatus(.failed(error.localizedDescription))
          self.teardownOnQueue()
        case .cancelled:
          self.setStatus(.stopped)
        default:
          break
        }
      }
    }

    newListener.newConnectionHandler = { [weak self] connection in
      self?.queue.async { self?.accept(connection) }
    }

    listener = newListener
    newListener.start(queue: queue)
  }

  private func stopOnQueue() {
    generation += 1
    teardownOnQueue()
    setStatus(.stopped)
  }

  private func teardownOnQueue() {
    listener?.stateUpdateHandler = nil
    listener?.newConnectionHandler = nil
    listener?.cancel()
    listener = nil
    for connection in connections.values {
      connection.cancel()
    }
    connections.removeAll()
    infoState.removeAll()
    setConnectedClientCount(0)
  }

  private func accept(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    connections[id] = connection
    infoState[id] = (false, .distantPast)
    setConnectedClientCount(connections.count)

    connection.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed, .cancelled:
        self?.queue.async { self?.remove(connection) }
      default:
        break
      }
    }

    connection.start(queue: queue)
    receive(on: connection)
  }

  private func remove(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    guard connections.removeValue(forKey: id) != nil else { return }
    infoState.removeValue(forKey: id)
    setConnectedClientCount(connections.count)
  }

  private func receive(on connection: NWConnection) {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      self.queue.async {
        if let data, !data.isEmpty {
          self.handleMessage(data, from: connection)
        }
        if error != nil || connection.state == .cancelled {
          self.remove(connection)
          return
        }
        self.receive(on: connection)
      }
    }
  }

  private func setStatus(_ newStatus: Status) {
    DispatchQueue.main.async { self.status = newStatus }
  }

  private func setConnectedClientCount(_ count: Int) {
    DispatchQueue.main.async { self.connectedClientCount = count }
  }

  private func handleMessage(_ data: Data, from connection: NWConnection) {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    guard let type = json["type"] as? String else { return }

    switch type {
    case "key":
      handleKeyMessage(json)

    case "move":
      SystemInputController.moveMouse(dx: intValue(json["dx"]) ?? 0, dy: intValue(json["dy"]) ?? 0)

    case "drag":
      SystemInputController.drag(
        dx: intValue(json["dx"]) ?? 0,
        dy: intValue(json["dy"]) ?? 0,
        button: buttonValue(json["button"])
      )

    case "drop", "dragEnd":
      SystemInputController.releaseDrag(button: buttonValue(json["button"]))

    case "scroll":
      SystemInputController.scroll(dx: intValue(json["dx"]) ?? 0, dy: intValue(json["dy"]) ?? 0)

    case "zoom":
      break

    case "click":
      let isDouble = (json["clickType"] as? String) == "double"
      SystemInputController.click(button: buttonValue(json["button"]), doubleClick: isDouble)

    case "dblclick":
      SystemInputController.click(button: buttonValue(json["button"]), doubleClick: true)

    case "ping":
      handlePing(connection)

    default:
      break
    }
  }

  private func handleKeyMessage(_ json: [String: Any]) {
    var keyCode: CGKeyCode?
    let rawKey = json["keyCode"] ?? json["keycode"] ?? json["key"] ?? json["code"]
    if let name = rawKey as? String {
      keyCode = KeyCodeMap.code(for: name)
    }
    if keyCode == nil, let number = intValue(rawKey) {
      keyCode = CGKeyCode(number)
    }
    guard let keyCode else { return }

    let modifiers = ModifierMapping.flags(fromBitmask: modifiersBitmask(json["modifiers"]))
    let keyDown = (json["keyType"] as? String ?? "keyDown") == "keyDown"
    SystemInputController.handleKey(keyCode: keyCode, modifiers: modifiers, keyDown: keyDown)
  }

  private func handlePing(_ connection: NWConnection) {
    send(json: ["type": "pong"], on: connection)
    send(json: ["type": "status", "caps_lock": KeyboardLayoutInfo.capsLockEnabled()], on: connection)

    let id = ObjectIdentifier(connection)
    let now = Date()
    let previous = infoState[id] ?? (false, .distantPast)
    let shouldSendInfo = !previous.sent || now.timeIntervalSince(previous.lastSentAt) >= infoThrottleInterval
    guard shouldSendInfo else { return }

    var payload: [String: Any] = ["type": "info"]
    if !previous.sent {
      payload["name"] = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
      payload["keyboard_layout"] = KeyboardLayoutInfo.keyboardLayoutPayload()
    }
    payload["cpu"] = DeviceStatus.cpuUsagePercentage()
    if let battery = DeviceStatus.batteryPercentage() {
      payload["battery"] = battery / 100
    }
    send(json: payload, on: connection)
    infoState[id] = (true, now)
  }

  private func send(json: [String: Any], on connection: NWConnection) {
    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])
    connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
  }

  private func intValue(_ any: Any?) -> Int? {
    if let intVal = any as? Int { return intVal }
    if let doubleVal = any as? Double { return Int(doubleVal) }
    if let stringVal = any as? String { return Int(stringVal) }
    return nil
  }

  private func buttonValue(_ any: Any?) -> CGMouseButton {
    switch (any as? String) ?? "left" {
    case "right": return .right
    case "middle": return .center
    default: return .left
    }
  }

  private func modifiersBitmask(_ any: Any?) -> Int {
    guard let any else { return 0 }
    if let intVal = any as? Int { return intVal }
    if let names = any as? [String] {
      var mask = 0
      for name in names {
        switch name.lowercased() {
        case "shift": mask |= 1
        case "control", "ctrl": mask |= 2
        case "option", "alt", "alternate": mask |= 4
        case "command", "cmd", "meta": mask |= 8
        default: break
        }
      }
      return mask
    }
    return 0
  }
}
