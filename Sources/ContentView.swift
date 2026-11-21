import SwiftUI
import WebKit

final class ZaloWebStore: ObservableObject {
    weak var webView: WKWebView?
    @Published var isMobileUI: Bool = true
    @Published var isInChat: Bool = false
    @Published var isLoading: Bool = false

    func goBackToList() {
        isInChat = false
        webView?.evaluateJavaScript("window.__zaloGoBack && window.__zaloGoBack();", completionHandler: nil)
    }

    func toggleUIMode() {
        isMobileUI.toggle()
        if !isMobileUI {
            isInChat = false
        }
        let flag = isMobileUI ? "true" : "false"
        webView?.evaluateJavaScript("window.__zaloSetMobileMode && window.__zaloSetMobileMode(\(flag));", completionHandler: nil)
    }

    func reload() {
        webView?.reload()
    }
}

struct ContentView: View {
    @StateObject private var store = ZaloWebStore()
    private let zaloBlue = Color(red: 0.0, green: 0.408, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            // Thanh tiêu đề phong cách Zalo iOS
            HStack(spacing: 12) {
                if store.isMobileUI && store.isInChat {
                    Button(action: store.goBackToList) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Tin nhắn")
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                } else {
                    Text("Zalo")
                        .font(.system(size: 18, weight: .bold))
                }

                Spacer()

                if store.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }

                // Nút chuyển nhanh giữa giao diện iOS và giao diện Web máy tính gốc
                Button(action: store.toggleUIMode) {
                    HStack(spacing: 4) {
                        Image(systemName: store.isMobileUI ? "desktopcomputer" : "iphone")
                        Text(store.isMobileUI ? "Web" : "iOS")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                }

                Button(action: store.reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(zaloBlue.ignoresSafeArea(edges: .top))

            ZaloWebView(store: store)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct ZaloWebView: UIViewRepresentable {
    @ObservedObject var store: ZaloWebStore

    // Giữ nguyên User-Agent macOS để Zalo cấp phiên Zalo Web
    private let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/18.0 Safari/605.1.15"

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Dùng viewport chuẩn di động để chữ sắc nét, đúng cỡ màn hình iPhone
        // trong khi User-Agent vẫn giả lập Safari macOS
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Cầu nối giao tiếp trạng thái giữa trang web và thanh tiêu đề SwiftUI
        config.userContentController.add(context.coordinator, name: "zaloBridge")

        // Script 1: Giả lập nền tảng macOS ngay khi trang bắt đầu tải
        let spoofScript = WKUserScript(
            source: #"""
            Object.defineProperty(navigator, 'platform', {
                get: function() { return 'MacIntel'; }
            });
            """#,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(spoofScript)

        // Script 2: Biến đổi giao diện Zalo Web thành dạng 1 cột giống Zalo iOS
        let mobileUIScript = WKUserScript(
            source: Self.mobileThemeJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(mobileUIScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = desktopUserAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        store.webView = webView

        if let url = URL(string: "https://chat.zalo.me") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "zaloBridge")
    }

    // Mã CSS & JS tiêm vào Zalo Web
    private static let mobileThemeJS = #"""
    (function() {
        if (window.__zaloMobileInstalled) return;
        window.__zaloMobileInstalled = true;

        var mobileEnabled = true;
        var inChat = false;

        function notifySwift(state) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zaloBridge) {
                    window.webkit.messageHandlers.zaloBridge.postMessage(state);
                }
            } catch (e) {}
        }

        function setViewport(isMobile) {
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
            }
            if (isMobile) {
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
            } else {
                meta.content = 'width=1024, initial-scale=0.38, user-scalable=yes';
            }
        }

        function injectCSS() {
            if (document.getElementById('ios-zalo-style')) return;
            var style = document.createElement('style');
            style.id = 'ios-zalo-style';
            style.textContent = `
                /* Bỏ giới hạn chiều rộng tối thiểu của bản máy tính */
                html.ios-zalo-ready,
                html.ios-zalo-ready body,
                html.ios-zalo-ready #app,
                html.ios-zalo-ready #container {
                    width: 100vw !important;
                    max-width: 100vw !important;
                    min-width: 0 !important;
                    overflow-x: hidden !important;
                    -webkit-tap-highlight-color: transparent;
                }

                /* Màn hình 1: Danh sách hội thoại chiếm toàn màn hình */
                html.ios-zalo-ready:not(.ios-zalo-in-chat) main,
                html.ios-zalo-ready:not(.ios-zalo-in-chat) #chatViewContainer {
                    display: none !important;
                }

                html.ios-zalo-ready:not(.ios-zalo-in-chat) #sidebarNav {
                    position: fixed !important;
                    top: 0 !important;
                    left: 0 !important;
                    right: 0 !important;
                    bottom: 56px !important;
                    width: 100vw !important;
                    max-width: 100vw !important;
                    min-width: 100vw !important;
                    height: calc(100% - 56px) !important;
                    z-index: 20 !important;
                }

                html.ios-zalo-ready:not(.ios-zalo-in-chat) #sidebarNav > *:not(#main-tab) {
                    width: 100vw !important;
                    max-width: 100vw !important;
                    flex: 1 !important;
                }

                /* Đưa thanh menu xanh bên trái xuống thành thanh tab ngang ở đáy */
                html.ios-zalo-ready:not(.ios-zalo-in-chat) #main-tab {
                    position: fixed !important;
                    left: 0 !important;
                    right: 0 !important;
                    bottom: 0 !important;
                    top: auto !important;
                    width: 100vw !important;
                    min-width: 100vw !important;
                    height: 56px !important;
                    min-height: 56px !important;
                    display: flex !important;
                    flex-direction: row !important;
                    align-items: center !important;
                    justify-content: space-around !important;
                    padding: 0 6px !important;
                    z-index: 100 !important;
                    overflow-x: auto !important;
                }

                html.ios-zalo-ready:not(.ios-zalo-in-chat) #main-tab > div {
                    display: flex !important;
                    flex-direction: row !important;
                    align-items: center !important;
                    justify-content: space-around !important;
                    height: 56px !important;
                    width: auto !important;
                    padding: 0 !important;
                    margin: 0 !important;
                }

                /* Màn hình 2: Khung chat chiếm toàn màn hình khi đã chọn hội thoại */
                html.ios-zalo-ready.ios-zalo-in-chat #sidebarNav,
                html.ios-zalo-ready.ios-zalo-in-chat #main-tab {
                    display: none !important;
                }

                html.ios-zalo-ready.ios-zalo-in-chat main {
                    position: fixed !important;
                    top: 0 !important;
                    left: 0 !important;
                    right: 0 !important;
                    bottom: 0 !important;
                    width: 100vw !important;
                    max-width: 100vw !important;
                    min-width: 0 !important;
                    height: 100% !important;
                    display: flex !important;
                    z-index: 50 !important;
                }

                /* Tự co giãn khung nhập tin nhắn và bảng thông tin phụ */
                html.ios-zalo-ready.ios-zalo-in-chat main * {
                    min-width: 0;
                }

                html.ios-zalo-ready.ios-zalo-in-chat #chatInfo,
                html.ios-zalo-ready.ios-zalo-in-chat aside[id*="chatInfo"] {
                    position: fixed !important;
                    top: 0 !important;
                    right: 0 !important;
                    bottom: 0 !important;
                    width: 100vw !important;
                    max-width: 100vw !important;
                    z-index: 80 !important;
                }
            `;
            document.head.appendChild(style);
        }

        function isLoggedInChatPage() {
            var isChatHost = location.hostname.indexOf('chat.zalo.me') !== -1;
            if (!isChatHost) return false;
            return !!(document.getElementById('sidebarNav') && document.querySelector('main'));
        }

        function syncLayout() {
            injectCSS();
            var html = document.documentElement;
            if (!mobileEnabled) {
                html.classList.remove('ios-zalo-ready', 'ios-zalo-in-chat');
                setViewport(false);
                return;
            }
            setViewport(true);
            if (isLoggedInChatPage()) {
                html.classList.add('ios-zalo-ready');
                if (inChat) {
                    html.classList.add('ios-zalo-in-chat');
                } else {
                    html.classList.remove('ios-zalo-in-chat');
                }
            } else {
                html.classList.remove('ios-zalo-ready', 'ios-zalo-in-chat');
                if (inChat) {
                    inChat = false;
                    notifySwift('inList');
                }
            }
        }

        window.__zaloGoBack = function() {
            inChat = false;
            syncLayout();
            notifySwift('inList');
        };

        window.__zaloSetMobileMode = function(enabled) {
            mobileEnabled = !!enabled;
            if (!mobileEnabled) inChat = false;
            syncLayout();
            notifySwift(inChat ? 'inChat' : 'inList');
        };

        // Tự động chuyển sang màn hình khung chat khi người dùng bấm vào một cuộc trò chuyện
        document.addEventListener('click', function(e) {
            if (!mobileEnabled || inChat || !isLoggedInChatPage()) return;
            var target = e.target;
            if (!target || !target.closest) return;

            // Bỏ qua nếu đang bấm vào thanh tab dưới đáy hoặc ô tìm kiếm
            if (target.closest('#main-tab') || target.closest('input, textarea')) return;

            var inSidebar = target.closest('#sidebarNav');
            var isConvItem = target.closest('#conversationListId, .msg-item, [class*="conv-item"], [data-id*="div_Conv"]');

            if (isConvItem || (inSidebar && e.clientY > 105)) {
                setTimeout(function() {
                    var hasActiveChat = document.querySelector('main #messageView, main #chatInput, main #richInput, main [contenteditable="true"]');
                    if (hasActiveChat) {
                        inChat = true;
                        syncLayout();
                        notifySwift('inChat');
                    }
                }, 150);
            }
        }, true);

        // Hỗ trợ cử chỉ vuốt từ cạnh trái màn hình để quay về danh sách tin nhắn
        var touchStartX = 0, touchStartY = 0;
        document.addEventListener('touchstart', function(e) {
            if (e.touches.length === 1) {
                touchStartX = e.touches[0].clientX;
                touchStartY = e.touches[0].clientY;
            }
        }, { passive: true });

        document.addEventListener('touchend', function(e) {
            if (!mobileEnabled || !inChat || e.changedTouches.length !== 1) return;
            var dx = e.changedTouches[0].clientX - touchStartX;
            var dy = Math.abs(e.changedTouches[0].clientY - touchStartY);
            if (touchStartX < 36 && dx > 70 && dy < 60) {
                window.__zaloGoBack();
            }
        }, { passive: true });

        // Theo dõi DOM để áp dụng ngay khi Zalo Web tải xong sau khi quét QR
        var timer = null;
        var observer = new MutationObserver(function() {
            if (timer) return;
            timer = setTimeout(function() {
                timer = null;
                syncLayout();
            }, 250);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });

        syncLayout();
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let store: ZaloWebStore

        init(store: ZaloWebStore) {
            self.store = store
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "zaloBridge", let state = message.body as? String else { return }
            DispatchQueue.main.async {
                if state == "inChat" {
                    self.store.isInChat = true
                } else if state == "inList" {
                    self.store.isInChat = false
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.preferredContentMode = .mobile

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow, preferences)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""

            let allowedSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
            if !allowedSchemes.contains(scheme) {
                decisionHandler(.cancel, preferences)
                return
            }

            if host.contains("apps.apple.com") || host.contains("itunes.apple.com") {
                decisionHandler(.cancel, preferences)
                return
            }

            let allowInWebViewOnly =
                WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
            decisionHandler(allowInWebViewOnly, preferences)
        }

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
                UIApplication.shared.open(url)
            }
            return nil
        }

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
