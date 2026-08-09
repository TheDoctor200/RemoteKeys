import Foundation

enum NetworkInfo {
  static func localIPAddress() -> String? {
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
    defer { freeifaddrs(ifaddrPtr) }

    var address: String?
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let flags = Int32(ptr.pointee.ifa_flags)
      let addrFamily = ptr.pointee.ifa_addr.pointee.sa_family
      guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0, addrFamily == UInt8(AF_INET) else {
        continue
      }
      guard String(cString: ptr.pointee.ifa_name) == "en0" else { continue }

      var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      getnameinfo(
        ptr.pointee.ifa_addr,
        socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
        &hostname,
        socklen_t(hostname.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      address = String(cString: hostname)
      break
    }
    return address
  }
}
