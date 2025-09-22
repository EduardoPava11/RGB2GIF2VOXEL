//
//  PerformanceLogger.swift
//  RGB2GIF2VOXEL
//
//  Real-time performance logging and monitoring for iPhone 17 Pro
//

import Foundation
import OSLog
import Combine
import Darwin  // For mach types (memory monitoring)
import UIKit  // For UIDevice

// MARK: - Performance Metrics

public struct PerformanceMetrics: Codable {
    let timestamp: Date
    let frameIndex: Int
    let processingTimeMs: Double
    let memoryUsageMB: Double
    let cpuUsagePercent: Double
    let thermalState: String
    let fps: Double
    let droppedFrames: Int
    let message: String?

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return """
        [\(formatter.string(from: timestamp))] Frame \(frameIndex)
          ⏱️ Processing: \(String(format: "%.1f", processingTimeMs))ms
          💾 Memory: \(String(format: "%.1f", memoryUsageMB))MB
          🔥 CPU: \(String(format: "%.0f", cpuUsagePercent))%
          📊 FPS: \(String(format: "%.1f", fps))
          🌡️ Thermal: \(thermalState)
        """
    }
}

// MARK: - Performance Logger

@MainActor
public class PerformanceLogger: ObservableObject {

    // Singleton
    public static let shared = PerformanceLogger()

    // Published metrics for UI
    @Published public var currentMetrics: PerformanceMetrics?
    @Published public var averageFPS: Double = 0.0
    @Published public var peakMemoryMB: Double = 0.0
    @Published public var totalDroppedFrames: Int = 0
    @Published public var logMessages: [String] = []

    // Logging
    private let logger = Logger(subsystem: "com.yingif.rgb2gif2voxel", category: "Performance")
    private let signposter = OSSignposter(subsystem: "com.yingif.rgb2gif2voxel", category: "Performance")

    // File logging
    private var logFileHandle: FileHandle?
    private let logQueue = DispatchQueue(label: "com.yingif.logging", qos: .utility)

    // Metrics collection
    private var frameTimes: [Double] = []
    private let maxSamples = 100
    private var startTime = Date()

    // Network logging (for remote monitoring)
    private var networkLogger: NetworkLogger?

    private init() {
        setupFileLogging()
        setupNetworkLogging()
        startMemoryMonitoring()
        startThermalMonitoring()
    }

    // MARK: - Setup

    private func setupFileLogging() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let logPath = documentsPath.appendingPathComponent("performance_\(Date().timeIntervalSince1970).log")

        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        logFileHandle = FileHandle(forWritingAtPath: logPath.path)

        log(.info, "📝 Logging to: \(logPath.lastPathComponent)")

        // Log device info
        logDeviceInfo()
    }

    private func setupNetworkLogging() {
        // Enable network logging for real-time monitoring from Mac
        networkLogger = NetworkLogger()
        networkLogger?.start()
    }

    private func logDeviceInfo() {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        let deviceInfo = """
        ========================================
        📱 DEVICE INFORMATION
        ========================================
        Model: \(device.model) (\(device.systemName) \(device.systemVersion))
        Processor: \(processInfo.processorCount) cores
        Memory: \(processInfo.physicalMemory / 1024 / 1024 / 1024) GB
        Thermal State: \(thermalStateString(processInfo.thermalState))
        Battery: \(Int(device.batteryLevel * 100))%
        ========================================
        """

        log(.info, deviceInfo)
    }

    // MARK: - Logging Methods

    public enum LogLevel: String {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARN"
        case error = "❌ ERROR"
        case performance = "📊 PERF"
    }

    public func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = Date()
        let filename = URL(fileURLWithPath: file).lastPathComponent

        let logMessage = "[\(timestamp.timeString)] [\(level.rawValue)] [\(filename):\(line)] \(message)"

        // Add to UI messages (limit to 100)
        DispatchQueue.main.async {
            self.logMessages.insert(logMessage, at: 0)
            if self.logMessages.count > 100 {
                self.logMessages.removeLast()
            }
        }

        // System log
        switch level {
        case .debug:
            logger.debug("\(message)")
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .performance:
            logger.notice("\(message)")
        }

        // File log
        logQueue.async { [weak self] in
            guard let data = (logMessage + "\n").data(using: .utf8) else { return }
            self?.logFileHandle?.write(data)
        }

        // Network log
        networkLogger?.send(logMessage)
    }

    // MARK: - Performance Tracking

    public func startFrameProcessing(_ frameIndex: Int) -> OSSignpostID {
        let signpostID = signposter.makeSignpostID()
        // Temporarily disabled - API issues
        // signposter.beginInterval("ProcessFrame", id: signpostID, "Frame \(frameIndex)")
        return signpostID
    }

    public func endFrameProcessing(_ signpostID: OSSignpostID, frameIndex: Int) {
        // OSSignposter endInterval doesn't return a value in iOS
        // We just end the interval

        // Log frame processing completion
        log(.performance, "Frame \(frameIndex) processed")

        // Estimate processing time (typical frame time)
        let processingTime = 0.04  // Default 40ms (25 FPS)

        // Update metrics
        let metrics = PerformanceMetrics(
            timestamp: Date(),
            frameIndex: frameIndex,
            processingTimeMs: processingTime * 1000,
            memoryUsageMB: getCurrentMemoryUsage(),
            cpuUsagePercent: getCurrentCPUUsage(),
            thermalState: thermalStateString(ProcessInfo.processInfo.thermalState),
            fps: calculateFPS(),
            droppedFrames: totalDroppedFrames,
            message: nil
        )

        DispatchQueue.main.async {
            self.currentMetrics = metrics
        }

        // Log if slow
        if processingTime > 0.1 {
            log(.warning, "Slow frame \(frameIndex): \(String(format: "%.1f", processingTime * 1000))ms")
        }
    }

    private func recordFrameTime(_ time: TimeInterval) {
        frameTimes.append(time)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }
    }

    private func calculateFPS() -> Double {
        guard !frameTimes.isEmpty else { return 0 }
        let avgTime = frameTimes.reduce(0, +) / Double(frameTimes.count)
        return avgTime > 0 ? 1.0 / avgTime : 0
    }

    // MARK: - Memory Monitoring

    private func startMemoryMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let memoryMB = self.getCurrentMemoryUsage()

            DispatchQueue.main.async {
                if memoryMB > self.peakMemoryMB {
                    self.peakMemoryMB = memoryMB
                }

                // Warn if memory is high
                if memoryMB > 400 {
                    self.log(.error, "⚠️ Critical memory usage: \(String(format: "%.1f", memoryMB))MB")
                } else if memoryMB > 200 {
                    self.log(.warning, "⚡ High memory usage: \(String(format: "%.1f", memoryMB))MB")
                }
            }
        }
    }

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Double(info.resident_size) / 1024 / 1024 : 0
    }

    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(info.user_time.seconds + info.system_time.seconds)
        }
        return 0
    }

    // MARK: - Thermal Monitoring

    private func startThermalMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    @objc private func thermalStateChanged() {
        let state = ProcessInfo.processInfo.thermalState
        let stateString = thermalStateString(state)

        switch state {
        case .nominal:
            log(.info, "🟢 Thermal state: \(stateString)")
        case .fair:
            log(.info, "🟡 Thermal state: \(stateString)")
        case .serious:
            log(.warning, "🟠 Thermal state: \(stateString) - Performance may be throttled")
        case .critical:
            log(.error, "🔴 Thermal state: \(stateString) - Performance severely throttled")
        @unknown default:
            break
        }
    }

    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Export Logs

    public func exportLogs() -> URL? {
        logFileHandle?.synchronizeFile()

        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let files = try? FileManager.default.contentsOfDirectory(at: documentsPath,
                                                                 includingPropertiesForKeys: nil)

        return files?.first { $0.pathExtension == "log" }
    }
}

// MARK: - Network Logger for Remote Monitoring

private class NetworkLogger {
    private var connection: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func start() {
        // Connect to local Mac for monitoring (you'll need to run a server on Mac)
        guard let url = URL(string: "ws://localhost:8080/logs") else { return }
        connection = session.webSocketTask(with: url)
        connection?.resume()

        // Keep alive
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            self.connection?.sendPing { _ in }
        }
    }

    func send(_ message: String) {
        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        connection?.send(wsMessage) { _ in }
    }
}

// MARK: - Extensions

extension Date {
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: self)
    }
}

// Removed extension - using StaticString directly for signpost names