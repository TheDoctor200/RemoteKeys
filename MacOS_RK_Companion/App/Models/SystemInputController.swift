import CoreGraphics
import Foundation

enum ModifierMapping {
  static func flags(fromBitmask bitmask: Int) -> CGEventFlags {
    var flags: CGEventFlags = []
    if bitmask & 1 != 0 { flags.insert(.maskShift) }
    if bitmask & 2 != 0 { flags.insert(.maskControl) }
    if bitmask & 4 != 0 { flags.insert(.maskAlternate) }
    if bitmask & 8 != 0 { flags.insert(.maskCommand) }
    return flags
  }
}

/// Posts synthetic keyboard and mouse events, mirroring the companion Python server's behavior.
enum SystemInputController {
  private static var dragActive = false

  static func handleKey(keyCode: CGKeyCode, modifiers: CGEventFlags, keyDown: Bool) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown) else { return }
    event.flags = modifiers
    event.post(tap: .cghidEventTap)

    guard keyDown else { return }
    // Client only sends keyDown for taps, so synthesize the matching keyUp shortly after.
    Thread.sleep(forTimeInterval: 0.004)
    guard let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
    upEvent.flags = modifiers
    upEvent.post(tap: .cghidEventTap)
  }

  static func moveMouse(dx: Int, dy: Int) {
    guard let locationEvent = CGEvent(source: nil) else { return }
    let current = locationEvent.location
    let newPoint = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))
    guard let moveEvent = CGEvent(
      mouseEventSource: nil,
      mouseType: .mouseMoved,
      mouseCursorPosition: newPoint,
      mouseButton: .left
    ) else { return }
    moveEvent.post(tap: .cghidEventTap)
  }

  static func scroll(dx: Int, dy: Int) {
    guard dx != 0 || dy != 0 else { return }
    guard let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 2,
      wheel1: Int32(-dy),
      wheel2: Int32(dx),
      wheel3: 0
    ) else { return }
    event.post(tap: .cghidEventTap)
  }

  static func click(button: CGMouseButton, doubleClick: Bool) {
    guard let locationEvent = CGEvent(source: nil) else { return }
    let position = locationEvent.location
    let (downType, upType) = eventTypes(for: button)
    let clickCount = doubleClick ? 2 : 1

    for _ in 0..<clickCount {
      if let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: position, mouseButton: button) {
        down.post(tap: .cghidEventTap)
      }
      if let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: position, mouseButton: button) {
        up.post(tap: .cghidEventTap)
      }
      if doubleClick {
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
  }

  static func drag(dx: Int, dy: Int, button: CGMouseButton) {
    guard let locationEvent = CGEvent(source: nil) else { return }
    let current = locationEvent.location
    let newPoint = CGPoint(x: current.x + CGFloat(dx), y: current.y + CGFloat(dy))

    if !dragActive {
      let (downType, _) = eventTypes(for: button)
      if let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: current, mouseButton: button) {
        down.post(tap: .cghidEventTap)
      }
      dragActive = true
    }

    let dragType: CGEventType
    switch button {
    case .left: dragType = .leftMouseDragged
    case .right: dragType = .rightMouseDragged
    default: dragType = .otherMouseDragged
    }
    if let drag = CGEvent(mouseEventSource: nil, mouseType: dragType, mouseCursorPosition: newPoint, mouseButton: button) {
      drag.post(tap: .cghidEventTap)
    }
  }

  static func releaseDrag(button: CGMouseButton) {
    guard let locationEvent = CGEvent(source: nil) else { return }
    let position = locationEvent.location
    let (_, upType) = eventTypes(for: button)
    if let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: position, mouseButton: button) {
      up.post(tap: .cghidEventTap)
    }
    dragActive = false
  }

  private static func eventTypes(for button: CGMouseButton) -> (down: CGEventType, up: CGEventType) {
    switch button {
    case .left: return (.leftMouseDown, .leftMouseUp)
    case .right: return (.rightMouseDown, .rightMouseUp)
    default: return (.otherMouseDown, .otherMouseUp)
    }
  }
}
