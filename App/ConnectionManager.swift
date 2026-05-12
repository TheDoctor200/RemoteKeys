import Foundation

class ConnectionManager {
  var onConnected: (() -> Void)?
  var onDisconnected: (() -> Void)?
  var onLatencyUpdate: ((Int) -> Void)?
  var onDeviceInfo: (([String: Any]) -> Void)?
  var onTerminalOutput: ((String) -> Void)?

  private let host: String
  private let port: Int
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var pingTimer: Timer?
  private var lastPingDate: Date?
  private var active = false

  init(host: String, port: Int) {
    self.host = host
    self.port = port
  }

  func connect() {
    guard let url = URL(string: "ws://\(host):\(port)/remote") else { return }
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 5
    urlSession = URLSession(configuration: config)
    webSocketTask = urlSession?.webSocketTask(with: url)
    webSocketTask?.resume()
    active = true
    onConnected?()
    send(["type": "ping"])
    startPinging()
    receiveLoop()
  }

  func disconnect() {
    active = false
    pingTimer?.invalidate()
    pingTimer = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    onDisconnected?()
  }

  func send(_ payload: [String: Any]) {
    guard let task = webSocketTask,
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let str = String(data: data, encoding: .utf8) else { return }
    task.send(.string(str)) { _ in }
  }

  private func receiveLoop() {
    guard active else { return }
    webSocketTask?.receive { [weak self] result in
      guard let self, self.active else { return }
      switch result {
      case .success(let message):
        self.handleMessage(message)
        self.receiveLoop()
      case .failure:
        DispatchQueue.main.async { self.onDisconnected?() }
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    guard case .string(let text) = message,
          let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    let type = json["type"] as? String
    if type == "info" {
      onDeviceInfo?(json)
    } else if type == "output" {
      if let lines = json["lines"] as? [String] {
        for line in lines where !line.isEmpty {
          onTerminalOutput?(line)
        }
      } else if let output = json["output"] as? String {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
          onTerminalOutput?(String(line))
        }
      } else if let line = json["line"] as? String {
        onTerminalOutput?(line)
      }
    }
  }

  private func startPinging() {
    pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
      guard let self, self.active else { return }
      self.lastPingDate = Date()
      self.send(["type": "ping"])
      self.webSocketTask?.sendPing { [weak self] error in
        guard let self, error == nil, let start = self.lastPingDate else { return }
        let ms = max(1, Int(Date().timeIntervalSince(start) * 1000))
        self.onLatencyUpdate?(ms)
      }
    }
  }
}
