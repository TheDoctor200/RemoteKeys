import SwiftUI

struct SetupView: View {
  @Bindable var model: RemoteControlModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        // Connection
        Section {
          HStack {
            Label("Host Address", systemImage: "network")
            Spacer()
            TextField("192.168.1.100", text: $model.hostAddress)
              .multilineTextAlignment(.trailing)
              .keyboardType(.numbersAndPunctuation)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .foregroundStyle(.secondary)
          }
          HStack {
            Label("Port", systemImage: "number")
            Spacer()
            TextField("8765", text: $model.hostPort)
              .multilineTextAlignment(.trailing)
              .keyboardType(.numberPad)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Connection")
        } footer: {
          Text("Install the RemoteKeys server app on your MacBook and ensure both devices are on the same Wi-Fi network.")
        }

        // Status
        Section {
          HStack {
            Label("Status", systemImage: "circle.fill")
              .foregroundStyle(statusColor)
            Spacer()
            Text(statusLabel)
              .foregroundStyle(.secondary)
          }

          if model.connectionState == .connected {
            HStack {
              Label("Latency", systemImage: "clock")
              Spacer()
              Text("\(model.latency) ms")
                .foregroundStyle(model.latency < 30 ? Color.green : (model.latency < 80 ? Color.orange : Color.red))
                .monospacedDigit()
            }
            HStack {
              Label("Type", systemImage: model.connectionType.icon)
              Spacer()
              Text(model.connectionType.label)
                .foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Status")
        }

        // Trackpad
        Section {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Label("Cursor Speed", systemImage: "cursorarrow.rays")
              Spacer()
              Text(String(format: "%.1f×", model.sensitivity))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.sensitivity, in: 0.5...5.0) {
              Text("Cursor Speed")
            } minimumValueLabel: {
              Image(systemName: "tortoise")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } maximumValueLabel: {
              Image(systemName: "hare")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Label("Scroll Speed", systemImage: "arrow.up.and.down")
              Spacer()
              Text(String(format: "%.1f×", model.scrollSensitivity))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: $model.scrollSensitivity, in: 0.5...3.0) {
              Text("Scroll Speed")
            } minimumValueLabel: {
              Image(systemName: "minus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } maximumValueLabel: {
              Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        } header: {
          Text("Trackpad")
        }

        // Actions
        Section {
          if model.connectionState != .connected {
            Button {
              model.connect()
              dismiss()
            } label: {
              HStack {
                Spacer()
                Label("Connect", systemImage: "cable.connector")
                  .fontWeight(.semibold)
                Spacer()
              }
            }
            .disabled(model.hostAddress.isEmpty)
          } else {
            Button(role: .destructive) {
              model.disconnect()
            } label: {
              HStack {
                Spacer()
                Label("Disconnect", systemImage: "cable.connector.slash")
                  .fontWeight(.semibold)
                Spacer()
              }
            }
          }
        } header: {
          Text("Actions")
        }
      }
      .navigationTitle("RemoteKeys")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .fontWeight(.semibold)
        }
      }
    }
  }

  private var statusColor: Color {
    switch model.connectionState {
    case .connected: return .green
    case .connecting: return .yellow
    case .disconnected: return .red
    }
  }

  private var statusLabel: String {
    switch model.connectionState {
    case .connected: return "Connected"
    case .connecting: return "Connecting…"
    case .disconnected: return "Disconnected"
    }
  }
}
