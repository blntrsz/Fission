@testable import FissionDesktop
import Foundation
import Testing

@MainActor
struct TerminalURLHandlerTests {
    @Test func opensRecognizedURL() throws {
        let expectedURL = try #require(URL(string: "https://example.com/issues/3"))
        var openedURL: URL?
        let handler = TerminalURLHandler { url in
            openedURL = url
            return true
        }

        let opened = handler.open(expectedURL.absoluteString)

        #expect(opened)
        #expect(openedURL == expectedURL)
    }
}
