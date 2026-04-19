// MARK: - FirestoreSyncService (Compatibility Shim)
//
// `FirestoreSyncService` has been superseded by `SyncCoordinator` as part of
// the Phase 1 repository split. This typealias preserves backward compatibility
// so all existing call sites continue to compile without modification:
//
//   FirestoreSyncService.shared.upload(card)    → SyncCoordinator.shared.upload(card)
//   FirestoreSyncService.shared.startListening() → SyncCoordinator.shared.startListening()
//
// To complete the migration, do a project-wide rename of FirestoreSyncService
// → SyncCoordinator and delete this file.

typealias FirestoreSyncService = SyncCoordinator
