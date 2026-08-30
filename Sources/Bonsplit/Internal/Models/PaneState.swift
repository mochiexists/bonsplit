import Foundation
import SwiftUI

/// State for a single pane (leaf node in the split tree)
@Observable
final class PaneState: Identifiable {
    let id: PaneID
    var tabs: [TabItem] {
        didSet {
            tabSelection.reconcile(orderedTabs: tabs, activeTabId: selectedTabId)
        }
    }
    var selectedTabId: UUID?
    var isFullWidthTabMode: Bool = false
    private var tabSelection: PaneTabSelection

    init(
        id: PaneID = PaneID(),
        tabs: [TabItem] = [],
        selectedTabId: UUID? = nil,
        isFullWidthTabMode: Bool = false
    ) {
        self.id = id
        let initialSelectedTabId = selectedTabId ?? tabs.first?.id
        self.tabs = tabs
        self.selectedTabId = initialSelectedTabId
        self.tabSelection = PaneTabSelection(activeTabId: initialSelectedTabId)
        self.isFullWidthTabMode = isFullWidthTabMode
    }

    /// Currently selected tab
    var selectedTab: TabItem? {
        tabs.first { $0.id == selectedTabId }
    }

    /// IDs selected for a grouped drag. The active content tab remains ``selectedTabId``.
    var selectedTabIds: Set<UUID> {
        tabSelection.ids
    }

    /// Select a tab by ID, optionally extending a contiguous range from the pane anchor.
    func selectTab(_ tabId: UUID, extendingSelection: Bool = false) {
        guard tabs.contains(where: { $0.id == tabId }) else { return }
        if extendingSelection {
            tabSelection.extend(to: tabId, orderedTabs: tabs)
        } else {
            tabSelection.replace(with: tabId)
        }
        selectedTabId = tabId
    }

    /// Ordered tabs represented by a drag that begins on `tabId`.
    func orderedTabsForDrag(startingAt tabId: UUID) -> [TabItem] {
        guard selectedTabIds.contains(tabId), selectedTabIds.count > 1 else {
            return tabs.filter { $0.id == tabId }
        }
        return tabs.filter { selectedTabIds.contains($0.id) }
    }

    /// Replace the grouped drag selection while choosing one active content tab.
    func selectTabs(_ tabIds: [UUID], activeTabId: UUID) {
        let requestedIds = Set(tabIds)
        guard requestedIds.contains(activeTabId),
              requestedIds.count == tabIds.count,
              requestedIds.isSubset(of: Set(tabs.map(\.id))) else { return }
        let selectedTabs = tabs.filter { requestedIds.contains($0.id) }
        guard Set(selectedTabs.map(\.isPinned)).count == 1 else { return }
        selectedTabId = activeTabId
        tabSelection.set(
            ids: requestedIds,
            anchorId: tabIds.first,
            orderedTabs: tabs,
            activeTabId: activeTabId
        )
    }

    /// Add a new tab
    func addTab(_ tab: TabItem, select: Bool = true) {
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let insertIndex = tab.isPinned ? pinnedCount : tabs.count
        tabs.insert(tab, at: insertIndex)
        if select {
            selectTab(tab.id)
        }
    }

    /// Insert a tab at a specific index
    func insertTab(_ tab: TabItem, at index: Int, select: Bool = true) {
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let requested = min(max(0, index), tabs.count)
        let safeIndex: Int
        if tab.isPinned {
            safeIndex = min(requested, pinnedCount)
        } else {
            safeIndex = max(requested, pinnedCount)
        }
        tabs.insert(tab, at: safeIndex)
        if select {
            selectTab(tab.id)
        }
    }

    /// Remove a tab and return it
    @discardableResult
    func removeTab(_ tabId: UUID) -> TabItem? {
        removeTabs([tabId]).first
    }

    /// Remove an ordered group without transiently collapsing its remaining selection.
    func removeTabs(_ tabIds: [UUID]) -> [TabItem] {
        let requestedIds = Set(tabIds)
        guard !requestedIds.isEmpty else { return [] }
        let indexedTabs = tabs.enumerated().filter { requestedIds.contains($0.element.id) }
        guard indexedTabs.count == requestedIds.count else { return [] }

        let removed = indexedTabs.map(\.element)
        let firstRemovedIndex = indexedTabs.map(\.offset).min() ?? 0
        let activeWasRemoved = selectedTabId.map(requestedIds.contains) ?? false
        tabs.removeAll { requestedIds.contains($0.id) }

        if activeWasRemoved {
            let remainingSelectedTabs = tabs.filter { selectedTabIds.contains($0.id) }
            if let nearestSelected = remainingSelectedTabs.min(by: { lhs, rhs in
                let lhsIndex = tabs.firstIndex(where: { $0.id == lhs.id }) ?? 0
                let rhsIndex = tabs.firstIndex(where: { $0.id == rhs.id }) ?? 0
                return abs(lhsIndex - firstRemovedIndex) < abs(rhsIndex - firstRemovedIndex)
            }) {
                selectedTabId = nearestSelected.id
            } else if !tabs.isEmpty {
                selectedTabId = tabs[min(firstRemovedIndex, tabs.count - 1)].id
            } else {
                selectedTabId = nil
            }
        }
        tabSelection.reconcile(orderedTabs: tabs, activeTabId: selectedTabId)
        return removed
    }

    /// Move a tab within this pane
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }

        // Treat dropping "on itself" or "after itself" as a no-op.
        // This avoids remove/insert churn that can cause brief visual artifacts during drag/drop.
        if destinationIndex == sourceIndex || destinationIndex == sourceIndex + 1 {
            return
        }

        let tab = tabs.remove(at: sourceIndex)
        let requestedIndex = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        let pinnedCount = tabs.filter { $0.isPinned }.count
        let adjustedIndex: Int
        if tab.isPinned {
            adjustedIndex = min(requestedIndex, pinnedCount)
        } else {
            adjustedIndex = max(requestedIndex, pinnedCount)
        }
        let safeIndex = min(max(0, adjustedIndex), tabs.count)
        tabs.insert(tab, at: safeIndex)
    }

    /// Move a group of tabs as one ordered block using original-array insertion coordinates.
    @discardableResult
    func moveTabs(_ tabIds: [UUID], to destinationIndex: Int) -> Bool {
        let requestedIds = Set(tabIds)
        guard !requestedIds.isEmpty,
              requestedIds.count == tabIds.count else { return false }
        let movingTabs = tabs.filter { requestedIds.contains($0.id) }
        guard movingTabs.count == requestedIds.count,
              Set(movingTabs.map(\.isPinned)).count == 1,
              destinationIndex >= 0,
              destinationIndex <= tabs.count else { return false }

        let orderBeforeMove = tabs.map(\.id)
        let movingIndices = tabs.indices.filter { requestedIds.contains(tabs[$0].id) }
        let removedBeforeDestination = movingIndices.filter { $0 < destinationIndex }.count
        var remainingTabs = tabs.filter { !requestedIds.contains($0.id) }
        let requestedIndex = destinationIndex - removedBeforeDestination
        let pinnedCount = remainingTabs.filter(\.isPinned).count
        let insertionIndex = movingTabs[0].isPinned
            ? min(max(0, requestedIndex), pinnedCount)
            : min(max(pinnedCount, requestedIndex), remainingTabs.count)
        remainingTabs.insert(contentsOf: movingTabs, at: insertionIndex)
        tabs = remainingTabs
        return tabs.map(\.id) != orderBeforeMove
    }

    /// Insert an ordered group and make that group the pane's drag selection.
    @discardableResult
    func insertTabs(_ newTabs: [TabItem], at index: Int?, selectedTabId: UUID?) -> Bool {
        guard !newTabs.isEmpty,
              Set(newTabs.map(\.id)).count == newTabs.count,
              Set(newTabs.map(\.isPinned)).count == 1,
              newTabs.allSatisfy({ newTab in !tabs.contains { $0.id == newTab.id } }) else {
            return false
        }

        let pinnedCount = tabs.filter(\.isPinned).count
        let requestedIndex = min(max(0, index ?? tabs.count), tabs.count)
        let insertionIndex = newTabs[0].isPinned
            ? min(requestedIndex, pinnedCount)
            : max(requestedIndex, pinnedCount)
        tabs.insert(contentsOf: newTabs, at: insertionIndex)

        let activeTabId = selectedTabId.flatMap { candidate in
            newTabs.contains { $0.id == candidate } ? candidate : nil
        } ?? newTabs.last?.id
        self.selectedTabId = activeTabId
        tabSelection.set(
            ids: Set(newTabs.map(\.id)),
            anchorId: newTabs.first?.id,
            orderedTabs: tabs,
            activeTabId: activeTabId
        )
        return true
    }
}

extension PaneState: Equatable {
    static func == (lhs: PaneState, rhs: PaneState) -> Bool {
        lhs.id == rhs.id
    }
}
