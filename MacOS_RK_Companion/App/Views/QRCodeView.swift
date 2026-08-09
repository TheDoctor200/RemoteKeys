import SwiftUI

struct QRCodeView: View {
  var content: String

  var body: some View {
    Group {
      if let cgImage = QRCodeGenerator.image(for: content) {
        Image(decorative: cgImage, scale: 1)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary)
          .overlay {
            Image(systemName: "qrcode")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
          }
      }
    }
    .accessibilityLabel("QR code to connect to \(content)")
  }
}
