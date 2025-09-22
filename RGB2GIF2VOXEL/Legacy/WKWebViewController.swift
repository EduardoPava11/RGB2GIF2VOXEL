import UIKit
import WebKit

/// WebView controller for hosting WASM plugins (Haskell wasm32-wasi)
/// Replaces Android WebView with iOS WKWebView
class WKWebViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private let messageHandler = "yingifBridge"

    // MARK: - Lifecycle

    override func loadView() {
        // Configure WebView with message handler
        let config = WKWebViewConfiguration()

        // Enable JavaScript
        config.preferences.javaScriptEnabled = true

        // Add message handler for native bridge
        config.userContentController.add(self, name: messageHandler)

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true

        // Create WebView
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self

        // Enable debugging in Safari (dev only)
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "WASM Plugins"
        setupNavigationBar()
        loadLocalContent()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshTapped)
        )
    }

    // MARK: - Content Loading

    /// Load local HTML/JS/WASM assets from bundle
    private func loadLocalContent() {
        // Check for www folder in bundle
        guard let wwwPath = Bundle.main.path(forResource: "www", ofType: nil),
              let indexPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "www") else {
            loadFallbackContent()
            return
        }

        let wwwURL = URL(fileURLWithPath: wwwPath)
        let indexURL = URL(fileURLWithPath: indexPath)

        // Load local files with file access permission
        webView.loadFileURL(indexURL, allowingReadAccessTo: wwwURL)
    }

    /// Fallback content when www folder doesn't exist
    private func loadFallbackContent() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>YinGIF WASM Host</title>
            <style>
                body {
                    font-family: -apple-system, system-ui;
                    margin: 20px;
                    background: #f0f0f0;
                }
                .container {
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 20px;
                    background: white;
                    border-radius: 10px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                h1 { color: #333; }
                .button {
                    display: inline-block;
                    padding: 10px 20px;
                    background: #007AFF;
                    color: white;
                    border-radius: 8px;
                    text-decoration: none;
                    margin: 10px 5px;
                    cursor: pointer;
                    border: none;
                    font-size: 16px;
                }
                .status {
                    padding: 10px;
                    background: #f8f8f8;
                    border-radius: 5px;
                    margin: 10px 0;
                    font-family: monospace;
                }
                #output {
                    min-height: 100px;
                    padding: 10px;
                    background: #f0f0f0;
                    border-radius: 5px;
                    white-space: pre-wrap;
                    font-family: monospace;
                    font-size: 12px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🎯 YinGIF WASM Host</h1>
                <p>WebView ready for WASM plugins</p>

                <div class="status">
                    <strong>Status:</strong> <span id="status">Ready</span>
                </div>

                <button class="button" onclick="testBridge()">Test Native Bridge</button>
                <button class="button" onclick="loadWASM()">Load WASM Module</button>
                <button class="button" onclick="processData()">Process Test Data</button>

                <h3>Output:</h3>
                <div id="output"></div>
            </div>

            <script>
                // Native bridge interface
                const YinGIF = {
                    // Send message to native
                    sendToNative: function(action, data) {
                        window.webkit.messageHandlers.yingifBridge.postMessage({
                            action: action,
                            data: data
                        });
                    },

                    // Receive from native
                    receiveFromNative: function(data) {
                        console.log('Received from native:', data);
                        document.getElementById('output').textContent +=
                            'Received: ' + JSON.stringify(data) + '\\n';
                    },

                    // Process Uint8Array data
                    processBuffer: function(buffer) {
                        // Convert ArrayBuffer to Uint8Array
                        const uint8 = new Uint8Array(buffer);
                        console.log('Processing buffer of size:', uint8.length);
                        return uint8;
                    }
                };

                // Test functions
                function testBridge() {
                    YinGIF.sendToNative('test', { message: 'Hello from WebView!' });
                    document.getElementById('status').textContent = 'Bridge test sent';
                }

                function loadWASM() {
                    document.getElementById('status').textContent = 'Loading WASM...';
                    // Placeholder for actual WASM loading
                    fetch('plugin.wasm')
                        .then(response => response.arrayBuffer())
                        .then(bytes => WebAssembly.instantiate(bytes))
                        .then(results => {
                            document.getElementById('status').textContent = 'WASM loaded';
                            console.log('WASM module:', results.instance);
                        })
                        .catch(err => {
                            document.getElementById('status').textContent = 'WASM not found (expected)';
                            console.log('WASM load error:', err);
                        });
                }

                function processData() {
                    // Create test data
                    const testData = new Uint8Array([1, 2, 3, 4, 5]);
                    YinGIF.sendToNative('processData', Array.from(testData));
                    document.getElementById('status').textContent = 'Data sent for processing';
                }

                // Ready notification
                window.addEventListener('load', () => {
                    YinGIF.sendToNative('ready', {});
                });
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - JavaScript Bridge

    /// Send data to JavaScript
    func sendToJavaScript(data: [String: Any]) {
        let jsonData = try? JSONSerialization.data(withJSONObject: data)
        guard let jsonString = jsonData?.base64EncodedString() else { return }

        let js = """
        (function() {
            const dataStr = atob('\(jsonString)');
            const data = JSON.parse(dataStr);
            if (window.YinGIF && window.YinGIF.receiveFromNative) {
                window.YinGIF.receiveFromNative(data);
            }
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("JS evaluation error: \(error)")
            }
        }
    }

    /// Send binary data to JavaScript
    func sendBinaryToJavaScript(_ data: Data) {
        let base64 = data.base64EncodedString()

        let js = """
        (function() {
            const base64 = '\(base64)';
            const binaryStr = atob(base64);
            const len = binaryStr.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) {
                bytes[i] = binaryStr.charCodeAt(i);
            }
            if (window.YinGIF && window.YinGIF.processBuffer) {
                window.YinGIF.processBuffer(bytes.buffer);
            }
        })();
        """

        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func refreshTapped() {
        webView.reload()
    }
}

// MARK: - WKScriptMessageHandler

extension WKWebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {

        guard message.name == messageHandler,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        handleJavaScriptMessage(action: action, data: body["data"])
    }

    private func handleJavaScriptMessage(action: String, data: Any?) {
        switch action {
        case "ready":
            print("WebView ready")

        case "test":
            print("Test message received:", data ?? "")
            // Echo back
            sendToJavaScript(data: ["echo": data ?? ""])

        case "processData":
            if let array = data as? [Int] {
                let uint8Data = Data(array.map { UInt8($0) })
                processDataFromWASM(uint8Data)
            }

        case "requestImage":
            sendTestImageToWASM()

        case "saveResult":
            if let result = data as? [String: Any] {
                saveWASMResult(result)
            }

        default:
            print("Unknown action: \(action)")
        }
    }

    private func processDataFromWASM(_ data: Data) {
        // Process data received from WASM
        // Could send to Rust processing pipeline
        print("Processing \(data.count) bytes from WASM")

        // Send back processed result
        let result = data.map { $0 &+ 1 } // Simple transformation
        sendBinaryToJavaScript(Data(result))
    }

    private func sendTestImageToWASM() {
        // Load test image and send to WASM
        if let image = UIImage(named: "test_image"),
           let imageData = image.pngData() {
            sendBinaryToJavaScript(imageData)
        }
    }

    private func saveWASMResult(_ result: [String: Any]) {
        // Save processed result from WASM
        print("Saving WASM result:", result)
    }
}

// MARK: - WKNavigationDelegate

extension WKWebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView finished loading")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView failed to load: \(error)")
    }

    func webView(_ webView: WKWebView,
                decidePolicyFor navigationAction: WKNavigationAction,
                decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        // Allow local file URLs and data URLs
        if let url = navigationAction.request.url {
            if url.isFileURL || url.scheme == "data" {
                decisionHandler(.allow)
                return
            }
        }

        // Block external URLs for security
        decisionHandler(.cancel)
    }
}

// MARK: - WKUIDelegate

extension WKWebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                runJavaScriptAlertPanelWithMessage message: String,
                initiatedByFrame frame: WKFrameInfo,
                completionHandler: @escaping () -> Void) {

        let alert = UIAlertController(title: "WASM Plugin", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }
}