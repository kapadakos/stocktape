//
//  MarqueeController.swift
//  StockTape
//
//  Pixel-smooth scrolling ticker for the menu-bar status item. Content scrolls
//  through a fixed-width clipping view at 60 fps, advancing by
//  (scrollSpeed / 60) points per frame — no per-character jumps.
//

import AppKit

final class MarqueeController {

    private weak var statusItem: NSStatusItem?
    private var timer: Timer?

    /// The full attributed string being scrolled (empty when showing a status).
    private var fullString = NSAttributedString()
    /// Cached width of `fullString` to avoid re-measuring every frame.
    private var fullStringWidth: CGFloat = 0
    /// Current horizontal scroll offset in points.
    private var pixelOffset: CGFloat = 0

    private let scrollView = ScrollingTextView()
    private let font = NSFont.monospacedSystemFont(ofSize: Constants.menuBarFontSize, weight: .medium)

    /// Current width of the ticker window; user-adjustable via the length slider.
    private var visibleWidth: CGFloat = TickerSettings.visibleWidth

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        statusItem.length = visibleWidth
        setupScrollView(button: statusItem.button)
    }

    private func setupScrollView(button: NSStatusBarButton?) {
        guard let button else { return }
        button.title = ""
        scrollView.frame = NSRect(x: 0, y: 0,
                                  width: visibleWidth,
                                  height: max(button.frame.height, 22))
        scrollView.autoresizingMask = [.width, .height]
        button.addSubview(scrollView)
    }

    // MARK: - Public API

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

        let newWidth = result.size().width
        // Keep the current scroll position when the tape's total width is
        // unchanged (same symbols and formatting), so a background refresh
        // doesn't snap the ticker back to the start. Reset only when the layout
        // width actually changes.
        let preserveOffset = fullStringWidth > 0 && abs(newWidth - fullStringWidth) < 0.5

        fullString = result
        fullStringWidth = newWidth
        if !preserveOffset || pixelOffset >= fullStringWidth {
            pixelOffset = 0
        }

        scrollView.set(result, scrolling: true)
        scrollView.setOffset(pixelOffset)
        resume()
    }

    func showStatus(_ text: String, color: NSColor) {
        pause()
        fullString = NSAttributedString()
        fullStringWidth = 0
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        scrollView.set(attributed, scrolling: false)
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        pause()
        // Nothing to scroll — stay static.
        guard fullString.length > 0,
              fullStringWidth > visibleWidth else { return }

        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        pause()
        fullString = NSAttributedString()
        fullStringWidth = 0
        scrollView.set(NSAttributedString(), scrolling: false)
    }

    // MARK: - Animation

    private func tick() {
        guard fullStringWidth > 0 else { return }
        pixelOffset += TickerSettings.scrollSpeed / 60
        if pixelOffset >= fullStringWidth { pixelOffset -= fullStringWidth }
        scrollView.setOffset(pixelOffset)
    }

    // MARK: - Live settings

    /// Change how fast the ticker scrolls (points/second). Takes effect on the
    /// next frame; persisted for the next launch.
    func setScrollSpeed(_ speed: CGFloat) {
        TickerSettings.scrollSpeed = speed
    }

    /// Resize the ticker window in the menu bar. Persisted for the next launch.
    func setVisibleWidth(_ width: CGFloat) {
        visibleWidth = width
        TickerSettings.visibleWidth = width
        statusItem?.length = width
        scrollView.frame.size.width = width
        scrollView.needsDisplay = true
        // Re-evaluate whether scrolling is needed at the new width.
        resume()
    }

    // MARK: - Segment building

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

// MARK: - ScrollingTextView

/// A fixed-width, layer-clipped view that draws an attributed string at a
/// pixel offset, repeating it seamlessly for wrap-around scrolling.
private final class ScrollingTextView: NSView {

    private var string = NSAttributedString()
    private var stringWidth: CGFloat = 0
    private var pixelOffset: CGFloat = 0
    private var isScrolling = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ string: NSAttributedString, scrolling: Bool) {
        self.string = string
        self.stringWidth = string.size().width
        self.pixelOffset = 0
        self.isScrolling = scrolling
        needsDisplay = true
    }

    func setOffset(_ offset: CGFloat) {
        pixelOffset = offset
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard string.length > 0 else { return }

        let strHeight = string.size().height
        let y = (bounds.height - strHeight) / 2

        if !isScrolling || stringWidth <= bounds.width {
            // Static or short-enough text: center horizontally.
            let x = max(0, (bounds.width - stringWidth) / 2)
            string.draw(at: NSPoint(x: x, y: y))
        } else {
            // Scrolling: draw at current offset, then again right after for
            // seamless wrap — the second copy fills the gap when the first
            // scrolls out of view.
            let x = -pixelOffset
            string.draw(at: NSPoint(x: x, y: y))
            string.draw(at: NSPoint(x: x + stringWidth, y: y))
        }
    }
}
