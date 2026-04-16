import SwiftUI
import SwiftData

// MARK: - PlannerView

/// Card Planner — tracks Chase 5/24, issuer velocity rules, and application history
/// for two players (P1 and P2). Toggle between players via the top-right control.
struct PlannerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CardApplication.applicationDate, order: .reverse)
    private var allApplications: [CardApplication]

    // P1 / P2 toggle — persisted so the user's last-used player is remembered.
    @AppStorage("plannerActivePlayer") private var activePlayer: String = "P1"

    @State private var showAddSheet    = false
    @State private var selectedApp: CardApplication? = nil
    @State private var addHapticTrigger = false

    // MARK: - Derived data (recomputed on player change or data change)

    private var playerApps: [CardApplication] {
        PlannerEligibilityEngine.applications(for: activePlayer, from: allApplications)
    }

    private var status524: Chase524Status {
        PlannerEligibilityEngine.chase524Status(player: activePlayer, applications: allApplications)
    }

    private var velocityStatuses: [VelocityRuleStatus] {
        PlannerEligibilityEngine.allVelocityStatuses(player: activePlayer, applications: allApplications)
    }

    private var hardInquiry: HardInquirySummary {
        PlannerEligibilityEngine.hardInquirySummary(player: activePlayer, applications: allApplications)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if allApplications.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("Card Planner")
            .toolbar { toolbarContent }
            .sensoryFeedback(.impact(weight: .light), trigger: addHapticTrigger)
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditApplicationView(existingApp: nil, defaultPlayer: activePlayer)
        }
        .sheet(item: $selectedApp) { app in
            AddEditApplicationView(existingApp: app, defaultPlayer: activePlayer)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {

                // ── Eligibility Dashboard ──────────────────────────────────────
                sectionHeader("Eligibility", systemImage: "shield.lefthalf.filled")

                PlannerDashboardSection(
                    status524: status524,
                    velocityStatuses: velocityStatuses,
                    hardInquiry: hardInquiry
                )

                // ── Application History ────────────────────────────────────────
                sectionHeader(
                    "Application History",
                    systemImage: "clock.fill",
                    trailing: "\(playerApps.count) card\(playerApps.count == 1 ? "" : "s")"
                )

                if playerApps.isEmpty {
                    playerEmptyState
                } else {
                    ForEach(playerApps) { app in
                        PlannerApplicationRow(app: app)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onTapGesture { selectedApp = app }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteApp(app)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // P1 / P2 toggle — top right, segmented
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                playerToggle

                Button {
                    addHapticTrigger.toggle()
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .glassEffect(in: Circle())
            }
        }
    }

    private var playerToggle: some View {
        Picker("Player", selection: $activePlayer) {
            Text("P1").tag("P1")
            Text("P2").tag("P2")
        }
        .pickerStyle(.segmented)
        .frame(width: 88)
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(
        _ title: String,
        systemImage: String,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "creditcard.and.123")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("No Applications Yet")
                        .font(.title2.weight(.semibold))
                    Text("Add your recent card applications to\ntrack 5/24 status and issuer velocity rules.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    addHapticTrigger.toggle()
                    showAddSheet = true
                } label: {
                    Label("Add Your First Application", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .glassEffect(in: Capsule())
            }
            .padding(.top, 80)
            .padding(.horizontal, 20)
        }
    }

    private var playerEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No applications logged for \(activePlayer)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                addHapticTrigger.toggle()
                showAddSheet = true
            } label: {
                Label("Add Application", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .glassEffect(in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Delete

    private func deleteApp(_ app: CardApplication) {
        let docID = app.syncID
        Task { await FirestoreSyncService.shared.deleteDocument(for: CardApplication.self, id: docID) }
        context.delete(app)
        try? context.save()
    }
}

#Preview {
    PlannerView()
        .modelContainer(for: [CardApplication.self], inMemory: true)
}
