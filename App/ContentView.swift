import SwiftUI

struct ContentView: View {
  @State private var model = RemoteControlModel()
  @State private var showSetup = false

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
  }

  private func keyboardHeight(_ geo: GeometryProxy) -> CGFloat {
    let total = geo.size.height
    // Keyboard gets ~38% of vertical space, trackpad gets the rest
    return max(220, min(280, total * 0.38))
  }
}
