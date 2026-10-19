#if os(macOS)
import Foundation
import Testing
import WebKit
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct WebKitContentProcessTests {
    @MainActor
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        var didFinish = false

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            self.didFinish = true
        }
    }

    @MainActor
    private final class EvaluationState {
        var isComplete = false
        var didFail = false
    }

    private func shouldSkipOnCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITHUB_ACTIONS"] == "true" || env["CI"] == "true"
    }

    @Test
    func `terminating a page stuck in JavaScript fails its pending evaluation`() async throws {
        if self.shouldSkipOnCI() {
            return
        }
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        // An endless microtask chain never yields back to WebKit's event loop (#4641).
        webView.loadHTMLString(
            "<script>function spin() { Promise.resolve().then(spin); } setTimeout(spin, 50);</script>",
            baseURL: nil)
        let loadDeadline = Date().addingTimeInterval(5)
        while !waiter.didFinish, Date() < loadDeadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try #require(waiter.didFinish)
        try? await Task.sleep(for: .milliseconds(300))

        let state = EvaluationState()
        webView.evaluateJavaScript("document.title") { _, error in
            state.isComplete = true
            state.didFail = error != nil
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(!state.isComplete, "A spinning page must not answer evaluations")

        #expect(WebKitContentProcess.terminate(webView))

        let deadline = Date().addingTimeInterval(5)
        while !state.isComplete, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(state.isComplete, "Termination must release the pending evaluation")
        #expect(state.didFail)
    }
}
#endif
