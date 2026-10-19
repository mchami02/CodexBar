#if os(macOS)
import Darwin
import Foundation
import WebKit

/// Ends a WKWebView's WebContent process when its page stops responding.
///
/// A page stuck inside JavaScript never services `stopLoading()`, navigations, or pending
/// `evaluateJavaScript` replies, and WebKit only reaps the process once every owner has
/// released the view. A caller suspended on such an evaluation keeps the view alive, so the
/// helper can spin at a full core indefinitely (#4641). Terminating the process stops the CPU
/// use and fails the pending evaluations, which lets the suspended caller unwind.
@MainActor
enum WebKitContentProcess {
    private static let log = CodexBarLog.logger(LogCategories.webkitTeardown)

    @discardableResult
    static func terminate(_ webView: WKWebView) -> Bool {
        // WebKit SPI, present since macOS 10.13; it also fails pending callbacks and
        // notifies `webViewWebContentProcessDidTerminate`.
        let killAndReset = NSSelectorFromString("_killWebContentProcessAndResetState")
        if webView.responds(to: killAndReset) {
            webView.perform(killAndReset)
            self.log.warning("WebContent process terminated")
            return true
        }

        let pidKey = "_webProcessIdentifier"
        guard webView.responds(to: NSSelectorFromString(pidKey)),
              let pid = (webView.value(forKey: pidKey) as? NSNumber)?.int32Value,
              pid > 0,
              pid != getpid()
        else {
            self.log.warning("WebContent process termination unavailable")
            return false
        }
        let killed = kill(pid, SIGKILL) == 0
        self.log.warning("WebContent process killed", metadata: ["success": "\(killed)"])
        return killed
    }
}
#endif
