import Foundation
import Testing
@testable import Bonsplit

@MainActor
@Suite struct PaneTabMultiSelectionTests {
    @Test
    func shiftSelectionIsContiguousAndStopsAtPinnedBoundary() {
        let pinnedA = TabItem(title: "Pinned A", isPinned: true)
        let pinnedB = TabItem(title: "Pinned B", isPinned: true)
        let regularA = TabItem(title: "Regular A")
        let regularB = TabItem(title: "Regular B")
        let pane = PaneState(tabs: [pinnedA, pinnedB, regularA, regularB])

        pane.selectTab(pinnedA.id)
        pane.selectTab(pinnedB.id, extendingSelection: true)
        #expect(pane.selectedTabIds == Set([pinnedA.id, pinnedB.id]))

        pane.selectTab(regularB.id, extendingSelection: true)
        #expect(pane.selectedTabIds == Set([regularB.id]))

        pane.selectTab(regularA.id, extendingSelection: true)
        #expect(pane.selectedTabIds == Set([regularA.id, regularB.id]))
    }

    @Test
    func plainSelectionCollapsesAndRemovalPrunesSelection() {
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        let third = TabItem(title: "Third")
        let pane = PaneState(tabs: [first, second, third])

        pane.selectTab(first.id)
        pane.selectTab(third.id, extendingSelection: true)
        #expect(pane.selectedTabIds == Set([first.id, second.id, third.id]))

        _ = pane.removeTab(third.id)
        #expect(pane.selectedTabIds == Set([first.id, second.id]))
        #expect(pane.selectedTabId == second.id)

        pane.selectTab(first.id)
        #expect(pane.selectedTabIds == Set([first.id]))

        let fourth = TabItem(title: "Fourth")
        pane.addTab(fourth)
        #expect(pane.selectedTabIds == Set([fourth.id]))
    }

    @Test
    func selectionIsPrunedWhenPinStateChanges() {
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        let pane = PaneState(tabs: [first, second])

        pane.selectTab(first.id)
        pane.selectTab(second.id, extendingSelection: true)
        pane.tabs[0].isPinned = true

        #expect(pane.selectedTabIds == Set([second.id]))
    }

    @Test
    func dragSelectionUsesPaneOrderAndFallsBackToDraggedTab() {
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        let third = TabItem(title: "Third")
        let pane = PaneState(tabs: [first, second, third])

        pane.selectTab(first.id)
        pane.selectTab(second.id, extendingSelection: true)

        #expect(pane.orderedTabsForDrag(startingAt: second.id).map(\.id) == [first.id, second.id])
        #expect(pane.orderedTabsForDrag(startingAt: third.id).map(\.id) == [third.id])
    }

    @Test
    func transferPayloadRoundTripsOrderedTabsAndDecodesLegacyPayload() throws {
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        let sourcePaneId = UUID()
        let transfer = TabTransferData(tab: second, tabs: [first, second], sourcePaneId: sourcePaneId)

        let decoded = try JSONDecoder().decode(
            TabTransferData.self,
            from: JSONEncoder().encode(transfer)
        )
        #expect(decoded.tab.id == second.id)
        #expect(decoded.orderedTabs.map(\.id) == [first.id, second.id])

        let legacy = try JSONSerialization.data(withJSONObject: [
            "tab": ["id": first.id.uuidString, "title": first.title],
            "sourcePaneId": sourcePaneId.uuidString,
            "sourceProcessId": Int(ProcessInfo.processInfo.processIdentifier),
        ])
        let legacyDecoded = try JSONDecoder().decode(TabTransferData.self, from: legacy)
        #expect(legacyDecoded.orderedTabs.map(\.id) == [first.id])
    }

    @Test
    func samePaneBatchMovePreservesOrderAndSelection() {
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        let third = TabItem(title: "Third")
        let fourth = TabItem(title: "Fourth")
        let pane = PaneState(tabs: [first, second, third, fourth])
        pane.selectTab(second.id)
        pane.selectTab(third.id, extendingSelection: true)

        #expect(pane.moveTabs([second.id, third.id], to: 4))
        #expect(pane.tabs.map(\.id) == [first.id, fourth.id, second.id, third.id])
        #expect(pane.selectedTabIds == Set([second.id, third.id]))
        #expect(pane.selectedTabId == third.id)
    }

    @Test
    func crossPaneBatchMovePreservesOrderAndClosesEmptySourcePane() throws {
        let controller = SplitViewController()
        let sourcePane = try #require(controller.focusedPane)
        let first = TabItem(title: "First")
        let second = TabItem(title: "Second")
        sourcePane.tabs = [first, second]
        sourcePane.selectTab(first.id)
        sourcePane.selectTab(second.id, extendingSelection: true)

        let destinationSeed = TabItem(title: "Destination")
        controller.splitPaneWithTab(
            sourcePane.id,
            orientation: .horizontal,
            tab: destinationSeed,
            insertFirst: false
        )
        let destinationPane = try #require(
            controller.rootNode.allPanes.first { $0.id != sourcePane.id }
        )

        #expect(controller.moveTabs(
            [first, second],
            from: sourcePane.id,
            to: destinationPane.id,
            atIndex: 1,
            selectedTabId: second.id
        ))
        #expect(controller.rootNode.allPanes.map(\.id) == [destinationPane.id])
        #expect(destinationPane.tabs.map(\.id) == [destinationSeed.id, first.id, second.id])
        #expect(destinationPane.selectedTabId == second.id)
        #expect(destinationPane.selectedTabIds == Set([first.id, second.id]))
    }

    @Test
    func publicSplitMovesOrderedTabsIntoOneNewPane() throws {
        let controller = BonsplitController()
        let sourcePane = try #require(controller.focusedPaneId)
        let first = try #require(controller.createTab(title: "First"))
        let second = try #require(controller.createTab(title: "Second"))

        let newPane = try #require(controller.splitPane(
            sourcePane,
            orientation: .horizontal,
            movingTabs: [first, second],
            selectedTabId: second,
            insertFirst: false
        ))

        #expect(controller.tabs(inPane: newPane).map(\.id) == [first, second])
        #expect(controller.selectedTabId(inPane: newPane) == second)
    }

    @Test
    func externalDropRequestKeepsSingularCompatibility() throws {
        let first = TabID()
        let second = TabID()
        let pane = PaneID()
        let destination = BonsplitController.ExternalTabDropRequest.Destination.insert(
            targetPane: pane,
            targetIndex: nil
        )

        let batch = try #require(BonsplitController.ExternalTabDropRequest(
            tabIds: [first, second],
            sourcePaneId: pane,
            destination: destination
        ))
        #expect(batch.tabId == first)
        #expect(batch.tabIds == [first, second])

        let singular = BonsplitController.ExternalTabDropRequest(
            tabId: second,
            sourcePaneId: pane,
            destination: destination
        )
        #expect(singular.tabIds == [second])
    }
}
