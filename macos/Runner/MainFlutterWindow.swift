import Cocoa
import CoreFoundation
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let keyboardChannelName = "openhand/keyboard"
  private static let charsetConverterChannelName = "charset_converter"
  private static let escapePressedMethod = "escapePressed"
  private static let setEscapeCaptureEnabledMethod = "setEscapeCaptureEnabled"
  private static let escapeKeyCode: UInt16 = 53

  private let defaultContentSize = NSSize(width: 1440, height: 920)
  private let minimumContentSize = NSSize(width: 1100, height: 720)
  private var charsetConverterChannel: FlutterMethodChannel?
  private var keyboardChannel: FlutterMethodChannel?
  private var escapeCaptureEnabled = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = minimumContentSize

    let usesTemplateWindowSize = abs(windowFrame.size.width - 800) < 1 &&
      abs(windowFrame.size.height - 600) < 1
    let isBelowMinimumWindowSize = windowFrame.size.width < minimumContentSize.width ||
      windowFrame.size.height < minimumContentSize.height
    if usesTemplateWindowSize || isBelowMinimumWindowSize {
      self.setContentSize(defaultContentSize)
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupCharsetConverterChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    keyboardChannel = FlutterMethodChannel(
      name: Self.keyboardChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    keyboardChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == Self.setEscapeCaptureEnabledMethod,
            let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.escapeCaptureEnabled = enabled
      result(nil)
    }

    super.awakeFromNib()
  }

  private func setupCharsetConverterChannel(binaryMessenger: FlutterBinaryMessenger) {
    // 上游 macOS 插件会在正常响应后再次回调，应用侧接管通道并统一响应出口。
    charsetConverterChannel = FlutterMethodChannel(
      name: Self.charsetConverterChannelName,
      binaryMessenger: binaryMessenger
    )
    charsetConverterChannel?.setMethodCallHandler { [weak self] call, result in
      result(self?.charsetConverterResponse(for: call) ?? FlutterMethodNotImplemented)
    }
  }

  private func charsetConverterResponse(for call: FlutterMethodCall) -> Any? {
    switch call.method {
    case "encode":
      guard
        let arguments = call.arguments as? [String: Any],
        let source = arguments["data"] as? String,
        let charset = arguments["charset"] as? String
      else {
        return FlutterError(
          code: "invalid_arguments",
          message: "字符编码参数无效。",
          details: nil
        )
      }
      guard let encoding = stringEncoding(named: charset) else {
        return FlutterError(
          code: "missing_charset",
          message: "当前系统不支持该字符编码。",
          details: charset
        )
      }
      guard let data = source.data(using: encoding, allowLossyConversion: false) else {
        return FlutterError(
          code: "encoding_failed",
          message: "文本包含目标字符编码无法表示的内容。",
          details: charset
        )
      }
      return FlutterStandardTypedData(bytes: data)

    case "decode":
      guard
        let arguments = call.arguments as? [String: Any],
        let data = arguments["data"] as? FlutterStandardTypedData,
        let charset = arguments["charset"] as? String
      else {
        return FlutterError(
          code: "invalid_arguments",
          message: "字符解码参数无效。",
          details: nil
        )
      }
      guard let encoding = stringEncoding(named: charset) else {
        return FlutterError(
          code: "missing_charset",
          message: "当前系统不支持该字符编码。",
          details: charset
        )
      }
      guard let output = String(data: data.data, encoding: encoding) else {
        return FlutterError(
          code: "decoding_failed",
          message: "输入数据不符合指定的字符编码。",
          details: charset
        )
      }
      return output

    case "check":
      guard
        let arguments = call.arguments as? [String: Any],
        let charset = arguments["charset"] as? String
      else { return false }
      return stringEncoding(named: charset) != nil

    case "availableCharsets":
      guard var cursor = CFStringGetListOfAvailableEncodings() else {
        return [String]()
      }
      var charsets = [String]()
      while cursor.pointee != kCFStringEncodingInvalidId {
        if let name = CFStringConvertEncodingToIANACharSetName(cursor.pointee) {
          charsets.append(name as String)
        }
        cursor = cursor.successor()
      }
      return charsets

    default:
      return FlutterMethodNotImplemented
    }
  }

  private func stringEncoding(named charset: String) -> String.Encoding? {
    let coreFoundationEncoding = CFStringConvertIANACharSetNameToEncoding(
      charset as NSString
    )
    guard coreFoundationEncoding != kCFStringEncodingInvalidId else { return nil }
    return String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(coreFoundationEncoding)
    )
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown,
       event.keyCode == Self.escapeKeyCode,
       !event.isARepeat,
       escapeCaptureEnabled {
      keyboardChannel?.invokeMethod(Self.escapePressedMethod, arguments: nil)
      return
    }
    super.sendEvent(event)
  }
}
