import SwiftUI
import SwiftData

struct CreditLoggingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let credit: Credit
    let card: Card

    @AppStorage("preferKeypadInput") private var preferKeypadInput = false
    @State private var dialAmount: Double = 0
    @State private var amountText: String = ""
    @State private var showConfetti = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var successHapticTrigger = false
    @State private var warningHapticTrigger = false
    @State private var shakeOffset: CGFloat = 0

    @FocusState private var inputFocused: Bool

    private var activePeriod: PeriodLog? {
        PeriodEngine.activePeriodLog(for: credit)
    }
    private var alreadyClaimed: Double { activePeriod?.claimedAmount ?? 0 }
    private var remaining: Double { max(credit.totalValue - alreadyClaimed, 0) }
    private var enteredAmount: Double {
        preferKeypadInput ? (Double(amountText) ?? 0) : dialAmount
    }
    private var isOverLimit: Bool { enteredAmount > remaining + 0.001 }
    private var previewFraction: Double {
        guard credit.totalValue > 0 else { return 0 }
        return min((alreadyClaimed + enteredAmount) / credit.totalValue, 1.0)
    }
    private var isFullClaim: Bool {
        abs(enteredAmount - remaining) < 0.01 && remaining > 0
    }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(.secondary.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)

                // 1. Credit identity bar
                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            LinearGradient(colors: [startColor, endColor],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(credit.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("\(credit.timeframeType.displayName) · \(activePeriod?.periodLabel ?? "")")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mini progress ring
                    ChunkyProgressRing(
                        fraction: previewFraction,
                        gradientStart: startColor,
                        gradientEnd: endColor,
                        strokeWidth: 5,
                        size: 44
                    )
                }
                .padding(.horizontal, 20)

                // 2. Ring + stats row
                HStack {
                    Text("$\(String(format: "%.0f", alreadyClaimed)) used")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.0f", remaining)) remaining")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(remaining > 0 ? startColor : .secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // 3. Input area
                if preferKeypadInput {
                    keypadInput
                } else {
                    dialInput
                }

                // 4. Toggle input mode
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        preferKeypadInput.toggle()
                    }
                } label: {
                    Text(preferKeypadInput ? "Use dial" : "Enter amount")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(startColor)
                }
                .padding(.top, 4)

                Spacer().frame(height: 16)

                // 5. Log Transaction button
                Button {
                    logTransaction()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [startColor.opacity(0.15), endColor.opacity(0.08)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }

                        Text("Log Transaction")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .disabled(enteredAmount <= 0 || isOverLimit)
                .opacity(enteredAmount <= 0 || isOverLimit ? 0.5 : 1.0)
                .scaleEffect(buttonScale)

                Spacer().frame(height: 12)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOverLimit)
            .sensoryFeedback(.success, trigger: successHapticTrigger)
            .sensoryFeedback(.warning, trigger: warningHapticTrigger)

            // Confetti overlay
            ConfettiCanvasView(
                isActive: $showConfetti,
                origin: CGPoint(x: 0.5, y: 0.85),
                accentColors: [startColor, endColor, .yellow, .white]
            )
        }
    }

    // MARK: - Dial Input

    private var dialInput: some View {
        VStack(spacing: 8) {
            RadialClaimDial(
                maxAmount: remaining,
                currentAmount: $dialAmount,
                accentStart: startColor,
                accentEnd: endColor,
                dialSize: 180
            )
            .padding(.top, 8)

            // Max button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    dialAmount = remaining
                }
                HapticEngine.shared.dialSnapToMax()
            } label: {
                Text("Max")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Capsule())
            .disabled(remaining <= 0)
        }
    }

    // MARK: - Keypad Input

    private var keypadInput: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("$")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)

                TextField("0", text: $amountText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isOverLimit ? .red : .primary)
                    .focused($inputFocused)
                    .frame(maxWidth: .infinity)
                    .offset(x: shakeOffset)

                Button {
                    amountText = remaining.truncatingRemainder(dividingBy: 1) == 0
                        ? String(Int(remaining))
                        : String(format: "%.2f", remaining)
                } label: {
                    Text("Max")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Capsule())
                .disabled(remaining <= 0)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if isOverLimit {
                Text("Exceeds remaining balance")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { inputFocused = true }
    }

    // MARK: - Log Transaction

    private func logTransaction() {
        if isOverLimit {
            warningHapticTrigger.toggle()
            withAnimation(.easeInOut(duration: 0.05).repeatCount(5, autoreverses: true)) {
                shakeOffset = 6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { shakeOffset = 0 }
            return
        }

        guard let period = activePeriod, enteredAmount > 0 else { return }

        let newTotal = alreadyClaimed + enteredAmount
        period.claimedAmount = min(newTotal, credit.totalValue)

        if period.claimedAmount >= credit.totalValue {
            period.periodStatus = .claimed
            NotificationManager.shared.cancelReminder(for: credit)
        } else {
            period.periodStatus = .partiallyClaimed
        }

        // Gamification
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let unlockedAchievements = GamificationEngine.recordClaim(
            amount: enteredAmount,
            credit: credit,
            cards: cards,
            context: context
        )

        try? context.save()

        // Button press animation
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            buttonScale = 0.95
        }

        if isFullClaim || period.claimedAmount >= credit.totalValue {
            // Full claim: confetti + delay dismiss
            successHapticTrigger.toggle()
            showConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } else {
            // Partial: just dismiss
            successHapticTrigger.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismiss()
            }
        }
    }
}
