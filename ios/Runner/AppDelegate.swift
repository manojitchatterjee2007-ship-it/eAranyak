import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var protectionChannel: FlutterMethodChannel?
  private var isProtectionEnabled = false
  private var blurOverlayView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    setupProtectionChannel()
    setupCaptureObservers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setupProtectionChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    protectionChannel = FlutterMethodChannel(
      name: "com.example.earanyak/content_protection",
      binaryMessenger: controller.binaryMessenger
    )

    protectionChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableProtection":
        self?.isProtectionEnabled = true
        self?.checkScreenCaptureState()
        result(true)
      case "disableProtection":
        self?.isProtectionEnabled = false
        self?.removeBlurOverlay()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setupCaptureObservers() {
    // Screen recording / mirroring notification
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCapturedDidChange),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )

    // User took a screenshot
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }

  @objc private func screenCapturedDidChange() {
    checkScreenCaptureState()
  }

  @objc private func userDidTakeScreenshot() {
    guard isProtectionEnabled else { return }
    protectionChannel?.invokeMethod("onScreenshotDetected", arguments: ["timestamp": Date().timeIntervalSince1970])
  }

  private func checkScreenCaptureState() {
    guard isProtectionEnabled else { return }
    let isCaptured = UIScreen.main.isCaptured
    protectionChannel?.invokeMethod("onCaptureStateChanged", arguments: ["isCaptured": isCaptured])
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    if isProtectionEnabled {
      addBlurOverlay()
    }
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    removeBlurOverlay()
    if isProtectionEnabled {
      checkScreenCaptureState()
    }
    super.applicationDidBecomeActive(application)
  }

  private func addBlurOverlay() {
    guard blurOverlayView == nil, let window = self.window else { return }
    let blurEffect = UIBlurEffect(style: .dark)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(blurView)
    blurOverlayView = blurView
  }

  private func removeBlurOverlay() {
    blurOverlayView?.removeFromSuperview()
    blurOverlayView = nil
  }
}
