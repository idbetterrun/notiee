import XCTest
@testable import Notiee

final class WebFetchToolTests: XCTestCase {
    // MARK: URL validation (SSRF guard)
    func testAllowsPublicHTTPS() {
        XCTAssertTrue(WebFetchTool.isAllowedURL(URL(string: "https://example.com/article")!))
    }

    func testRejectsNonHTTPScheme() {
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "ftp://example.com")!))
    }

    func testRejectsLocalhostAndLoopback() {
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://localhost/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://127.0.0.1/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://[::1]/x")!))
    }

    func testRejectsPrivateRanges() {
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://10.0.0.5/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://192.168.1.1/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://172.16.0.1/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://169.254.0.1/x")!))
    }

    func testRejectsLocalDomain() {
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://printer.local/x")!))
    }

    func testRejectsSSRFEvasionForms() {
        // IPv4-mapped IPv6 pointing at loopback
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://[::ffff:127.0.0.1]/x")!))
        // Trailing dot on a loopback literal (resolver treats as 127.0.0.1)
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://127.0.0.1./x")!))
        // Octal-encoded loopback (0177 == 127 to getaddrinfo)
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://0177.0.0.1/x")!))
        // IPv6 unique-local and link-local
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://[fc00::1]/x")!))
        XCTAssertFalse(WebFetchTool.isAllowedURL(URL(string: "http://[fe80::1]/x")!))
    }

    func testAllowsPublicIPLiteral() {
        XCTAssertTrue(WebFetchTool.isAllowedURL(URL(string: "http://93.184.216.34/x")!))
    }

    // MARK: HTML -> text extraction
    func testStripsScriptStyleAndTags() {
        let html = "<html><head><style>a{}</style><script>var x=1;</script></head><body><h1>Hi</h1><p>World</p></body></html>"
        let text = WebFetchTool.extractText(from: html, maxChars: 1000)
        XCTAssertTrue(text.contains("Hi"))
        XCTAssertTrue(text.contains("World"))
        XCTAssertFalse(text.contains("var x"))
        XCTAssertFalse(text.contains("a{}"))
        XCTAssertFalse(text.contains("<"))
    }

    func testStripsMultilineScriptBlock() {
        let html = """
        <body><h1>Hi</h1>
        <script>
        var leak = "secret";
        console.log(leak);
        </script>
        <p>World</p></body>
        """
        let text = WebFetchTool.extractText(from: html, maxChars: 1000)
        XCTAssertTrue(text.contains("Hi"))
        XCTAssertTrue(text.contains("World"))
        XCTAssertFalse(text.contains("leak"), "多行 <script> 内容不得泄漏到正文")
        XCTAssertFalse(text.contains("console.log"))
    }

    func testDecodesCommonEntities() {
        let text = WebFetchTool.extractText(from: "<p>Tom &amp; Jerry &lt;3</p>", maxChars: 1000)
        XCTAssertTrue(text.contains("Tom & Jerry <3"))
    }

    func testTruncatesToMaxChars() {
        let html = "<p>" + String(repeating: "x", count: 5000) + "</p>"
        let text = WebFetchTool.extractText(from: html, maxChars: 100)
        XCTAssertLessThanOrEqual(text.count, 100 + 20) // allow short truncation marker
        XCTAssertTrue(text.contains("…"))
    }
}
