import Foundation

@main
struct VisitGroupStoreChecks {
    static func main() {
        let suite = "BlogAssistant.GroupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VisitGroupStore(defaults: defaults)
        let automatic = [["a", "b", "c"], ["d", "e"]]
        store.assign(["a", "c"], to: "source")
        store.assign(["b"], to: "split")
        var groups = VisitGroupStore.apply(to: automatic, assignments: store.assignments)
        precondition(groups.first { $0.id == "source" }?.photoIDs == ["a", "c"])
        precondition(groups.first { $0.id == "split" }?.photoIDs == ["b"])
        store.assign(["b", "d", "e"], to: "destination")
        let reopened = VisitGroupStore(defaults: UserDefaults(suiteName: suite)!)
        groups = VisitGroupStore.apply(to: automatic, assignments: reopened.assignments)
        precondition(groups.first { $0.id == "destination" }?.photoIDs == ["b", "d", "e"])
        let all = groups.flatMap(\.photoIDs)
        precondition(all.count == 5 && Set(all) == Set(automatic.flatMap { $0 }))
        // Photos falling outside the fetch window do not invalidate remaining memberships.
        groups = VisitGroupStore.apply(to: [["c", "new"], ["e"]], assignments: reopened.assignments)
        precondition(groups.first { $0.id == "source" }?.photoIDs == ["c"])
        precondition(groups.first { $0.id == "new" }?.isManual == false)
        store.reset(["a", "b", "c", "d", "e"])
        groups = VisitGroupStore.apply(to: automatic, assignments: store.assignments)
        precondition(groups.map(\.photoIDs) == automatic)
        precondition(groups.allSatisfy { !$0.isManual })
        precondition(VisitGroupStore.apply(to: [], assignments: store.assignments).isEmpty)
        print("Passed manual split, move, merge, persistence, photo preservation and reset checks")
    }
}
