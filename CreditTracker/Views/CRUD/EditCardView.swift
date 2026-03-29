import SwiftUI
import SwiftData

struct EditCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: Card

    @State private var name: String
    @State private var annualFee: String
    @State private var startColor: Color
    @State private var endColor: Color
    @State private var saveHapticTrigger = false
    @State private var deleteWarningTrigger = false

    init(card: Card) {
        self.card = card
        _name = State(initialValue: card.name)
        _annualFee = State(initialValue: String(Int(card.annualFee)))
        _startColor = State(initialValue: Color(hex: card.gradientStartHex))
        _endColor = State(initialValue: Color(hex: card.gradientEndHex))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Details") {
                    TextField("Card Name", text: $name)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Annual Fee", text: $annualFee)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Card Colors") {
                    ColorPicker("Gradient Start", selection: $startColor, supportsOpacity: false)
                    ColorPicker("Gradient End", selection: $endColor, supportsOpacity: false)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [startColor.opacity(0.6), endColor.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 60)
                        .overlay(
                            Text(name.isEmpty ? "Card Preview" : name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        )
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Button(role: .destructive) {
                        deleteWarningTrigger.toggle()
                        context.delete(card)
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Card")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
        .sensoryFeedback(.warning, trigger: deleteWarningTrigger)
    }

    private func saveChanges() {
        card.name = name.trimmingCharacters(in: .whitespaces)
        card.annualFee = Double(annualFee) ?? 0
        card.gradientStartHex = startColor.toHex()
        card.gradientEndHex = endColor.toHex()
        try? context.save()
        saveHapticTrigger.toggle()
        dismiss()
    }
}
