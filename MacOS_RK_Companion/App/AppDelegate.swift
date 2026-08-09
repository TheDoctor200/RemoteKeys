import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if AppSettings.shared.runSilentlyInBackground {
      NSApp.setActivationPolicy(.accessory)
    }
    WebSocketServer.shared.start(port: UInt16(AppSettings.shared.port))
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification: Notification) {
    WebSocketServer.shared.stop()
  }
}
