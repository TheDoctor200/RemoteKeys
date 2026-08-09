import SwiftUI

@main
struct AppDefinition: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Bindable private var settings = AppSettings.shared

  var body: some Scene {
    WindowGroup(id: "main") {
      ContentView()
        .environment(settings)
    }
    .windowResizability(.contentSize)

    MenuBarExtra("RemoteKeys Companion", systemImage: "keyboard.fill", isInserted: $settings.showInMenuBar) {
      MenuBarView()
        .environment(settings)
    }
    .menuBarExtraStyle(.window)
  }
}
