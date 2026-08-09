import Foundation
import IOKit.ps

enum DeviceStatus {
  static func cpuUsagePercentage() -> Double {
    var loadAverages = [Double](repeating: 0, count: 3)
    getloadavg(&loadAverages, 3)
    let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
    return min(100, (loadAverages[0] / cores) * 100)
  }

  static func batteryPercentage() -> Double? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
    guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    guard let source = sources.first else { return nil }
    guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
      return nil
    }
    guard let current = description[kIOPSCurrentCapacityKey] as? Int,
          let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else {
      return nil
    }
    return Double(current) / Double(max) * 100
  }
}
