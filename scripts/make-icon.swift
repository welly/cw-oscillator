// Renders the CW Oscillator app icon: a keyed sine-wave burst (a dit and a dah) over a lit
// key lamp, on a dark teal tile. Writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift              (from the repository root)
//        swift scripts/make-icon.swift preview.png  (also writes a 1024 px preview)
import AppKit
import SwiftUI

private let top = Color(red: 0.10, green: 0.36, blue: 0.40)
private let bottom = Color(red: 0.04, green: 0.16, blue: 0.20)
private let glow = Color(red: 1.00, green: 0.62, blue: 0.18)

struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 10)
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(0.55), .clear], center: .center,
                                     startRadius: 0, endRadius: 300))
                .frame(width: 600, height: 600)
            KeyedWave()
                .stroke(glow, style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                .frame(width: 640, height: 300)
                .shadow(color: glow.opacity(0.8), radius: 18)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// A flat line with two bursts of sine wave: a short one (dit) and a long one (dah).
struct KeyedWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        let amplitude = rect.height / 2
        // Bursts as fractions of the width: dit then dah, one unit gap between.
        let bursts: [ClosedRange<Double>] = [0.12...0.30, 0.42...0.88]
        let cycleWidth = 0.04
        let steps = 900
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            var y = 0.0
            if let burst = bursts.first(where: { $0.contains(t) }) {
                let local = (t - burst.lowerBound) / (burst.upperBound - burst.lowerBound)
                let ramp = sin(.pi / 2 * min(1, local * 5, (1 - local) * 5)) // raised-cosine keying
                y = sin(2 * .pi * (t - burst.lowerBound) / cycleWidth) * ramp * ramp
            }
            let point = CGPoint(x: rect.minX + t * rect.width, y: mid - y * amplitude)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

@MainActor
func renderPNG(size: Int) -> Data {
    let content = AppIcon()
        .scaleEffect(CGFloat(size) / 1024)
        .frame(width: CGFloat(size), height: CGFloat(size))
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

@MainActor
func main() throws {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: fm.currentDirectoryPath)
    let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: iconset) }
    for base in [16, 32, 128, 256, 512] {
        try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
        try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
    let resources = root.appendingPathComponent("Resources")
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    let icns = resources.appendingPathComponent("AppIcon.icns")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("Wrote \(icns.path)")

    if CommandLine.arguments.count > 1 {
        let preview = URL(fileURLWithPath: CommandLine.arguments[1])
        try renderPNG(size: 1024).write(to: preview)
        print("Wrote \(preview.path)")
    }
}

try MainActor.assumeIsolated { try main() }
