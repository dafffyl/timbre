import FluidAudio
import Foundation
import AVFoundation

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let modelsDir = URL(fileURLWithPath: args[2])

// Gain adaptatif par fenêtre (AGC) : remonte les passages faibles (locuteur éloigné).
func normalized(_ url: URL, window: Double = 1.0, targetRMS: Float = 0.08, maxGainDB: Float = 24) throws -> URL {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let frames = AVAudioFrameCount(file.length)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    try file.read(into: buffer)
    let n = Int(buffer.frameLength)
    let sr = format.sampleRate
    let ch = buffer.floatChannelData![0]
    let win = Int(window * sr)
    var gains = [Float](repeating: 1, count: n / win + 2)
    for w in 0..<gains.count {
        let s = w * win, e = min(n, s + win)
        if s >= e { continue }
        var sum: Float = 0
        for i in s..<e { sum += ch[i] * ch[i] }
        let rms = (sum / Float(e - s)).squareRoot()
        let g = rms < 0.002 ? 1 : min(targetRMS / rms, powf(10, maxGainDB / 20))
        gains[w] = max(1, g)
    }
    // interpolation linéaire du gain pour éviter les marches
    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    out.frameLength = buffer.frameLength
    let o = out.floatChannelData![0]
    for i in 0..<n {
        let pos = Double(i) / Double(win) - 0.5
        let a = max(0, Int(pos.rounded(.down))), b = min(gains.count - 1, a + 1)
        let t = Float(max(0, pos) - Double(a))
        let g = gains[a] * (1 - t) + gains[b] * t
        o[i] = max(-1, min(1, ch[i] * g))
    }
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("norm-\(UUID().uuidString).wav")
    let outFile = try AVAudioFile(forWriting: dest, settings: format.settings)
    try outFile.write(from: out)
    return dest
}

struct Out: Encodable { var variants: [String: [[String]]] = [:] }
var out = Out()

func run(_ name: String, config: OfflineDiarizerConfig, audio: URL) async {
    let manager = OfflineDiarizerManager(config: config)
    do {
        try await manager.prepareModels(directory: modelsDir)
        let result = try await manager.process(audio)
        out.variants[name] = result.segments.map { [$0.speakerId, String($0.startTimeSeconds), String($0.endTimeSeconds)] }
        print("ok \(name): \(result.segments.count) segments")
    } catch {
        print("ERROR \(name): \(error)")
    }
}

let outPath = args[3]
let knownSpeakers = Int(args[4]) ?? 0
let boosted = try normalized(input)
let base = OfflineDiarizerConfig()
await run("default", config: base, audio: input)
var z = base; z.zeroVoteReembed = .init(enabled: true, minDurationSeconds: 0.4)
await run("zeroVote", config: z, audio: input)
await run("agc", config: base, audio: boosted)
var k = base; k.clustering.numSpeakers = knownSpeakers
if knownSpeakers > 0 { await run("numSpeakers", config: k, audio: input) }
var th5 = base; th5.clustering.threshold = 0.5
await run("thr0.5", config: th5, audio: input)
var th8 = base; th8.clustering.threshold = 0.8
await run("thr0.8", config: th8, audio: input)
var ov = base; ov.postProcessing.exclusiveSegments = false
await run("overlapSegments", config: ov, audio: input)
try JSONEncoder().encode(out).write(to: URL(fileURLWithPath: outPath))
