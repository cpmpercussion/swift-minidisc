// at3tool-compatible front end over ATRACKit, so upstream's tests/run_tests.py --bin can
// check that our SwiftPM build of the encoder is byte-exact.
//
//   atrac3-swift -e [-br KBPS] in.wav out.at3
//   atrac3-swift -d in.at3 out.wav
//   atrac3-swift -lp2|-lp4 in.(mp3|m4a|flac|…) out.at3    decode with Core Audio, then encode
import ATRACKit
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
var mode = ""
var kbps = 0
var paths: [String] = []
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-e", "-d", "-lp2", "-lp4": mode = arg
    case "-br" where !args.isEmpty: kbps = Int(args.removeFirst()) ?? 0
    default: paths.append(arg)
    }
}
guard !mode.isEmpty, paths.count == 2 else {
    FileHandle.standardError.write("usage: atrac3-swift -e [-br KBPS] | -d | -lp2 | -lp4  in out\n".data(using: .utf8)!)
    exit(2)
}

do {
    let input = URL(fileURLWithPath: paths[0])
    let output: Data
    switch mode {
    case "-e": output = try ATRAC3File.encode(wav: Data(contentsOf: input), kbps: kbps)
    case "-d": output = try ATRAC3File.decode(at3: Data(contentsOf: input))
    default:
        let pcm = try AudioFileDecoder.decode(url: input)
        let encoder = try ATRAC3Encoder(mode: mode == "-lp2" ? .lp2 : .lp4)
        var frames = encoder.write(pcm)
        frames += encoder.finish()
        output = encoder.at3Header(totalSamples: pcm.count / 2, dataBytes: frames.count) + frames
    }
    try output.write(to: URL(fileURLWithPath: paths[1]))
} catch {
    FileHandle.standardError.write("atrac3-swift: \(paths[0]): \(error)\n".data(using: .utf8)!)
    exit(1)
}
