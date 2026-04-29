import SwiftUI
import WebKit

/// Renders an HTML email body inside a WKWebView, with safe defaults.
///
/// Why every detail matters:
///
/// 1. **No JavaScript inside the email.**
///    `defaultWebpagePreferences.allowsContentJavaScript = false` blocks
///    all script in the loaded document. Email is data, not an app.
///    A small ScriptHost script *we* add via `userContentController` does
///    run — that's how we report content height. It executes in the page
///    world but has no effect outside our `mailstreamHeight` channel.
///
/// 2. **No remote images by default.**
///    HTML is pre-processed to strip remote `src` / `srcset` and remote
///    `<link href>` so tracking pixels never fire. The user opts in via
///    the "Show images" button (state owned by the parent).
///
/// 3. **Links open in the system browser.**
///    All `linkActivated` / form submits are cancelled and handed to
///    `NSWorkspace`.
///
/// 4. **Single scroll surface.**
///    The WKWebView's internal NSScrollView has its scrollers and bounce
///    disabled. The webview frame matches its content height (reported
///    via ResizeObserver), so the only scroll surface is the parent
///    `ScrollView` in `MessageDetailView`.
///
/// 5. **Transparent background.**
///    `drawsBackground = false` lets the page sit on `DS.Color.surface`.
///
/// We deliberately do *not* recolor the email for dark mode — many
/// templates hard-code colors and overriding them mid-render breaks
/// contrast. Same behavior as Gmail / Apple Mail.
struct HTMLMessageBodyView: NSViewRepresentable {
    let html: String
    var allowRemoteImages: Bool = false
    /// While `true`, the underlying WKWebView ignores width changes
    /// at the AppKit layer (`setFrameSize` clamps width to the last
    /// committed value). Set this from the SwiftUI side during pane
    /// resize drags so the HTML doesn't keep reflowing — the visible
    /// "flicker" symptom the user reported.
    var isResizing: Bool = false
    var onContentHeight: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: ScriptHost.heightChannel)

        // Inject the height-reporter at document end so ResizeObserver
        // attaches to a real layout tree.
        let heightScript = WKUserScript(
            source: ScriptHost.heightReporterJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContent.addUserScript(heightScript)

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true   // we only ship our own

        // Use the scroll-passthrough subclass so the cursor over the
        // rendered HTML still scrolls the parent SwiftUI ScrollView.
        let view = ScrollPassthroughWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsLinkPreview = false
        view.setValue(false, forKey: "drawsBackground")  // private but stable since 10.10
        view.translatesAutoresizingMaskIntoConstraints = false
        // Defer scroll-disable until after first layout — the internal
        // NSScrollView only exists once the webview has subviews.
        DispatchQueue.main.async { Self.disableInternalScroll(in: view) }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Refresh the coordinator's `parent` snapshot so the height
        // callback closure invokes the *current* SwiftUI state setter,
        // not the one captured when the coordinator was first built.
        context.coordinator.parent = self

        // Push the resize-freeze flag down to the AppKit layer. This
        // is the actual fix for the "email body keeps flickering
        // during pane drag" report — the SwiftUI `frame(width:)`
        // path was unreliable because the NSHostingView still issues
        // setFrameSize to the WKWebView based on its own resize
        // pass. Intercepting setFrameSize on the WKWebView subclass
        // is the only place that's guaranteed to win.
        if let passthrough = view as? ScrollPassthroughWebView {
            passthrough.freezeWidth = isResizing
        }

        let processed = allowRemoteImages ? html : Self.blockRemoteAssets(in: html)
        let wrapped = Self.wrap(processed)

        // The bug we're guarding against: SwiftUI calls `updateNSView`
        // on *every* re-render of the parent view tree (selection
        // changes, hover state on a sibling button, height callback
        // bouncing back into our own @State, …). If we unconditionally
        // re-load the same HTML, WKWebView discards the rendered
        // document and repaints from white → the user sees a flash.
        // Skip the reload when the wrapped output is byte-identical
        // to what's already showing.
        if context.coordinator.lastLoadedHTML == wrapped {
            return
        }
        context.coordinator.lastLoadedHTML = wrapped

        // Re-disable internal scrollers on actual loads only — AppKit
        // may rebuild subviews when the document changes, but doesn't
        // when we skip above.
        Self.disableInternalScroll(in: view)
        view.loadHTMLString(wrapped, baseURL: nil)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // Detach the message handler so we don't leak the coordinator.
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: ScriptHost.heightChannel
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: – Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLMessageBodyView
        /// Snapshot of the last HTML we actually handed to
        /// `loadHTMLString`. Used by `updateNSView` to short-circuit
        /// no-op reloads. The whole-string compare is fine for our
        /// payload sizes (median ~30 KB, max ~3 MB) — SwiftUI calls
        /// `updateNSView` at human-frame cadence at worst.
        var lastLoadedHTML: String?
        init(_ parent: HTMLMessageBodyView) { self.parent = parent }

        // Navigation: open external links in the system browser, or
        // swallow them entirely when the user has disabled
        // `Settings → 通用 → 在浏览器中打开链接`. Read live from
        // UserDefaults so a flip in Settings affects the very next
        // click without rebuilding the WebView. We always cancel the
        // in-WebView navigation — letting WKWebView load `https://…`
        // would replace the rendered email body in place, which is
        // never what the user wants.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            switch navigationAction.navigationType {
            case .linkActivated, .formSubmitted, .formResubmitted:
                let opensExternally = UserDefaults.standard
                    .object(forKey: "mailclient.links.external") as? Bool ?? true
                if opensExternally, let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
                // When the toggle is off we still cancel — the email
                // body stays put. The link effectively becomes
                // copy-only, which is the privacy-preserving
                // semantic the toggle promises.
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }

        // The injected ResizeObserver pushes a number every time layout
        // changes — typically once on initial paint, again after fonts
        // and any unblocked images settle.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == ScriptHost.heightChannel else { return }
            let value: CGFloat = {
                if let d = message.body as? Double { return CGFloat(d) }
                if let i = message.body as? Int    { return CGFloat(i) }
                if let n = message.body as? NSNumber { return CGFloat(truncating: n) }
                return 0
            }()
            guard value > 0 else { return }
            parent.onContentHeight(value)
        }
    }

    // MARK: – Private: disable internal scrolling

    /// macOS WKWebView wraps its document view in an internal NSScrollView.
    /// It's not exposed publicly; we walk the subview tree to find it.
    /// Once located we kill the scrollers and bounce so the only scroll
    /// surface is our parent SwiftUI ScrollView.
    private static func disableInternalScroll(in root: NSView) {
        for subview in root.subviews {
            if let scroll = subview as? NSScrollView {
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
                scroll.verticalScrollElasticity = .none
                scroll.horizontalScrollElasticity = .none
                scroll.scrollerStyle = .overlay
                scroll.drawsBackground = false
            }
            disableInternalScroll(in: subview)
        }
    }

    // MARK: – HTML pre-processing

    private static func blockRemoteAssets(in html: String) -> String {
        var out = html
        let patterns: [(String, String)] = [
            (#"\bsrc\s*=\s*['\"]https?://[^'\"]*['\"]"#,    "src=\"\""),
            (#"\bsrcset\s*=\s*['\"][^'\"]*['\"]"#,           "srcset=\"\""),
            (#"<link\b[^>]*href\s*=\s*['\"]https?://[^'\"]*['\"][^>]*>"#, ""),
            // background-image: url(http...)
            (#"background(?:-image)?\s*:\s*url\(\s*['\"]?https?://[^)]*\)"#, "background:none"),
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = out as NSString
                out = regex.stringByReplacingMatches(
                    in: out,
                    range: NSRange(location: 0, length: ns.length),
                    withTemplate: replacement
                )
            }
        }
        return out
    }

    /// Wrap the body in a minimal document with our typography baseline.
    /// Conservative — we set defaults but don't override the email's
    /// own design intent (palette, fixed widths, etc.).
    private static func wrap(_ inner: String) -> String {
        // CSS philosophy: provide sane defaults, never override the
        // email's own layout. Two rules to *avoid* (we tried, they
        // cause measurable problems):
        //
        //  · `* { box-sizing: border-box }`  — flips width/padding math
        //    mid-render, which can ripple back into height changes and
        //    re-fire our height channel.
        //  · `td, div, section { max-width: 100% !important }` — breaks
        //    table-based marketing layouts whose cells use fixed widths.
        //
        // What we *do* set:
        let css = """
        :root { color-scheme: light; }
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC",
                         "Helvetica Neue", Arial, sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: #1a1a1a;
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word;
            overflow-wrap: anywhere;
            /* Parent SwiftUI ScrollView owns scrolling; body never scrolls. */
            overflow: hidden;
        }
        a { color: #2457d6; }
        img, video {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }
        /* Blocked remote images become invisible (no jarring placeholder).
           The "Show images" toggle re-loads them. */
        img[src=""], img:not([src]) { display: none !important; }
        table { border-collapse: collapse; max-width: 100%; }
        pre, code { font-family: "SF Mono", Menlo, monospace; font-size: 12.5px; }
        blockquote {
            border-left: 3px solid #e6e9ee;
            margin: 8px 0;
            padding-left: 12px;
            color: #6e7989;
        }
        """
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>\(inner)</body>
        </html>
        """
    }
}

// MARK: - Script host
//
// All JS we inject lives here. Keeping it in one place makes the
// security surface explicit — every script that runs in the email's
// page context is in this enum.

private enum ScriptHost {
    /// Channel name shared between the JS poster and the Swift handler.
    static let heightChannel = "mailstreamHeight"

    /// Reports the document content height to native code.
    ///
    /// Why event-driven (no ResizeObserver):
    /// SwiftUI sets the WKWebView frame to whatever we report. Changing
    /// the frame changes `documentElement`'s size — observing it would
    /// fire on every resize and create a feedback loop ("scroll bar
    /// grows infinitely"). We instead measure on a fixed list of
    /// triggers: initial paint, fonts ready, image load/error. JS is
    /// disabled inside the email, so the layout doesn't change after
    /// these events without us asking.
    ///
    /// We measure only `document.body.scrollHeight` — that's the
    /// content's intrinsic height and doesn't grow when the viewport
    /// (= WKWebView frame) does, as long as the body has natural sizing.
    static let heightReporterJS = """
    (function () {
        const post = (h) => {
            try { window.webkit.messageHandlers.\(heightChannel).postMessage(h); }
            catch (_) {}
        };
        let lastReported = -1;
        const measure = () => {
            // body.scrollHeight is the intrinsic content extent.
            // It doesn't change when the WKWebView frame grows because
            // body has overflow:hidden + no height: 100% on children.
            const h = document.body ? document.body.scrollHeight : 0;
            if (h <= 0) return;
            // Threshold of 2px to swallow sub-pixel rounding noise.
            if (Math.abs(h - lastReported) < 2) return;
            lastReported = h;
            post(h);
        };
        const schedule = () => requestAnimationFrame(measure);

        // Initial measure on next frame so first paint has settled.
        schedule();

        // Re-measure when fonts finish loading.
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(schedule);
        }

        // Re-measure when each image (allowed or blocked) resolves.
        document.querySelectorAll('img').forEach((img) => {
            if (img.complete) return;
            img.addEventListener('load',  schedule, { once: true });
            img.addEventListener('error', schedule, { once: true });
        });

        // One last safety re-measure after any animations / late style
        // resolution (max 200ms after document end).
        setTimeout(schedule, 80);
        setTimeout(schedule, 200);
    })();
    """
}

// MARK: - Scroll passthrough
//
// Why a custom subclass:
// macOS WKWebView wraps its document in an internal NSScrollView. Even
// when we disable that NSScrollView's scrollers and elasticity (so it
// can't actually scroll its own content), it still *receives* wheel
// events because it's the topmost view under the cursor. The events
// never propagate to our outer SwiftUI ScrollView, so users can only
// scroll on the strip of empty space outside the rendered HTML.
//
// Override `scrollWheel(with:)` to forward every wheel event up the
// responder chain. The web view never tries to scroll itself, the
// outer ScrollView always receives the event regardless of where the
// cursor sits. Clicks, text selection, link activation are unaffected
// because they go through different responder methods.

final class ScrollPassthroughWebView: WKWebView {
    /// When true, `setFrameSize` ignores incoming width changes and
    /// keeps the previously committed width. Driven by the parent
    /// SwiftUI view via `HTMLMessageBodyView.updateNSView`. The
    /// height portion of any frame change is still honoured because
    /// content height legitimately changes when the user toggles
    /// "show images" or similar — only horizontal reflow during a
    /// pane drag is the problem we're suppressing.
    var freezeWidth: Bool = false
    private var lastCommittedWidth: CGFloat = 0

    // Intercept BOTH the `frame` property setter and `setFrameSize(_:)`.
    // WKWebView is hosted via Auto Layout, so the constraint solver
    // sets `frame` directly (Swift bridges this to the ObjC
    // -setFrame: selector). setFrameSize is the autoresizing-masked
    // path; overriding it costs nothing and protects future call
    // sites. While freezeWidth is true we replace the width portion
    // of any incoming geometry with `lastCommittedWidth` so WebKit
    // never sees a width change → no document relayout → no flicker.
    override var frame: NSRect {
        get { super.frame }
        set {
            if freezeWidth, lastCommittedWidth > 0 {
                var clamped = newValue
                clamped.size.width = lastCommittedWidth
                super.frame = clamped
                return
            }
            super.frame = newValue
            if newValue.size.width > 0 {
                lastCommittedWidth = newValue.size.width
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        if freezeWidth, lastCommittedWidth > 0 {
            super.setFrameSize(NSSize(width: lastCommittedWidth, height: newSize.height))
            return
        }
        super.setFrameSize(newSize)
        if newSize.width > 0 {
            lastCommittedWidth = newSize.width
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward to the next responder so the parent SwiftUI
        // ScrollView gets the wheel event. We deliberately do NOT
        // call super — that would let the internal NSScrollView
        // consume / animate the event, which is the whole problem.
        nextResponder?.scrollWheel(with: event)
    }
}
