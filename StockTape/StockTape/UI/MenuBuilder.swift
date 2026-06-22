//
//  MenuBuilder.swift
//  StockTape
//
//  Builds the dropdown NSMenu shown when the status item is clicked. Rebuilt
//  on each data refresh (and on click when the cache is stale). Position rows
//  are monospaced and space-padded into columns so prices and changes align.
//

import AppKit

/// High-level display state used to decide which menu the user sees.
enum TapeState {
    case loading
    case refreshing
    case normal
    case noPositions
    case networkError
    case authExpired
    case setupIncomplete
}

/// Actions the menu can trigger, handled by AppDelegate.
protocol MenuActionHandler: AnyObject {
    func menuDidSelectRefresh()
    func menuDidSelectReauthenticate()
    func menuDidSelectClearCredentials()
    func menuDidSelectOpenLog()
    func menuDidSelectToggleLaunchAtLogin()
    func menuDidSelectCompleteSetup()
    func menuDidSelectQuit()
}

final class MenuBuilder: NSObject {

    weak var handler: MenuActionHandler?

    private let rowFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let timeFormatter: DateFormatter
    private let priceFormatter: NumberFormatter

    private let symbolWidth = 6
    private let priceWidth = 12

    init(handler: MenuActionHandler) {
        self.handler = handler

        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        priceFormatter = NumberFormatter()
        priceFormatter.numberStyle = .decimal
        priceFormatter.usesGroupingSeparator = true

        super.init()
    }

    // MARK: - Build

    func buildMenu(state: TapeState,
                   positions: [PositionDisplay],
                   lastUpdate: Date?,
                   launchAtLogin: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch state {
        case .setupIncomplete:
            addSetupItems(to: menu)

        case .loading:
            addStatusItem("Loading positions…", to: menu)
            addQuit(to: menu)

        case .refreshing:
            addStatusItem("Updating…", to: menu)
            addQuit(to: menu)

        case .networkError:
            addStatusItem("⚠ Couldn't reach Schwab.", to: menu)
            addStatusItem("Check your connection and try again.", to: menu)
            menu.addItem(.separator())
            addAction("↻  Retry", #selector(refresh), to: menu)
            addSettingsAndQuit(to: menu, launchAtLogin: launchAtLogin)

        case .authExpired:
            addStatusItem("⚠ Your Schwab session expired.", to: menu)
            menu.addItem(.separator())
            addAction("Re-authenticate", #selector(reauthenticate), to: menu)
            addSettingsAndQuit(to: menu, launchAtLogin: launchAtLogin)

        case .noPositions:
            addHeader(lastUpdate: lastUpdate, to: menu)
            addStatusItem("No open positions found.", to: menu)
            menu.addItem(.separator())
            addAction("↻  Refresh Now", #selector(refresh), to: menu)
            addSettingsAndQuit(to: menu, launchAtLogin: launchAtLogin)

        case .normal:
            addHeader(lastUpdate: lastUpdate, to: menu)
            menu.addItem(.separator())
            for position in positions {
                menu.addItem(positionRow(for: position))
            }
            menu.addItem(.separator())
            addAction("↻  Refresh Now", #selector(refresh), to: menu)
            addSettingsAndQuit(to: menu, launchAtLogin: launchAtLogin)
        }

        return menu
    }

    // MARK: - Sections

    private func addHeader(lastUpdate: Date?, to menu: NSMenu) {
        let time = lastUpdate.map { timeFormatter.string(from: $0) } ?? "—"
        let item = NSMenuItem(title: "📊 Positions  —  updated \(time)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addStatusItem(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addSetupItems(to menu: NSMenu) {
        addAction("⚙  Complete Setup", #selector(completeSetup), to: menu)
        menu.addItem(.separator())
        addAction("Quit", #selector(quit), to: menu)
    }

    private func addSettingsAndQuit(to menu: NSMenu, launchAtLogin: Bool) {
        addSettingsSubmenu(to: menu, launchAtLogin: launchAtLogin)
        menu.addItem(.separator())
        addAction("Quit", #selector(quit), to: menu)
    }

    private func addSettingsSubmenu(to menu: NSMenu, launchAtLogin: Bool) {
        let settingsItem = NSMenuItem(title: "⚙  Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        addAction("Re-authenticate", #selector(reauthenticate), to: submenu)
        addAction("Clear Credentials", #selector(clearCredentials), to: submenu)
        addAction("Open Log File", #selector(openLog), to: submenu)

        let launchItem = makeAction("Launch at Login", #selector(toggleLaunchAtLogin))
        launchItem.state = launchAtLogin ? .on : .off
        submenu.addItem(launchItem)

        settingsItem.submenu = submenu
        menu.addItem(settingsItem)
    }

    private func addQuit(to menu: NSMenu) {
        menu.addItem(.separator())
        addAction("Quit", #selector(quit), to: menu)
    }

    // MARK: - Position rows

    private func positionRow(for position: PositionDisplay) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = attributedRow(for: position)
        return item
    }

    private func attributedRow(for position: PositionDisplay) -> NSAttributedString {
        // Column 1: symbol, left-aligned, padded.
        let symbol = position.symbol.padding(toLength: max(symbolWidth, position.symbol.count),
                                              withPad: " ",
                                              startingAt: 0)

        // Column 2: price, right-aligned.
        let priceText = formattedPrice(position.price)
        let pricePadded = String(repeating: " ", count: max(0, priceWidth - priceText.count)) + priceText

        // Column 3: change.
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
        let changeText = String(format: "%@ %+.2f%%", arrow, position.percentChange)

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\(symbol)  \(pricePadded)    ", attributes: [
            .font: rowFont,
            .foregroundColor: NSColor.labelColor,
        ]))
        result.append(NSAttributedString(string: changeText, attributes: [
            .font: rowFont,
            .foregroundColor: color,
        ]))
        return result
    }

    private func formattedPrice(_ price: Double) -> String {
        // Drop cents for prices over $1,000.
        priceFormatter.maximumFractionDigits = price > 1000 ? 0 : 2
        priceFormatter.minimumFractionDigits = price > 1000 ? 0 : 2
        let number = priceFormatter.string(from: NSNumber(value: price)) ?? "\(price)"
        return "$\(number)"
    }

    // MARK: - Action item helpers

    @discardableResult
    private func addAction(_ title: String, _ selector: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = makeAction(title, selector)
        menu.addItem(item)
        return item
    }

    private func makeAction(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    // MARK: - Selectors → handler

    @objc private func refresh() { handler?.menuDidSelectRefresh() }
    @objc private func reauthenticate() { handler?.menuDidSelectReauthenticate() }
    @objc private func clearCredentials() { handler?.menuDidSelectClearCredentials() }
    @objc private func openLog() { handler?.menuDidSelectOpenLog() }
    @objc private func toggleLaunchAtLogin() { handler?.menuDidSelectToggleLaunchAtLogin() }
    @objc private func completeSetup() { handler?.menuDidSelectCompleteSetup() }
    @objc private func quit() { handler?.menuDidSelectQuit() }
}
