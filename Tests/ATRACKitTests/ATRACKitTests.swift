import ATRACKit
import Foundation
import Testing

/// Deterministic stereo test signal: a chirp on the left, LCG noise on the right.
func testSignal(frames: Int) -> [Int16] {
    var seed: UInt32 = 12345
    var pcm = [Int16](repeating: 0, count: frames * 2)
    for i in 0..<frames {
        let t = Double(i) / 44_100
        pcm[2 * i] = Int16(8000 * sin(2 * .pi * (200 + 2000 * t) * t))
        seed = seed &* 1_664_525 &+ 1_013_904_223
        pcm[2 * i + 1] = Int16(truncatingIfNeeded: Int32(bitPattern: seed) >> 20)
    }
    return pcm
}

func wavFile(_ pcm: [Int16]) -> Data {
    func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    let data = pcm.withUnsafeBytes { Data($0) }
    var wav = Data("RIFF".utf8) + le(UInt32(36 + data.count)) + Data("WAVEfmt ".utf8)
    wav += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(2)) + le(UInt32(44_100)) + le(UInt32(176_400))
    wav += le(UInt16(4)) + le(UInt16(16)) + Data("data".utf8) + le(UInt32(data.count)) + data
    return wav
}

@Test(arguments: [MiniDiscLPMode.lp2, .lp4])
func streamingInPiecesMatchesWholeFile(mode: MiniDiscLPMode) throws {
    let pcm = testSignal(frames: 3 * 44_100)
    let whole = try ATRAC3File.encode(wav: wavFile(pcm), kbps: mode.kbps)

    // Awkward block sizes, as when tracks of arbitrary length are joined gaplessly.
    let encoder = try ATRAC3Encoder(mode: mode)
    var frames = Data()
    var start = 0
    for size in [1, 777, 1024, 6143, 44_100, 3] .cycled(until: pcm.count / 2) {
        let end = min(start + size, pcm.count / 2)
        frames += pcm[2 * start..<2 * end].withUnsafeBufferPointer { encoder.write($0) }
        start = end
    }
    frames += encoder.finish()
    #expect(frames.count % encoder.frameBytes == 0)
    let streamed = encoder.at3Header(totalSamples: pcm.count / 2, dataBytes: frames.count) + frames
    #expect(streamed == whole)
}

@Test func decodesCompressedFilesWithCoreAudio() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let wav = dir.appending(path: "in.wav"), m4a = dir.appending(path: "in.m4a")
    try wavFile(testSignal(frames: 2 * 44_100)).write(to: wav)

    let afconvert = Process()
    afconvert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    afconvert.arguments = ["-f", "m4af", "-d", "aac@48000", wav.path, m4a.path]
    try afconvert.run()
    afconvert.waitUntilExit()
    #expect(afconvert.terminationStatus == 0)

    #expect(try AudioFileDecoder.decode(url: wav) == testSignal(frames: 2 * 44_100))
    let pcm = try AudioFileDecoder.decode(url: m4a)
    #expect(abs(pcm.count / 2 - 2 * 44_100) < 4096)   // AAC priming/padding
    let encoder = try ATRAC3Encoder(mode: .lp2)
    #expect(!(encoder.write(pcm) + encoder.finish()).isEmpty)
}

extension Array where Element == Int {
    /// Repeats the sizes until they cover `total`.
    func cycled(until total: Int) -> [Int] {
        var out: [Int] = [], sum = 0
        while sum < total { for s in self where sum < total { out.append(s); sum += s } }
        return out
    }
}
