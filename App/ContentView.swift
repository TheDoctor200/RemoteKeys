import SwiftUI

struct ContentView: View {
  @State private var model = RemoteControlModel()
  @State private var showSetup = false

  @AppStorage("appTheme") private var appTheme = 0
  @AppStorage("appTint") private var appTint = 0

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          // Header
          HeaderView(model: model, onSetupTap: { showSetup = true })

          Divider()

          // Keyboard section
          KeyboardView(model: model)
            .frame(height: keyboardHeight(geo))
            .background(Color(uiColor: .systemGroupedBackground))

          Divider()

          // Trackpad section
          TrackpadView(model: model)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        // Terminal overlay
        if model.showTerminal {
          TerminalBarView(model: model)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.snappy(duration: 0.3), value: model.showTerminal)
    }
    .sheet(isPresented: $showSetup) {
      SetupView(model: model)
        .presentationDetents([.medium, .large])
    }
    .preferredColorScheme(colorScheme)
    .tint(tintColor)
  }

  private var colorScheme: ColorScheme? {
    switch appTheme {
    case 1: return .light
    case 2: return .dark
    default: return nil
    }
  }

  private var tintColor: Color {
    switch appTint {
    case 0: return .blue
    case 1: return .red
    case 2: return .green
    case 3: return .orange
    case 4: return .purple
    case 5: return .pink
    case 6: return .yellow
    case 7: return .mint
    case 8: return .cyan
    case 9: return .indigo
    case 10: return .teal
    case 11: return .brown
    case 12: return .gray
    case 13: return .primary
    default: return .blue
    }
  }

  private func keyboardHeight(_ geo: GeometryProxy) -> CGFloat {
    let total = geo.size.height
    // Keyboard gets ~38% of vertical space, trackpad gets the rest
    return max(220, min(280, total * 0.38))
  }
}
