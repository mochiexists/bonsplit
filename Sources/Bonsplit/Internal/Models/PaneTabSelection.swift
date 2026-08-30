import Foundation

/// Pane-local selection used to move an ordered group of tabs together.
struct PaneTabSelection: Equatable {
    private(set) var ids: Set<UUID>
    private(set) var anchorId: UUID?

    init(activeTabId: UUID?) {
        self.ids = activeTabId.map { [$0] } ?? []
        self.anchorId = activeTabId
    }

    mutating func replace(with tabId: UUID?) {
        ids = tabId.map { [$0] } ?? []
        anchorId = tabId
    }

    mutating func extend(to tabId: UUID, orderedTabs: [TabItem]) {
        guard let clickedIndex = orderedTabs.firstIndex(where: { $0.id == tabId }) else { return }
        guard let anchorId,
              let anchorIndex = orderedTabs.firstIndex(where: { $0.id == anchorId }),
              orderedTabs[anchorIndex].isPinned == orderedTabs[clickedIndex].isPinned else {
            replace(with: tabId)
            return
        }

        let lower = min(anchorIndex, clickedIndex)
        let upper = max(anchorIndex, clickedIndex)
        let isPinned = orderedTabs[clickedIndex].isPinned
        ids = Set(orderedTabs[lower...upper].filter { $0.isPinned == isPinned }.map(\.id))
    }

    mutating func set(ids: Set<UUID>, anchorId: UUID?, orderedTabs: [TabItem], activeTabId: UUID?) {
        self.ids = ids
        self.anchorId = anchorId
        reconcile(orderedTabs: orderedTabs, activeTabId: activeTabId)
    }

    mutating func reconcile(orderedTabs: [TabItem], activeTabId: UUID?) {
        let liveIds = Set(orderedTabs.map(\.id))
        ids.formIntersection(liveIds)
        if let anchorId, !liveIds.contains(anchorId) {
            self.anchorId = nil
        }
        if ids.isEmpty, let activeTabId, liveIds.contains(activeTabId) {
            ids = [activeTabId]
        }
        if self.anchorId == nil {
            self.anchorId = activeTabId.flatMap { liveIds.contains($0) ? $0 : nil }
        }
        if let partitionTabId = activeTabId ?? self.anchorId,
           let isPinned = orderedTabs.first(where: { $0.id == partitionTabId })?.isPinned {
            ids = ids.filter { selectedId in
                orderedTabs.first(where: { $0.id == selectedId })?.isPinned == isPinned
            }
        }
    }
}
