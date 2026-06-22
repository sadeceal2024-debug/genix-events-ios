import UIKit
import WebKit
import Speech
import AVFoundation
import StoreKit

var webView: WKWebView! = nil

class ViewController: UIViewController, WKNavigationDelegate, UIDocumentInteractionControllerDelegate {
    enum LoadingMode {
        case defaultCachePolicy
        case forceCache
    }

    var documentController: UIDocumentInteractionController?
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var connectionProblemView: UIImageView!
    @IBOutlet weak var webviewView: UIView!
    var toolbarView: UIToolbar!
    
    var htmlIsLoaded = false;
    private var loadingMode = LoadingMode.defaultCachePolicy
    
    private var themeObservation: NSKeyValueObservation?
    var currentWebViewTheme: UIUserInterfaceStyle = .unspecified
    override var preferredStatusBarStyle : UIStatusBarStyle {
        if #available(iOS 13, *), overrideStatusBar{
            if #available(iOS 15, *) {
                return .default
            } else {
                return statusBarTheme == "dark" ? .lightContent : .darkContent
            }
        }
        return .default
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initWebView()
        initToolbarView()
        loadRootUrl()
        if #available(iOS 15.0, *) { GenixIAP.shared.startObserving() }
    
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification , object: nil)
        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        DugunTakip.webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: nil)
    }
    
    @objc func keyboardWillHide(_ notification: NSNotification) {
        DugunTakip.webView.setNeedsLayout()
    }
    
    func initWebView() {
        DugunTakip.webView = createWebView(container: webviewView, WKSMH: self, WKND: self, NSO: self, VC: self)
        webviewView.addSubview(DugunTakip.webView);
        
        DugunTakip.webView.uiDelegate = self;
        
        DugunTakip.webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)

        if(pullToRefresh){
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(refreshWebView(_:)), for: UIControl.Event.valueChanged)
            DugunTakip.webView.scrollView.addSubview(refreshControl)
            DugunTakip.webView.scrollView.bounces = true
        }

        if #available(iOS 15.0, *), adaptiveUIStyle {
            themeObservation = DugunTakip.webView.observe(\.themeColor) { [unowned self] webView, _ in
                let backgroundColor = DugunTakip.webView.underPageBackgroundColor;
                let themeColor = DugunTakip.webView.themeColor;
                currentWebViewTheme = themeColor?.isLight() ?? backgroundColor?.isLight() ?? true ? .light : .dark
                self.overrideUIStyle()
                view.backgroundColor = themeColor ?? backgroundColor;
            }
        }
    }

    @objc func refreshWebView(_ sender: UIRefreshControl) {
        DugunTakip.webView?.reload()
        sender.endRefreshing()
    }

    func createToolbarView() -> UIToolbar{
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 60
        
        #if targetEnvironment(macCatalyst)
        if (statusBarHeight == 0){
            statusBarHeight = 30
        }
        #endif
        
        let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: webviewView.frame.width, height: 0))
        toolbarView.sizeToFit()
        toolbarView.frame = CGRect(x: 0, y: 0, width: webviewView.frame.width, height: toolbarView.frame.height + statusBarHeight)
//        toolbarView.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin, .flexibleWidth]
        
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let close = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(loadRootUrl))
        toolbarView.setItems([close,flex], animated: true)
        
        toolbarView.isHidden = true
        
        return toolbarView
    }
    
    func overrideUIStyle(toDefault: Bool = false) {
        if #available(iOS 15.0, *), adaptiveUIStyle {
            if (((htmlIsLoaded && !DugunTakip.webView.isHidden) || toDefault) && self.currentWebViewTheme != .unspecified) {
                UIApplication
                    .shared
                    .connectedScenes
                    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                    .first { $0.isKeyWindow }?.overrideUserInterfaceStyle = toDefault ? .unspecified : self.currentWebViewTheme;
            }
        }
    }
    
    func initToolbarView() {
        toolbarView =  createToolbarView()
        
        webviewView.addSubview(toolbarView)
    }
    
    @objc func loadRootUrl(cachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy) {
        DugunTakip.webView.load(URLRequest(url: SceneDelegate.universalLinkToLaunch ?? SceneDelegate.shortcutLinkToLaunch ?? rootUrl, cachePolicy: cachePolicy))
    }
    
    func reloadWebview(
        loadingMode: LoadingMode = LoadingMode.defaultCachePolicy
    ) {
        switch loadingMode {
        case LoadingMode.defaultCachePolicy:
            loadRootUrl(cachePolicy: .useProtocolCachePolicy);

        case LoadingMode.forceCache:
            loadRootUrl(cachePolicy: .useProtocolCachePolicy);
        }

        self.loadingMode = loadingMode
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
        htmlIsLoaded = true
        
        self.setProgress(1.0, true)
        self.animateConnectionProblem(false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DugunTakip.webView.isHidden = false
            self.loadingView.isHidden = true
           
            self.setProgress(0.0, false)
            
            self.overrideUIStyle()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        htmlIsLoaded = false;
        
        if (error as NSError)._code == (-999) { return }
        if (error as NSError)._code == 102 { return }
        
        self.overrideUIStyle(toDefault: true);
        webView.isHidden = true;
        loadingView.isHidden = false;

        if loadingMode == LoadingMode.defaultCachePolicy {
            DispatchQueue.main.async {
                self.reloadWebview(loadingMode: LoadingMode.forceCache)
            }
        } else {
            animateConnectionProblem(true);
            setProgress(0.05, true);
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.setProgress(0.1, true);
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.reloadWebview()
                }
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if (keyPath == #keyPath(WKWebView.estimatedProgress) &&
                DugunTakip.webView.isLoading &&
                !self.loadingView.isHidden &&
                !self.htmlIsLoaded) {
                    var progress = Float(DugunTakip.webView.estimatedProgress);
                    
                    if (progress >= 0.8) { progress = 1.0; };
                    if (progress >= 0.3) { self.animateConnectionProblem(false); }
                    
                    self.setProgress(progress, true);
        }
    }
    
    func setProgress(_ progress: Float, _ animated: Bool) {
        self.progressView.setProgress(progress, animated: animated);
    }
    
    
    func animateConnectionProblem(_ show: Bool) {
        if (show) {
            self.connectionProblemView.isHidden = false;
            self.connectionProblemView.alpha = 0
            UIView.animate(withDuration: 0.7, delay: 0, options: [.repeat, .autoreverse], animations: {
                self.connectionProblemView.alpha = 1
            })
        }
        else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [], animations: {
                self.connectionProblemView.alpha = 0 // Here you will get the animation you want
            }, completion: { _ in
                self.connectionProblemView.isHidden = true;
                self.connectionProblemView.layer.removeAllAnimations();
            })
        }
    }
        
    deinit {
        DugunTakip.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}

extension UIColor {
    // Check if the color is light or dark, as defined by the injected lightness threshold.
    // Some people report that 0.7 is best. I suggest to find out for yourself.
    // A nil value is returned if the lightness couldn't be determined.
    func isLight(threshold: Float = 0.5) -> Bool? {
        let originalCGColor = self.cgColor

        // Now we need to convert it to the RGB colorspace. UIColor.white / UIColor.black are greyscale and not RGB.
        // If you don't do this then you will crash when accessing components index 2 below when evaluating greyscale colors.
        let RGBCGColor = originalCGColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        guard let components = RGBCGColor?.components else {
            return nil
        }
        guard components.count >= 3 else {
            return nil
        }

        let brightness = Float(((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000)
        return (brightness > threshold)
    }
}

extension ViewController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "print" {
            printView(webView: DugunTakip.webView)
        }
        if message.name == "push-subscribe" {
            handleSubscribeTouch(message: message)
        }
        if message.name == "push-permission-request" {
            handlePushPermission()
        }
        if message.name == "push-permission-state" {
            handlePushState()
        }
        if message.name == "push-token" {
            handleFCMToken()
        }
        if message.name == "alkomutSpeech" {
            handleAlkomutSpeech(message)
        }
        if message.name == "iap" {
            handleIAP(message)
        }
  }
}

// ===== Native speech recognition (SFSpeechRecognizer) =====
// iOS WKWebView does not support the Web Speech API, so speech-to-text is
// handled by the device engine; the resulting text is passed to the web layer.
private let alkomutRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
private var alkomutAudioEngine: AVAudioEngine?
private var alkomutRequest: SFSpeechAudioBufferRecognitionRequest?
private var alkomutTask: SFSpeechRecognitionTask?

extension ViewController {
    func handleAlkomutSpeech(_ message: WKScriptMessage) {
        let action = ((message.body as? [String: Any])?["action"] as? String) ?? (message.body as? String) ?? ""
        if action == "start" { startNativeSpeech() }
        else if action == "stop" { stopNativeSpeech() }
    }

    func startNativeSpeech() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.sendSpeechToJS("", true, "izin-yok"); return }
                self.beginAlkomutRecognition()
            }
        }
    }

    func beginAlkomutRecognition() {
        alkomutTask?.cancel(); alkomutTask = nil
        let engine = AVAudioEngine()
        alkomutAudioEngine = engine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        alkomutRequest = request

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            sendSpeechToJS("", true, "ses-oturumu"); return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { sendSpeechToJS("", true, "motor"); return }

        alkomutTask = alkomutRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                self.sendSpeechToJS(result.bestTranscription.formattedString, result.isFinal, nil)
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopNativeSpeech()
            }
        }
    }

    func stopNativeSpeech() {
        alkomutAudioEngine?.stop()
        alkomutAudioEngine?.inputNode.removeTap(onBus: 0)
        alkomutRequest?.endAudio()
        alkomutAudioEngine = nil
        alkomutRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func sendSpeechToJS(_ text: String, _ isFinal: Bool, _ error: String?) {
        let jsonText = (try? JSONSerialization.data(withJSONObject: [text]))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let errJs = error.map { "'\($0)'" } ?? "null"
        let js = "window.alkomutNativeResult && window.alkomutNativeResult(\(jsonText), \(isFinal ? "true" : "false"), \(errJs));"
        DispatchQueue.main.async {
            DugunTakip.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// ===== In-App Purchase (StoreKit 2) =====
extension ViewController {
    func handleIAP(_ message: WKScriptMessage) {
        guard #available(iOS 15.0, *) else {
            DugunTakip.webView?.evaluateJavaScript(
                "window.genixIAPResult && window.genixIAPResult({event:'error',ok:false,error:'ios15-gerekli'});",
                completionHandler: nil)
            return
        }
        let body = message.body as? [String: Any] ?? [:]
        let action = (body["action"] as? String) ?? ""
        let productId = (body["productId"] as? String) ?? "com.genixsoft.dugun.pro.yearly"
        switch action {
        case "products": GenixIAP.shared.products([productId])
        case "purchase": GenixIAP.shared.purchase(productId)
        case "restore":  GenixIAP.shared.restore()
        case "status":   GenixIAP.shared.status()
        default: break
        }
    }
}

@available(iOS 15.0, *)
final class GenixIAP {
    static let shared = GenixIAP()
    private var updatesTask: Task<Void, Never>? = nil
    private let iso = ISO8601DateFormatter()

    private func emit(_ event: String, _ payload: [String: Any]) {
        var data = payload
        data["event"] = event
        let json = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.genixIAPResult && window.genixIAPResult(\(json));"
        DispatchQueue.main.async {
            DugunTakip.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func startObserving() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self?.handleVerified(transaction, source: "update")
                    await transaction.finish()
                }
            }
        }
    }

    private func handleVerified(_ t: Transaction, source: String) async {
        emit("purchase", [
            "ok": true,
            "productId": t.productID,
            "transactionId": String(t.id),
            "originalTransactionId": String(t.originalID),
            "purchaseDate": iso.string(from: t.purchaseDate),
            "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? "",
            "source": source
        ])
    }

    func products(_ ids: [String]) {
        Task {
            do {
                let products = try await Product.products(for: ids)
                let list = products.map { p -> [String: Any] in
                    ["productId": p.id, "displayName": p.displayName, "description": p.description, "displayPrice": p.displayPrice]
                }
                emit("products", ["ok": true, "products": list])
            } catch {
                emit("products", ["ok": false, "error": "\(error)"])
            }
        }
    }

    func purchase(_ productId: String) {
        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    emit("purchase", ["ok": false, "error": "urun-bulunamadi", "productId": productId]); return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await handleVerified(transaction, source: "purchase")
                        await transaction.finish()
                    case .unverified(_, let err):
                        emit("purchase", ["ok": false, "error": "dogrulanamadi: \(err)", "productId": productId])
                    }
                case .userCancelled:
                    emit("purchase", ["ok": false, "cancelled": true, "productId": productId])
                case .pending:
                    emit("purchase", ["ok": false, "pending": true, "productId": productId])
                @unknown default:
                    emit("purchase", ["ok": false, "error": "bilinmeyen", "productId": productId])
                }
            } catch {
                emit("purchase", ["ok": false, "error": "\(error)", "productId": productId])
            }
        }
    }

    func restore() {
        Task {
            try? await AppStore.sync()
            var found: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result {
                    found.append(["productId": t.productID, "transactionId": String(t.id), "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? ""])
                }
            }
            emit("restore", ["ok": true, "entitlements": found])
        }
    }

    func status() {
        Task {
            var active: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result {
                    active.append(["productId": t.productID, "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? ""])
                }
            }
            emit("status", ["ok": true, "active": active, "isActive": !active.isEmpty])
        }
    }
}