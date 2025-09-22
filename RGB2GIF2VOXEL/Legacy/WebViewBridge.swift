import WebKit
import Foundation
import Combine

// Shared types for quantization
struct LinearRGBBuffer {
    let data: Data
    let width: Int
    let height: Int
}

struct QuantizationResult {
    let palette: [UInt32]
    let indices: Data
}

struct NeuralPriors: Codable {
    let colorBias: [Float]
    let spatialWeights: [Float]
    let temporalHints: [Float]?
}

@MainActor
class WebViewBridge: NSObject, ObservableObject {
    let webView: WKWebView
    private var quantizationContinuation: CheckedContinuation<QuantizationResult, Error>?

    override init() {
        // Configure WKWebView with message handlers
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()

        // Enable SharedArrayBuffer if available (iOS 15.2+)
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // Set up process pool for isolation
        configuration.processPool = WKProcessPool()

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        // Add message handlers
        configuration.userContentController.add(self, name: "quantizationResult")
        configuration.userContentController.add(self, name: "wasmReady")
        configuration.userContentController.add(self, name: "wasmError")
        configuration.userContentController.add(self, name: "debugLog")

        // Configure WebView settings
        if #available(iOS 16.4, *) {
            webView.isInspectable = true // For debugging in Safari
        }
    }

    func loadWASMModules() async {
        // Load the HTML that contains WASI shim and Haskell WASM modules
        let htmlString = generateWASMHTML()

        await withCheckedContinuation { continuation in
            webView.loadHTMLString(htmlString, baseURL: Bundle.main.resourceURL)
            // Wait for WASM to be ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }
    }

    func quantizePalette(linearRGB: LinearRGBBuffer, priors: NeuralPriors, seed: UInt32) async throws -> QuantizationResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.quantizationContinuation = continuation

            // Prepare data for WASM
            let rgbData = linearRGB.data.base64EncodedString()
            let priorsJSON = try? JSONEncoder().encode(priors)
            let priorsString = priorsJSON?.base64EncodedString() ?? ""

            // Call WASM quantization function
            let jsCode = """
            (async function() {
                try {
                    const rgbData = Uint8Array.from(atob('\(rgbData)'), c => c.charCodeAt(0));
                    const priorsData = Uint8Array.from(atob('\(priorsString)'), c => c.charCodeAt(0));

                    // Call the Haskell WASM quantizer
                    const result = await window.wasmQuantizer.quantizePalette({
                        width: \(linearRGB.width),
                        height: \(linearRGB.height),
                        rgbData: rgbData,
                        priors: priorsData,
                        seed: \(seed),
                        algorithm: 'wu' // or 'neuquant' or 'octree'
                    });

                    // Send result back to Swift
                    window.webkit.messageHandlers.quantizationResult.postMessage({
                        palette: Array.from(result.palette),
                        indices: btoa(String.fromCharCode(...result.indices))
                    });
                } catch (error) {
                    window.webkit.messageHandlers.wasmError.postMessage({
                        error: error.toString()
                    });
                }
            })();
            """

            webView.evaluateJavaScript(jsCode) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func generateWASMHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>YinGif WASM Processor</title>
        </head>
        <body>
            <script type="module">
                // Browser WASI shim - single instance for all modules
                import { WASI, File, OpenFile, PreopenDirectory } from '@bjorn3/browser_wasi_shim';

                // Debug logging
                window.debugLog = (msg) => {
                    window.webkit.messageHandlers.debugLog.postMessage({ message: msg });
                };

                // Initialize WASI with minimal permissions (stdio/memory only)
                const args = [];
                const env = [];
                const fds = [
                    new OpenFile(new File([])), // stdin
                    new OpenFile(new File([])), // stdout
                    new OpenFile(new File([])), // stderr
                ];

                const wasi = new WASI(args, env, fds);

                // Load Haskell WASM modules
                async function loadWasmModule(name, wasmPath) {
                    try {
                        const response = await fetch(wasmPath);
                        const wasmBinary = await response.arrayBuffer();

                        // Instantiate with WASI imports
                        const { instance } = await WebAssembly.instantiate(wasmBinary, {
                            wasi_snapshot_preview1: wasi.wasiImport,
                        });

                        // Initialize WASI
                        wasi.initialize(instance);

                        return instance.exports;
                    } catch (error) {
                        debugLog(`Failed to load ${name}: ${error}`);
                        throw error;
                    }
                }

                // Load quantizer modules
                async function initializeQuantizers() {
                    const modules = await Promise.all([
                        loadWasmModule('wu', 'wu_quantizer.wasm'),
                        loadWasmModule('neuquant', 'neuquant.wasm'),
                        loadWasmModule('octree', 'octree_quantizer.wasm'),
                    ]);

                    return {
                        wu: modules[0],
                        neuquant: modules[1],
                        octree: modules[2],
                    };
                }

                // Main quantization interface
                window.wasmQuantizer = {
                    modules: null,

                    async init() {
                        this.modules = await initializeQuantizers();
                        window.webkit.messageHandlers.wasmReady.postMessage({ ready: true });
                    },

                    async quantizePalette(params) {
                        const { width, height, rgbData, priors, seed, algorithm } = params;

                        if (!this.modules || !this.modules[algorithm]) {
                            throw new Error(`Algorithm ${algorithm} not available`);
                        }

                        const module = this.modules[algorithm];

                        // Allocate memory for input/output
                        const inputPtr = module.malloc(rgbData.length);
                        const outputPalettePtr = module.malloc(256 * 3); // 256 colors * RGB
                        const outputIndicesPtr = module.malloc(width * height);

                        try {
                            // Copy input data to WASM memory
                            const memory = new Uint8Array(module.memory.buffer);
                            memory.set(rgbData, inputPtr);

                            // Call the quantization function
                            const result = module.quantize(
                                inputPtr,
                                width,
                                height,
                                outputPalettePtr,
                                outputIndicesPtr,
                                seed
                            );

                            if (result !== 0) {
                                throw new Error(`Quantization failed with code ${result}`);
                            }

                            // Read results from WASM memory
                            const palette = new Uint32Array(256);
                            const paletteBytes = new Uint8Array(module.memory.buffer, outputPalettePtr, 256 * 3);

                            for (let i = 0; i < 256; i++) {
                                const r = paletteBytes[i * 3];
                                const g = paletteBytes[i * 3 + 1];
                                const b = paletteBytes[i * 3 + 2];
                                palette[i] = (r << 16) | (g << 8) | b | 0xFF000000;
                            }

                            const indices = new Uint8Array(
                                module.memory.buffer,
                                outputIndicesPtr,
                                width * height
                            ).slice(); // Copy to avoid memory issues

                            return { palette, indices };

                        } finally {
                            // Clean up allocated memory
                            module.free(inputPtr);
                            module.free(outputPalettePtr);
                            module.free(outputIndicesPtr);
                        }
                    }
                };

                // Initialize on load
                window.wasmQuantizer.init().catch(error => {
                    debugLog(`Initialization failed: ${error}`);
                });

                // WebGL preview context for testing
                const canvas = document.createElement('canvas');
                canvas.width = 512;
                canvas.height = 512;
                canvas.style.display = 'none';
                document.body.appendChild(canvas);

                const gl = canvas.getContext('webgl2', {
                    antialias: false,
                    depth: false,
                    stencil: false,
                    alpha: true,
                    premultipliedAlpha: false,
                });

                window.glContext = gl;
                window.previewCanvas = canvas;

                debugLog('WebView WASM bridge initialized');
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - WKScriptMessageHandler
extension WebViewBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "quantizationResult":
            handleQuantizationResult(message.body)

        case "wasmReady":
            print("WASM modules loaded and ready")

        case "wasmError":
            handleWASMError(message.body)

        case "debugLog":
            if let body = message.body as? [String: Any],
               let msg = body["message"] as? String {
                print("[WASM Debug]: \(msg)")
            }

        default:
            break
        }
    }

    private func handleQuantizationResult(_ body: Any) {
        guard let data = body as? [String: Any],
              let paletteArray = data["palette"] as? [Int],
              let indicesBase64 = data["indices"] as? String,
              let indicesData = Data(base64Encoded: indicesBase64) else {
            quantizationContinuation?.resume(throwing: BridgeError.invalidResult)
            quantizationContinuation = nil
            return
        }

        let palette = paletteArray.map { UInt32($0) }
        let result = QuantizationResult(palette: palette, indices: indicesData)

        quantizationContinuation?.resume(returning: result)
        quantizationContinuation = nil
    }

    private func handleWASMError(_ body: Any) {
        guard let data = body as? [String: Any],
              let errorMsg = data["error"] as? String else {
            quantizationContinuation?.resume(throwing: BridgeError.unknownError)
            quantizationContinuation = nil
            return
        }

        quantizationContinuation?.resume(throwing: BridgeError.wasmError(errorMsg))
        quantizationContinuation = nil
    }
}

enum BridgeError: Error {
    case invalidResult
    case unknownError
    case wasmError(String)
}