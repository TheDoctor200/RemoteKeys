import SwiftUI

// MARK: - Key Model

struct VKey: Identifiable {
  let id = UUID()
  var label: String
  var value: String
  var flex: CGFloat = 1.0
  var icon: String? = nil
  var modifier: ModifierKey? = nil

  var isModifier: Bool { modifier != nil }

  static func char(_ c: String) -> VKey { VKey(label: c, value: c) }
  static func special(_ label: String, _ value: String, flex: CGFloat = 1.5, icon: String? = nil) -> VKey {
    VKey(label: label, value: value, flex: flex, icon: icon)
  }
  static func mod(_ key: ModifierKey, flex: CGFloat = 1.3) -> VKey {
    VKey(label: key.shortLabel, value: key.rawValue, flex: flex, modifier: key)
  }
}

// MARK: - Keyboard View

struct KeyboardView: View {
  var model: RemoteControlModel

  private let fnRow: [VKey] = [
    VKey(label: "esc", value: "escape", flex: 1),
    VKey(label: "F1", value: "f1"), VKey(label: "F2", value: "f2"),
    VKey(label: "F3", value: "f3"), VKey(label: "F4", value: "f4"),
    VKey(label: "F5", value: "f5"), VKey(label: "F6", value: "f6"),
    VKey(label: "F7", value: "f7"), VKey(label: "F8", value: "f8"),
    VKey(label: "F9", value: "f9"), VKey(label: "F10", value: "f10"),
    VKey(label: "F11", value: "f11"), VKey(label: "F12", value: "f12"),
  ]

  private let numRow: [VKey] = [
    .char("1"), .char("2"), .char("3"), .char("4"), .char("5"),
    .char("6"), .char("7"), .char("8"), .char("9"), .char("0"),
    .special("⌫", "backspace", flex: 1.5, icon: "delete.backward.fill"),
  ]

  private let row1: [VKey] = [
    .char("q"), .char("w"), .char("e"), .char("r"), .char("t"),
    .char("y"), .char("u"), .char("i"), .char("o"), .char("p"),
  ]

  private let row2: [VKey] = [
    .char("a"), .char("s"), .char("d"), .char("f"), .char("g"),
    .char("h"), .char("j"), .char("k"), .char("l"),
    .special("↵", "return", flex: 1.5, icon: "return"),
  ]

  private let row3: [VKey] = [
    .mod(.shift, flex: 1.5),
    .char("z"), .char("x"), .char("c"), .char("v"),
    .char("b"), .char("n"), .char("m"),
    .mod(.shift, flex: 1.5),
  ]

  private let row4: [VKey] = [
    .mod(.control, flex: 1.3),
    .mod(.option, flex: 1.3),
    .mod(.command, flex: 1.3),
    VKey(label: "space", value: "space", flex: 3.5),
    VKey(label: "⇥", value: "tab", flex: 1.2, icon: "arrow.right.to.line"),
  ]

  private let arrowRow: [VKey] = [
    VKey(label: "←", value: "left", flex: 1, icon: "arrow.left"),
    VKey(label: "↑", value: "up", flex: 1, icon: "arrow.up"),
    VKey(label: "↓", value: "down", flex: 1, icon: "arrow.down"),
    VKey(label: "→", value: "right", flex: 1, icon: "arrow.right"),
  ]

  var body: some View {
    VStack(spacing: 5) {
      // Top control row
      HStack(spacing: 6) {
        Button {
          withAnimation(.snappy(duration: 0.2)) { model.showFnKeys.toggle() }
        } label: {
          Text("fn")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(model.showFnKeys ? Color.accentColor : Color(uiColor: .systemFill))
            .foregroundStyle(model.showFnKeys ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)

        // Active modifier chips
        HStack(spacing: 4) {
          ForEach(ModifierKey.allCases, id: \.self) { mod in
            if model.activeModifiers.contains(mod) {
              Text(mod.symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .transition(.scale.combined(with: .opacity))
            }
          }
        }
        .animation(.snappy(duration: 0.15), value: model.activeModifiers)

        Spacer()

        if model.capsLock {
          Label("CAPS", systemImage: "capslock.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 4)

      if model.showFnKeys {
        keyRow(fnRow)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      keyRow(numRow)
      keyRow(row1)
      keyRow(row2)
      keyRow(row3)

      HStack(spacing: 5) {
        keyRow(row4)
        keyRow(arrowRow)
          .frame(width: keyRowArrowWidth)
      }
    }
    .animation(.snappy(duration: 0.2), value: model.showFnKeys)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  // Arrow keys section has 4 equal keys — compute a fixed width
  private var keyRowArrowWidth: CGFloat { 4 * 32 + 3 * 4 }

  private func keyRow(_ keys: [VKey]) -> some View {
    GeometryReader { geo in
      let spacing: CGFloat = 4
      let totalFlex = keys.reduce(0) { $0 + $1.flex }
      let usable = geo.size.width - spacing * CGFloat(keys.count - 1)
      let unit = usable / totalFlex

      HStack(spacing: spacing) {
        ForEach(keys) { key in
          KeyButton(key: key, model: model)
            .frame(width: unit * key.flex)
        }
      }
    }
    .frame(height: 36)
  }
}

// MARK: - Key Button

struct KeyButton: View {
  var key: VKey
  var model: RemoteControlModel

  @State private var isPressed = false
  @State private var hapticTrigger = false

  private var isActive: Bool {
    guard let mod = key.modifier else { return false }
    return model.activeModifiers.contains(mod)
  }

  var body: some View {
    Button {
      handleTap()
    } label: {
      ZStack {
        keyBackground
          .clipShape(RoundedRectangle(cornerRadius: 7))
          .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)

        keyLabel
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .scaleEffect(isPressed ? 0.88 : 1.0)
      .animation(.snappy(duration: 0.1), value: isPressed)
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: hapticTrigger)
  }

  @ViewBuilder
  private var keyLabel: some View {
    if let icon = key.icon, key.label != "⌫" && key.label != "↵" && key.label != "⇥" {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(labelColor)
    } else if let icon = key.icon {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(labelColor)
    } else {
      Text(key.label)
        .font(.system(
          size: key.label.count > 3 ? 10 : (key.label.count > 1 ? 12 : 16),
          weight: key.isModifier ? .semibold : .regular,
          design: key.isModifier ? .rounded : .default
        ))
        .foregroundStyle(labelColor)
    }
  }

  @ViewBuilder
  private var keyBackground: some View {
    if isActive {
      Color.accentColor
    } else if key.isModifier {
      Color(uiColor: .secondarySystemFill)
    } else if key.value == "space" {
      Color(uiColor: .systemFill).opacity(0.6)
    } else {
      Color(uiColor: .systemBackground).opacity(0.9)
    }
  }

  private var labelColor: Color {
    isActive ? .white : .primary
  }

  private func handleTap() {
    hapticTrigger.toggle()
    if let mod = key.modifier {
      model.toggleModifier(mod)
    } else {
      isPressed = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        isPressed = false
      }
      model.sendKey(key.value)
    }
  }
}
