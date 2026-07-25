import AppKit
import Testing
@testable import Bonsplit

@MainActor
@Suite struct HostProvidedTabContextMenuTests {
    @Test func menuEvaluatesAndRoutesHostProvidedItems() throws {
        let target = TabContextMenuActionTarget()
        var selectedIdentifier: String?
        target.onCustomItem = { selectedIdentifier = $0 }
        var providerCalls = 0
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: TabContextMenuState(
                isPinned: false,
                isUnread: false,
                isBrowser: false,
                isAudioMuted: false,
                isTerminal: true,
                hasCustomTitle: false,
                canCloseToLeft: false,
                canCloseToRight: false,
                canCloseOthers: false,
                canMoveToNewWorkspace: false,
                canMoveToLeftPane: false,
                canMoveToRightPane: false,
                forkConversationDefaultAction: .forkConversationRight,
                isZoomed: false,
                hasSplits: false,
                shortcuts: [:]
            ),
            moveDestinationsProvider: { [] },
            forkConversationAvailabilityProvider: { .hidden },
            customItemsProvider: {
                providerCalls += 1
                return [
                    TabContextMenuItem(id: "copyFile", title: "Copy File"),
                    TabContextMenuItem(id: "disabled", title: "Disabled", isEnabled: false),
                ]
            }
        )

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)
        let copyFileItem = try #require(menu.items.first { $0.title == "Copy File" })
        let disabledItem = try #require(menu.items.first { $0.title == "Disabled" })

        #expect(providerCalls == 1)
        #expect(copyFileItem.isEnabled)
        #expect(!disabledItem.isEnabled)
        target.performCustomItem(copyFileItem)
        #expect(selectedIdentifier == "copyFile")
    }

    @Test func controllerForwardsHostProvidedItemToDelegate() throws {
        let controller = BonsplitController()
        let pane = try #require(controller.focusedPaneId)
        let tabID = try #require(controller.createTab(title: "Test", kind: "terminal"))
        let delegate = HostProvidedTabContextMenuDelegate()
        controller.delegate = delegate

        controller.requestTabContextMenuItem("copyFile", for: tabID, inPane: pane)

        #expect(delegate.identifier == "copyFile")
        #expect(delegate.tabID == tabID)
        #expect(delegate.paneID == pane)
    }
}

@MainActor
private final class HostProvidedTabContextMenuDelegate: BonsplitDelegate {
    var identifier: String?
    var tabID: TabID?
    var paneID: PaneID?

    func splitTabBar(
        _ controller: BonsplitController,
        didRequestTabContextMenuItem identifier: String,
        for tab: Tab,
        inPane pane: PaneID
    ) {
        self.identifier = identifier
        tabID = tab.id
        paneID = pane
    }
}
