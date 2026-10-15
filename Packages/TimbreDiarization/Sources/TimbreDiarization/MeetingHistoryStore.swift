/// Persistance des réunions transcrites — implémentation concrète côté App
/// (fichier JSON, voir `FileMeetingHistoryStore`), même principe que
/// `ModelProvisioningStateStore` : l'abstraction vit ici pour que le reste
/// du pipeline reste testable sans vrai disque.
public protocol MeetingHistoryStore: Sendable {
    func loadAll() -> [MeetingRecord]
    func save(_ record: MeetingRecord)
    /// Remplace l'enregistrement existant de même `id` — utilisé pour
    /// persister un renommage de locuteur après coup, distinct de `save`
    /// (qui ajoute toujours) pour ne jamais confondre "nouvelle réunion" et
    /// "modification d'une réunion déjà enregistrée".
    func update(_ record: MeetingRecord)
    func delete(id: MeetingRecord.ID)
}
