import Flutter
import Foundation
import UIKit

/// 节流配置 iCloud Drive 同步桥接（iOS 端）。
///
/// 2026-05-19 — 与 macOS 端保持一致：
///   * `pushIcloud` / `pullIcloud` → NSUbiquitousKeyValueStore；
///   * 监听 `didChangeExternallyNotification`，远端有新版本时反向调用
///     Dart 端 `cloudConfigChanged`，让自动同步触发拉取；
///   * 同时监听 `UIApplication.willEnterForegroundNotification`，
///     从后台恢复时主动 synchronize 一次，加速跨设备同步可见性。
///
/// 部署条件：Xcode 中需为 Target 启用 iCloud capability →
/// Key-Value storage，并配相同 entitlement，否则 store.synchronize()
/// 始终返回 false。
class CloudSyncBridge {
  static let channelName = "openhand/cloud_sync"
  /// 与 macOS 端使用相同 key 以便跨平台读写同一份配置。
  static let throttleConfigKey = "openhand.throttle_config.v1"

  private static var channel: FlutterMethodChannel?
  private static var externalObserver: NSObjectProtocol?
  private static var foregroundObserver: NSObjectProtocol?

  static func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "pushIcloud":
        Self.handlePush(call: call, result: result)
      case "pullIcloud":
        Self.handlePull(call: call, result: result)
      case "isIcloudAvailable":
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = ch

    NSUbiquitousKeyValueStore.default.synchronize()
    if self.externalObserver == nil {
      self.externalObserver = NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: NSUbiquitousKeyValueStore.default,
        queue: .main
      ) { note in
        Self.handleExternalChange(note: note)
      }
    }
    if self.foregroundObserver == nil {
      self.foregroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.willEnterForegroundNotification,
        object: nil,
        queue: .main
      ) { _ in
        NSUbiquitousKeyValueStore.default.synchronize()
      }
    }
  }

  private static func handlePush(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let json = args["config_json"] as? String,
      !json.isEmpty
    else {
      result(FlutterError(code: "invalid_args", message: "config_json required", details: nil))
      return
    }
    if json.lengthOfBytes(using: .utf8) > 900_000 {
      result(
        FlutterError(
          code: "payload_too_large",
          message: "config exceeds NSUbiquitousKeyValueStore 1MB cap",
          details: nil
        ))
      return
    }
    let store = NSUbiquitousKeyValueStore.default
    store.set(json, forKey: throttleConfigKey)
    let synchronized = store.synchronize()
    result([
      "ok": synchronized,
      "synchronized": synchronized,
    ])
  }

  private static func handlePull(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let store = NSUbiquitousKeyValueStore.default
    _ = store.synchronize()
    let json = store.string(forKey: throttleConfigKey)
    result([
      "ok": json != nil,
      "config_json": json ?? "",
    ])
  }

  /// 仅当变更涉及 throttleConfigKey 时才推送，避免无关 key 触发 Dart 端
  /// 不必要的 pull。
  private static func handleExternalChange(note: Notification) {
    let userInfo = note.userInfo ?? [:]
    let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
    if !changedKeys.isEmpty && !changedKeys.contains(throttleConfigKey) {
      return
    }
    let reason = (userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1
    self.channel?.invokeMethod(
      "cloudConfigChanged",
      arguments: [
        "reason": reason,
        "changed_keys": changedKeys,
      ]
    )
  }
}
