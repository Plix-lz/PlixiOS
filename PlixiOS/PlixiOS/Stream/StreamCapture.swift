import Foundation
import WebKit

/// Scripts propios de PLIX (no provienen del servidor). Port de HlsJsHooks / StreamWishJsHooks:
/// interceptan fetch, XHR y Hls.js en la página del embed y reportan la URL del stream a Swift.
/// iOS no permite interceptar peticiones de red del WebView como `shouldInterceptRequest` en Android,
/// así que la detección depende de estos hooks y del escaneo del DOM.
enum CaptureScripts {
    static let handlerName = "plixCapture"

    static let detect = """
    (function(){
      if(window.__plixHookHls)return;window.__plixHookHls=true;
      function norm(u){try{return (u||'').toString().replace(/\\\\\\//g,'/');}catch(e){return '';}}
      function abs(u){try{return new URL(norm(u),location.href).href;}catch(e){return norm(u);}}
      function esStream(u){
        u=norm(u).toLowerCase();
        if(!u||u.indexOf('blob:')===0||u.indexOf('data:')===0)return false;
        if(u.indexOf('init-')>=0||u.indexOf('fragment-')>=0||u.indexOf('.m4s')>=0||u.indexOf('.woff')>=0)return false;
        if(u.indexOf('betwinner')>=0||u.indexOf('amd-cdn-')>=0)return false;
        if(u.indexOf('/content/stream/agl/')>=0&&u.indexOf('.mp4')>=0)return false;
        if(u.indexOf('.m3u8')>=0||u.indexOf('%2em3u8')>=0||u.indexOf('/m3u8')>=0||u.indexOf('m3u8?')>=0)return true;
        if(u.indexOf('master.txt')>=0||(u.indexOf('index-f')>=0&&u.indexOf('.txt')>=0))return true;
        if(u.indexOf('.mpd')>=0)return true;
        if(u.indexOf('.mp4')>=0)return true;
        if(u.indexOf('.urlset')>=0&&(u.indexOf('/hls3/')>=0||u.indexOf('/hls2/')>=0||u.indexOf('/hls/')>=0))return true;
        return (u.indexOf('/hls3/')>=0||u.indexOf('/hls2/')>=0||u.indexOf('/hls/')>=0||u.indexOf('/stream/')>=0)
          &&(u.indexOf('playlist')>=0||u.indexOf('master')>=0||u.indexOf('index')>=0);
      }
      var sent={};
      function report(u){
        u=abs(u);if(!u||!esStream(u)||sent[u])return;sent[u]=1;
        try{window.webkit.messageHandlers.\(handlerName).postMessage({page:String(location.href).slice(0,2048),url:u.slice(0,4096)});}catch(e){}
      }
      function scan(){try{
        document.querySelectorAll('video,source,a,iframe,script,link').forEach(function(el){
          var c=(el.src||el.href||'');if(c)report(c);
          if(el.tagName==='VIDEO'){try{if(el.currentSrc)report(el.currentSrc);}catch(e){}}
          if(el.tagName==='SCRIPT'&&el.textContent&&el.textContent.length<400000){
            var t=norm(el.textContent);
            var m=t.match(/https?:\\/\\/[^\\s"'<>]+?(?:\\.m3u8|\\/m3u8|master\\.txt|index-f\\d+-v1-a1\\.txt|\\.mpd|\\.mp4|\\/hls3?\\/[^\\s"'<>]+)[^\\s"'<>]*/gi)||[];
            m.forEach(report);
          }
        });
        if(window.performance&&performance.getEntriesByType){performance.getEntriesByType('resource').forEach(function(e){report(e&&e.name);});}
      }catch(e){}}
      var of=window.fetch;
      if(of){window.fetch=function(input){try{report(typeof input==='string'?input:(input&&input.url));}catch(e){}return of.apply(this,arguments);};}
      if(window.XMLHttpRequest&&XMLHttpRequest.prototype){
        var ox=XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open=function(m,url){try{report(url);}catch(e){}return ox.apply(this,arguments);};
      }
      function hookHls(){try{var H=window.Hls;if(!H||!H.prototype||H.prototype.__plixHooked)return;
        H.prototype.__plixHooked=true;var old=H.prototype.loadSource;
        H.prototype.loadSource=function(u){try{report(u);}catch(e){}return old.apply(this,arguments);};}catch(e){}}
      hookHls();setInterval(hookHls,400);
      document.addEventListener('DOMContentLoaded',scan);scan();setInterval(scan,700);
    })();
    """

    static let forcePlay = """
    (function(){
      if(window.__plixForzar)return;window.__plixForzar=true;
      function ev(el,t){try{el.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));}catch(e){}}
      function tocar(el){try{if(!el)return;ev(el,'pointerdown');ev(el,'mousedown');ev(el,'mouseup');ev(el,'click');}catch(e){}}
      function activar(){try{
        document.querySelectorAll('video').forEach(function(v){try{v.muted=true;v.autoplay=true;v.playsInline=true;
          var p=v.play&&v.play();if(p&&p.catch)p.catch(function(){});}catch(e){}});
        document.querySelectorAll('.jw-icon-playback,.vjs-big-play-button,.plyr__control--overlaid,[class*=play]').forEach(tocar);
      }catch(e){}}
      activar();setInterval(activar,900);
    })();
    """

    static let mute = "(function(){try{document.querySelectorAll('video').forEach(function(v){v.muted=true;v.pause();});}catch(e){}})();"
}

/// Evita el ciclo de retención WKUserContentController → handler.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Captura el stream real de un embed cargándolo en un WKWebView (oculto, o visible si el
/// servidor exige verificación humana). Solo se aceptan mensajes del handler propio,
/// con estructura y URL validadas.
@MainActor
final class StreamCaptureEngine: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var needsUserInteraction = false
    @Published private(set) var isCapturing = false

    let webView: WKWebView
    private var continuation: CheckedContinuation<CapturedStream?, Never>?
    private var candidates: [String: String] = [:]
    private var embedURL = ""
    private var embedHost = ""
    private var forcePlay = true
    private var settleTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: CaptureScripts.detect, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        controller.add(WeakMessageHandler(self), name: CaptureScripts.handlerName)
        webView.customUserAgent = HTTP.mobileBrowserUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
    }

    /// Devuelve el stream o nil si se agotó el tiempo o se canceló.
    func capture(embed: String, label: String, timeout: TimeInterval, visible: Bool) async -> CapturedStream? {
        cancel()
        guard let url = URL(string: StreamURL.normalize(embed)), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        embedURL = url.absoluteString
        embedHost = url.host?.lowercased() ?? ""
        candidates = [:]
        forcePlay = !visible
        needsUserInteraction = visible
        isCapturing = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            var request = URLRequest(url: url)
            request.setValue(embedRefererFor(label: label, url: url.absoluteString), forHTTPHeaderField: "Referer")
            webView.load(request)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.finishWithBestCandidate()
            }
        }
    }

    /// El usuario pidió ver el servidor (verificación / captcha) sin reiniciar la captura.
    func revealForUser() {
        needsUserInteraction = true
        forcePlay = false
    }

    func cancel() {
        settleTask?.cancel()
        timeoutTask?.cancel()
        settleTask = nil
        timeoutTask = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: nil)
        }
        webView.stopLoading()
        webView.evaluateJavaScript(CaptureScripts.mute)
        webView.loadHTMLString("", baseURL: nil)
        isCapturing = false
        needsUserInteraction = false
    }

    private func embedRefererFor(label: String, url: String) -> String {
        ServerFamily.from(url: url, label: label).fallbackReferer ?? "https://pelixplay.app/"
    }

    private func finish(_ result: CapturedStream?) {
        settleTask?.cancel()
        timeoutTask?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        isCapturing = false
        needsUserInteraction = false
        webView.evaluateJavaScript(CaptureScripts.mute)
        continuation.resume(returning: result)
    }

    private func finishWithBestCandidate() async {
        guard continuation != nil else { return }
        guard let best = candidates.keys.max(by: { StreamURL.playlistQualityScore($0) < StreamURL.playlistQualityScore($1) }) else {
            finish(nil)
            return
        }
        let page = candidates[best] ?? embedURL
        let cookies = await cookieHeader(for: best)
        let referer = StreamURL.isHttp(page) ? page : embedURL
        finish(CapturedStream(url: best, referer: referer, embedUrl: embedURL,
                              headers: StreamHeaders.build(streamURL: best, referer: referer, embedURL: embedURL, cookies: cookies)))
    }

    private func cookieHeader(for urlString: String) async -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return nil }
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
        guard !matching.isEmpty else { return nil }
        return matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    // MARK: Validación del puente JS → Swift

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == CaptureScripts.handlerName, continuation != nil,
              let body = message.body as? [String: Any], body.count <= 2,
              let rawURL = body["url"] as? String, rawURL.count <= 4096 else { return }
        let page = (body["page"] as? String).map { String($0.prefix(2048)) } ?? embedURL
        let url = StreamURL.normalize(rawURL)
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(), scheme == "https" || scheme == "http",
              parsed.host != nil, !StreamURL.isJunk(url), !StreamURL.isDash(url), Self.looksLikeStream(url) else { return }
        candidates[url] = page
        let score = StreamURL.playlistQualityScore(url)
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: score >= 100 ? 300_000_000 : 1_200_000_000)
            guard !Task.isCancelled else { return }
            await self?.finishWithBestCandidate()
        }
    }

    static func looksLikeStream(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("init-") || lower.contains("fragment-") || lower.contains(".m4s") { return false }
        if lower.contains("youtube.com") || lower.contains("youtu.be") { return false }
        if StreamURL.isPlayableStream(url) { return true }
        if lower.contains("master.txt") || (lower.contains("index-f") && lower.contains(".txt")) { return true }
        return ["/hls3/", "/hls2/", "/hls/", "/stream/"].contains(where: lower.contains)
            && ["playlist", "master", "index"].contains(where: lower.contains)
    }

    // MARK: Navegación restringida

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
            return
        }
        guard scheme == "https" || scheme == "http" else {
            decisionHandler(.cancel)
            return
        }
        if StreamURL.isJunk(url.absoluteString) {
            decisionHandler(.cancel)
            return
        }
        let isMain = action.targetFrame?.isMainFrame ?? true
        if isMain, action.navigationType == .linkActivated, url.host?.lowercased() != embedHost {
            decisionHandler(.cancel)
            return
        }
        if StreamURL.isPlayableStream(url.absoluteString) && continuation != nil {
            candidates[url.absoluteString] = embedURL
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if forcePlay { webView.evaluateJavaScript(CaptureScripts.forcePlay) }
    }

    /// Bloquea pop-ups (ventanas nuevas de publicidad).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }
}
