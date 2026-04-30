import SwiftUI

struct HeaderView: View {
  var model: RemoteControlModel
  var onSetupTap: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      connectionStatus
      Spacer(minLength: 8)
      deviceInfo
      Spacer(minLength: 8)
      actionButtons
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }

  // MARK: Connection Status

  private var connectionStatus: some View {
    HStack(spacing: 8) {
      ZStack {
        Circle()
          .fill(statusColor.opacity(0.25))
          .frame(width: 16, height: 16)
          .scaleEffect(model.connectionState == .connected ? 1.4 : 1.0)
          .animation(
            model.connectionState == .connected
              ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
              : .default,
            value: model.connectionState
          )
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(statusLabel)
          .font(.system(size: 12, weight: .semibold))

        HStack(spacing: 4) {
          Image(systemName: model.connectionType.icon)
            .font(.system(size: 10))
          if model.connectionState == .connected {
            Text("\(model.latency) ms")
              .font(.system(size: 10))
          } else {
            Text(model.connectionType.label)
              .font(.system(size: 10))
          }
        }
        .foregroundStyle(.secondary)
      }
    }
    .frame(minWidth: 90, alignment: .leading)
  }

  // MARK: Device Info

  private var deviceInfo: some View {
    VStack(spacing: 3) {
      Text(model.macName)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)

      if model.connectionState == .connected {
        HStack(spacing: 10) {
          // Battery
          HStack(spacing: 3) {
            Image(systemName: batteryIcon)
              .font(.system(size: 11))
              .foregroundStyle(batteryColor)
            Text("\(Int(model.batteryLevel * 100))%")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
          // CPU
          HStack(spacing: 3) {
            Image(systemName: "cpu")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
            Text("\(Int(model.cpuUsage * 100))%")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
      } else {
        Text("—")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
      }
    }
    .multilineTextAlignment(.center)
  }

  // MARK: Actions

  private var actionButtons: some View {
    HStack(spacing: 14) {
      Button {
        withAnimation(.snappy(duration: 0.3)) {
          model.showTerminal.toggle()
        }
      } label: {
        Image(systemName: "terminal")
          .font(.system(size: 17))
          .foregroundStyle(model.showTerminal ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      }
      .accessibilityLabel("Toggle Terminal")

      Button(action: onSetupTap) {
        Image(systemName: "gear")
          .font(.system(size: 17))
          .foregroundStyle(.secondary)
      }
      .accessibilityLabel("Settings")
    }
    .frame(minWidth: 90, alignment: .trailing)
  }

  // MARK: Helpers

  private var statusColor: Color {
    switch model.connectionState {
    case .connected: return .green
    case .connecting: return .yellow
    case .disconnected: return Color(red: 1, green: 0.3, blue: 0.3)
    }
  }

  private var statusLabel: String {
    switch model.connectionState {
    case .connected: return "Connected"
    case .connecting: return "Connecting…"
    case .disconnected: return "Disconnected"
    }
  }

  private var batteryIcon: String {
    switch model.batteryLevel {
    case 0.75...: return "battery.100"
    case 0.50...: return "battery.75"
    case 0.25...: return "battery.50"
    case 0.10...: return "battery.25"
    default: return "battery.0"
    }
  }

  private var batteryColor: Color {
    if model.batteryLevel < 0.2 { return .red }
    if model.batteryLevel < 0.4 { return .orange }
    return .green
  }
}
