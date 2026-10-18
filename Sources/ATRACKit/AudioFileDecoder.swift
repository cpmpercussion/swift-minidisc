import AVFoundation

/// Decodes any file Core Audio can read to interleaved 16-bit stereo PCM at 44.1 kHz,
/// the input every MiniDisc mode takes.
public enum AudioFileDecoder {
    public static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true)!

    public static func decode(url: URL) throws -> [Int16] {
        let file = try AVAudioFile(forReading: url)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw ATRAC3Error.codec("cannot convert from \(file.processingFormat)")
        }
        // Dither when reducing 24-bit (or float) sources to 16-bit, rather than truncating.
        // 16-bit sources pass through unchanged.
        converter.dither = !isSixteenBit(file.fileFormat.streamDescription.pointee)
        let chunk: AVAudioFrameCount = 32_768
        let ratio = outputFormat.sampleRate / file.processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(chunk) * ratio) + 1024
        var samples: [Int16] = []
        samples.reserveCapacity(Int(Double(file.length) * ratio) * 2)
        var readError: Error?
        var reachedEnd = false

        while true {
            let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity)!
            var convertError: NSError?
            let status = converter.convert(to: out, error: &convertError) { _, inputStatus in
                // AVAudioFile throws rather than returning an empty buffer at the end of the file.
                if reachedEnd || file.framePosition >= file.length {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
                do {
                    try file.read(into: input)
                } catch {
                    readError = error
                }
                if input.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let error = readError ?? convertError { throw error }
            let data = out.int16ChannelData![0]
            samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(out.frameLength) * 2))
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }

    private static func isSixteenBit(_ asbd: AudioStreamBasicDescription) -> Bool {
        switch asbd.mFormatID {
        case kAudioFormatLinearPCM:
            return asbd.mFormatFlags & kAudioFormatFlagIsFloat == 0 && asbd.mBitsPerChannel <= 16
        case kAudioFormatAppleLossless:
            return asbd.mFormatFlags == kAppleLosslessFormatFlag_16BitSourceData
        case kAudioFormatFLAC:
            return asbd.mFormatFlags == kAppleLosslessFormatFlag_16BitSourceData
        default:
            return false  // lossy codecs decode to float
        }
    }
}
