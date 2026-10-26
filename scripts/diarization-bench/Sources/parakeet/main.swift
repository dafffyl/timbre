import FluidAudio
import Foundation

// usage : parakeet audio.wav out.json modelsDir
let a = CommandLine.arguments
let audio = URL(fileURLWithPath: a[1])
let outURL = URL(fileURLWithPath: a[2])
let modelsDir = URL(fileURLWithPath: a[3])

let models = try await AsrModels.downloadAndLoad(to: modelsDir, version: .v3)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
let start = Date()
let result = try await manager.transcribe(audio, decoderState: &state)
let elapsed = Date().timeIntervalSince(start)

struct Tok: Codable { let token: String; let start: Double; let end: Double; let confidence: Float }
struct Out: Codable { let text: String; let duration: Double; let seconds: Double; let tokens: [Tok] }
let toks = (result.tokenTimings ?? []).map { Tok(token: $0.token, start: $0.startTime, end: $0.endTime, confidence: $0.confidence) }
try JSONEncoder().encode(Out(text: result.text, duration: result.duration, seconds: elapsed, tokens: toks)).write(to: outURL)
print("ok \(a[1]) : \(toks.count) jetons, \(String(format: "%.0f", elapsed)) s pour \(String(format: "%.0f", result.duration)) s d'audio")
