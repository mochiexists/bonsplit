import AppKit
import Testing
@testable import Bonsplit

@MainActor
@Suite struct SplitActionSecondaryClickTests {
    private func mouseEvent(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    @Test func rightClickRoutesToSecondaryHandlerNotPrimaryAction() throws {
        let view = SplitActionMouseDownNSView()
        var primaryCount = 0
        var secondaryCount = 0
        view.onMouseDown = { primaryCount += 1 }
        view.onSecondaryClick = { _, _ in
            secondaryCount += 1
            return true
        }

        view.rightMouseDown(with: try mouseEvent(.rightMouseDown))

        #expect(primaryCount == 0)
        #expect(secondaryCount == 1)
    }

    @Test func controlClickRoutesToSecondaryHandler() throws {
        let view = SplitActionMouseDownNSView()
        var primaryCount = 0
        var secondaryCount = 0
        view.onMouseDown = { primaryCount += 1 }
        view.onSecondaryClick = { _, _ in
            secondaryCount += 1
            return true
        }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, flags: [.control]))

        #expect(primaryCount == 0)
        #expect(secondaryCount == 1)
    }

    @Test func plainClickStillFiresPrimaryAction() throws {
        let view = SplitActionMouseDownNSView()
        var primaryCount = 0
        var secondaryCount = 0
        view.onMouseDown = { primaryCount += 1 }
        view.onSecondaryClick = { _, _ in
            secondaryCount += 1
            return true
        }

        view.mouseDown(with: try mouseEvent(.leftMouseDown))

        #expect(primaryCount == 1)
        #expect(secondaryCount == 0)
    }

    @Test func unhandledSecondaryClickFallsBackToPrimaryAction() throws {
        let view = SplitActionMouseDownNSView()
        var primaryCount = 0
        view.onMouseDown = { primaryCount += 1 }
        view.onSecondaryClick = { _, _ in false }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, flags: [.control]))

        #expect(primaryCount == 1)
    }

    @Test func secondaryClickClassification() throws {
        #expect(SplitActionSecondaryClickNSView.isSecondaryClick(try mouseEvent(.rightMouseDown)))
        #expect(SplitActionSecondaryClickNSView.isSecondaryClick(try mouseEvent(.leftMouseDown, flags: [.control])))
        #expect(!SplitActionSecondaryClickNSView.isSecondaryClick(try mouseEvent(.leftMouseDown)))
        #expect(!SplitActionSecondaryClickNSView.isSecondaryClick(try mouseEvent(.leftMouseDown, flags: [.command])))
    }

    @Test func highlightedSplitActionsStartEmpty() {
        let controller = BonsplitController()
        #expect(controller.highlightedSplitActions.isEmpty)
    }
}
