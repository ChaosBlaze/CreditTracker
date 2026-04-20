import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - ExportImportView

/// Sheet presented from SettingsView > Data > Backup & Restore.
///
/// ## Export flow
/// 1. Tap "Export Backup"  →  generate temp JSON file  →  iOS share sheet.
///
/// ## Import flow
/// 1. Choose import mode (Merge or Replace All) via the segmented control.
/// 2. Tap "Choose Backup File…"  →  system file picker (JSON).
/// 3. Replace mode shows a confirmation dialog; Merge proceeds immediately.
/// 4. Result summary appears with an optional "Re-upload to Firestore" button.
struct ExportImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    // Export state
    @State private var isExporting     = false
    @State private var exportURL: URL?
    @State private var showShareSheet  = false

    // Import state
    @State private var showFileImporter   = false
    @State private var importMode         = DataExportManager.ImportMode.merge
    @State private var pendingFileURL: URL?
    @State private var showReplaceConfirm = false
    @State private var isImporting        = false
    @State private var importResult: DataExportManager.ImportResult?

    // Re-upload state
    @State private var isReUploading = false
    @State private var reUploadDone  = false

    // Error state
    @State private var alertTitle   = ""
    @State private var alertMessage = ""
    @State private var showAlert    = false

    private let manager     = DataExportManager.shared
    private let syncService = FirestoreSyncService.shared

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                exportSection
                importModeSection
                importSection
                if let result = importResult {
                    resultSection(result)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Backup & Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // File picker for import
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { pickResult in
                handleFilePick(pickResult)
            }
            // Confirmation before a destructive Replace import
            .confirmationDialog(
                "Replace All Data?",
                isPresented: $showReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    if let url = pendingFileURL { performImport(from: url) }
                }
                Button("Cancel", role: .cancel) { pendingFileURL = nil }
            } message: {
                Text("This will permanently delete all existing cards, credits, and records, then restore the backup. This cannot be undone.")
            }
            // Generic error alert
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            // iOS share sheet
            .sheet(isPresented: $showShareSheet, onDismiss: { exportURL = nil }) {
                if let url = exportURL {
                    ShareSheetView(fileURL: url)
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                HStack {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.blue)
                    Spacer()
                    if isExporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isExporting || isImporting)
        } header: {
            Text("Export")
        } footer: {
            Text("All cards, credits, period logs, bonus cards, loyalty programs, and card applications are saved to a single JSON file.")
        }
    }

    // MARK: - Import Mode Section

    private var importModeSection: some View {
        Section {
            Picker("Import Mode", selection: $importMode) {
                Text("Merge").tag(DataExportManager.ImportMode.merge)
                Text("Replace All").tag(DataExportManager.ImportMode.replace)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Import Mode")
        } footer: {
            switch importMode {
            case .merge:
                Text("Merge adds only records whose UUIDs don't already exist locally. Existing records are untouched.")
            case .replace:
                Text("Replace All deletes everything first, then inserts the backup. Use this to fully restore from a backup or to reset Firestore.")
            }
        }
    }

    // MARK: - Import Section

    private var importSection: some View {
        Section("Import") {
            Button {
                showFileImporter = true
            } label: {
                HStack {
                    Label("Choose Backup File…", systemImage: "square.and.arrow.down")
                        .foregroundStyle(importMode == .replace ? .red : .blue)
                    Spacer()
                    if isImporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isImporting || isExporting)
        }
    }

    // MARK: - Result Section

    @ViewBuilder
    private func resultSection(_ result: DataExportManager.ImportResult) -> some View {
        Section {
            // Summary row
            VStack(alignment: .leading, spacing: 6) {
                Label("Import Complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            // Re-upload to Firestore
            Button {
                reUploadToFirestore()
            } label: {
                HStack {
                    Label(
                        reUploadDone ? "Re-upload Complete" : "Re-upload to Firestore",
                        systemImage: reUploadDone ? "checkmark.icloud.fill" : "icloud.and.arrow.up"
                    )
                    .foregroundStyle(reUploadDone ? .green : .blue)
                    Spacer()
                    if isReUploading { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isReUploading || reUploadDone)
        } header: {
            Text("Result")
        } footer: {
            if !reUploadDone {
                Text("Re-uploading pushes all imported records to Firestore. Useful after a Replace import to fix cloud sync issues.")
            } else {
                Text("All local data has been pushed to Firestore.")
            }
        }
    }

    // MARK: - Export Action

    private func exportBackup() {
        isExporting = true
        Task {
            do {
                exportURL     = try manager.exportFileURL(from: context)
                showShareSheet = true
            } catch {
                showError("Export Failed", message: error.localizedDescription)
            }
            isExporting = false
        }
    }

    // MARK: - Import Actions

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showError("Could Not Open File", message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingFileURL = url
            if importMode == .replace {
                showReplaceConfirm = true
            } else {
                performImport(from: url)
            }
        }
    }

    private func performImport(from url: URL) {
        isImporting  = true
        importResult = nil
        reUploadDone = false

        Task {
            do {
                // Security-scoped resource access is required for files picked
                // from outside the app's sandbox (Files app, iCloud, etc.)
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

                let data   = try Data(contentsOf: url)
                let result = try manager.importData(data, into: context, mode: importMode)
                importResult = result
            } catch {
                showError("Import Failed", message: error.localizedDescription)
            }
            isImporting    = false
            pendingFileURL = nil
        }
    }

    // MARK: - Re-upload Action

    private func reUploadToFirestore() {
        isReUploading = true
        Task {
            async let cards    = context.fetch(FetchDescriptor<Card>())
            async let credits  = context.fetch(FetchDescriptor<Credit>())
            async let logs     = context.fetch(FetchDescriptor<PeriodLog>())
            async let bonuses  = context.fetch(FetchDescriptor<BonusCard>())
            async let loyalty  = context.fetch(FetchDescriptor<LoyaltyProgram>())
            async let apps     = context.fetch(FetchDescriptor<CardApplication>())
            async let settings = context.fetch(FetchDescriptor<FamilySettings>())

            let allCards    = (try? await cards)    ?? []
            let allCredits  = (try? await credits)  ?? []
            let allLogs     = (try? await logs)     ?? []
            let allBonuses  = (try? await bonuses)  ?? []
            let allLoyalty  = (try? await loyalty)  ?? []
            let allApps     = (try? await apps)     ?? []
            let allSettings = (try? await settings) ?? []

            for item in allCards    { await syncService.upload(item) }
            for item in allCredits  { await syncService.upload(item) }
            for item in allLogs     { await syncService.upload(item) }
            for item in allBonuses  { await syncService.upload(item) }
            for item in allLoyalty  { await syncService.upload(item) }
            for item in allApps     { await syncService.upload(item) }
            if let s = allSettings.first { await syncService.upload(s) }

            isReUploading = false
            reUploadDone  = true
        }
    }

    // MARK: - Error Helper

    private func showError(_ title: String, message: String) {
        alertTitle   = title
        alertMessage = message
        showAlert    = true
    }
}

// MARK: - ShareSheetView

/// UIActivityViewController wrapper for presenting the iOS share sheet.
private struct ShareSheetView: UIViewControllerRepresentable {

    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
