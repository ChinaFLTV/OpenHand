import Cocoa
import FlutterMacOS
import Foundation

/// 节流配置 iCloud Drive 同步桥接（macOS 端）。
///
/// 2026-05-18 — Flutter 端调 `openhand/cloud_sync` channel 的
/// `pushIcloud` / `pullIcloud` 方法，service 把 JSON 字符串读写到
/// `NSUbiquitousKeyValueStore`（key-value 容量 1MB，足够装节流配置）。
///
/// NSUbiquitousKeyValueStore 自动跨 macOS / iOS / iPadOS 同步，无需
/// OAuth / 文件路径，部署最简单；用户已登录 iCloud 即可。
class CloudSyncBridge {
  static let channelName = "openhand/cloud_sync"
  /// 与 iOS 端使用相同 key 以便跨平台读写同一份配置。
  static let throttleConfigKey = "openhand.throttle_config.v1"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
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
    // 主动同步一次让远端最新值落入本地；忽略返回 bool（不为 false 致命）。
    _ = store.synchronize()
    let json = store.string(forKey: throttleConfigKey)
    result([
      "ok": json != nil,
      "config_json": json ?? "",
    ])
  }
}
