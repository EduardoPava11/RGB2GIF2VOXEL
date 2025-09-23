import Foundation

/// Policy for pyramid downsampling and N×N×N cube tensor capture
public struct CubePolicy {

    /// Available cube sizes for N×N×N tensor capture
    public static let availableLevels = [528, 264, 256, 132, 128]

    /// Default recommended level (128³ for reduced footprint/performance headroom)
    public static let defaultLevel = 128

    /// Maximum frames we can capture (largest cube)
    public static let maxFrames = 528

    /// Default palette size for high-quality captures
    public static let defaultPaletteSize = 256

    /// Choose the best pyramid level given a max budget
    /// - Parameter maxBudget: Maximum frames we can handle (N³ memory constraint)
    /// - Returns: Largest N that satisfies N³ ≤ maxBudget
    public static func chooseLevel(maxBudget: Int) -> Int {
        // For each level, compute N³ memory requirement
        for level in availableLevels {
            let memoryNeeded = level * level * level
            if memoryNeeded <= maxBudget {
                return level
            }
        }
        return 128 // Fallback to smallest available in our set
    }

    /// Get a user-friendly label for a pyramid level
    public static func labelForLevel(_ level: Int) -> String {
        switch level {
        case 528:
            return "528³ (147MB)"
        case 264:
            return "264³ (18MB)"
        case 256:
            return "256³ (17MB) • HD Quality"
        case 132:
            return "132³ (2.3MB)"
        case 128:
            return "128³ (2.1MB) • Optimal"
        default:
            return "\(level)³"
        }
    }

    /// Memory requirement in bytes for N×N×N tensor
    public static func memoryRequirement(for level: Int) -> Int {
        return level * level * level // Each pixel is 1 byte (palette index)
    }
}
