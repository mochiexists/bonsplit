import XCTest
@testable import Bonsplit

/// Tests for the split action button secondary-action + highlight API added
/// for the Mochi fork's right-click "open in external browser" toggle.
final class SplitButtonSecondaryActionTests: XCTestCase {

    private final class RecordingDelegate: BonsplitDelegate {
        var secondaryActions: [(BonsplitConfiguration.SplitActionButton.Action, PaneID)] = []

        func splitTabBar(
            _ controller: BonsplitController,
            didRequestSplitButtonSecondaryAction action: BonsplitConfiguration.SplitActionButton.Action,
            inPane pane: PaneID
        ) {
            secondaryActions.append((action, pane))
        }
    }

    @MainActor
    func testNewBrowserActionRawValueIsStable() {
        // The host keys its highlight set off this raw value; keep it stable.
        XCTAssertEqual(BonsplitConfiguration.SplitActionButton.Action.newBrowser.rawValue, "newBrowser")
    }

    @MainActor
    func testRequestSecondaryActionForwardsToDelegate() {
        let controller = BonsplitController()
        let delegate = RecordingDelegate()
        controller.delegate = delegate

        let pane = PaneID(id: UUID())
        controller.requestSplitButtonSecondaryAction(.newBrowser, inPane: pane)

        XCTAssertEqual(delegate.secondaryActions.count, 1)
        XCTAssertEqual(delegate.secondaryActions.first?.0, .newBrowser)
        XCTAssertEqual(delegate.secondaryActions.first?.1, pane)
    }

    @MainActor
    func testHighlightedSplitButtonActionsIsMutable() {
        let controller = BonsplitController()
        XCTAssertTrue(controller.highlightedSplitButtonActions.isEmpty)

        controller.highlightedSplitButtonActions.insert(
            BonsplitConfiguration.SplitActionButton.Action.newBrowser.rawValue
        )
        XCTAssertTrue(controller.highlightedSplitButtonActions.contains("newBrowser"))

        controller.highlightedSplitButtonActions.remove("newBrowser")
        XCTAssertFalse(controller.highlightedSplitButtonActions.contains("newBrowser"))
    }

    @MainActor
    func testSecondaryActionDefaultDelegateIsNoOp() {
        // A delegate that doesn't implement the optional method must not crash.
        final class EmptyDelegate: BonsplitDelegate {}
        let controller = BonsplitController()
        let delegate = EmptyDelegate()
        controller.delegate = delegate
        controller.requestSplitButtonSecondaryAction(.newBrowser, inPane: PaneID(id: UUID()))
    }
}
