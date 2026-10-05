import Foundation

/// How the volume slider's position maps to output gain.
///
/// `Preferences.gain` is the gain (0–100, a linear amplitude multiplier). The
/// slider shows the *position*, and this curve converts between the two:
/// `gain = position^exponent` on 0…1. Loudness is heard in dB, so a linear
/// slider crams every quiet level into its first few percent; a perceptual one
/// spreads them out.
struct VolumeCurve: Equatable {
    enum Kind: String, CaseIterable {
        case linear, perceptual
    }

    static let gainRange: ClosedRange<Double> = 0...100
    static let sliderRange: ClosedRange<Double> = 0...100
    static let exponentRange: ClosedRange<Double> = 2...5
    static let defaultExponent = 3.0

    var kind: Kind
    var exponent: Double

    /// The same curve with its exponent brought inside `exponentRange`.
    var clamped: VolumeCurve {
        VolumeCurve(kind: kind, exponent: Self.exponentRange.clamp(exponent))
    }

    /// The exponent actually applied: 1 for linear.
    var effectiveExponent: Double { kind == .linear ? 1 : exponent }

    /// Gain (0–100) for a slider position (0–100).
    func gain(forSlider slider: Double) -> Double {
        let p = Self.sliderRange.clamp(slider) / 100
        return pow(p, effectiveExponent) * 100
    }

    /// Slider position (0–100) for a gain (0–100).
    func slider(forGain gain: Double) -> Double {
        let g = Self.gainRange.clamp(gain) / 100
        return pow(g, 1 / effectiveExponent) * 100
    }

    /// Loudness in dB (floored at `floor`) for a slider position (0–100).
    func decibels(forSlider slider: Double, floor: Double = -60) -> Double {
        let g = gain(forSlider: slider) / 100
        guard g > 0 else { return floor }
        return max(floor, 20 * log10(g))
    }
}

extension ClosedRange {
    func clamp(_ value: Bound) -> Bound {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}
