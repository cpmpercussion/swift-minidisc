import Foundation

/// What each MiniDisc mode sends over NetMD.
public enum MiniDiscEncoding {
    /// Encodes files back to back through one encoder, so the joins are gapless. Each track's
    /// frames stop 50-73 ms short of its audio (encoder look-ahead), so marks land that early.
    public static func gaplessLP(_ urls: [URL], mode: MiniDiscLPMode) throws -> [Data] {
        let encoder = try ATRAC3Encoder(mode: mode)
        return try urls.enumerated().map { n, url in
            var frames = encoder.write(try AudioFileDecoder.decode(url: url))
            if n == urls.count - 1 { frames += encoder.finish() }
            return frames
        }
    }

    /// SP: 16-bit big-endian stereo PCM, which the unit encodes itself.
    public static func spPCM(_ url: URL) throws -> Data {
        try AudioFileDecoder.decode(url: url).map(\.bigEndian).withUnsafeBytes { Data($0) }
    }
}
