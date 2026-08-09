import AppKit
import Foundation

@Observable
final class AppSettings {
  static let shared = AppSettings()

  var port: Int {
    didSet {
      UserDefaults.standard.set(port, forKey: "port")
      if WebSocketServer.shared.isRunning {
        WebSocketServer.shared.restart(port: UInt16(port))
      }
    }
  }

  var launchAtLogin: Bool {
    didSet {
      UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
      LoginItemManager.setEnabled(launchAtLogin)
    }
  }

  var runSilentlyInBackground: Bool {
    didSet {
      UserDefaults.standard.set(runSilentlyInBackground, forKey: "runSilentlyInBackground")
      NSApp.setActivationPolicy(runSilentlyInBackground ? .accessory : .regular)
    }
  }

  var showInMenuBar: Bool {
    didSet { UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar") }
  }

  private init() {
    let defaults = UserDefaults.standard
    port = defaults.object(forKey: "port") as? Int ?? 8765
    launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    runSilentlyInBackground = defaults.bool(forKey: "runSilentlyInBackground")
    showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
  }
}
