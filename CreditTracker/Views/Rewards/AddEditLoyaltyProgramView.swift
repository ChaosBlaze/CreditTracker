import SwiftUI
import SwiftData

// MARK: - AddLoyaltyProgramView

/// Two-step sheet for adding a loyalty program:
///   1. `ProgramPickerView` — searchable catalog (matches mockup)
///   2. `ProgramDetailFormView` — balance, owner, colors — pushed via NavigationStack
///
/// Calling `dismiss()` from `ProgramDetailFormView.onSave` dismisses the entire sheet
/// because the closure captures `AddLoyaltyProgramView`'s dismiss action.
struct AddLoyaltyProgramView: View {
    @Environment(\.dismiss) private var dismiss

    /// When non-nil, NavigationStack pushes to the detail form.
    @State private var selectedTemplate: LoyaltyProgramTemplate? = nil

    var body: some View {
        NavigationStack {
            ProgramPickerView { template in
                selectedTemplate = template
            }
            .navigationDestination(item: $selectedTemplate) { template in
                ProgramDetailFormView(template: template, onSave: { dismiss() })
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - ProgramPickerView

/// Searchable, categorised list of known loyalty programs — mirrors the
/// "Add Points Category" mockups (IMG_5398–IMG_5402).
///
/// Each row shows a gradient icon circle + program name.
/// Tapping a row fires `onSelect` which drives NavigationStack navigation.
struct ProgramPickerView: View {
    let onSelect: (LoyaltyProgramTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredAll: [LoyaltyProgramTemplate] {
        guard !searchText.isEmpty else { return LoyaltyProgramTemplate.all }
        return LoyaltyProgramTemplate.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Filtered templates grouped by category in canonical order.
    private var grouped: [(LoyaltyCategory, [LoyaltyProgramTemplate])] {
        let dict = Dictionary(grouping: filteredAll) { $0.category }
        return LoyaltyCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        List {
            // ── Catalog sections ───────────────────────────────────────────────
            ForEach(grouped, id: \.0) { category, templates in
                Section {
                    ForEach(templates) { template in
                        Button {
                            onSelect(template)
                        } label: {
                            catalogRow(template)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(category.displayName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // ── Custom / manual entry ──────────────────────────────────────────
            Section {
                Button {
                    onSelect(LoyaltyProgramTemplate(
                        name: "",
                        category: .other,
                        gradientStartHex: "#1A1A2E",
                        gradientEndHex: "#16213E"
                    ))
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 40, height: 40)
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("Custom Program")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("OTHER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "Search programs")
        .navigationTitle("Add Points Program")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Catalog Row

    @ViewBuilder
    private func catalogRow(_ template: LoyaltyProgramTemplate) -> some View {
        HStack(spacing: 14) {
            ProgramIconView(
                initials:      template.initials,
                startColor:    Color(hex: template.gradientStartHex),
                endColor:      Color(hex: template.gradientEndHex),
                size:          40,
                logoAssetName: template.logoAssetName
            )
            Text(template.name)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - ProgramDetailFormView

/// Second step in the add flow: balance, owner, gradient colors, and notes.
/// Pre-populated from the chosen `LoyaltyProgramTemplate`.
/// Calls `onSave()` after inserting into SwiftData — the closure dismisses the sheet.
struct ProgramDetailFormView: View {
    @Environment(\.modelContext) private var context

    let template: LoyaltyProgramTemplate
    let onSave: () -> Void

    @State private var programName: String
    @State private var category: LoyaltyCategory
    @State private var ownerName: String = ""
    @State private var balanceText: String = ""
    @State private var startColor: Color
    @State private var endColor: Color
    @State private var notes: String = ""
    @State private var saveHapticTrigger = false

    // MARK: Init

    init(template: LoyaltyProgramTemplate, onSave: @escaping () -> Void) {
        self.template = template
        self.onSave   = onSave
        _programName  = State(initialValue: template.name)
        _category     = State(initialValue: template.category)
        _startColor   = State(initialValue: Color(hex: template.gradientStartHex))
        _endColor     = State(initialValue: Color(hex: template.gradientEndHex))
    }

    // MARK: Body

    var body: some View {
        Form {
            // ── Program identity ───────────────────────────────────────────────
            Section("Program") {
                TextField("Program Name", text: $programName)
                    .autocorrectionDisabled()
                Picker("Category", selection: $category) {
                    ForEach(LoyaltyCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                    }
                }
            }

            // ── Account ────────────────────────────────────────────────────────
            Section("Account") {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("Owner (e.g. Shekar, Wife)", text: $ownerName)
                }
                HStack {
                    Text("Current Balance")
                        .foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $balanceText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            }

            // ── Gradient colors ────────────────────────────────────────────────
            Section {
                HStack {
                    Text("Start Color")
                    Spacer()
                    ColorPicker("", selection: $startColor, supportsOpacity: false)
                        .labelsHidden()
                }
                HStack {
                    Text("End Color")
                    Spacer()
                    ColorPicker("", selection: $endColor, supportsOpacity: false)
                        .labelsHidden()
                }
                HStack {
                    Text("Preview")
                    Spacer()
                    ProgramIconView(
                        initials: previewInitials,
                        startColor: startColor,
                        endColor: endColor,
                        size: 36
                    )
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Colors tint the Liquid Glass card on the Rewards dashboard.")
            }

            // ── Notes ──────────────────────────────────────────────────────────
            Section("Notes") {
                TextField("Account numbers, expiry dates, tips…",
                          text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle(template.name.isEmpty ? "Custom Program" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(programName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
    }

    // MARK: - Helpers

    private var previewInitials: String {
        let skip = Set(["the", "of", "and", "&", "miles", "points", "rewards",
                        "plus", "one", "air", "plan"])
        let words = programName
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && !skip.contains($0.lowercased()) }
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }

    // MARK: - Save

    private func save() {
        let program = LoyaltyProgram(
            programName:      programName.trimmingCharacters(in: .whitespaces),
            category:         category,
            ownerName:        ownerName.trimmingCharacters(in: .whitespaces),
            pointBalance:     Int(balanceText) ?? 0,
            gradientStartHex: startColor.toHex(),
            gradientEndHex:   endColor.toHex(),
            notes:            notes.isEmpty ? nil : notes
        )
        context.insert(program)
        try? context.save()
        saveHapticTrigger.toggle()
        Task { await FirestoreSyncService.shared.upload(program) }
        onSave()
    }
}

// MARK: - EditLoyaltyProgramView

/// Full-featured editor presented when a user taps an existing program row.
/// Supports updating balance, owner, appearance, and notes.
/// Applies `.sensoryFeedback(.success)` on save to confirm the update.
struct EditLoyaltyProgramView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let program: LoyaltyProgram

    // MARK: Editable state

    @State private var programName:  String
    @State private var category:     LoyaltyCategory
    @State private var ownerName:    String
    @State private var balanceText:  String
    @State private var startColor:   Color
    @State private var endColor:     Color
    @State private var notes:        String
    @State private var saveHapticTrigger = false

    // MARK: Init

    init(program: LoyaltyProgram) {
        self.program   = program
        _programName   = State(initialValue: program.programName)
        _category      = State(initialValue: program.categoryType)
        _ownerName     = State(initialValue: program.ownerName)
        _balanceText   = State(initialValue: "\(program.pointBalance)")
        _startColor    = State(initialValue: Color(hex: program.gradientStartHex))
        _endColor      = State(initialValue: Color(hex: program.gradientEndHex))
        _notes         = State(initialValue: program.notes ?? "")
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Program identity ───────────────────────────────────────────
                Section("Program") {
                    TextField("Program Name", text: $programName)
                        .autocorrectionDisabled()
                    Picker("Category", selection: $category) {
                        ForEach(LoyaltyCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                        }
                    }
                }

                // ── Account ────────────────────────────────────────────────────
                Section("Account") {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Owner (e.g. Shekar, Wife)", text: $ownerName)
                    }
                    HStack {
                        Text("Current Balance")
                        Spacer()
                        TextField("0", text: $balanceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                // ── Appearance ─────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Start Color")
                        Spacer()
                        ColorPicker("", selection: $startColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                    HStack {
                        Text("End Color")
                        Spacer()
                        ColorPicker("", selection: $endColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Preview")
                        Spacer()
                        ProgramIconView(
                            initials: previewInitials,
                            startColor: startColor,
                            endColor: endColor,
                            size: 36
                        )
                    }
                } header: {
                    Text("Appearance")
                }

                // ── Notes ──────────────────────────────────────────────────────
                Section("Notes") {
                    TextField("Account numbers, expiry dates, tips…",
                              text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                // ── Metadata ───────────────────────────────────────────────────
                Section {
                    HStack {
                        Text("Last Updated")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(program.lastUpdated, style: .relative)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } header: {
                    Text("Info")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        let docID = program.syncID
                        Task { await FirestoreSyncService.shared.deleteDocument(for: LoyaltyProgram.self, id: docID) }
                        context.delete(program)
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Program")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(programName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var previewInitials: String {
        let skip = Set(["the", "of", "and", "&", "miles", "points", "rewards",
                        "plus", "one", "air", "plan"])
        let words = programName
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && !skip.contains($0.lowercased()) }
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
    }

    // MARK: - Save

    private func save() {
        program.programName     = programName.trimmingCharacters(in: .whitespaces)
        program.category        = category.rawValue
        program.ownerName       = ownerName.trimmingCharacters(in: .whitespaces)
        program.pointBalance    = Int(balanceText) ?? program.pointBalance
        program.gradientStartHex = startColor.toHex()
        program.gradientEndHex   = endColor.toHex()
        program.notes           = notes.isEmpty ? nil : notes
        program.lastUpdated     = Date()
        try? context.save()
        saveHapticTrigger.toggle()
        Task { await FirestoreSyncService.shared.upload(program) }
        dismiss()
    }
}
