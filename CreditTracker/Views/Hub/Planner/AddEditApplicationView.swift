import SwiftUI
import SwiftData

// MARK: - AddEditApplicationView

/// Modal sheet for creating a new card application or editing an existing one.
/// Pass `existingApp: nil` to create; pass a `CardApplication` to edit.
struct AddEditApplicationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existingApp: CardApplication?
    let defaultPlayer: String

    // MARK: - Form State

    @State private var cardName:         String = ""
    @State private var issuer:           String = KnownIssuer.chase.rawValue
    @State private var customIssuer:     String = ""
    @State private var cardType:         CardApplicationType = .personal
    @State private var applicationDate:  Date = Date()
    @State private var isApproved:       Bool = true
    @State private var player:           String = "P1"
    @State private var creditLimit:      String = ""
    @State private var annualFee:        String = ""
    @State private var notes:            String = ""

    @State private var isUsingCustomIssuer = false
    @State private var showDeleteConfirm   = false
    @State private var saveHapticTrigger   = false
    @State private var deleteHapticTrigger = false

    private var isEditing: Bool { existingApp != nil }

    private var resolvedIssuer: String {
        isUsingCustomIssuer ? customIssuer.trimmingCharacters(in: .whitespaces) : issuer
    }

    private var canSave: Bool {
        !cardName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !resolvedIssuer.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cardDetailsSection
                    applicationDetailsSection
                    playerSection
                    if !notes.isEmpty || !isEditing {
                        notesSection
                    } else {
                        notesSection
                    }
                    if isEditing {
                        dangerZone
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .navigationTitle(isEditing ? "Edit Application" : "Add Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sensoryFeedback(.impact(weight: .medium), trigger: saveHapticTrigger)
            .sensoryFeedback(.warning,                  trigger: deleteHapticTrigger)
            .confirmationDialog(
                "Delete Application?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove \"\(cardName)\" from your application history.")
            }
        }
        .onAppear { populateIfEditing() }
    }

    // MARK: - Sections

    private var cardDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Card Details", systemImage: "creditcard.fill")

            VStack(spacing: 10) {
                // Card name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Card Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Chase Sapphire Preferred", text: $cardName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(12)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Issuer picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Issuer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !isUsingCustomIssuer {
                        Picker("Issuer", selection: $issuer) {
                            ForEach(KnownIssuer.allCases.filter { $0 != .other }, id: \.rawValue) { known in
                                Text(known.rawValue).tag(known.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            isUsingCustomIssuer = true
                        } label: {
                            Text("Other issuer…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                    } else {
                        HStack {
                            TextField("Issuer name", text: $customIssuer)
                                .textFieldStyle(.plain)
                                .font(.body)
                            Button {
                                isUsingCustomIssuer = false
                                customIssuer = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                // Card type
                VStack(alignment: .leading, spacing: 6) {
                    Text("Card Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(CardApplicationType.allCases, id: \.self) { type in
                            typeChip(type)
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func typeChip(_ type: CardApplicationType) -> some View {
        let selected = cardType == type
        Button { cardType = type } label: {
            HStack(spacing: 6) {
                Image(systemName: type.systemImage)
                    .font(.caption.weight(.semibold))
                Text(type.displayName)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Color.purple : Color.clear, in: Capsule())
            .glassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: cardType)
    }

    private var applicationDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Application Details", systemImage: "doc.text.fill")

            VStack(spacing: 10) {
                // Date
                VStack(alignment: .leading, spacing: 6) {
                    Text("Application Date")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    DatePicker("Application Date", selection: $applicationDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Approval toggle
                HStack {
                    Label("Approved", systemImage: isApproved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isApproved ? .green : .red)
                    Spacer()
                    Toggle("", isOn: $isApproved)
                        .labelsHidden()
                }
                .padding(12)
                .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .animation(.spring(response: 0.25), value: isApproved)

                // Annual Fee + Credit Limit (side by side)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Annual Fee")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("$").foregroundStyle(.secondary)
                            TextField("0", text: $annualFee)
                                .keyboardType(.decimalPad)
                        }
                        .padding(12)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Credit Limit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("$").foregroundStyle(.secondary)
                            TextField("Optional", text: $creditLimit)
                                .keyboardType(.decimalPad)
                        }
                        .padding(12)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Account Holder", systemImage: "person.2.fill")

            Picker("Player", selection: $player) {
                Text("P1").tag("P1")
                Text("P2").tag("P2")
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Notes", systemImage: "note.text")

            TextField(
                "Targeted offer, NLL status, referral link, account number…",
                text: $notes,
                axis: .vertical
            )
            .lineLimit(3...6)
            .font(.subheadline)
            .padding(12)
            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Danger Zone", systemImage: "exclamationmark.triangle.fill")

            Button(role: .destructive) {
                deleteHapticTrigger.toggle()
                showDeleteConfirm = true
            } label: {
                Label("Delete Application", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(12)
            }
            .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isEditing ? "Save" : "Add") {
                saveHapticTrigger.toggle()
                save()
            }
            .fontWeight(.semibold)
            .disabled(!canSave)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Persistence

    private func populateIfEditing() {
        guard let app = existingApp else {
            player = defaultPlayer
            return
        }
        cardName        = app.cardName
        cardType        = app.cardTypeEnum
        applicationDate = app.applicationDate
        isApproved      = app.isApproved
        player          = app.player
        annualFee       = app.annualFee > 0 ? String(format: "%.0f", app.annualFee) : ""
        creditLimit     = app.creditLimit > 0 ? String(format: "%.0f", app.creditLimit) : ""
        notes           = app.notes

        // Determine if issuer is known or custom
        if KnownIssuer(rawValue: app.issuer) != nil {
            issuer = app.issuer
            isUsingCustomIssuer = false
        } else {
            customIssuer = app.issuer
            isUsingCustomIssuer = true
        }
    }

    private func save() {
        let resolvedAF = Double(annualFee) ?? 0.0
        let resolvedCL = Double(creditLimit) ?? 0.0

        if let app = existingApp {
            // Update existing
            app.cardName        = cardName.trimmingCharacters(in: .whitespaces)
            app.issuer          = resolvedIssuer
            app.cardType        = cardType.rawValue
            app.applicationDate = applicationDate
            app.isApproved      = isApproved
            app.player          = player
            app.annualFee       = resolvedAF
            app.creditLimit     = resolvedCL
            app.notes           = notes.trimmingCharacters(in: .whitespaces)

            try? context.save()
            Task { await FirestoreSyncService.shared.upload(app) }
        } else {
            // Create new
            let app = CardApplication(
                cardName:        cardName.trimmingCharacters(in: .whitespaces),
                issuer:          resolvedIssuer,
                cardType:        cardType,
                applicationDate: applicationDate,
                isApproved:      isApproved,
                player:          player,
                creditLimit:     resolvedCL,
                annualFee:       resolvedAF,
                notes:           notes.trimmingCharacters(in: .whitespaces)
            )
            context.insert(app)
            try? context.save()
            Task { await FirestoreSyncService.shared.upload(app) }
        }

        dismiss()
    }

    private func confirmDelete() {
        guard let app = existingApp else { return }
        let docID = app.syncID
        Task { await FirestoreSyncService.shared.deleteDocument(for: CardApplication.self, id: docID) }
        context.delete(app)
        try? context.save()
        dismiss()
    }
}

#Preview {
    AddEditApplicationView(existingApp: nil, defaultPlayer: "P1")
        .modelContainer(for: [CardApplication.self], inMemory: true)
}
