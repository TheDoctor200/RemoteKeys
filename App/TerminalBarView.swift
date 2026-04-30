import SwiftUI

struct TerminalBarView: View {
  var model: RemoteControlModel

  @State private var commandText = ""
  @State private var isExpanded = false
  @FocusState private var focused: Bool
  @State private var hapticTrigger = false

  var body: some View {
    VStack(spacing: 0) {
      if isExpanded {
        outputPanel
        Divider()
      }
      inputBar
    }
    .background(.bar)
    .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 0, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: isExpanded ? 16 : 0, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
    )
    .padding(.horizontal, isExpanded ? 12 : 0)
    .padding(.bottom, isExpanded ? 12 : 0)
    .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: hapticTrigger)
  }

  private var outputPanel: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 3) {
          ForEach(model.terminalOutput) { line in
            Text(line.text)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(line.isOutput ? Color.green : Color(uiColor: .label).opacity(0.6))
              .textSelection(.enabled)
              .id(line.id)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 160)
      .background(Color.black.opacity(0.82))
      .onChange(of: model.terminalOutput.count) { _, _ in
        if let last = model.terminalOutput.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

  private var inputBar: some View {
    HStack(spacing: 10) {
      Button {
        withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
      } label: {
        Image(systemName: isExpanded ? "terminal.fill" : "terminal")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Color.green)
      }
      .accessibilityLabel("Toggle output")

      TextField("Enter command…", text: $commandText)
        .font(.system(size: 14, design: .monospaced))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focused)
        .onSubmit { sendCommand() }

      if !commandText.isEmpty {
        Button { sendCommand() } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(Color.accentColor)
        }
        .transition(.scale.combined(with: .opacity))
      }

      Button {
        withAnimation(.snappy(duration: 0.3)) {
          model.showTerminal = false
          focused = false
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 22))
          .foregroundStyle(.secondary)
      }
      .accessibilityLabel("Close terminal")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .animation(.snappy(duration: 0.15), value: commandText.isEmpty)
  }

  private func sendCommand() {
    let cmd = commandText.trimmingCharacters(in: .whitespaces)
    guard !cmd.isEmpty else { return }
    hapticTrigger.toggle()
    model.sendTerminalCommand(cmd)
    commandText = ""
    withAnimation(.snappy) { isExpanded = true }
  }
}
