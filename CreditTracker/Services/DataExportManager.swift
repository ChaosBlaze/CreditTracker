import Foundation
import SwiftData

// MARK: - DataExportManager
//
// Serializes all local SwiftData models to a versioned JSON file and
// deserializes them back on import.
//
// ## Backward / Forward Compatibility
//
// The export file carries a `schemaVersion` integer:
//
//   v1  (this version)  — Cards, Credits, PeriodLogs, BonusCards,
//                         LoyaltyPrograms, CardApplications, FamilySettings
//
// Rules that keep old backups importable in future app versions:
//   • Every field in the Codable import structs uses `decodeIfPresent`,
//     falling back to a sensible default.  New fields added in schema v2+
//     will simply decode as their default when reading a v1 backup.
//   • Unknown JSON keys are silently ignored by JSONDecoder (Swift default).
//   • `schemaVersion` guards against importing a backup written by a
//     future app that the current code cannot understand.
//
// Rules that keep new backups importable in old app versions:
//   • The app refuses to import when `schemaVersion > currentSchemaVersion`.
//   • All newly-added top-level array keys are `decodeIfPresent`, so an
//     older build reading a v2 backup simply skips the new collection.

@MainActor
final class DataExportManager {

    static let shared = DataExportManager()
    private init() {}

    // MARK: - Encoder / Decoder

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Export

    /// Serialises all SwiftData models into a versioned JSON payload.
    func exportData(from context: ModelContext) throws -> Data {
        let cards = (try context.fetch(FetchDescriptor<Card>()))
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(ExportCard.init)

        let bonusCards = try context.fetch(FetchDescriptor<BonusCard>())
            .map(ExportBonusCard.init)

        let loyaltyPrograms = try context.fetch(FetchDescriptor<LoyaltyProgram>())
            .map(ExportLoyaltyProgram.init)

        let cardApplications = (try context.fetch(FetchDescriptor<CardApplication>()))
            .sorted { $0.applicationDate > $1.applicationDate }
            .map(ExportCardApplication.init)

        var descriptor = FetchDescriptor<FamilySettings>()
        descriptor.fetchLimit = 1
        let familySettings = (try? context.fetch(descriptor).first).map(ExportFamilySettings.init)

        let envelope = ExportEnvelope(
            cards:            cards,
            bonusCards:       bonusCards,
            loyaltyPrograms:  loyaltyPrograms,
            cardApplications: cardApplications,
            familySettings:   familySettings
        )

        do {
            return try encoder.encode(envelope)
        } catch {
            throw ExportError.encodingFailed(error)
        }
    }

    /// Writes the export payload to a uniquely-named temp file and returns the URL.
    /// The caller is responsible for presenting the share sheet.
    func exportFileURL(from context: ModelContext) throws -> URL {
        let data = try exportData(from: context)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr  = formatter.string(from: Date())
        let filename = "CreditTracker-backup-\(dateStr).json"
        let url      = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ExportError.fileWriteFailed(error)
        }
    }

    // MARK: - Import

    enum ImportMode {
        /// Wipe all existing data, then insert everything from the backup.
        case replace
        /// Insert records whose UUIDs don't yet exist locally; skip duplicates.
        case merge
    }

    struct ImportResult {
        var cardsImported: Int            = 0
        var creditsImported: Int          = 0
        var logsImported: Int             = 0
        var bonusCardsImported: Int       = 0
        var loyaltyProgramsImported: Int  = 0
        var cardApplicationsImported: Int = 0

        var summary: String {
            var parts: [String] = []
            if cardsImported > 0 {
                parts.append(
                    "\(cardsImported) card\(cardsImported == 1 ? "" : "s") " +
                    "(\(creditsImported) credit\(creditsImported == 1 ? "" : "s"), " +
                    "\(logsImported) log\(logsImported == 1 ? "" : "s"))"
                )
            }
            if bonusCardsImported > 0 {
                parts.append("\(bonusCardsImported) bonus card\(bonusCardsImported == 1 ? "" : "s")")
            }
            if loyaltyProgramsImported > 0 {
                parts.append("\(loyaltyProgramsImported) loyalty program\(loyaltyProgramsImported == 1 ? "" : "s")")
            }
            if cardApplicationsImported > 0 {
                parts.append("\(cardApplicationsImported) card application\(cardApplicationsImported == 1 ? "" : "s")")
            }
            return parts.isEmpty ? "No data found in backup" : parts.joined(separator: ", ")
        }
    }

    /// Deserialises a backup file and inserts models into SwiftData.
    ///
    /// - Parameters:
    ///   - data:    Raw JSON bytes from the backup file.
    ///   - context: The SwiftData context to write into.
    ///   - mode:    `.replace` wipes first; `.merge` skips existing UUIDs.
    /// - Returns:  A summary of how many records were imported.
    @discardableResult
    func importData(_ data: Data, into context: ModelContext, mode: ImportMode) throws -> ImportResult {
        guard !data.isEmpty else { throw ExportError.emptyFile }

        let envelope: ExportEnvelope
        do {
            envelope = try decoder.decode(ExportEnvelope.self, from: data)
        } catch {
            throw ExportError.decodingFailed(error)
        }

        guard envelope.schemaVersion <= ExportEnvelope.currentSchemaVersion else {
            throw ExportError.unsupportedSchemaVersion(envelope.schemaVersion)
        }

        // --- Replace: wipe all existing data first ---
        if mode == .replace {
            let existingCards = try context.fetch(FetchDescriptor<Card>())
            existingCards.forEach { context.delete($0) }

            let existingBonus = try context.fetch(FetchDescriptor<BonusCard>())
            existingBonus.forEach { context.delete($0) }

            let existingLP = try context.fetch(FetchDescriptor<LoyaltyProgram>())
            existingLP.forEach { context.delete($0) }

            let existingApps = try context.fetch(FetchDescriptor<CardApplication>())
            existingApps.forEach { context.delete($0) }

            try context.save()
        }

        var result = ImportResult()

        // --- Collect existing UUIDs for merge-mode deduplication ---
        let existingCardIDs: Set<UUID>
        let existingBonusIDs: Set<UUID>
        let existingLPIDs: Set<UUID>
        let existingAppIDs: Set<UUID>

        if mode == .merge {
            existingCardIDs  = Set((try context.fetch(FetchDescriptor<Card>())).map(\.id))
            existingBonusIDs = Set((try context.fetch(FetchDescriptor<BonusCard>())).map(\.id))
            existingLPIDs    = Set((try context.fetch(FetchDescriptor<LoyaltyProgram>())).map(\.id))
            existingAppIDs   = Set((try context.fetch(FetchDescriptor<CardApplication>())).map(\.id))
        } else {
            existingCardIDs  = []
            existingBonusIDs = []
            existingLPIDs    = []
            existingAppIDs   = []
        }

        // --- Cards → Credits → PeriodLogs ---
        for exportCard in envelope.cards {
            guard !existingCardIDs.contains(exportCard.id) else { continue }

            let card = exportCard.toModel()
            context.insert(card)
            result.cardsImported += 1

            for exportCredit in exportCard.credits {
                let credit      = exportCredit.toModel()
                credit.card     = card
                card.credits.append(credit)
                context.insert(credit)
                result.creditsImported += 1

                for exportLog in exportCredit.periodLogs {
                    let log       = exportLog.toModel()
                    log.credit    = credit
                    credit.periodLogs.append(log)
                    context.insert(log)
                    result.logsImported += 1
                }
            }
        }

        // --- BonusCards ---
        for exportBonus in envelope.bonusCards {
            guard !existingBonusIDs.contains(exportBonus.id) else { continue }
            context.insert(exportBonus.toModel())
            result.bonusCardsImported += 1
        }

        // --- LoyaltyPrograms ---
        for exportLP in envelope.loyaltyPrograms {
            guard !existingLPIDs.contains(exportLP.id) else { continue }
            context.insert(exportLP.toModel())
            result.loyaltyProgramsImported += 1
        }

        // --- CardApplications ---
        for exportApp in envelope.cardApplications {
            guard !existingAppIDs.contains(exportApp.id) else { continue }
            context.insert(exportApp.toModel())
            result.cardApplicationsImported += 1
        }

        // --- FamilySettings (optional; skip device-specific token) ---
        if let exportSettings = envelope.familySettings, mode == .replace {
            var descriptor = FetchDescriptor<FamilySettings>()
            descriptor.fetchLimit = 1
            let existing = try? context.fetch(descriptor).first
            let settings = existing ?? {
                let s = FamilySettings()
                context.insert(s)
                return s
            }()
            settings.discordReminderEnabled = exportSettings.discordReminderEnabled
            settings.discordReminderHour    = exportSettings.discordReminderHour
            settings.discordReminderMinute  = exportSettings.discordReminderMinute
            // lastModifiedByToken intentionally NOT restored (device-specific)
        }

        try context.save()
        return result
    }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileWriteFailed(Error)
    case unsupportedSchemaVersion(Int)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let e):
            return "Failed to prepare export: \(e.localizedDescription)"
        case .decodingFailed(let e):
            return "Invalid backup file — the data could not be read: \(e.localizedDescription)"
        case .fileWriteFailed(let e):
            return "Could not write backup file: \(e.localizedDescription)"
        case .unsupportedSchemaVersion(let v):
            return "This backup was created with a newer version of the app (schema v\(v)). Please update the app to import it."
        case .emptyFile:
            return "The selected file is empty or could not be read."
        }
    }
}

// ============================================================
// MARK: - Export Envelope (versioned wrapper)
// ============================================================

struct ExportEnvelope: Codable {

    /// Increment this ONLY when a breaking schema change is made.
    /// Non-breaking additions (new optional fields, new collections) do NOT
    /// require incrementing because `decodeIfPresent` handles missing keys.
    static let currentSchemaVersion = 1

    let schemaVersion:    Int
    let exportedAt:       Date
    let appVersion:       String
    let cards:            [ExportCard]
    let bonusCards:       [ExportBonusCard]
    let loyaltyPrograms:  [ExportLoyaltyProgram]
    let cardApplications: [ExportCardApplication]
    let familySettings:   ExportFamilySettings?    // optional — absent in very old backups

    init(
        cards:            [ExportCard],
        bonusCards:       [ExportBonusCard],
        loyaltyPrograms:  [ExportLoyaltyProgram],
        cardApplications: [ExportCardApplication],
        familySettings:   ExportFamilySettings?
    ) {
        self.schemaVersion    = ExportEnvelope.currentSchemaVersion
        self.exportedAt       = Date()
        self.appVersion       = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.cards            = cards
        self.bonusCards       = bonusCards
        self.loyaltyPrograms  = loyaltyPrograms
        self.cardApplications = cardApplications
        self.familySettings   = familySettings
    }

    // Custom decoder — every field uses decodeIfPresent so that future
    // app versions can read this v1 backup even after the schema grows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion    = try c.decodeIfPresent(Int.self,                    forKey: .schemaVersion)    ?? 1
        exportedAt       = try c.decodeIfPresent(Date.self,                   forKey: .exportedAt)       ?? Date()
        appVersion       = try c.decodeIfPresent(String.self,                 forKey: .appVersion)       ?? "unknown"
        cards            = try c.decodeIfPresent([ExportCard].self,            forKey: .cards)            ?? []
        bonusCards       = try c.decodeIfPresent([ExportBonusCard].self,       forKey: .bonusCards)       ?? []
        loyaltyPrograms  = try c.decodeIfPresent([ExportLoyaltyProgram].self,  forKey: .loyaltyPrograms)  ?? []
        cardApplications = try c.decodeIfPresent([ExportCardApplication].self, forKey: .cardApplications) ?? []
        familySettings   = try c.decodeIfPresent(ExportFamilySettings.self,    forKey: .familySettings)
    }
}

// ============================================================
// MARK: - Per-Model Export Structs
// ============================================================
// Each struct has:
//   init(_ model:)       — builds from a SwiftData model for export
//   init(from decoder:)  — forward-compatible decoder (decodeIfPresent for all non-id fields)
//   toModel() -> T       — reconstructs the SwiftData model for import

struct ExportCard: Codable {
    let id:                       UUID
    let name:                     String
    let annualFee:                Double
    let gradientStartHex:         String
    let gradientEndHex:           String
    let sortOrder:                Int
    let paymentDueDay:            Int?
    let paymentReminderDaysBefore: Int
    let paymentReminderEnabled:   Bool
    let annualFeeDate:            Date?
    let annualFeeReminderEnabled: Bool
    let credits:                  [ExportCredit]

    init(_ model: Card) {
        id                        = model.id
        name                      = model.name
        annualFee                 = model.annualFee
        gradientStartHex          = model.gradientStartHex
        gradientEndHex            = model.gradientEndHex
        sortOrder                 = model.sortOrder
        paymentDueDay             = model.paymentDueDay
        paymentReminderDaysBefore = model.paymentReminderDaysBefore
        paymentReminderEnabled    = model.paymentReminderEnabled
        annualFeeDate             = model.annualFeeDate
        annualFeeReminderEnabled  = model.annualFeeReminderEnabled
        credits                   = model.credits
            .sorted { $0.name < $1.name }
            .map(ExportCredit.init)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                        = try c.decode(UUID.self, forKey: .id)
        name                      = try c.decodeIfPresent(String.self, forKey: .name)                      ?? "Imported Card"
        annualFee                 = try c.decodeIfPresent(Double.self, forKey: .annualFee)                 ?? 0
        gradientStartHex          = try c.decodeIfPresent(String.self, forKey: .gradientStartHex)          ?? "#A8A9AD"
        gradientEndHex            = try c.decodeIfPresent(String.self, forKey: .gradientEndHex)            ?? "#E8E8E8"
        sortOrder                 = try c.decodeIfPresent(Int.self,    forKey: .sortOrder)                 ?? 0
        paymentDueDay             = try c.decodeIfPresent(Int.self,    forKey: .paymentDueDay)
        paymentReminderDaysBefore = try c.decodeIfPresent(Int.self,    forKey: .paymentReminderDaysBefore) ?? 3
        paymentReminderEnabled    = try c.decodeIfPresent(Bool.self,   forKey: .paymentReminderEnabled)    ?? true
        annualFeeDate             = try c.decodeIfPresent(Date.self,   forKey: .annualFeeDate)
        annualFeeReminderEnabled  = try c.decodeIfPresent(Bool.self,   forKey: .annualFeeReminderEnabled)  ?? false
        credits                   = try c.decodeIfPresent([ExportCredit].self, forKey: .credits)           ?? []
    }

    func toModel() -> Card {
        let m = Card(
            id:                       id,
            name:                     name,
            annualFee:                annualFee,
            gradientStartHex:         gradientStartHex,
            gradientEndHex:           gradientEndHex,
            sortOrder:                sortOrder,
            paymentDueDay:            paymentDueDay,
            paymentReminderDaysBefore: paymentReminderDaysBefore,
            paymentReminderEnabled:   paymentReminderEnabled
        )
        m.annualFeeDate            = annualFeeDate
        m.annualFeeReminderEnabled = annualFeeReminderEnabled
        return m
    }
}

struct ExportCredit: Codable {
    let id:                   UUID
    let name:                 String
    let totalValue:           Double
    let timeframe:            String
    let reminderDaysBefore:   Int
    let customReminderEnabled: Bool
    let periodLogs:           [ExportPeriodLog]

    init(_ model: Credit) {
        id                    = model.id
        name                  = model.name
        totalValue            = model.totalValue
        timeframe             = model.timeframe
        reminderDaysBefore    = model.reminderDaysBefore
        customReminderEnabled = model.customReminderEnabled
        periodLogs            = model.periodLogs
            .sorted { $0.periodStart < $1.periodStart }
            .map(ExportPeriodLog.init)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                    = try c.decode(UUID.self, forKey: .id)
        name                  = try c.decodeIfPresent(String.self, forKey: .name)                  ?? "Imported Credit"
        totalValue            = try c.decodeIfPresent(Double.self, forKey: .totalValue)            ?? 0
        timeframe             = try c.decodeIfPresent(String.self, forKey: .timeframe)             ?? TimeframeType.monthly.rawValue
        reminderDaysBefore    = try c.decodeIfPresent(Int.self,    forKey: .reminderDaysBefore)    ?? 5
        customReminderEnabled = try c.decodeIfPresent(Bool.self,   forKey: .customReminderEnabled) ?? true
        periodLogs            = try c.decodeIfPresent([ExportPeriodLog].self, forKey: .periodLogs) ?? []
    }

    func toModel() -> Credit {
        Credit(
            id:                   id,
            name:                 name,
            totalValue:           totalValue,
            timeframe:            TimeframeType(rawValue: timeframe) ?? .monthly,
            reminderDaysBefore:   reminderDaysBefore,
            customReminderEnabled: customReminderEnabled
        )
    }
}

struct ExportPeriodLog: Codable {
    let id:            UUID
    let periodLabel:   String
    let periodStart:   Date
    let periodEnd:     Date
    let status:        String
    let claimedAmount: Double

    init(_ model: PeriodLog) {
        id            = model.id
        periodLabel   = model.periodLabel
        periodStart   = model.periodStart
        periodEnd     = model.periodEnd
        status        = model.status
        claimedAmount = model.claimedAmount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        periodLabel   = try c.decodeIfPresent(String.self, forKey: .periodLabel)   ?? ""
        periodStart   = try c.decodeIfPresent(Date.self,   forKey: .periodStart)   ?? Date()
        periodEnd     = try c.decodeIfPresent(Date.self,   forKey: .periodEnd)     ?? Date()
        status        = try c.decodeIfPresent(String.self, forKey: .status)        ?? PeriodStatus.pending.rawValue
        claimedAmount = try c.decodeIfPresent(Double.self, forKey: .claimedAmount) ?? 0
    }

    func toModel() -> PeriodLog {
        PeriodLog(
            id:            id,
            periodLabel:   periodLabel,
            periodStart:   periodStart,
            periodEnd:     periodEnd,
            status:        PeriodStatus(rawValue: status) ?? .pending,
            claimedAmount: claimedAmount
        )
    }
}

struct ExportBonusCard: Codable {
    let id:                         UUID
    let cardName:                   String
    let bonusAmount:                String
    let dateOpened:                 Date
    let accountHolderName:          String
    let miscNotes:                  String
    let requiresPurchases:          Bool
    let purchaseTarget:             Double
    let currentPurchaseAmount:      Double
    let requiresDirectDeposit:      Bool
    let directDepositTarget:        Double
    let currentDirectDepositAmount: Double
    let requiresOther:              Bool
    let otherDescription:           String
    let isOtherCompleted:           Bool
    let isCompleted:                Bool

    init(_ model: BonusCard) {
        id                         = model.id
        cardName                   = model.cardName
        bonusAmount                = model.bonusAmount
        dateOpened                 = model.dateOpened
        accountHolderName          = model.accountHolderName
        miscNotes                  = model.miscNotes
        requiresPurchases          = model.requiresPurchases
        purchaseTarget             = model.purchaseTarget
        currentPurchaseAmount      = model.currentPurchaseAmount
        requiresDirectDeposit      = model.requiresDirectDeposit
        directDepositTarget        = model.directDepositTarget
        currentDirectDepositAmount = model.currentDirectDepositAmount
        requiresOther              = model.requiresOther
        otherDescription           = model.otherDescription
        isOtherCompleted           = model.isOtherCompleted
        isCompleted                = model.isCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                         = try c.decode(UUID.self, forKey: .id)
        cardName                   = try c.decodeIfPresent(String.self, forKey: .cardName)                   ?? "Imported Card"
        bonusAmount                = try c.decodeIfPresent(String.self, forKey: .bonusAmount)                ?? ""
        dateOpened                 = try c.decodeIfPresent(Date.self,   forKey: .dateOpened)                 ?? Date()
        accountHolderName          = try c.decodeIfPresent(String.self, forKey: .accountHolderName)          ?? ""
        miscNotes                  = try c.decodeIfPresent(String.self, forKey: .miscNotes)                  ?? ""
        requiresPurchases          = try c.decodeIfPresent(Bool.self,   forKey: .requiresPurchases)          ?? false
        purchaseTarget             = try c.decodeIfPresent(Double.self, forKey: .purchaseTarget)             ?? 0
        currentPurchaseAmount      = try c.decodeIfPresent(Double.self, forKey: .currentPurchaseAmount)      ?? 0
        requiresDirectDeposit      = try c.decodeIfPresent(Bool.self,   forKey: .requiresDirectDeposit)      ?? false
        directDepositTarget        = try c.decodeIfPresent(Double.self, forKey: .directDepositTarget)        ?? 0
        currentDirectDepositAmount = try c.decodeIfPresent(Double.self, forKey: .currentDirectDepositAmount) ?? 0
        requiresOther              = try c.decodeIfPresent(Bool.self,   forKey: .requiresOther)              ?? false
        otherDescription           = try c.decodeIfPresent(String.self, forKey: .otherDescription)           ?? ""
        isOtherCompleted           = try c.decodeIfPresent(Bool.self,   forKey: .isOtherCompleted)           ?? false
        isCompleted                = try c.decodeIfPresent(Bool.self,   forKey: .isCompleted)                ?? false
    }

    func toModel() -> BonusCard {
        let m = BonusCard(id: id, cardName: cardName, bonusAmount: bonusAmount, dateOpened: dateOpened)
        m.accountHolderName          = accountHolderName
        m.miscNotes                  = miscNotes
        m.requiresPurchases          = requiresPurchases
        m.purchaseTarget             = purchaseTarget
        m.currentPurchaseAmount      = currentPurchaseAmount
        m.requiresDirectDeposit      = requiresDirectDeposit
        m.directDepositTarget        = directDepositTarget
        m.currentDirectDepositAmount = currentDirectDepositAmount
        m.requiresOther              = requiresOther
        m.otherDescription           = otherDescription
        m.isOtherCompleted           = isOtherCompleted
        m.isCompleted                = isCompleted
        return m
    }
}

struct ExportLoyaltyProgram: Codable {
    let id:               UUID
    let programName:      String
    let category:         String
    let ownerName:        String
    let pointBalance:     Int
    let lastUpdated:      Date
    let gradientStartHex: String
    let gradientEndHex:   String
    let notes:            String?

    init(_ model: LoyaltyProgram) {
        id               = model.id
        programName      = model.programName
        category         = model.category
        ownerName        = model.ownerName
        pointBalance     = model.pointBalance
        lastUpdated      = model.lastUpdated
        gradientStartHex = model.gradientStartHex
        gradientEndHex   = model.gradientEndHex
        notes            = model.notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self, forKey: .id)
        programName      = try c.decodeIfPresent(String.self, forKey: .programName)      ?? "Imported Program"
        category         = try c.decodeIfPresent(String.self, forKey: .category)         ?? LoyaltyCategory.other.rawValue
        ownerName        = try c.decodeIfPresent(String.self, forKey: .ownerName)        ?? ""
        pointBalance     = try c.decodeIfPresent(Int.self,    forKey: .pointBalance)     ?? 0
        lastUpdated      = try c.decodeIfPresent(Date.self,   forKey: .lastUpdated)      ?? Date()
        gradientStartHex = try c.decodeIfPresent(String.self, forKey: .gradientStartHex) ?? "#1A1A2E"
        gradientEndHex   = try c.decodeIfPresent(String.self, forKey: .gradientEndHex)   ?? "#16213E"
        notes            = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    func toModel() -> LoyaltyProgram {
        LoyaltyProgram(
            id:               id,
            programName:      programName,
            category:         LoyaltyCategory(rawValue: category) ?? .other,
            ownerName:        ownerName,
            pointBalance:     pointBalance,
            lastUpdated:      lastUpdated,
            gradientStartHex: gradientStartHex,
            gradientEndHex:   gradientEndHex,
            notes:            notes
        )
    }
}

struct ExportCardApplication: Codable {
    let id:              UUID
    let cardName:        String
    let issuer:          String
    let cardType:        String
    let applicationDate: Date
    let isApproved:      Bool
    let player:          String
    let creditLimit:     Double
    let annualFee:       Double
    let notes:           String

    init(_ model: CardApplication) {
        id              = model.id
        cardName        = model.cardName
        issuer          = model.issuer
        cardType        = model.cardType
        applicationDate = model.applicationDate
        isApproved      = model.isApproved
        player          = model.player
        creditLimit     = model.creditLimit
        annualFee       = model.annualFee
        notes           = model.notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        cardName        = try c.decodeIfPresent(String.self, forKey: .cardName)        ?? "Imported Application"
        issuer          = try c.decodeIfPresent(String.self, forKey: .issuer)          ?? ""
        cardType        = try c.decodeIfPresent(String.self, forKey: .cardType)        ?? CardApplicationType.personal.rawValue
        applicationDate = try c.decodeIfPresent(Date.self,   forKey: .applicationDate) ?? Date()
        isApproved      = try c.decodeIfPresent(Bool.self,   forKey: .isApproved)      ?? true
        player          = try c.decodeIfPresent(String.self, forKey: .player)          ?? "P1"
        creditLimit     = try c.decodeIfPresent(Double.self, forKey: .creditLimit)     ?? 0
        annualFee       = try c.decodeIfPresent(Double.self, forKey: .annualFee)       ?? 0
        notes           = try c.decodeIfPresent(String.self, forKey: .notes)           ?? ""
    }

    func toModel() -> CardApplication {
        CardApplication(
            id:              id,
            cardName:        cardName,
            issuer:          issuer,
            cardType:        CardApplicationType(rawValue: cardType) ?? .personal,
            applicationDate: applicationDate,
            isApproved:      isApproved,
            player:          player,
            creditLimit:     creditLimit,
            annualFee:       annualFee,
            notes:           notes
        )
    }
}

struct ExportFamilySettings: Codable {
    let discordReminderEnabled: Bool
    let discordReminderHour:    Int
    let discordReminderMinute:  Int
    // lastModifiedByToken intentionally excluded — it's a device-specific FCM token.

    init(_ model: FamilySettings) {
        discordReminderEnabled = model.discordReminderEnabled
        discordReminderHour    = model.discordReminderHour
        discordReminderMinute  = model.discordReminderMinute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        discordReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .discordReminderEnabled) ?? false
        discordReminderHour    = try c.decodeIfPresent(Int.self,  forKey: .discordReminderHour)    ?? Constants.discordReminderDefaultHour
        discordReminderMinute  = try c.decodeIfPresent(Int.self,  forKey: .discordReminderMinute)  ?? Constants.discordReminderDefaultMinute
    }
}
