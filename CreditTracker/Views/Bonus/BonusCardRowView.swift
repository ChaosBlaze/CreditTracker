import SwiftUI
import SwiftData

struct BonusCardRowView: View {
    @Environment(\.modelContext) private var context
    let bonus: BonusCard

    @State private var completeHapticTrigger = false
    @State private var showEditSheet = false

    // Gradient palette for bonus cards (cycles by hash)
    private var cardGradient: (Color, Color) {
        let palettes: [(Color, Color)] = [
            (.purple, .indigo),
            (.orange, .pink),
            (.teal, .cyan),
            (.green, .mint),
            (.blue, .purple),
            (.red, .orange),
        ]
        let idx = abs(bonus.cardName.hashValue) % palettes.count
        return palettes[idx]
    }

    private var startColor: Color { cardGradient.0 }
    private var endColor: Color { cardGradient.1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [startColor.opacity(0.22), endColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bonus.cardName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(bonus.bonusAmount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(startColor)
                        Text("Opened \(DateHelpers.shortDateString(bonus.dateOpened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if bonus.isCompleted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            showEditSheet = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !bonus.isCompleted {
                    Divider()
                    requirementsSection
                }
            }
            .padding(16)
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .sensoryFeedback(.success, trigger: completeHapticTrigger)
        .sheet(isPresented: $showEditSheet) {
            EditBonusView(bonus: bonus)
        }
    }

    // MARK: - Requirements

    @ViewBuilder
    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if bonus.requiresPurchases {
                purchaseProgressRow
            }
            if bonus.requiresDirectDeposit {
                directDepositRow
            }
            if bonus.requiresOther {
                otherRequirementRow
            }

            // Complete button – shown when all requirements are met
            if bonus.allRequirementsMet {
                Button {
                    markComplete()
                } label: {
                    Label("Mark Bonus Complete", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private var purchaseProgressRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: bonus.currentPurchaseAmount >= bonus.purchaseTarget
                      ? "checkmark.circle.fill" : "cart")
                    .foregroundStyle(bonus.currentPurchaseAmount >= bonus.purchaseTarget ? .green : startColor)
                    .font(.caption)
                Text("Minimum Spend")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(String(format: "%.0f", bonus.currentPurchaseAmount)) / $\(String(format: "%.0f", bonus.purchaseTarget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LinearProgressBar(
                fraction: bonus.purchaseFraction,
                startColor: startColor,
                endColor: endColor
            )
        }
    }

    private var directDepositRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: bonus.currentDirectDepositAmount >= bonus.directDepositTarget
                      ? "checkmark.circle.fill" : "banknote")
                    .foregroundStyle(bonus.currentDirectDepositAmount >= bonus.directDepositTarget ? .green : startColor)
                    .font(.caption)
                Text("Direct Deposit")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(String(format: "%.0f", bonus.currentDirectDepositAmount)) / $\(String(format: "%.0f", bonus.directDepositTarget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LinearProgressBar(
                fraction: bonus.directDepositFraction,
                startColor: startColor,
                endColor: endColor
            )
        }
    }

    private var otherRequirementRow: some View {
        Button {
            bonus.isOtherCompleted.toggle()
            try? context.save()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bonus.isOtherCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(bonus.isOtherCompleted ? .green : .secondary)
                    .font(.body)
                Text(bonus.otherDescription.isEmpty ? "Other Requirement" : bonus.otherDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: bonus.isOtherCompleted)
    }

    private func markComplete() {
        bonus.isCompleted = true
        try? context.save()
        completeHapticTrigger.toggle()
    }
}

// MARK: - Linear Progress Bar

struct LinearProgressBar: View {
    let fraction: Double
    let startColor: Color
    let endColor: Color
    var height: CGFloat = 6

    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(startColor.opacity(0.15))
                    .frame(height: height)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [startColor, endColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * animated, height: height)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
                animated = fraction
            }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                animated = newValue
            }
        }
    }
}

// MARK: - Edit Bonus Sheet

struct EditBonusView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let bonus: BonusCard

    @State private var currentPurchaseText: String
    @State private var currentDDText: String
    @State private var isOtherCompleted: Bool

    init(bonus: BonusCard) {
        self.bonus = bonus
        _currentPurchaseText = State(initialValue: bonus.currentPurchaseAmount > 0
            ? String(format: "%.2f", bonus.currentPurchaseAmount) : "")
        _currentDDText = State(initialValue: bonus.currentDirectDepositAmount > 0
            ? String(format: "%.2f", bonus.currentDirectDepositAmount) : "")
        _isOtherCompleted = State(initialValue: bonus.isOtherCompleted)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Progress Update") {
                    if bonus.requiresPurchases {
                        HStack {
                            Text("Total Spent")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $currentPurchaseText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        Text("Target: $\(String(format: "%.0f", bonus.purchaseTarget))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if bonus.requiresDirectDeposit {
                        HStack {
                            Text("Total Deposited")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("0", text: $currentDDText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        Text("Target: $\(String(format: "%.0f", bonus.directDepositTarget))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if bonus.requiresOther {
                        Toggle("Other Requirement Done", isOn: $isOtherCompleted)
                        if !bonus.otherDescription.isEmpty {
                            Text(bonus.otherDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        context.delete(bonus)
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Bonus")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Update Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveProgress() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func saveProgress() {
        if bonus.requiresPurchases {
            bonus.currentPurchaseAmount = Double(currentPurchaseText) ?? bonus.currentPurchaseAmount
        }
        if bonus.requiresDirectDeposit {
            bonus.currentDirectDepositAmount = Double(currentDDText) ?? bonus.currentDirectDepositAmount
        }
        if bonus.requiresOther {
            bonus.isOtherCompleted = isOtherCompleted
        }
        try? context.save()
        dismiss()
    }
}
