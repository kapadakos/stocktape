//
//  AppDelegate.swift
//  StockTape
//
//  Owns the status item, marquee, dropdown menu, refresh scheduler, and the
//  app lifecycle. Wires AuthManager + SchwabClient to the UI.
//

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    // UI
    private var statusItem: NSStatusItem!
    private var marquee: MarqueeController!
    private var menuBuilder: MenuBuilder!
    private var onboarding: OnboardingWindowController?

    // Services
    private let auth = AuthManager.shared
    private let client = SchwabClient()

    // State
    private var state: TapeState = .loading
    private var positions: [PositionDisplay] = []
    private var lastUpdate: Date?
    private var isRefreshing = false
    private var hasLoadedOnce = false
    private var hasWarnedRefreshTokenExpiry = false

    private var refreshTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("StockTape launched.")

        setupStatusItem()
        registerNotifications()

        if !auth.hasCredentials {
            enterSetupState()
        } else if !auth.hasRefreshToken {
            // Credentials present but no token yet — go straight to OAuth.
            marquee.showStatus("StockTape ↻", color: .secondaryLabelColor)
            auth.beginAuthorization()
        } else {
            marquee.showStatus("StockTape ↻", color: .secondaryLabelColor)
            startScheduler()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("StockTape terminating.")
        refreshTimer?.invalidate()
        marquee?.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: Constants.marqueeDisplayWidth)
        marquee = MarqueeController(statusItem: statusItem)
        menuBuilder = MenuBuilder(handler: self)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func registerNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(didWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep),
                              name: NSWorkspace.willSleepNotification, object: nil)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(authDidComplete),
                           name: AuthManager.didAuthenticate, object: nil)
        center.addObserver(self, selector: #selector(authDidFail(_:)),
                           name: AuthManager.didFailAuthentication, object: nil)
        center.addObserver(self, selector: #selector(authRequiresReauth),
                           name: AuthManager.didRequireReauth, object: nil)
    }

    // MARK: - State transitions

    private func enterSetupState() {
        state = .setupIncomplete
        marquee.showStatus("⚙ Setup StockTape", color: .secondaryLabelColor)
        showOnboarding()
    }

    private func showOnboarding() {
        if onboarding == nil {
            let controller = OnboardingWindowController()
            controller.onConnect = { [weak self] clientID, secret in
                guard let self else { return }
                guard self.auth.saveCredentials(clientID: clientID, clientSecret: secret) else {
                    self.presentError("Could not save credentials to the Keychain.")
                    return
                }
                self.auth.beginAuthorization()
            }
            onboarding = controller
        }
        onboarding?.show()
    }

    // MARK: - Refresh scheduling

    private func startScheduler() {
        performRefresh()   // fire immediately on launch
    }

    private func scheduleNextRefresh() {
        refreshTimer?.invalidate()
        let interval = MarketHours.refreshInterval()
        Logger.shared.info("Next refresh scheduled in \(Int(interval))s (market open: \(MarketHours.isMarketOpen())).")
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.performRefresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func performRefresh() {
        guard auth.isAuthenticated else {
            Logger.shared.warn("Refresh requested but not authenticated.")
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true

        if hasLoadedOnce {
            state = .refreshing
            marquee.showStatus("↻ Updating...", color: .secondaryLabelColor)
        } else {
            state = .loading
            marquee.showStatus("StockTape ↻", color: .secondaryLabelColor)
        }

        client.fetchPositions { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false

            switch result {
            case .success(let positions):
                self.positions = positions
                self.lastUpdate = Date()
                self.hasLoadedOnce = true
                if positions.isEmpty {
                    self.state = .noPositions
                    self.marquee.showStatus("No positions found", color: .secondaryLabelColor)
                } else {
                    self.state = .normal
                    self.marquee.setPositions(positions)
                }
                Logger.shared.info("Refresh succeeded: \(positions.count) position(s).")
                self.checkRefreshTokenExpiry()
            case .failure(let error):
                self.handleRefreshFailure(error)
            }

            self.scheduleNextRefresh()
        }
    }

    private func handleRefreshFailure(_ error: Error) {
        Logger.shared.error("Refresh failed: \(error.localizedDescription)")

        // Distinguish auth failures from network failures for the badge.
        if case SchwabClient.ClientError.auth = error {
            state = .authExpired
            marquee.showStatus("⚠ Auth expired", color: .systemOrange)
        } else {
            state = .networkError
            marquee.showStatus("⚠ Network error", color: .systemOrange)
        }
    }

    // MARK: - Proactive re-auth warning

    private func checkRefreshTokenExpiry() {
        guard !hasWarnedRefreshTokenExpiry, auth.isRefreshTokenExpiringSoon else { return }
        hasWarnedRefreshTokenExpiry = true

        let expiresAt = auth.refreshTokenExpiresAt
        let timeDesc: String
        if let expiresAt {
            let hours = max(0, Int(expiresAt.timeIntervalSinceNow / 3600))
            timeDesc = hours > 0 ? "in about \(hours) hour\(hours == 1 ? "" : "s")" : "very soon"
        } else {
            timeDesc = "soon"
        }

        Logger.shared.warn("Refresh token expiring \(timeDesc) — prompting user to re-authenticate.")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "StockTape — Re-authentication needed"
        alert.informativeText = """
        Your Schwab session will expire \(timeDesc). Re-authenticate now to avoid \
        an interruption to your live ticker.

        This takes about 30 seconds.
        """
        alert.addButton(withTitle: "Re-authenticate Now")
        alert.addButton(withTitle: "Later")
        alert.window.level = .floating

        if alert.runModal() == .alertFirstButtonReturn {
            auth.clearTokens()
            auth.beginAuthorization()
        }
    }

    // MARK: - Workspace notifications

    @objc private func didWake() {
        Logger.shared.info("Woke from sleep — refreshing.")
        guard auth.isAuthenticated else { return }
        performRefresh()
    }

    @objc private func willSleep() {
        Logger.shared.info("Going to sleep — pausing scheduler.")
        refreshTimer?.invalidate()
        refreshTimer = nil
        marquee.pause()
    }

    // MARK: - Auth notifications

    @objc private func authDidComplete() {
        Logger.shared.info("Authentication complete.")
        onboarding?.close()
        hasLoadedOnce = false
        startScheduler()
    }

    @objc private func authDidFail(_ note: Notification) {
        let message = (note.userInfo?["error"] as? Error)?.localizedDescription
            ?? "Authentication failed."
        Logger.shared.error("Authentication failed: \(message)")
        state = auth.hasCredentials ? .authExpired : .setupIncomplete
        marquee.showStatus(auth.hasCredentials ? "⚠ Auth expired" : "⚙ Setup StockTape",
                           color: auth.hasCredentials ? .systemOrange : .secondaryLabelColor)
        presentError(message)
    }

    @objc private func authRequiresReauth() {
        Logger.shared.warn("Re-authentication required — restarting OAuth flow.")
        state = .authExpired
        marquee.showStatus("⚠ Auth expired", color: .systemOrange)
        auth.beginAuthorization()
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Logger.shared.info("Launch at Login set to \(enabled).")
        } catch {
            Logger.shared.error("Launch at Login toggle failed: \(error.localizedDescription)")
            presentError("Could not change Launch at Login: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var isCacheStale: Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > Constants.cacheStalenessInterval
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "StockTape"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        alert.runModal()
    }
}

// MARK: - NSMenuDelegate (rebuild on each open)

extension AppDelegate: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = menuBuilder.buildMenu(state: state,
                                          positions: positions,
                                          lastUpdate: lastUpdate,
                                          launchAtLogin: isLaunchAtLoginEnabled)
        let items = fresh.items
        fresh.removeAllItems()          // detach so items can move to `menu`
        menu.removeAllItems()
        for item in items { menu.addItem(item) }

        // If the cache is older than the threshold, refresh in the background.
        if state == .normal || state == .noPositions, isCacheStale {
            performRefresh()
        }
    }
}

// MARK: - MenuActionHandler

extension AppDelegate: MenuActionHandler {

    func menuDidSelectRefresh() {
        performRefresh()
    }

    func menuDidSelectReauthenticate() {
        Logger.shared.info("User requested re-authentication.")
        auth.clearTokens()
        auth.beginAuthorization()
    }

    func menuDidSelectClearCredentials() {
        Logger.shared.info("User cleared credentials.")
        auth.clearAllCredentials()
        positions = []
        lastUpdate = nil
        hasLoadedOnce = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        enterSetupState()
    }

    func menuDidSelectOpenLog() {
        NSWorkspace.shared.open(Logger.shared.fileURL)
    }

    func menuDidSelectToggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }

    func menuDidSelectCompleteSetup() {
        showOnboarding()
    }

    func menuDidSelectQuit() {
        NSApp.terminate(nil)
    }
}
