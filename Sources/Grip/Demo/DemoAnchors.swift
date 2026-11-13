#if os(macOS)
import SwiftUI

/// Remembers where named controls are on screen, so the scripted demo can point at them.
@MainActor
final class DemoAnchors {
    static let shared = DemoAnchors()
    var frames: [String: CGRect] = [:]
}

extension View {
    func demoAnchor(_ id: String) -> some View {
        background(
            GeometryReader { g in
                Color.clear
                    .onAppear { DemoAnchors.shared.frames[id] = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in DemoAnchors.shared.frames[id] = f }
            }
        )
    }
}
#endif
