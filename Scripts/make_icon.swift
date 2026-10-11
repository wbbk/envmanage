import AppKit

// 程序化绘制 EnvManage 应用图标（浅色主题），输出 .iconset 所需各尺寸 PNG。
// 用法: swift make_icon.swift <输出目录(将作为 AppIcon.iconset)>

let args = CommandLine.arguments
let outDir = args.count >= 2 ? args[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// 在指定像素画布上绘制图标。
func drawIcon(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: px, height: px)
    render(in: bounds)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

func render(in bounds: NSRect) {
    NSColor.clear.set()
    bounds.fill()

    let s = bounds.width
    let pad = s * 0.09
    let rect = bounds.insetBy(dx: pad, dy: pad)
    let radius = rect.width * 0.225

    // 背景：浅色圆角矩形 + 竖向渐变
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.99, alpha: 1.0),
    ])
    gradient?.draw(in: bg, angle: -90)

    // 顶部高光
    bg.addClip()
    let gloss = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY,
                                                 width: rect.width, height: rect.height / 2),
                             xRadius: radius, yRadius: radius)
    NSColor(calibratedWhite: 1.0, alpha: 0.25).setFill()
    gloss.fill()
    NSGraphicsContext.current?.cgContext.resetClip()

    // 主体：一个白色“设置卡片”
    let cardW = rect.width * 0.62
    let cardH = rect.height * 0.5
    let card = NSRect(x: rect.midX - cardW / 2, y: rect.midY - cardH / 2,
                      width: cardW, height: cardH)
    let cardRadius = card.width * 0.12
    let cardPath = NSBezierPath(roundedRect: card, xRadius: cardRadius, yRadius: cardRadius)
    NSColor.white.setFill()
    cardPath.fill()
    NSColor(calibratedRed: 0.72, green: 0.80, blue: 0.93, alpha: 1.0).setStroke()
    cardPath.lineWidth = max(1, s * 0.006)
    cardPath.stroke()

    // 卡片内三行开关列表
    let rowH = card.height / 3.0
    let pillW = card.width * 0.34
    let pillH = rowH * 0.5
    let leftPad = card.minX + card.width * 0.10
    let knobColors: [(on: Bool, color: NSColor)] = [
        (true, NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)),
        (true, NSColor(calibratedRed: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)),
        (false, NSColor(calibratedRed: 0.62, green: 0.68, blue: 0.78, alpha: 1.0)),
    ]

    for i in 0..<3 {
        let centerY = card.maxY - rowH * (CGFloat(i) + 0.5)
        // 左侧 key/value 条
        let barW = card.width * 0.34
        let bar = NSBezierPath(roundedRect:
            NSRect(x: leftPad, y: centerY - pillH * 0.18, width: barW, height: pillH * 0.36),
            xRadius: pillH * 0.18, yRadius: pillH * 0.18)
        NSColor(calibratedRed: 0.80, green: 0.85, blue: 0.93, alpha: 1.0).setFill()
        bar.fill()

        // 右侧开关
        let info = knobColors[i]
        let pillX = card.maxX - leftPad - pillW
        let pill = NSRect(x: pillX, y: centerY - pillH / 2, width: pillW, height: pillH)
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2)
        info.color.setFill()
        pillPath.fill()
        // 旋钮
        let kr = pillH * 0.38
        let kx = info.on ? pill.maxX - pillH / 2 : pill.minX + pillH / 2
        let knob = NSBezierPath(ovalIn: NSRect(x: kx - kr, y: centerY - kr, width: kr * 2, height: kr * 2))
        NSColor.white.setFill()
        knob.fill()
    }
}

// 需要的尺寸（点, @1x / @2x）
let spec: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for item in spec {
    if let data = drawIcon(px: item.px) {
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(item.name)
        try? data.write(to: url)
        FileHandle.standardError.write(Data("生成 \(item.name) (\(item.px)px)\n".utf8))
    }
}
FileHandle.standardError.write(Data("图标输出完成 -> \(outDir)\n".utf8))
