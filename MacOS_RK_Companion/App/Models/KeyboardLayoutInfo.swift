import CoreGraphics
import Foundation

enum KeyboardLayoutInfo {
  private static let layoutKeyCodes: [String: [CGKeyCode]] = [
    "numberRow": [18, 19, 20, 21, 23, 22, 26, 28, 25, 29],
    "row1": [12, 13, 14, 15, 17, 16, 32, 34, 31, 35],
    "row2": [0, 1, 2, 3, 5, 4, 38, 40, 37],
    "row3": [6, 7, 8, 9, 11, 45, 46],
  ]

  private static let fallbackRows: [String: [String]] = [
    "numberRow": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "row1": ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    "row2": ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    "row3": ["z", "x", "c", "v", "b", "n", "m"],
  ]

  static func currentLayoutName() -> String {
    return displayName(for: buildKeyboardLayoutRows())
  }

  static func capsLockEnabled() -> Bool {
    CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
  }

  static func keyboardLayoutPayload() -> [String: Any] {
    let rows = buildKeyboardLayoutRows()
    return [
      "identifier": layoutIdentifier(for: rows),
      "name": displayName(for: rows),
      "row_order": Array(layoutKeyCodes.keys),
      "rows": rows,
    ]
  }

  private static func buildKeyboardLayoutRows() -> [String: [String]] {
    var rows: [String: [String]] = [:]

    for (rowName, keyCodes) in layoutKeyCodes {
      let fallbackRow = fallbackRows[rowName] ?? []
      var rowLabels: [String] = []

      for (index, keyCode) in keyCodes.enumerated() {
        let fallbackLabel = index < fallbackRow.count ? fallbackRow[index] : ""
        let label = translatedLabel(for: keyCode) ?? fallbackLabel
        rowLabels.append(label)
      }

      rows[rowName] = rowLabels
    }

    return rows
  }

  private static func translatedLabel(for keyCode: CGKeyCode) -> String? {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
      return nil
    }

    var actualLength = 0
    var characters = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &actualLength, unicodeString: &characters)
    guard actualLength > 0 else { return nil }

    let text = String(utf16CodeUnits: characters, count: actualLength)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return text.count == 1 ? text : nil
  }

  private static func layoutIdentifier(for rows: [String: [String]]) -> String {
    let signature = ["row1", "row2", "row3"].map { rows[$0, default: []].joined() }.joined(separator: "/")
    switch signature {
    case "qwertyuiop/asdfghjkl/zxcvbnm": return "us"
    case "azertyuiop/qsdfghjklm/wxcvbn": return "azerty"
    default: return "detected"
    }
  }

  private static func displayName(for rows: [String: [String]]) -> String {
    switch layoutIdentifier(for: rows) {
    case "us": return "US / QWERTY"
    case "azerty": return "French / AZERTY"
    default: return "Detected Keyboard Layout"
    }
  }
}
