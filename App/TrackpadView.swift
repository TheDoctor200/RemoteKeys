import SwiftUI

struct TrackpadView: View {
  @Bindable var model: RemoteControlModel

  @State private var lastDrag: DragGesture.Value? = nil
  @State private var tapHaptic = false
  @State private var pointerPos: CGPoint = .zero
  @State private var showPointer = false
  @State private var pinchAnchorScale: CGFloat = 1.0

  var body: some View {
    VStack(spacing: 10) {
      // Controls bar
      HStack(spacing: 12) {
        Picker("Mode", selection: $model.trackpadMode) {
          ForEach(TrackpadMode.allCases, id: \.self) { mode in
            Label(mode.rawValue, systemImage: mode == .cursor ? "cursorarrow" : (mode == .scroll ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.draw"))
              .tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        // Sensitivity
        HStack(spacing: 6) {
          Image(systemName: "gauge.with.dots.needle.33percent")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
          Slider(value: $model.sensitivity, in: 0.5...5.0) {
            Text("Speed")
          } minimumValueLabel: {
            Image(systemName: "minus")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          } maximumValueLabel: {
            Image(systemName: "plus")
              .font(.system(size: 10))
              .foregroundStyle(.secondary)
          }
          .frame(width: 90)
        }
      }
      .padding(.horizontal, 4)

      // Trackpad surface
      ZStack {
        // Background
        RoundedRectangle(cornerRadius: 20)
          .fill(
            LinearGradient(
              stops: [
                .init(color: Color(uiColor: .secondarySystemBackground), location: 0),
                .init(color: Color(uiColor: .tertiarySystemBackground), location: 1),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(
            RoundedRectangle(cornerRadius: 20)
              .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

        // Mode hint
        VStack(spacing: 6) {
          Image(systemName: model.trackpadMode == .cursor ? "cursorarrow.rays" : (model.trackpadMode == .scroll ? "arrow.up.and.down.and.arrow.left.and.right" : "hand.draw"))
            .font(.system(size: 32))
            .foregroundStyle(.primary.opacity(0.06))

          Text(model.trackpadMode == .cursor ? "Move cursor" : (model.trackpadMode == .scroll ? "Scroll" : "Drag"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.12))
        }

        // Touch feedback dot
        if showPointer {
          Circle()
            .fill(Color.accentColor.opacity(0.6))
            .frame(width: 18, height: 18)
            .blur(radius: 2)
            .position(pointerPos)
            .allowsHitTesting(false)
            .transition(.opacity)
        }

        // Hint strip at bottom
        VStack {
          Spacer()
          HStack(spacing: 20) {
            Label("Tap", systemImage: "hand.tap")
            Label("Hold → Right click", systemImage: "hand.point.up")
            Label("Pinch → Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
          }
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .padding(.bottom, 10)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(RoundedRectangle(cornerRadius: 20))
      .gesture(
        DragGesture(minimumDistance: 2)
          .onChanged { val in
            if let last = lastDrag {
              let dx = val.translation.width - last.translation.width
              let dy = val.translation.height - last.translation.height
              if model.trackpadMode == .cursor {
                model.sendMouseMove(dx: dx, dy: dy)
              } else if model.trackpadMode == .drag {
                model.sendMouseDrag(dx: dx, dy: dy)
              } else {
                model.sendScroll(dx: -dx * 0.6, dy: -dy * 0.6)
              }
            }
            lastDrag = val
            pointerPos = val.location
            showPointer = true
          }
          .onEnded { _ in
            lastDrag = nil
            if model.trackpadMode == .drag {
              model.sendMouseDragEnd()
            }
            withAnimation(.easeOut(duration: 0.3)) { showPointer = false }
          }
          .simultaneously(with:
            MagnifyGesture()
              .onChanged { val in
                let delta = val.magnification / pinchAnchorScale
                model.sendZoom(scale: delta)
                pinchAnchorScale = val.magnification
              }
              .onEnded { _ in pinchAnchorScale = 1.0 }
          )
      )
      .onTapGesture(count: 2) {
        tapHaptic.toggle()
        model.sendDoubleClick()
      }
      .onTapGesture {
        tapHaptic.toggle()
        model.sendClick()
      }
      .onLongPressGesture(minimumDuration: 0.45) {
        tapHaptic.toggle()
        model.sendClick(button: "right")
      }
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: tapHaptic)

      // Button bar
      HStack(spacing: 8) {
        TrackpadActionButton(label: "Left Click", icon: "cursorarrow.click", hapticTrigger: $tapHaptic) {
          model.sendClick(button: "left")
        }
        TrackpadActionButton(label: "Right Click", icon: "cursorarrow.click.2", hapticTrigger: $tapHaptic) {
          model.sendClick(button: "right")
        }
        TrackpadActionButton(label: "Middle", icon: "cursorarrow.motionlines.click", hapticTrigger: $tapHaptic) {
          model.sendClick(button: "middle")
        }
      }
    }
  }
}

struct TrackpadActionButton: View {
  var label: String
  var icon: String
  @Binding var hapticTrigger: Bool
  var action: () -> Void

  @State private var pressed = false

  var body: some View {
    Button {
      hapticTrigger.toggle()
      pressed = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
      action()
    } label: {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 15, weight: .medium))
        Text(label)
          .font(.system(size: 10, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(Color(uiColor: .secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
      )
      .scaleEffect(pressed ? 0.93 : 1.0)
      .animation(.snappy(duration: 0.1), value: pressed)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
  }
}
