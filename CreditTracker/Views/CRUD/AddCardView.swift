import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Card.sortOrder) private var cards: [Card]

    @State private var name = ""
    @State private var annualFee = ""
    @State private var startColor = Color(hex: "#A8A9AD")
    @State private var endColor = Color(hex: "#E8E8E8")
    @State private var saveHapticTrigger = false
    @State private var presetHapticTrigger = false

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

                    // Preview
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

                Section("Quick Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorPresets, id: \.0) { preset in
                                Button {
                                    presetHapticTrigger.toggle()
                                    startColor = Color(hex: preset.1)
                                    endColor = Color(hex: preset.2)
                                } label: {
                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: preset.1), Color(hex: preset.2)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 36, height: 36)
                                        Text(preset.0)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveCard()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
        .sensoryFeedback(.selection, trigger: presetHapticTrigger)
    }

    private var colorPresets: [(String, String, String)] {
        [
            ("Gold", "#B76E79", "#C9A96E"),
            ("Platinum", "#A8A9AD", "#E8E8E8"),
            ("Sapphire", "#0C2340", "#1A5276"),
            ("Ruby", "#BB0000", "#C0392B"),
            ("Navy", "#C9A96E", "#003366"),
            ("Emerald", "#1B4332", "#2D6A4F"),
            ("Violet", "#4A0E8F", "#7B2FBE"),
            ("Obsidian", "#1C1C1E", "#3A3A3C"),
        ]
    }

    private func saveCard() {
        let fee = Double(annualFee) ?? 0
        let card = Card(
            name: name.trimmingCharacters(in: .whitespaces),
            annualFee: fee,
            gradientStartHex: startColor.toHex(),
            gradientEndHex: endColor.toHex(),
            sortOrder: cards.count
        )
        context.insert(card)
        try? context.save()
        saveHapticTrigger.toggle()
        dismiss()
    }
}
