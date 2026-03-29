import SwiftUI
import SwiftData

struct CreditLoggingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let credit: Credit
    let card: Card

    @State private var amountText: String = ""
    @State private var successHapticTrigger = false
    @State private var warningHapticTrigger = false
    @State private var shakeOffset: CGFloat = 0

    @FocusState private var inputFocused: Bool

    private var activePeriod: PeriodLog? {
        PeriodEngine.activePeriodLog(for: credit)
    }
    private var alreadyClaimed: Double { activePeriod?.claimedAmount ?? 0 }
    private var remaining: Double { max(credit.totalValue - alreadyClaimed, 0) }
    private var enteredAmount: Double { Double(amountText) ?? 0 }
    private var isOverLimit: Bool { enteredAmount > remaining + 0.001 }
    private var previewFraction: Double {
        guard credit.totalValue > 0 else { return 0 }
        return min((alreadyClaimed + enteredAmount) / credit.totalValue, 1.0)
    }
    private var startColor: Color { Color(hex: card.gradientStartHex) }
    private var endColor: Color { Color(hex: card.gradientEndHex) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(credit.timeframeType.displayName + " · " + (activePeriod?.periodLabel ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Mini progress ring
                ProgressRingView(
                    fraction: previewFraction,
                    startColor: startColor,
                    endColor: endColor,
                    lineWidth: 5,
                    size: 44
                )
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 20)

            // Remaining label
            HStack {
                Text("$\(String(format: "%.0f", alreadyClaimed)) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.0f", remaining)) remaining")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(remaining > 0 ? startColor : .secondary)
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 12)

            // Large amount input row
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("$")
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)

                TextField("0", text: $amountText)
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isOverLimit ? .red : .primary)
                    .focused($inputFocused)
                    .frame(maxWidth: .infinity)
                    .offset(x: shakeOffset)

                // Max button
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
                .glassEffect(in: Capsule())
                .disabled(remaining <= 0)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)

            if isOverLimit {
                Text("Exceeds remaining balance")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 4)
            }

            Spacer().frame(height: 24)

            // Log Transaction button
            Button {
                logTransaction()
            } label: {
                Text("Log Transaction")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 20)
            .disabled(enteredAmount <= 0 || isOverLimit)
            .opacity(enteredAmount <= 0 || isOverLimit ? 0.5 : 1.0)

            Spacer().frame(height: 8)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOverLimit)
        .sensoryFeedback(.success, trigger: successHapticTrigger)
        .sensoryFeedback(.warning, trigger: warningHapticTrigger)
        .onAppear { inputFocused = true }
    }

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

        try? context.save()
        successHapticTrigger.toggle()
        dismiss()
    }
}
