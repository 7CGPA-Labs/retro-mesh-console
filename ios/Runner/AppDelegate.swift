import Flutter
import UIKit
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var externalWindow: UIWindow?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    if let registrar = self.registrar(forPlugin: "CastingAdapter") {
        CastingAdapter.register(with: registrar)
    }
    let channel = FlutterMethodChannel(name: "dev.seven_cgpalabs.mojosnap/projection",
                                       binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "openSystemCastMenu" {
        if #available(iOS 11.0, *) {
          DispatchQueue.main.async {
            let routePicker = AVRoutePickerView()
            routePicker.isHidden = true
            if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
              window.addSubview(routePicker)
              for subview in routePicker.subviews {
                if let button = subview as? UIButton {
                  button.sendActions(for: .touchUpInside)
                  break
                }
              }
              // Clean up after it presents
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                routePicker.removeFromSuperview()
              }
            }
          }
          result(true)
        } else {
          result(false)
        }
      } else if call.method == "startTVProjection" {
        self.setupExternalScreen()
        result(true)
      } else if call.method == "stopTVProjection" {
        self.externalWindow = nil
        result(true)
      } else if call.method == "startWebServer" {
        let ip = WebCaster.shared.startServer()
        result(ip)
      } else if call.method == "stopWebServer" {
        WebCaster.shared.stopServer()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    let systemChannel = FlutterMethodChannel(name: "dev.seven_cgpalabs.mojosnap/system", binaryMessenger: controller.binaryMessenger)
    systemChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "startHost":
        NetworkManager.shared.startHost()
        result(nil)
      case "startClient":
        NetworkManager.shared.startClient()
        result(nil)
      case "sendInput":
        if let args = call.arguments as? [String: Any],
           let buttonId = args["buttonId"] as? Int,
           let pressed = args["pressed"] as? Bool {
            NetworkManager.shared.sendInput(buttonId: buttonId, pressed: pressed)
        }
        result(nil)
      case "keepScreenOn":
        if let args = call.arguments as? [String: Any],
           let enable = args["enable"] as? Bool {
            UIApplication.shared.isIdleTimerDisabled = enable
        }
        result(nil)
      default:
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
