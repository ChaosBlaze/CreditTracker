import SwiftUI

/// Animated numeric display where each digit rolls vertically to its target.
/// Creates the airport departure board / odometer effect.
struct OdometerText: View {
    let value: Double
    var prefix: String = "$"
    var showSign: Bool = false
    var font: Font = .system(size: 34, weight: .bold, design: .monospaced)
    var color: AnyShapeStyle = AnyShapeStyle(.primary)

    @State private var displayDigits: [OdometerDigit] = []
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 0) {
            if showSign {
                Text(value >= 0 ? "+" : "-")
                    .font(font)
                    .foregroundStyle(color)
            }

            Text(prefix)
                .font(font)
                .foregroundStyle(color)

            ForEach(Array(displayDigits.enumerated()), id: \.offset) { index, digit in
                SingleDigitView(
                    digit: digit.value,
                    isComma: digit.isComma,
                    font: font,
                    color: color,
                    delay: Double(displayDigits.count - 1 - index) * 0.05
                )
            }
        }
        .onAppear {
            displayDigits = formatDigits(0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                displayDigits = formatDigits(abs(value))
                hasAppeared = true
            }
        }
        .onChange(of: value) { _, newValue in
            displayDigits = formatDigits(abs(newValue))
        }
    }

    private func formatDigits(_ val: Double) -> [OdometerDigit] {
        let intVal = Int(val)
        let str = formatWithCommas(intVal)
        return str.map { char in
            if char == "," {
                return OdometerDigit(value: 0, isComma: true)
            } else {
                return OdometerDigit(value: Int(String(char)) ?? 0, isComma: false)
            }
        }
    }

    private func formatWithCommas(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct OdometerDigit: Equatable {
    let value: Int
    let isComma: Bool
}

struct SingleDigitView: View {
    let digit: Int
    let isComma: Bool
    let font: Font
    let color: AnyShapeStyle
    let delay: Double

    @State private var animatedOffset: CGFloat = 0
    @State private var targetOffset: CGFloat = 0

    var body: some View {
        if isComma {
            Text(",")
                .font(font)
                .foregroundStyle(color)
        } else {
            Text("\(digit)")
                .font(font)
                .foregroundStyle(color)
                .offset(y: animatedOffset)
                .clipShape(Rectangle())
                .onChange(of: digit) { oldValue, newValue in
                    // Animate roll-up effect
                    animatedOffset = 20
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9).delay(delay)) {
                        animatedOffset = 0
                    }
                }
                .onAppear {
                    animatedOffset = 30
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9).delay(delay)) {
                        animatedOffset = 0
                    }
                }
        }
    }
}

/// Convenience for gradient-filled odometer text
struct GradientOdometerText: View {
    let value: Double
    let gradientColors: [Color]
    var prefix: String = "$"
    var showSign: Bool = false
    var font: Font = .system(size: 34, weight: .bold, design: .monospaced)

    var body: some View {
        OdometerText(
            value: value,
            prefix: prefix,
            showSign: showSign,
            font: font,
            color: AnyShapeStyle(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
    }
}
