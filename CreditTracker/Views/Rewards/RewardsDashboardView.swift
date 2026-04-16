import SwiftUI
import SwiftData

// MARK: - RewardsDashboardView

/// Main Rewards tab — shows the family's loyalty programs grouped by category
/// or by owner, with swipe-to-delete and tap-to-edit on every row.
struct RewardsDashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LoyaltyProgram.programName) private var programs: [LoyaltyProgram]

    // MARK: Sheet / modal state
    @State private var showAddProgram       = false
    @State private var selectedProgram: LoyaltyProgram? = nil
    @State private var programToDelete: LoyaltyProgram? = nil
    @State private var showDeleteConfirm    = false

    // MARK: Haptics
    @State private var addHapticTrigger     = false
    @State private var deleteHapticTrigger  = false

    // MARK: Grouping
    private enum GroupingMode: String, CaseIterable {
        case category = "Category"
        case owner    = "Owner"
    }
    @State private var groupingMode: GroupingMode = .category

    // MARK: - Grouped Queries

    private var groupedByCategory: [(LoyaltyCategory, [LoyaltyProgram])] {
        let dict = Dictionary(grouping: programs) { $0.categoryType }
        return LoyaltyCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    private var groupedByOwner: [(String, [LoyaltyProgram])] {
        let dict = Dictionary(grouping: programs) { prog -> String in
            prog.ownerName.isEmpty ? "No Owner" : prog.ownerName
        }
        return dict.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if programs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            switch groupingMode {
                            case .category:
                                ForEach(groupedByCategory, id: \.0) { category, items in
                                    sectionHeader(category.displayName, systemImage: category.systemImage)
                                    ForEach(items) { program in
                                        programRow(program)
                                    }
                                }
                            case .owner:
                                ForEach(groupedByOwner, id: \.0) { owner, items in
                                    sectionHeader(owner, systemImage: "person.fill")
                                    ForEach(items) { program in
                                        programRow(program)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Rewards")
            .toolbar { toolbarContent }
            .sensoryFeedback(.impact(weight: .light), trigger: addHapticTrigger)
            .sensoryFeedback(.warning, trigger: deleteHapticTrigger)
            .confirmationDialog(
                "Delete Program?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let p = programToDelete { deleteProgram(p) }
                }
                Button("Cancel", role: .cancel) { programToDelete = nil }
            } message: {
                if let p = programToDelete {
                    Text("Remove \"\(p.programName)\" from your rewards tracker?")
                }
            }
        }
        .sheet(isPresented: $showAddProgram) {
            AddLoyaltyProgramView()
        }
        .sheet(item: $selectedProgram) { program in
            EditLoyaltyProgramView(program: program)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                addHapticTrigger.toggle()
                showAddProgram = true
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .glassEffect(in: Circle())
        }

        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Group By", selection: $groupingMode) {
                    ForEach(GroupingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue,
                              systemImage: mode == .category ? "tag.fill" : "person.2.fill")
                            .tag(mode)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func programRow(_ program: LoyaltyProgram) -> some View {
        LoyaltyCardView(program: program)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { selectedProgram = program }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    programToDelete = program
                    deleteHapticTrigger.toggle()
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "star.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("No Programs Yet")
                        .font(.title2.weight(.semibold))
                    Text("Track airline miles, hotel points,\nand bank rewards in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    addHapticTrigger.toggle()
                    showAddProgram = true
                } label: {
                    Label("Add Your First Program", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .glassEffect(in: Capsule())
            }
            .padding(.top, 80)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Delete

    private func deleteProgram(_ program: LoyaltyProgram) {
        let docID = program.syncID
        Task { await FirestoreSyncService.shared.deleteDocument(for: LoyaltyProgram.self, id: docID) }
        context.delete(program)
        try? context.save()
        programToDelete = nil
    }
}

#Preview {
    RewardsDashboardView()
        .modelContainer(for: [LoyaltyProgram.self], inMemory: true)
}
