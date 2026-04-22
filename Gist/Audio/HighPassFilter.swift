import Accelerate

/// 80Hz high-pass filter using vDSP biquad.
/// Removes low-frequency rumble from audio.
struct HighPassFilter {
    private var coefficients: [Double] = []
    private var delays: [Double] = []

    // Pre-allocated working buffers — resized only when sample count grows
    private var _doubleBuf: [Double] = []
    private var _outputBuf: [Double] = []

    init(cutoffHz: Double = 80.0, sampleRate: Double = 48000.0) {
        // Compute biquad coefficients for a 2nd-order Butterworth high-pass
        let w0 = 2.0 * Double.pi * cutoffHz / sampleRate
        let alpha = sin(w0) / (2.0 * sqrt(2.0)) // Q = sqrt(2)/2 for Butterworth

        let b0 = (1.0 + cos(w0)) / 2.0
        let b1 = -(1.0 + cos(w0))
        let b2 = (1.0 + cos(w0)) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cos(w0)
        let a2 = 1.0 - alpha

        // Normalize by a0
        coefficients = [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
        delays = [Double](repeating: 0, count: 4) // 2 sections * 2 delays
    }

    /// Apply high-pass filter to audio samples in-place.
    mutating func apply(to samples: inout [Float]) {
        guard !samples.isEmpty, coefficients.count == 5 else { return }

        let n = samples.count
        let count = vDSP_Length(n)

        // Resize working buffers only when needed (no per-call allocation)
        if _doubleBuf.count < n {
            _doubleBuf = [Double](repeating: 0, count: n)
            _outputBuf = [Double](repeating: 0, count: n)
        }

        // Float → Double using vDSP (no .map allocation)
        vDSP_vspdp(samples, 1, &_doubleBuf, 1, count)

        vDSP_deq22D(&_doubleBuf, 1, &coefficients, &_outputBuf, 1, count - 2)

        // Double → Float using vDSP (no .map allocation)
        vDSP_vdpsp(_outputBuf, 1, &samples, 1, count)
    }
}
