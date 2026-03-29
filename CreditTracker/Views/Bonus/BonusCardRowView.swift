import SwiftUI
import SwiftData

struct BonusCardRowView: View {
    @Environment(\.modelContext) private var context
    let bonus: BonusCard

    @State private var completeHapticTrigger = false
    @State private var showEditSheet = false

    private var startColor: Color { Self.gradientPalette(for: bonus).0 }
    private var endColor: Color { Self.gradientPalette(for: bonus).1 }

    // Build step list from bonus requirements
    private var steps: [BonusStep] {
        var s: [BonusStep] = []
        if bonus.requiresPurchases {
            s.append(BonusStep(label: "Min Spend", icon: "cart"))
        }
        if bonus.requiresDirectDeposit {
            s.append(BonusStep(label: "Direct Deposit", icon: "banknote"))
        }
        if bonus.requiresOther {
            s.append(BonusStep(label: bonus.otherDescription.isEmpty ? "Other" : String(bonus.otherDescription.prefix(15)), icon: "list.bullet"))
        }
        return s
    }

    private var currentStep: Int {
        var completed = 0
        if bonus.requiresPurchases && bonus.currentPurchaseAmount >= bonus.purchaseTarget {
            completed += 1
        }
        if bonus.requiresDirectDeposit && bonus.currentDirectDepositAmount >= bonus.directDepositTarget {
            completed += 1
        }
        if bonus.requiresOther && bonus.isOtherCompleted {
            completed += 1
        }
        return completed
    }

    private var totalSteps: Int { steps.count }

    var body: some View {
        AtmosphericCardView(
            gradientStart: startColor,
            gradientEnd: endColor
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bonus.cardName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(bonus.bonusAmount)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [startColor, endColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("Opened \(DateHelpers.shortDateString(bonus.dateOpened))")
                            .font(.system(size: 13))
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

                if !bonus.isCompleted && !steps.isEmpty {
                    // Step progress indicator
                    StepProgressView(
                        steps: steps,
                        currentStep: currentStep,
                        accentColor: startColor
                    )
                    .padding(.vertical, 4)

                    // Progress summary
                    Text("\(currentStep) of \(totalSteps) steps complete")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    // Detailed progress bars
                    if bonus.requiresPurchases {
                        requirementRow(
                            label: "Minimum Spend",
                            icon: bonus.currentPurchaseAmount >= bonus.purchaseTarget ? "checkmark.circle.fill" : "cart",
                            iconColor: bonus.currentPurchaseAmount >= bonus.purchaseTarget ? .green : startColor,
                            current: bonus.currentPurchaseAmount,
                            target: bonus.purchaseTarget,
                            fraction: bonus.purchaseFraction
                        )
                    }

                    if bonus.requiresDirectDeposit {
                        requirementRow(
                            label: "Direct Deposit",
                            icon: bonus.currentDirectDepositAmount >= bonus.directDepositTarget ? "checkmark.circle.fill" : "banknote",
                            iconColor: bonus.currentDirectDepositAmount >= bonus.directDepositTarget ? .green : startColor,
                            current: bonus.currentDirectDepositAmount,
                            target: bonus.directDepositTarget,
                            fraction: bonus.directDepositFraction
                        )
                    }

                    if bonus.requiresOther {
                        otherRequirementRow
                    }

                    // Complete button
                    if bonus.allRequirementsMet {
                        Button {
                            markComplete()
                        } label: {
                            Label("Mark Bonus Complete", systemImage: "star.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [startColor, endColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: completeHapticTrigger)
        .sheet(isPresented: $showEditSheet) {
            EditBonusView(bonus: bonus)
        }
    }

    // MARK: - Requirement Row

    @ViewBuilder
    private func requirementRow(label: String, icon: String, iconColor: Color, current: Double, target: Double, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("$\(String(format: "%.0f", current)) / $\(String(format: "%.0f", target))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            LinearProgressBar(
                fraction: fraction,
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
                    .font(.system(size: 13, weight: .medium))
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

    // MARK: - Gradient Palette (public for BonusView access)

    static func gradientPalette(for bonus: BonusCard) -> (Color, Color) {
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
