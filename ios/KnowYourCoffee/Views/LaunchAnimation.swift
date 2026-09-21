import SwiftUI

// Branded opening animation wrapped around the app's first screen. The static
// launch screen uses the same espresso background (LaunchBackground color set),
// so the handoff into this view has no flash.
struct LaunchAnimation<Content: View>: View {
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineProgress: CGFloat = 0
    @State private var markScale: CGFloat = 0.98
    @State private var showsContent = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Always in the hierarchy so HomeView's .task loads shops while the
            // mark draws; only its opacity changes.
            content
                .opacity(showsContent ? 1 : 0)

            // Backdrop and mark fade out together via the transition. Applying
            // .opacity to them directly would not animate, because flipping
            // showsContent removes this branch in the same frame.
            if !showsContent {
                ZStack {
                    // Static hexes, not the dynamic palette: the opening mark is
                    // espresso-on-cream in both themes, matching LaunchBackground.
                    LaunchAnimation.backdrop

                    CoffeeSnobContour()
                        .trim(from: 0, to: lineProgress)
                        .stroke(
                            LaunchAnimation.stroke,
                            style: StrokeStyle(
                                lineWidth: 5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 270)
                        .padding(44)
                        .scaleEffect(markScale)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .background(LaunchAnimation.backdrop.ignoresSafeArea())
        .task {
            await playOpeningAnimation()
        }
    }

    private static var backdrop: Color { Color(hex: 0x2B1D14) }
    private static var stroke: Color { Color(hex: 0xFBF8F3) }

    @MainActor
    private func playOpeningAnimation() async {
        guard !showsContent else { return }

        if reduceMotion {
            lineProgress = 1
            try? await Task.sleep(for: .milliseconds(180))
            showsContent = true
            return
        }

        // Draw the free-form contour.
        withAnimation(.easeInOut(duration: 0.72)) {
            lineProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(720))

        // A restrained finish rather than a bouncy logo animation.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
            markScale = 1.025
        }

        try? await Task.sleep(for: .milliseconds(160))

        // Reveal the real first screen without delaying interaction for long.
        withAnimation(.easeOut(duration: 0.24)) {
            showsContent = true
        }
    }
}

/// A normalized, free-form contour combining a coffee cup and monocle.
/// The path order is intentional because `trim` reveals it from left to right.
private struct CoffeeSnobContour: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * w, y: y * h)
        }

        var path = Path()
        path.move(to: point(0.13, 0.31))

        // Cup rim and right shoulder.
        path.addCurve(
            to: point(0.67, 0.31),
            control1: point(0.24, 0.28),
            control2: point(0.52, 0.32)
        )
        path.addCurve(
            to: point(0.73, 0.36),
            control1: point(0.71, 0.31),
            control2: point(0.74, 0.32)
        )

        // Handle, drawn as a single loose loop.
        path.addCurve(
            to: point(0.88, 0.35),
            control1: point(0.76, 0.39),
            control2: point(0.82, 0.33)
        )
        path.addCurve(
            to: point(0.90, 0.52),
            control1: point(0.95, 0.34),
            control2: point(0.96, 0.47)
        )
        path.addCurve(
            to: point(0.72, 0.52),
            control1: point(0.85, 0.56),
            control2: point(0.78, 0.51)
        )

        // Monocle stem and small flourish.
        path.addCurve(
            to: point(0.69, 0.64),
            control1: point(0.72, 0.57),
            control2: point(0.73, 0.63)
        )
        path.addCurve(
            to: point(0.66, 0.60),
            control1: point(0.64, 0.68),
            control2: point(0.62, 0.60)
        )
        path.addCurve(
            to: point(0.70, 0.56),
            control1: point(0.66, 0.55),
            control2: point(0.70, 0.55)
        )

        // Cup bowl closes the continuous line.
        path.addCurve(
            to: point(0.48, 0.77),
            control1: point(0.66, 0.70),
            control2: point(0.58, 0.77)
        )
        path.addCurve(
            to: point(0.13, 0.31),
            control1: point(0.28, 0.79),
            control2: point(0.14, 0.57)
        )

        // Monocle lens. This appears near the end of the draw animation.
        path.move(to: point(0.58, 0.35))
        path.addCurve(
            to: point(0.68, 0.45),
            control1: point(0.64, 0.35),
            control2: point(0.68, 0.39)
        )
        path.addCurve(
            to: point(0.58, 0.55),
            control1: point(0.68, 0.51),
            control2: point(0.64, 0.55)
        )
        path.addCurve(
            to: point(0.48, 0.45),
            control1: point(0.52, 0.55),
            control2: point(0.48, 0.51)
        )
        path.addCurve(
            to: point(0.58, 0.35),
            control1: point(0.48, 0.39),
            control2: point(0.52, 0.35)
        )

        return path
    }
}

#Preview {
    LaunchAnimation {
        HomeView()
    }
}
