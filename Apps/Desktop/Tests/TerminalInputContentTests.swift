import AppKit
@testable import FissionDesktop
import Foundation
import Testing

struct TerminalInputContentTests {
    @Test func commandShiftClickRemovesOnlyShiftForGhosttyLinkActivation() {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .capsLock]

        #expect(
            TerminalLinkActivation.modifiersForGhostty(modifiers)
                == [.command, .option, .capsLock]
        )
    }

    @Test func shiftWithoutCommandIsPreservedForTerminalSelection() {
        let modifiers: NSEvent.ModifierFlags = [.shift, .option]

        #expect(TerminalLinkActivation.modifiersForGhostty(modifiers) == modifiers)
    }

    @Test func prefersURLsOverThePasteboardString() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a file.txt"),
            URL(string: "https://example.com/a?q=1")!
        ]

        #expect(
            TerminalInputContent.text(urls: urls, string: "ignored")
                == "/tmp/a\\ file.txt https://example.com/a?q=1"
        )
    }

    @Test func shellEscapesSingleQuotes() {
        let url = URL(fileURLWithPath: "/tmp/it's here.png")

        #expect(TerminalInputContent.text(urls: [url], string: nil) == "/tmp/it\\'s\\ here.png")
    }

    @Test func fallsBackToPlainText() {
        #expect(TerminalInputContent.text(urls: [], string: "hello") == "hello")
        #expect(TerminalInputContent.text(urls: [], string: "") == nil)
    }

    @Test func readsFileURLsFromPasteboardBeforeDisplayNames() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/Screenshot 1.png")
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("Screenshot 1.png", forType: .string)

        #expect(TerminalInputContent.text(from: pasteboard) == "/tmp/Screenshot\\ 1.png")
    }

    @Test func recognizesAdditionalImageFormats() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let data = Data([0xFF, 0xD8, 0xFF])
        pasteboard.setData(data, forType: PasteboardImage.Format.jpeg.pasteboardType)

        let image = try #require(PasteboardImage(from: pasteboard))
        #expect(image.format == .jpeg)
        #expect(image.data == data)
    }

    @Test func stagesClipboardImageDataAsAFile() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let url = try TerminalImageStaging.store(PasteboardImage(data: data, format: .png))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == data)
    }
}
