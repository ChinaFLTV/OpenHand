import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 系统菜单与 Flutter 页面导航共用的通道名。
  static let menuChannelName = "openhand/menu"

  /// 首次使用时延迟初始化，允许在应用启动回调完成前安全调用。
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

  /// 由 `MainMenu.xib` 的设置菜单触发，通知 Flutter 打开设置页。
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

  /// 注册 iCloud 同步方法通道，由 `ThrottleCloudSyncService` 按需调用。
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
