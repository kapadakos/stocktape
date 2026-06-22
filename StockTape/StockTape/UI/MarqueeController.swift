//
//  MarqueeController.swift
//  StockTape
//
//  Owns the scrolling ticker shown in the status item button. The full
//  concatenated attributed string is rotated one character per tick to produce
//  the scroll, exactly as described in the build spec. A monospaced font keeps
//  the width from jittering as characters cycle.
//

import AppKit

final class MarqueeController {

    private weak var statusItem: NSStatusItem?
    private var timer: Timer?

    /// The full, concatenated ticker string.
    private var fullString = NSAttributedString()
    /// Current rotation offset into `fullString`.
    private var offset = 0

    private let font = NSFont.monospacedSystemFont(ofSize: Constants.menuBarFontSize, weight: .medium)

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    // MARK: - Public API

    /// Replace the ticker contents with the given positions and resume scrolling.
    func setPositions(_ positions: [PositionDisplay]) {
        guard !positions.isEmpty else {
            showStatus("No positions found", color: Constants.flatColor)
            return
        }

        let result = NSMutableAttributedString()
        for position in positions {
            result.append(segment(for: position))
            result.append(separator())
        }

        fullString = result
        offset = 0
        resume()
    }

    /// Display fixed, non-scrolling text (loading / error / status). Pauses scroll.
    func showStatus(_ text: String, color: NSColor) {
        pause()
        fullString = NSAttributedString()
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        statusItem?.button?.attributedTitle = attributed
    }

    /// Pause scrolling without clearing the current title.
    func pause() {
        timer?.invalidate()
        timer = nil
    }

    /// Resume (or start) scrolling the current ticker string.
    func resume() {
        pause()
        guard fullString.length > 0 else { return }

        // Render the first frame immediately so the bar isn't blank for a tick.
        renderCurrentFrame()

        let timer = Timer(timeInterval: Constants.marqueeTickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common keeps the ticker advancing during menu tracking / scrolling.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        pause()
        fullString = NSAttributedString()
    }

    // MARK: - Scrolling

    private func tick() {
        guard fullString.length > 0 else { return }
        offset += 1
        if offset >= fullString.length { offset = 0 }
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        let length = fullString.length
        guard length > 0 else { return }

        let head = fullString.attributedSubstring(from: NSRange(location: offset, length: length - offset))
        let rotated = NSMutableAttributedString(attributedString: head)
        if offset > 0 {
            let tail = fullString.attributedSubstring(from: NSRange(location: 0, length: offset))
            rotated.append(tail)
        }
        statusItem?.button?.attributedTitle = rotated
    }

    // MARK: - Segment building

    private func segment(for position: PositionDisplay) -> NSAttributedString {
        let arrow: String
        let color: NSColor
        switch position.direction {
        case .up:
            arrow = "▲"
            color = Constants.upColor
        case .down:
            arrow = "▼"
            color = Constants.downColor
        case .flat:
            arrow = "▪"
            color = Constants.flatColor
        }

        let percent = String(format: "%+.2f%%", position.percentChange)
        let text = "\(arrow) \(position.symbol) \(percent)"
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
