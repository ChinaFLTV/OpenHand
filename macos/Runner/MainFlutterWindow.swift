import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let defaultContentSize = NSSize(width: 1440, height: 920)
  private let minimumContentSize = NSSize(width: 1100, height: 720)

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

    super.awakeFromNib()
  }
}
