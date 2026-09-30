/// Persistance des réunions transcrites — implémentation concrète côté App
/// (fichier JSON, voir `FileMeetingHistoryStore`), même principe que
/// `ModelProvisioningStateStore` : l'abstraction vit ici pour que le reste
/// du pipeline reste testable sans vrai disque.
public protocol MeetingHistoryStore: Sendable {
    func loadAll() -> [MeetingRecord]
    func save(_ record: MeetingRecord)
    func delete(id: MeetingRecord.ID)
}
