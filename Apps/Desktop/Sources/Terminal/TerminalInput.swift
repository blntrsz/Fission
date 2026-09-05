import AppKit
import GhosttyTerminal

/// Converts pasteboard objects into the text Ghostty expects on its paste path.
enum TerminalInputContent {
    static func text(from pasteboard: NSPasteboard) -> String? {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        return text(urls: urls, string: pasteboard.string(forType: .string))
    }

    static func text(urls: [URL], string: String?) -> String? {
        if !urls.isEmpty {
            return urls
                .map { $0.isFileURL ? shellEscape($0.path) : $0.absoluteString }
                .joined(separator: " ")
        }
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static let shellMetacharacters: Set<Character> = [
        "\\", " ", "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'", "`",
        "!", "#", "$", "&", ";", "|", "*", "?", "\t"
    ]

    private static func shellEscape(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if shellMetacharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
    }
}

/// Ghostty's default macOS link binding compares modifiers exactly against Command.
/// Its mouse-capture path removes Shift before matching links; do the same at the
/// embedding boundary because `AppTerminalView` does not expose capture state.
enum TerminalLinkActivation {
    static func modifiersForGhostty(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        guard modifiers.contains([.command, .shift]) else { return modifiers }

        var linkModifiers = modifiers
        linkModifiers.remove(.shift)
        return linkModifiers
    }

    static func eventForGhostty(_ event: NSEvent) -> NSEvent {
        let modifiers = modifiersForGhostty(event.modifierFlags)
        guard modifiers != event.modifierFlags else { return event }

        return NSEvent.mouseEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: modifiers,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            eventNumber: event.eventNumber,
            clickCount: event.clickCount,
            pressure: event.pressure
        ) ?? event
    }
}

enum TerminalInterruptRouting {
    static func shouldHandleDirectly(
        eventType: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        let relevantModifiers = modifiers.intersection([.command, .shift, .option, .control])
        return eventType == .keyDown
            && relevantModifiers == .control
            && charactersIgnoringModifiers?.lowercased() == "c"
    }
}

@MainActor
final class FissionTerminalView: AppTerminalView {
    private static let acceptedDropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string
    ] + PasteboardImage.acceptedTypes

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedDropTypes)
    }

    override func setSurfaceVisible(_ visible: Bool) {
        super.setSurfaceVisible(visible)
        if visible {
            registerForDraggedTypes(Self.acceptedDropTypes)
        } else {
            unregisterDraggedTypes()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if TerminalInterruptRouting.shouldHandleDirectly(
            eventType: event.type,
            modifiers: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) {
            // SwiftUI's command responder chain can consume Control-C before
            // AppTerminalView receives keyDown. Route it through Ghostty's key
            // path directly so shells and terminal applications always see it.
            keyDown(with: event)
            return true
        }
        if isPasteShortcut(event), pasteImage(from: .general) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: TerminalLinkActivation.eventForGhostty(event))
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: TerminalLinkActivation.eventForGhostty(event))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: TerminalLinkActivation.eventForGhostty(event))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.canPaste(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Self.canPaste(from: sender.draggingPasteboard) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        Self.canPaste(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard pasteDroppedContent(from: pasteboard) else { return false }
        _ = acquireProgrammaticFocus()
        return true
    }

    func pasteImageFromMenu() -> Bool {
        guard window?.firstResponder === self else { return false }
        return pasteImage(from: .general)
    }

    private func isPasteShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.type == .keyDown
            && modifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    static func canPaste(from pasteboard: NSPasteboard) -> Bool {
        // Drag payloads such as macOS screenshot thumbnails may be lazy. Match
        // Ghostty by deciding from advertised types and reading data only on drop.
        guard let types = pasteboard.types else { return false }
        return !Set(types).isDisjoint(with: Set(acceptedDropTypes))
    }

    private func pasteDroppedContent(from pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            guard let text = TerminalInputContent.text(from: pasteboard) else { return false }
            return paste(text: text)
        }

        let parts = items.compactMap(droppedText(from:))
        guard !parts.isEmpty else { return false }
        return paste(text: parts.joined(separator: " "))
    }

    private func droppedText(from item: NSPasteboardItem) -> String? {
        if let url = url(from: item, type: .fileURL) {
            return TerminalInputContent.text(urls: [url], string: nil)
        }
        if let image = PasteboardImage(from: item),
           let url = try? TerminalImageStaging.store(image) {
            return TerminalInputContent.text(urls: [url], string: nil)
        }
        if let url = url(from: item, type: .URL) {
            return TerminalInputContent.text(urls: [url], string: nil)
        }
        return item.string(forType: .string)
    }

    private func url(from item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> URL? {
        if let value = item.string(forType: type) {
            return URL(string: value)
        }
        guard let data = item.data(forType: type) else { return nil }
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    private func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        // URLs and text retain Ghostty's normal clipboard pipeline, including
        // paste protection. Only raw image data needs host-side staging.
        guard TerminalInputContent.text(from: pasteboard) == nil,
              let image = PasteboardImage(from: pasteboard),
              let url = try? TerminalImageStaging.store(image),
              let path = TerminalInputContent.text(urls: [url], string: nil)
        else {
            return false
        }
        return paste(text: path)
    }

}

struct PasteboardImage {
    enum Format: String, CaseIterable {
        case png
        case jpeg
        case heic
        case gif
        case tiff

        var pasteboardType: NSPasteboard.PasteboardType {
            NSPasteboard.PasteboardType("public.\(rawValue)")
        }
    }

    static let acceptedTypes = Format.allCases.map(\.pasteboardType)

    let data: Data
    let format: Format

    init(data: Data, format: Format) {
        self.data = data
        self.format = format
    }

    init?(from pasteboard: NSPasteboard) {
        if let image = Self.firstImage(dataForType: pasteboard.data(forType:)) {
            self = image
            return
        }
        guard let data = NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return nil }
        self.init(data: data, format: .tiff)
    }

    init?(from item: NSPasteboardItem) {
        guard let image = Self.firstImage(dataForType: item.data(forType:)) else { return nil }
        self = image
    }

    private static func firstImage(
        dataForType: (NSPasteboard.PasteboardType) -> Data?
    ) -> PasteboardImage? {
        for format in Format.allCases {
            if let data = dataForType(format.pasteboardType) {
                return PasteboardImage(data: data, format: format)
            }
        }
        return nil
    }
}

enum TerminalImageStaging {
    static let directory = FileManager.default.temporaryDirectory
        .appending(path: "fission-terminal-paste", directoryHint: .isDirectory)

    static func store(_ image: PasteboardImage) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        removeStaleFiles(using: fileManager)

        let destination = directory.appending(
            path: "image-\(UUID().uuidString).\(image.format.rawValue)",
            directoryHint: .notDirectory
        )
        try image.data.write(to: destination, options: .atomic)
        return destination
    }

    private static func removeStaleFiles(using fileManager: FileManager) {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
