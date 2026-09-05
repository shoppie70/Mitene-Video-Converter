#!/usr/bin/env swift

import Foundation
import AppKit

let fileManager = FileManager.default
let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let assetsDir = currentDir.appendingPathComponent("assets")
let resourcesDir = currentDir.appendingPathComponent("Resources")
let docsAssetsDir = currentDir.appendingPathComponent("docs/assets")

try? fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
try? fileManager.createDirectory(at: docsAssetsDir, withIntermediateDirectories: true)

let sourceIconURL = assetsDir.appendingPathComponent("app-icon.png")
guard let sourceImage = NSImage(contentsOf: sourceIconURL) else {
    print("Error: Could not load \(sourceIconURL.path)")
    exit(1)
}

func savePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to convert image to PNG for \(url.path)")
        return
    }
    do {
        try pngData.write(to: url)
        print("Created: \(url.lastPathComponent)")
    } catch {
        print("Failed to save \(url.path): \(error)")
    }
}

func resizeImage(_ image: NSImage, targetSize: CGSize) -> NSImage {
    let newImage = NSImage(size: targetSize)
    newImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    newImage.unlockFocus()
    return newImage
}

// 1. macOS HIG App Icon (1024x1024 with 824x824 squircle + drop shadow)
print("Generating macOS App Icon...")
let canvasSize = CGSize(width: 1024, height: 1024)
let iconTileSize = CGSize(width: 824, height: 824)
let originX = (canvasSize.width - iconTileSize.width) / 2.0
let originY = (canvasSize.height - iconTileSize.height) / 2.0 - 10.0 // slight downward optical balance

let macAppIcon = NSImage(size: canvasSize)
macAppIcon.lockFocus()
if let context = NSGraphicsContext.current?.cgContext {
    context.interpolationQuality = .high
    
    // Draw shadow
    context.saveGState()
    let shadowColor = NSColor(red: 0, green: 0, blue: 0, alpha: 0.28).cgColor
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: shadowColor)
    
    // Draw base icon into shadowed context
    let targetRect = NSRect(x: originX, y: originY, width: iconTileSize.width, height: iconTileSize.height)
    sourceImage.draw(in: targetRect, from: NSRect(origin: .zero, size: sourceImage.size), operation: .sourceOver, fraction: 1.0)
    context.restoreGState()
}
macAppIcon.unlockFocus()

// Create iconset directory
let iconsetDir = currentDir.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat, CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2),
]

for (name, pt, scale) in iconSizes {
    let px = pt * scale
    let resized = resizeImage(macAppIcon, targetSize: CGSize(width: px, height: px))
    savePNG(resized, to: iconsetDir.appendingPathComponent(name))
}

// Run iconutil to create Resources/AppIcon.icns
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
try? fileManager.removeItem(at: icnsURL)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus == 0 {
        print("Successfully generated Resources/AppIcon.icns")
    } else {
        print("iconutil failed with code \(iconutil.terminationStatus)")
    }
} catch {
    print("Failed to run iconutil: \(error)")
}

try? fileManager.removeItem(at: iconsetDir)

// 2. Web & LP Assets
print("\nGenerating Web & LP assets...")
// docs/assets/app-icon.png (512x512 clean original squircle)
let webIcon512 = resizeImage(sourceImage, targetSize: CGSize(width: 512, height: 512))
savePNG(webIcon512, to: docsAssetsDir.appendingPathComponent("app-icon.png"))

// docs/assets/app-icon-128.png
let webIcon128 = resizeImage(sourceImage, targetSize: CGSize(width: 128, height: 128))
savePNG(webIcon128, to: docsAssetsDir.appendingPathComponent("app-icon-128.png"))

// docs/assets/favicon.png (32x32)
let favicon32 = resizeImage(sourceImage, targetSize: CGSize(width: 32, height: 32))
savePNG(favicon32, to: docsAssetsDir.appendingPathComponent("favicon.png"))
savePNG(favicon32, to: docsAssetsDir.appendingPathComponent("favicon.ico"))

// docs/assets/apple-touch-icon.png (180x180, with solid coral background so corners are not dark on iOS)
let touchIcon = NSImage(size: CGSize(width: 180, height: 180))
touchIcon.lockFocus()
let coralColor = NSColor(red: 0.965, green: 0.463, blue: 0.341, alpha: 1.0)
coralColor.setFill()
NSRect(x: 0, y: 0, width: 180, height: 180).fill()
sourceImage.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180),
                 from: NSRect(origin: .zero, size: sourceImage.size),
                 operation: .sourceOver,
                 fraction: 1.0)
touchIcon.unlockFocus()
savePNG(touchIcon, to: docsAssetsDir.appendingPathComponent("apple-touch-icon.png"))

// 3. docs/assets/og-image.png (1200x630 Social Card)
print("\nGenerating OGP Social Card (1200x630)...")
let ogSize = CGSize(width: 1200, height: 630)
let ogImage = NSImage(size: ogSize)
ogImage.lockFocus()
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.interpolationQuality = .high
    
    // Background gradient: #F8F9FC -> #EBF0F7
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let startColor = CGColor(colorSpace: colorSpace, components: [0.973, 0.976, 0.988, 1.0])!
    let endColor = CGColor(colorSpace: colorSpace, components: [0.922, 0.941, 0.969, 1.0])!
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: [startColor, endColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 630), end: CGPoint(x: 1200, y: 0), options: [])
    }
    
    // Decorative subtle ambient coral glow in top-right
    let glowCenter = CGPoint(x: 950, y: 340)
    let glowColor = CGColor(colorSpace: colorSpace, components: [0.965, 0.463, 0.341, 0.18])!
    let clearColor = CGColor(colorSpace: colorSpace, components: [0.965, 0.463, 0.341, 0.0])!
    if let radial = CGGradient(colorsSpace: colorSpace, colors: [glowColor, clearColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(radial, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 360, options: [])
    }
    
    // Draw Right Side: App Icon with deep drop shadow
    let iconSize: CGFloat = 380
    let iconRect = NSRect(x: 760, y: 125, width: iconSize, height: iconSize)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.22])!)
    sourceImage.draw(in: iconRect, from: NSRect(origin: .zero, size: sourceImage.size), operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()
    
    // Draw Left Side Typography
    // Badge pill
    let pillRect = NSRect(x: 80, y: 475, width: 320, height: 38)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 19, yRadius: 19)
    NSColor(white: 1.0, alpha: 0.85).setFill()
    pillPath.fill()
    
    // Little coral dot in pill
    let dotRect = NSRect(x: 96, y: 489, width: 10, height: 10)
    let dotPath = NSBezierPath(ovalIn: dotRect)
    coralColor.setFill()
    dotPath.fill()
    
    let pillText = "Mitene Video Converter for Mac"
    let pillFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    let pillAttrs: [NSAttributedString.Key: Any] = [
        .font: pillFont,
        .foregroundColor: NSColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1.0)
    ]
    pillText.draw(at: NSPoint(x: 116, y: 484), withAttributes: pillAttrs)
    
    // Main Title: 2分にしてね
    let titleText = "2分にしてね"
    let titleFont = NSFont.systemFont(ofSize: 64, weight: .black)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor(red: 0.1, green: 0.13, blue: 0.18, alpha: 1.0)
    ]
    titleText.draw(at: NSPoint(x: 80, y: 375), withAttributes: titleAttrs)
    
    // Subtitle: 長い動画を、みてねサイズに。
    let subTitleText = "長い動画を、みてねサイズに。"
    let subTitleFont = NSFont.systemFont(ofSize: 32, weight: .bold)
    let subTitleAttrs: [NSAttributedString.Key: Any] = [
        .font: subTitleFont,
        .foregroundColor: NSColor(red: 0.25, green: 0.3, blue: 0.38, alpha: 1.0)
    ]
    subTitleText.draw(at: NSPoint(x: 80, y: 310), withAttributes: subTitleAttrs)
    
    // Description bullets
    let descText = "動画を入れるだけ。119秒以内へ自動分割 & 高画質軽量化。\n撮影日時を保持して写真アプリへ自動連携。"
    let descFont = NSFont.systemFont(ofSize: 21, weight: .regular)
    let paraStyle = NSMutableParagraphStyle()
    paraStyle.lineSpacing = 8
    let descAttrs: [NSAttributedString.Key: Any] = [
        .font: descFont,
        .foregroundColor: NSColor(red: 0.38, green: 0.44, blue: 0.52, alpha: 1.0),
        .paragraphStyle: paraStyle
    ]
    descText.draw(in: NSRect(x: 80, y: 200, width: 620, height: 80), withAttributes: descAttrs)
    
    // Feature chips at bottom
    let chips = ["完全ローカル処理", "Apple Silicon & Intel", "macOS 14以降対応"]
    var chipX: CGFloat = 80
    for chip in chips {
        let chipFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        let chipAttrs: [NSAttributedString.Key: Any] = [
            .font: chipFont,
            .foregroundColor: NSColor(red: 0.3, green: 0.35, blue: 0.45, alpha: 1.0)
        ]
        let textSize = chip.size(withAttributes: chipAttrs)
        let chipWidth = textSize.width + 24
        let chipRect = NSRect(x: chipX, y: 120, width: chipWidth, height: 32)
        let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 8, yRadius: 8)
        NSColor(white: 1.0, alpha: 0.7).setFill()
        chipPath.fill()
        NSColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 0.8).setStroke()
        chipPath.lineWidth = 1
        chipPath.stroke()
        
        chip.draw(at: NSPoint(x: chipX + 12, y: 127), withAttributes: chipAttrs)
        chipX += chipWidth + 12
    }
}
ogImage.unlockFocus()
savePNG(ogImage, to: docsAssetsDir.appendingPathComponent("og-image.png"))

print("All icons successfully generated!")
