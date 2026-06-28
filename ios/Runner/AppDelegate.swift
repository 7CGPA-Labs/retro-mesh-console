import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var externalWindow: UIWindow?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.retromesh.console/projection",
                                       binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "startTVProjection" {
        self.setupExternalScreen()
        result(true)
      } else if call.method == "stopTVProjection" {
        self.externalWindow = nil
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Listen for screen connect/disconnect notifications (AirPlay/HDMI plug)
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenDidConnect),
        name: UIScreen.didConnectNotification,
        object: nil
    )
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenDidDisconnect),
        name: UIScreen.didDisconnectNotification,
        object: nil
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @objc private func screenDidConnect(notification: Notification) {
      setupExternalScreen()
  }
  
  @objc private func screenDidDisconnect(notification: Notification) {
      externalWindow = nil
  }
  
  private func setupExternalScreen() {
      guard UIScreen.screens.count > 1 else { return }
      let secondaryScreen = UIScreen.screens[1]
      
      let windowFrame = secondaryScreen.bounds
      let extWindow = UIWindow(frame: windowFrame)
      extWindow.screen = secondaryScreen
      
      let externalViewController = UIViewController()
      externalViewController.view.backgroundColor = .black
      
      let label = UILabel()
      label.text = "Retro Mesh Console: Projection Active\nWebGL TV Viewport Projected via AirPlay"
      label.numberOfLines = 0
      label.textColor = .white
      label.textAlignment = .center
      label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
      label.frame = externalViewController.view.bounds
      label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      
      externalViewController.view.addSubview(label)
      extWindow.rootViewController = externalViewController
      extWindow.isHidden = false
      self.externalWindow = extWindow
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
