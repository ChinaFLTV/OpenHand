import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Channel name shared with the Flutter side
  /// (`MethodChannel('openhand/menu')`) for system menu → in-app navigation.
  static let menuChannelName = "openhand/menu"

  /// Lazily initialised on first use so it is safe to invoke even if
  /// `applicationDidFinishLaunching` has not yet wired things up.
  private var menuChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupMenuChannelIfNeeded()
    setupCloudSyncChannelIfNeeded()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Wired from `MainMenu.xib` → "OpenHand" → "Settings…" menu item.
  /// Sends a single `openSettings` call to the Flutter side, which is
  /// responsible for navigating to the Settings pane.
  @IBAction func openSettings(_ sender: Any?) {
    setupMenuChannelIfNeeded()
    menuChannel?.invokeMethod("openSettings", arguments: nil)
  }

  private func setupMenuChannelIfNeeded() {
    guard menuChannel == nil else { return }
    guard
      let window = mainFlutterWindow,
      let controller = window.contentViewController as? FlutterViewController
    else { return }
    menuChannel = FlutterMethodChannel(
      name: AppDelegate.menuChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  /// 2026-05-18 — 注册 iCloud 同步 method channel；Flutter 端通过
  /// `ThrottleCloudSyncService` 在 provider=iCloud 时调用。
  private var cloudSyncRegistered = false
  private func setupCloudSyncChannelIfNeeded() {
    guard !cloudSyncRegistered else { return }
    guard
      let window = mainFlutterWindow,
      let controller = window.contentViewController as? FlutterViewController
    else { return }
    CloudSyncBridge.register(with: controller.engine.binaryMessenger)
    cloudSyncRegistered = true
  }
}
