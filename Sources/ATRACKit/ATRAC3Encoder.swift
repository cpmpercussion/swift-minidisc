import CATRAC3
import Foundation

public enum ATRAC3Error: Error, CustomStringConvertible {
    case unsupportedMode(kbps: Int, channels: Int)
    case codec(String)

    public var description: String {
        switch self {
        case let .unsupportedMode(kbps, channels): "unsupported ATRAC3 mode: \(kbps) kbps, \(channels) channels"
        case let .codec(message): message
        }
    }
}

/// MiniDisc long-play modes. Both take stereo 44.1 kHz input.
public enum MiniDiscLPMode: Sendable {
    case lp2, lp4

    public var kbps: Int { self == .lp2 ? 132 : 66 }
}

/// Streaming ATRAC3 encoder. Feed interleaved 16-bit PCM in blocks of any size; the output is
/// raw ATRAC3 frames (no header). Encoding consecutive tracks with one encoder is gapless.
public final class ATRAC3Encoder {
    private let encoder: OpaquePointer
    public let channels: Int

    public init(kbps: Int, channels: Int) throws {
        guard let encoder = at3_encoder_create(Int32(kbps), Int32(channels)) else {
            throw ATRAC3Error.unsupportedMode(kbps: kbps, channels: channels)
        }
        self.encoder = encoder
        self.channels = channels
    }

    public convenience init(mode: MiniDiscLPMode) throws {
        try self.init(kbps: mode.kbps, channels: 2)
    }

    deinit { at3_encoder_destroy(encoder) }

    public var frameBytes: Int { Int(at3_encoder_frame_bytes(encoder)) }
    public var isJointStereo: Bool { at3_encoder_joint_stereo(encoder) != 0 }

    /// Encodes `pcm` (interleaved, `channels` samples per frame) and returns the whole frames
    /// that are ready. The encoder keeps some look-ahead, which `finish()` flushes.
    public func write(_ pcm: UnsafeBufferPointer<Int16>) -> Data {
        let samples = pcm.count / channels
        var out = Data(count: at3_encoder_max_output(encoder, samples))
        let n = out.withUnsafeMutableBytes { buf in
            at3_encoder_write(encoder, pcm.baseAddress, samples, buf.bindMemory(to: UInt8.self).baseAddress)
        }
        return out.prefix(n)
    }

    public func write(_ pcm: [Int16]) -> Data {
        pcm.withUnsafeBufferPointer { write($0) }
    }

    /// Ends the stream and returns the remaining frames.
    public func finish() -> Data {
        var out = Data(count: 4 * frameBytes)
        let n = out.withUnsafeMutableBytes { buf in
            at3_encoder_finish(encoder, buf.bindMemory(to: UInt8.self).baseAddress)
        }
        return out.prefix(n)
    }

    /// The 80-byte .at3 (RIFF/WAVE) header at3tool writes in front of the frames.
    public func at3Header(totalSamples: Int, dataBytes: Int) -> Data {
        var header = Data(count: Int(AT3_HEADER_BYTES))
        header.withUnsafeMutableBytes { buf in
            at3_write_header(buf.bindMemory(to: UInt8.self).baseAddress, Int32(channels), Int32(frameBytes),
                             isJointStereo ? 1 : 0, UInt32(totalSamples), UInt32(dataBytes))
        }
        return header
    }
}

/// Whole-file conversions, as the upstream command-line tool does them.
public enum ATRAC3File {
    /// Encodes a 16-bit 44.1 kHz WAV file image to an .at3 file image. `kbps` 0 picks the default.
    public static func encode(wav: Data, kbps: Int = 0) throws -> Data {
        try convert(wav) { bytes, len, out, outLen in at3_encode_wav(bytes, len, Int32(kbps), out, outLen, nil) }
    }

    /// Decodes an .at3 file image to a 16-bit WAV file image.
    public static func decode(at3: Data) throws -> Data {
        try convert(at3) { bytes, len, out, outLen in at3_decode_at3(bytes, len, out, outLen) }
    }

    private static func convert(
        _ input: Data,
        _ body: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                 UnsafeMutablePointer<Int>) -> UnsafePointer<CChar>?
    ) throws -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let err = input.withUnsafeBytes { body($0.bindMemory(to: UInt8.self).baseAddress, input.count, &out, &outLen) }
        if let err { throw ATRAC3Error.codec(String(cString: err)) }
        defer { at3_free(out) }
        return Data(bytes: out!, count: outLen)
    }
}
