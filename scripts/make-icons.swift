// Draws Hoardly's icon and logo, and writes every size the app, extension and stores need.
// usage: swift scripts/make-icons.swift   (from the repo root)
import AppKit
import SwiftUI

extension Color {
    init(_ hex: UInt32) { self.init(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
}

/// Down arrow (shaft + head) in its frame.
struct Arrow: Shape {
    func path(in r: CGRect) -> Path {
        let (w, h) = (r.width, r.height)
        var p = Path()
        p.addLines([CGPoint(x: w * 0.36, y: 0), CGPoint(x: w * 0.64, y: 0), CGPoint(x: w * 0.64, y: h * 0.52),
                    CGPoint(x: w, y: h * 0.52), CGPoint(x: w * 0.5, y: h), CGPoint(x: 0, y: h * 0.52), CGPoint(x: w * 0.36, y: h * 0.52)])
        p.closeSubpath()
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// The mark: a white arrow dropping onto a golden stack — the hoard. `grid` insets it like a macOS app icon.
struct Icon: View {
    let size: CGFloat
    var grid = true

    var body: some View {
        let b = grid ? size * 824 / 1024 : size
        let shape = RoundedRectangle(cornerRadius: b * 0.2237, style: .continuous)
        let gold = LinearGradient(colors: [Color(0xFFD970), Color(0xFFA928)], startPoint: .top, endPoint: .bottom)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(0x5E6BFF), Color(0x7A35E0)], startPoint: .top, endPoint: .bottom))
                .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)))
                .shadow(color: .black.opacity(grid ? 0.35 : 0), radius: size * 0.014, y: size * 0.012)
            Arrow().fill(.white)
                .overlay(Arrow().stroke(.white, style: StrokeStyle(lineWidth: b * 0.05, lineJoin: .round)))
                .frame(width: b * 0.44, height: b * 0.44)
                .offset(y: -b * 0.12)
            VStack(spacing: b * 0.035) {
                ForEach([0.46, 0.56, 0.66], id: \.self) { width in
                    Capsule().fill(gold).frame(width: b * width, height: b * 0.075)
                }
            }
            .offset(y: b * 0.27)
        }
        .frame(width: b, height: b)
        .frame(width: size, height: size)
    }
}

struct Logo: View {
    let dark: Bool
    var body: some View {
        HStack(spacing: 18) {
            Icon(size: 132)
            Text("Hoardly")
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundStyle(dark ? Color.white : Color(0x1D1B2E))
        }
        .padding(.horizontal, 16)
    }
}

@MainActor func write(_ view: some View, _ path: String, scale: CGFloat = 1) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = false
    let png = NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
}

MainActor.assumeIsolated {
    // macOS app icon: every slot of the asset catalog.
    let set = "Hoardly/Assets.xcassets/AppIcon.appiconset"
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            write(Icon(size: CGFloat(points * scale)), "\(set)/\(name)")
            images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
        }
    }
    let contents = ["images": images, "info": ["author": "xcode", "version": 1]] as [String: Any]
    try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: "\(set)/Contents.json"))
    try! #"{"info":{"author":"xcode","version":1}}"#.write(toFile: "Hoardly/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)

    // Browser extension: full-bleed (toolbar icons have no room for the macOS grid's padding).
    for size in [16, 32, 48, 96, 128] {
        write(Icon(size: CGFloat(size), grid: false), "extension/icon-\(size).png")
    }

    // Store listings and README.
    write(Icon(size: 1024), "design/icon-1024.png")
    write(Icon(size: 300, grid: false), "design/icon-300.png") // Edge Add-ons logo
    write(Logo(dark: false), "design/logo.png", scale: 2)
    write(Logo(dark: true), "design/logo-dark.png", scale: 2)
}
