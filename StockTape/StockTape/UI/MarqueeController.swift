//
//  MarqueeController.swift
//  StockTape
//
//  Pixel-smooth scrolling ticker for the menu-bar status item. Content scrolls
//  through a fixed-width clipping view at 60 fps, advancing by
//  (scrollSpeed / 60) points per frame — no per-character jumps. The text is
//  rendered once into a cached bitmap, so each frame only moves a layer.
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
    /// Current scroll speed (points/second); user-adjustable via the speed slider.
    private var scrollSpeed: CGFloat = TickerSettings.scrollSpeed

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
        let period = scrollView.scrollPeriod
        guard fullStringWidth > 0, period > 0 else { return }
        pixelOffset += scrollSpeed / 60
        if pixelOffset >= period { pixelOffset -= period }
        scrollView.setOffset(pixelOffset)
    }

    // MARK: - Live settings

    /// Change how fast the ticker scrolls (points/second). Takes effect on the
    /// next frame; persisted for the next launch.
    func setScrollSpeed(_ speed: CGFloat) {
        TickerSettings.scrollSpeed = speed
        scrollSpeed = TickerSettings.scrollSpeed
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

/// A fixed-width, layer-clipped view that shows an attributed string at a
/// pixel offset, repeating it seamlessly for wrap-around scrolling. A scrolling
/// tape is rendered once into a cached bitmap; each frame then only moves a
/// layer, so no text is laid out or drawn while it scrolls.
private final class ScrollingTextView: NSView {

    /// Longest tape (in device pixels) cached as one bitmap, within GPU texture
    /// limits. Longer tapes fall back to drawing every frame.
    private static let maxCachedPixelWidth = 8192

    private var string = NSAttributedString()
    private var stringWidth: CGFloat = 0
    private var pixelOffset: CGFloat = 0
    private var isScrolling = false

    private let tapeLayer = CALayer()
    private let firstCopy = CALayer()
    private let secondCopy = CALayer()
    private var isTapeCached = false
    private var tapeScale: CGFloat = 2

    /// Distance after which the scrolling tape repeats.
    private(set) var scrollPeriod: CGFloat = 0

    private var shouldScroll: Bool {
        isScrolling && string.length > 0 && stringWidth > bounds.width
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        tapeLayer.anchorPoint = .zero
        tapeLayer.isHidden = true
        for copy in [firstCopy, secondCopy] {
            copy.anchorPoint = .zero
            tapeLayer.addSublayer(copy)
        }
        layer?.addSublayer(tapeLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ string: NSAttributedString, scrolling: Bool) {
        self.string = string
        self.stringWidth = string.size().width
        self.pixelOffset = 0
        self.isScrolling = scrolling
        rebuildTape()
    }

    func setOffset(_ offset: CGFloat) {
        pixelOffset = offset
        if isTapeCached {
            applyTapeOffset()
        } else {
            needsDisplay = true
        }
    }

    // MARK: - Cached tape

    override func setFrameSize(_ newSize: NSSize) {
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        if heightChanged || shouldScroll != isTapeCached {
            rebuildTape()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuildTape()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuildTape()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildTape()
    }

    private func rebuildTape() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = Int((stringWidth * scale).rounded(.up))
        let pixelHeight = Int((bounds.height * scale).rounded(.up))
        scrollPeriod = stringWidth
        needsDisplay = true

        guard shouldScroll,
              pixelWidth > 0, pixelHeight > 0,
              pixelWidth <= Self.maxCachedPixelWidth,
              let image = renderTape(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale)
        else {
            isTapeCached = false
            withoutAnimation {
                tapeLayer.isHidden = true
                firstCopy.contents = nil
                secondCopy.contents = nil
            }
            return
        }

        // Whole device pixels keep the seam between the two copies invisible.
        let width = CGFloat(pixelWidth) / scale
        let height = CGFloat(pixelHeight) / scale
        scrollPeriod = width
        tapeScale = scale
        isTapeCached = true

        withoutAnimation {
            for (index, copy) in [firstCopy, secondCopy].enumerated() {
                copy.contents = image
                copy.contentsScale = scale
                copy.bounds = CGRect(x: 0, y: 0, width: width, height: height)
                copy.position = CGPoint(x: CGFloat(index) * width, y: 0)
            }
            tapeLayer.bounds = CGRect(x: 0, y: 0, width: width * 2, height: height)
            tapeLayer.position = CGPoint(x: snappedTapeX, y: 0)
            tapeLayer.isHidden = false
        }
    }

    private func renderTape(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> CGImage? {
        guard let colorSpace = window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: pixelWidth,
                                      height: pixelHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        let y = (bounds.height - string.size().height) / 2

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            string.draw(at: NSPoint(x: 0, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Tape position snapped to whole device pixels so text stays crisp.
    private var snappedTapeX: CGFloat {
        -(pixelOffset * tapeScale).rounded() / tapeScale
    }

    private func applyTapeOffset() {
        let x = snappedTapeX
        guard x != tapeLayer.position.x else { return }
        withoutAnimation { tapeLayer.position.x = x }
    }

    private func withoutAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    // MARK: - Drawing (static text, or tapes too long to cache)

    override func draw(_ dirtyRect: NSRect) {
        guard string.length > 0, !isTapeCached else { return }

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
