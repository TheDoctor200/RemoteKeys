import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
  static func image(for string: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else { return nil }
    let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    return CIContext().createCGImage(scaled, from: scaled.extent)
  }
}
