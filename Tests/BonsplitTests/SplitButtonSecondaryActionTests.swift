import XCTest
@testable import Bonsplit

/// Tests for the split action button highlight + context-menu-toggle API added
/// for the Mochi fork's "open in external browser" toggle on the browser button.
final class SplitButtonContextToggleTests: XCTestCase {

    @MainActor
    func testNewBrowserActionRawValueIsStable() {
        // The host keys its highlight set off this raw value; keep it stable.
        XCTAssertEqual(BonsplitConfiguration.SplitActionButton.Action.newBrowser.rawValue, "newBrowser")
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
    func testContextToggleProviderDrivesHostState() {
        let controller = BonsplitController()
        var external = false
        controller.splitButtonContextToggleProvider = { action in
            guard action == .newBrowser else { return nil }
            return SplitButtonContextToggle(
                title: "Open in External Browser",
                isOn: external,
                onToggle: { external = $0 }
            )
        }

        // No toggle for non-browser buttons.
        XCTAssertNil(controller.splitButtonContextToggleProvider?(.newTerminal) ?? nil)

        // Browser button exposes a toggle reflecting and mutating host state.
        let toggle = try? XCTUnwrap(controller.splitButtonContextToggleProvider?(.newBrowser) ?? nil)
        XCTAssertEqual(toggle?.title, "Open in External Browser")
        XCTAssertEqual(toggle?.isOn, false)

        toggle?.onToggle(true)
        XCTAssertTrue(external)
        // A freshly fetched toggle reflects the new state.
        XCTAssertEqual(controller.splitButtonContextToggleProvider?(.newBrowser)?.isOn, true)
    }
}
