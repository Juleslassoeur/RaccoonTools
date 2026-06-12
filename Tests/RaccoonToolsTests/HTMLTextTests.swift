import Testing
@testable import RaccoonTools

struct HTMLTextTests {
    @Test func stripsTagsAndCollapsesWhitespace() {
        let html = "<html><body><h1>Title</h1>\n\n  <p>Hello   <b>world</b>!</p></body></html>"
        #expect(stripHTML(html) == "Title Hello world !")
    }

    @Test func removesScriptAndStyleBlocksEntirely() {
        let html = "<p>before</p><script>var x = '<p>not text</p>';</script><style>p { color: red }</style><p>after</p>"
        #expect(stripHTML(html) == "before after")
    }

    @Test func scriptMatchingIsCaseInsensitive() {
        let html = "<P>a</P><SCRIPT>junk()</SCRIPT><p>b</p>"
        #expect(stripHTML(html) == "a b")
    }

    @Test func unterminatedScriptDropsTheRest() {
        let html = "<p>kept</p><script>never closed"
        #expect(stripHTML(html) == "kept")
    }

    @Test func plainTextPassesThrough() {
        #expect(stripHTML("just some text") == "just some text")
    }

    @Test func capLimitsInputSize() {
        let html = "<p>" + String(repeating: "a", count: 100) + "</p>"
        let out = stripHTML(html, cap: 10)
        // Capped input: only what fits in the first 10 chars survives
        #expect(out.count <= 10)
    }

    @Test func largePageFinishesQuickly() {
        // The regex-based version took minutes on inputs like this
        let block = "<div class=\"x\"><script>var a = 1;</script><p>content here</p></div>"
        let html = String(repeating: block, count: 5_000)  // ~340KB
        let start = ContinuousClock.now
        let out = stripHTML(html)
        let elapsed = ContinuousClock.now - start
        #expect(out.contains("content here"))
        #expect(elapsed < .seconds(5))
    }
}
