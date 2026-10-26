import AVFoundation
import FluidAudio
import Foundation

// usage: reassign audio.wav ref.rttm diar.json outExtra.json [variant]
let a = CommandLine.arguments
let audioURL = URL(fileURLWithPath: a[1])
let variant = a.count > 5 ? a[5] : "default"

func loadSamples(_ url: URL) throws -> [Float] {
    let f = try AVAudioFile(forReading: url)
    let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
    try f.read(into: b)
    return Array(UnsafeBufferPointer(start: b.floatChannelData![0], count: Int(b.frameLength)))
}
let samples = try loadSamples(audioURL)
let sr = 16000.0

struct Seg { var spk: String; var s: Double; var e: Double }
let diar = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[3]))) as! [String: Any]
let variants = diar["variants"] as! [String: [[String]]]
let segs = variants[variant]!.map { Seg(spk: $0[0], s: Double($0[1])!, e: Double($0[2])!) }

// parole de référence (proxy des mots de Whisper) : union des segments RTTM
var ref: [(Double, Double)] = []
for line in try String(contentsOf: URL(fileURLWithPath: a[2]), encoding: .utf8).split(separator: "\n") {
    let f = line.split(separator: " ")
    if f.first == "SPEAKER", let st = Double(f[3]), let du = Double(f[4]) { ref.append((st, st + du)) }
}
func union(_ xs: [(Double, Double)]) -> [(Double, Double)] {
    var out: [(Double, Double)] = []
    for x in xs.sorted(by: { $0.0 < $1.0 }) {
        if var last = out.last, x.0 <= last.1 + 0.01 { last.1 = max(last.1, x.1); out[out.count - 1] = last } else { out.append(x) }
    }
    return out
}
func subtract(_ base: [(Double, Double)], _ cut: [(Double, Double)]) -> [(Double, Double)] {
    var out: [(Double, Double)] = []
    for b in base {
        var pieces = [b]
        for c in cut {
            var next: [(Double, Double)] = []
            for p in pieces {
                if c.1 <= p.0 || c.0 >= p.1 { next.append(p); continue }
                if c.0 > p.0 { next.append((p.0, c.0)) }
                if c.1 < p.1 { next.append((c.1, p.1)) }
            }
            pieces = next
        }
        out += pieces
    }
    return out
}
let refU = union(ref)
let covered = union(segs.map { ($0.s, $0.e) })
let uncovered = subtract(refU, covered).filter { $0.1 - $0.0 >= 0.6 }

let models = try await DiarizerModels.downloadIfNeeded()
let manager = DiarizerManager()
manager.initialize(models: models)

// Une empreinte vaut mieux avec une fenêtre pleine : on répète le clip jusqu'à 10 s.
func embed(_ s: Double, _ e: Double) -> [Float]? {
    let i0 = max(0, Int(s * sr)), i1 = min(samples.count, Int(e * sr))
    guard i1 - i0 > Int(0.5 * sr) else { return nil }
    let clip = Array(samples[i0..<i1])
    var tiled: [Float] = []
    while tiled.count < Int(10 * sr) { tiled += clip }
    return try? manager.extractSpeakerEmbedding(from: Array(tiled.prefix(Int(10 * sr))))
}
func normalize(_ v: [Float]) -> [Float] { let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return n > 0 ? v.map { $0 / n } : v }

func cosDist(_ a: [Float], _ b: [Float]) -> Float { 1 - zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
var centroids: [String: [Float]] = [:]
for spk in Set(segs.map(\.spk)) {
    let mine = segs.filter { $0.spk == spk && $0.e - $0.s >= 1.0 }.sorted { ($0.e - $0.s) > ($1.e - $1.s) }.prefix(12)
    var acc = [Float](repeating: 0, count: 256); var n = 0
    for s in mine { if let e = embed(s.s, min(s.e, s.s + 6)) { for k in 0..<256 { acc[k] += e[k] }; n += 1 } }
    if n > 0 { centroids[spk] = normalize(acc) }
}
print("centroïdes: \(centroids.keys.sorted()) ; zones non couvertes: \(uncovered.count) (\(String(format: "%.0f", uncovered.reduce(0) { $0 + $1.1 - $1.0 })) s)")

var extra: [[String]] = []
var skipped = 0
for u in uncovered {
    var t = u.0
    while t < u.1 - 0.05 {
        var end = min(u.1, t + 3.0)
        if u.1 - end < 1.0 { end = u.1 }
        if let e = embed(t, end) {
            let ranked = centroids.map { ($0.key, cosDist(normalize(e), $0.value)) }.sorted { $0.1 < $1.1 }
            extra.append([ranked[0].0, String(t), String(end), String(ranked[0].1), String(ranked.count > 1 ? ranked[1].1 : 2)])
        } else { skipped += 1 }
        t = end
    }
}
print("fenêtres réassignées: \(extra.count), ignorées (trop courtes): \(skipped)")
try JSONSerialization.data(withJSONObject: ["extra": extra]).write(to: URL(fileURLWithPath: a[4]))
