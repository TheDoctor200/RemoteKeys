import AVFoundation
import SwiftUI
import UIKit

struct SetupView: View {
  @Bindable var model: RemoteControlModel
  @Environment(\.dismiss) private var dismiss

  @AppStorage("appTheme") private var appTheme = 0 // 0 = System, 1 = Light, 2 = Dark
  @AppStorage("appTint") private var appTint = 0 // 0 = Blue, 1 = Red, 2 = Green, 3 = Orange, 4 = Purple
  @State private var showingScanner = false
  @State private var scannerErrorMessage: String?

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

          Button {
            showingScanner = true
          } label: {
            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .foregroundStyle(.secondary)
        } header: {
          Text("Connection")
        } footer: {
          Text("Install the RemoteKeys server app on your MacBook and ensure both devices are on the same Wi-Fi network. You can also scan the QR code from the Mac companion to fill the address and port automatically.")
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

        // Appearance
        Section {
          Picker("Theme", selection: $appTheme) {
            Text("System").tag(0)
            Text("Light").tag(1)
            Text("Dark").tag(2)
          }
          Picker("Accent Color", selection: $appTint) {
            Text("Blue").tag(0)
            Text("Red").tag(1)
            Text("Green").tag(2)
            Text("Orange").tag(3)
            Text("Purple").tag(4)
            Text("Pink").tag(5)
            Text("Yellow").tag(6)
            Text("Mint").tag(7)
            Text("Cyan").tag(8)
            Text("Indigo").tag(9)
            Text("Teal").tag(10)
            Text("Brown").tag(11)
            Text("Gray").tag(12)
            Text("Black / White").tag(13)
          }
        } header: {
          Text("Appearance")
        }

        // Actions
        Section {
          if model.connectionState != .connected {
            Button {
              model.toggleConnection()
              dismiss()
            } label: {
              HStack {
                Spacer()
                Label(model.connectionActionLabel, systemImage: model.connectionActionSystemImage)
                  .fontWeight(.semibold)
                Spacer()
              }
            }
            .disabled(model.connectionActionDisabled)
          } else {
            Button(role: .destructive) {
              model.toggleConnection()
            } label: {
              HStack {
                Spacer()
                Label(model.connectionActionLabel, systemImage: model.connectionActionSystemImage)
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
      .sheet(isPresented: $showingScanner) {
        QRScannerView { scannedCode in
          if model.applyConnectionString(scannedCode) {
            showingScanner = false
          } else {
            scannerErrorMessage = "The QR code did not contain a valid RemoteKeys address and port."
            showingScanner = false
          }
        }
        .ignoresSafeArea()
      }
      .alert("Scan QR Code", isPresented: Binding(
        get: { scannerErrorMessage != nil },
        set: { if !$0 { scannerErrorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {
          scannerErrorMessage = nil
        }
      } message: {
        Text(scannerErrorMessage ?? "")
      }
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

private struct QRScannerView: UIViewControllerRepresentable {
  var onCodeScanned: (String) -> Void

  func makeUIViewController(context: Context) -> ScannerViewController {
    let controller = ScannerViewController()
    controller.onCodeScanned = onCodeScanned
    return controller
  }

  func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
    uiViewController.onCodeScanned = onCodeScanned
  }
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCodeScanned: ((String) -> Void)?

  private let session = AVCaptureSession()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let messageLabel = UILabel()
  private var didScanCode = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureScanner()
    configureOverlay()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
  }

  private func configureScanner() {
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      showUnavailableMessage()
      return
    }

    session.addInput(input)

    let metadataOutput = AVCaptureMetadataOutput()
    guard session.canAddOutput(metadataOutput) else {
      showUnavailableMessage()
      return
    }

    session.addOutput(metadataOutput)
    metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
    metadataOutput.metadataObjectTypes = [.qr]

    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.insertSublayer(previewLayer, at: 0)

    DispatchQueue.global(qos: .userInitiated).async { [session] in
      session.startRunning()
    }
  }

  private func configureOverlay() {
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    messageLabel.text = "Point the camera at the QR code shown in the Mac companion app."
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    messageLabel.textColor = .white
    messageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    messageLabel.layer.cornerRadius = 14
    messageLabel.layer.masksToBounds = true
    messageLabel.font = .preferredFont(forTextStyle: .callout)

    view.addSubview(messageLabel)
    NSLayoutConstraint.activate([
      messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      messageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32)
    ])
  }

  private func showUnavailableMessage() {
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    messageLabel.text = "Camera scanning is unavailable on this device."
    messageLabel.numberOfLines = 0
    messageLabel.textAlignment = .center
    messageLabel.textColor = .white
    messageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
    messageLabel.layer.cornerRadius = 14
    messageLabel.layer.masksToBounds = true
    messageLabel.font = .preferredFont(forTextStyle: .callout)

    view.addSubview(messageLabel)
    NSLayoutConstraint.activate([
      messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
    ])
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard !didScanCode,
          let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          metadataObject.type == .qr,
          let stringValue = metadataObject.stringValue else { return }

    didScanCode = true
    session.stopRunning()
    onCodeScanned?(stringValue)
  }
}
