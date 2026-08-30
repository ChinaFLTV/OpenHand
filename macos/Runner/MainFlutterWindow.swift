import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let keyboardChannelName = "openhand/keyboard"
  private static let escapePressedMethod = "escapePressed"
  private static let setEscapeCaptureEnabledMethod = "setEscapeCaptureEnabled"
  private static let escapeKeyCode: UInt16 = 53

  private let defaultContentSize = NSSize(width: 1440, height: 920)
  private let minimumContentSize = NSSize(width: 1100, height: 720)
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
