import Foundation

@main
struct VisitNameStoreChecks {
    static func main() {
        let suite = "BlogAssistant.NameTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VisitNameStore(defaults: defaults)
        store.save("  정돈 성수\n", for: ["a", "b"])
        let reopened = VisitNameStore(defaults: UserDefaults(suiteName: suite)!)
        precondition(reopened.names(for: ["b", "new-photo"]) == ["정돈 성수"])
        precondition(reopened.isComplete(for: ["a", "b"]))
        precondition(!reopened.isComplete(for: ["b", "new-photo"]))
        precondition(!reopened.isComplete(for: []))
        store.save("어니언", for: ["c"])
        precondition(store.names(for: ["b", "c"]).count == 2)
        precondition(!store.isComplete(for: ["b", "c"]))
        store.save("통합 이름", for: ["b", "c"])
        precondition(store.names(for: ["b", "c"]) == ["통합 이름"])
        store.save(" \n", for: ["b", "c"])
        precondition(store.names(for: ["b", "c"]).isEmpty)
        precondition(!store.isComplete(for: ["b", "c"]))
        precondition(store.names(for: ["a"]) == ["정돈 성수"])
        print("Passed visit name persistence, overlapping photos, conflict and clearing checks")
    }
}
