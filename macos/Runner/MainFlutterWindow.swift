import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var protectionChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupProtectionChannel(controller: flutterViewController)

    super.awakeFromNib()
  }

  private func setupProtectionChannel(controller: FlutterViewController) {
    protectionChannel = FlutterMethodChannel(
      name: "com.example.earanyak/content_protection",
      binaryMessenger: controller.engine.binaryMessenger
    )

    protectionChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableProtection":
        // NSWindowSharingNone excludes window from macOS screen capture / sharing
        self?.sharingType = .none
        result(true)
      case "disableProtection":
        self?.sharingType = .readWrite
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
