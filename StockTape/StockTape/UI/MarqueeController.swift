//
//  MarqueeController.swift
//  StockTape
//
//  Pixel-smooth scrolling ticker for the menu bar status item.
//
//  The full attributed string is rendered once into a doubled NSImage
//  (string + string, side by side) so the visible 196pt window can always
//  be extracted as a single contiguous slice — no wrap-around gaps.
//  A 60 fps timer advances the slice position by 1.5 pt/frame, giving
//  sub-character movement that looks smooth even on non-ProMotion displays.
//

import AppKit

final class MarqueeController {

    private weak var statusItem: NSStatusItem?
    private var timer: Timer?

    private var fullImage: NSImage?      // doubled pre-render of the full ticker
    private var singleWidth: CGFloat = 0 // logical-point width of one full cycle
    private var offset: CGFloat = 0      // current scroll position in points

    private let font = NSFont.monospacedSystemFont(ofSize: Constants.menuBarFontSize,
                                                    weight: .medium)

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    // MARK: - Public API

    func setPositions(_ positions: [PositionDisplay]) {
        guard !positions.isEmpty else {
            showStatus("No positions found", color: Constants.flatColor)
            return
        }
        let string = buildString(for: positions)
        singleWidth = ceil(string.size().width)
        guard singleWidth > 0 else { return }
        fullImage = renderDoubled(string)
        offset = 0
        Logger.shared.info("Marquee set: \(positions.count) position(s), \(Int(singleWidth))pt wide.")
        resume()
    }

    func showStatus(_ text: String, color: NSColor) {
        pause()
        fullImage = nil
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        statusItem?.button?.image = nil
        statusItem?.button?.attributedTitle = attributed
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        pause()
        guard fullImage != nil else { return }
        renderCurrentFrame()
        let t = Timer(timeInterval: Constants.marqueeTickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        pause()
        fullImage = nil
    }

    // MARK: - Scrolling

    private func tick() {
        offset += Constants.marqueeScrollSpeed
        if offset >= singleWidth { offset -= singleWidth }
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard let src = fullImage else { return }
        let w = Constants.marqueeDisplayWidth
        let h = src.size.height
        // Crop a w×h window starting at `offset` from the doubled image.
        let frame = NSImage(size: NSSize(width: w, height: h))
        frame.lockFocus()
        src.draw(
            in:   NSRect(x: 0,      y: 0, width: w, height: h),
            from: NSRect(x: offset, y: 0, width: w, height: h),
            operation: .copy,
            fraction: 1.0
        )
        frame.unlockFocus()
        statusItem?.button?.attributedTitle = NSAttributedString()
        statusItem?.button?.image = frame
        statusItem?.button?.imageScaling = .scaleNone
    }

    // MARK: - Rendering helpers

    /// Renders `string` twice side-by-side into a single NSImage so the scroll
    /// window can always be extracted as a contiguous slice.
    private func renderDoubled(_ string: NSAttributedString) -> NSImage {
        let strSize = string.size()
        let h = NSStatusBar.system.thickness
        let image = NSImage(size: NSSize(width: singleWidth * 2, height: h))
        image.lockFocus()
        let y = (h - strSize.height) / 2
        string.draw(at: NSPoint(x: 0,            y: y))
        string.draw(at: NSPoint(x: singleWidth,   y: y))
        image.unlockFocus()
        return image
    }

    private func buildString(for positions: [PositionDisplay]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for position in positions {
            result.append(segment(for: position))
            result.append(separator())
        }
        return result
    }

    private func segment(for position: PositionDisplay) -> NSAttributedString {
        let (arrow, color): (String, NSColor) = {
            switch position.direction {
            case .up:   return ("▲", Constants.upColor)
            case .down: return ("▼", Constants.downColor)
            case .flat: return ("▪", Constants.flatColor)
            }
        }()
        let text = "\(arrow) \(position.symbol) \(String(format: "%+.2f%%", position.percentChange))"
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
    }

    private func separator() -> NSAttributedString {
        NSAttributedString(string: Constants.separatorString, attributes: [
            .font: font,
            .foregroundColor: Constants.separatorColor,
        ])
    }
}
