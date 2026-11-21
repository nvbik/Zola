import SwiftUI
import WebKit

// Quản lý trạng thái và điều khiển WKWebView từ thanh công cụ
final class ZaloWebStore: ObservableObject {
    weak var webView: WKWebView?
    @Published var pageZoom: CGFloat = 0.75
    @Published var isLoading: Bool = false

    func reload() {
        webView?.reload()
    }

    func goHome() {
        guard let url = URL(string: "https://chat.zalo.me") else { return }
        webView?.load(URLRequest(url: url))
    }

    func adjustZoom(by delta: CGFloat) {
        let next = min(max(pageZoom + delta, 0.45), 1.25)
        pageZoom = (next * 100).rounded() / 100
        webView?.pageZoom = pageZoom
    }
}

struct ContentView: View {
    @StateObject private var store = ZaloWebStore()

    var body: some View {
        VStack(spacing: 0) {
            // Thanh công cụ gọn nhẹ để thu phóng giao diện desktop trên màn hình iPhone
            HStack(spacing: 16) {
                Button(action: store.goHome) {
                    Image(systemName: "house")
                }

                Button(action: store.reload) {
                    Image(systemName: "arrow.clockwise")
                }

                Spacer()

                if store.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: { store.adjustZoom(by: -0.05) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(store.pageZoom * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40)
                    Button(action: { store.adjustZoom(by: 0.05) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))

            ZaloWebView(store: store)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct ZaloWebView: UIViewRepresentable {
    @ObservedObject var store: ZaloWebStore

    // User-Agent của Safari trên macOS (khớp engine WebKit nên ít lỗi JS nhất)
    private let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/18.0 Safari/605.1.15"

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // 1. Lưu Cookie, LocalStorage và IndexedDB cố định để không bị đăng xuất
        config.websiteDataStore = .default()

        // 2. Bật chế độ hiển thị Desktop mặc định của WebKit
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // 3. Cho phép phát video/âm thanh trực tiếp trong khung chat
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // 4. Tiêm JS ngay khi khởi tạo trang để giả lập nền tảng macOS
        let spoofScriptSource = """
        Object.defineProperty(navigator, 'platform', {
            get: function() { return 'MacIntel'; }
        });
        """
        let spoofScript = WKUserScript(
            source: spoofScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(spoofScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = desktopUserAgent
        webView.pageZoom = store.pageZoom
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        store.webView = webView

        if let url = URL(string: "https://chat.zalo.me") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.pageZoom != store.pageZoom {
            uiView.pageZoom = store.pageZoom
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let store: ZaloWebStore

        init(store: ZaloWebStore) {
            self.store = store
        }

        // Chặn chuyển hướng sang app Zalo gốc hoặc App Store
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            // Ép buộc chế độ Desktop trên mọi bước chuyển hướng (id.zalo.me -> chat.zalo.me)
            preferences.preferredContentMode = .desktop

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow, preferences)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""

            // Hủy các Deep Link như zalo:// hoặc itms-apps://
            let allowedSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
            if !allowedSchemes.contains(scheme) {
                decisionHandler(.cancel, preferences)
                return
            }

            if host.contains("apps.apple.com") || host.contains("itunes.apple.com") {
                decisionHandler(.cancel, preferences)
                return
            }

            // Dùng cờ AllowWithoutTryingAppLink (rawValue + 2) để chặn Universal Link mở app Zalo
            let allowInWebViewOnly =
                WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowInWebViewOnly, preferences)
        }

        // Xử lý các liên kết mở tab mới (target="_blank")
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                return nil
            }

            let host = url.host?.lowercased() ?? ""
            if host.contains("zalo.me") || host.contains("zaloapp.com") {
                webView.load(navigationAction.request)
            } else {
                // Mở các link web bên ngoài bằng Safari hệ thống
                UIApplication.shared.open(url)
            }
            return nil
        }

        // Tự động cấp quyền Micro/Camera cho WebView (dùng khi gửi tin nhắn thoại)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.store.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.store.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.store.isLoading = false }
        }
    }
}
