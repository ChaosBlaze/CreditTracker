import SwiftUI

struct ProgressRingView: View {
    let fraction: Double
    let startColor: Color
    let endColor: Color
    var lineWidth: CGFloat = 6
    var size: CGFloat = 44

    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(
                    startColor.opacity(0.18),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [startColor, endColor]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center label
            if fraction >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(endColor)
            } else {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedFraction = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animatedFraction = newValue
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ProgressRingView(fraction: 0.0, startColor: .blue, endColor: .purple)
        ProgressRingView(fraction: 0.5, startColor: .orange, endColor: .pink)
        ProgressRingView(fraction: 1.0, startColor: .green, endColor: .teal)
    }
    .padding()
}
