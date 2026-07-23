import Flutter
import UIKit
import AVKit

@_silgen_name("set_global_tv_layer")
func set_global_tv_layer(_ layer: UnsafeMutableRawPointer)

class CastingAdapter: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    private var externalWindow: UIWindow?
    private var currentTarget: [String: Any]?
    private var imageView: UIImageView?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = CastingAdapter()
        instance.setupChannels(registrar: registrar)
        registrar.addApplicationDelegate(instance)
    }
    
    private func setupChannels(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(name: "dev.seven_cgpalabs.mojosnap/casting",
                                             binaryMessenger: registrar.messenger())
        eventChannel = FlutterEventChannel(name: "dev.seven_cgpalabs.mojosnap/casting_events",
                                           binaryMessenger: registrar.messenger())
        
        registrar.addMethodCallDelegate(self, channel: methodChannel!)
        eventChannel?.setStreamHandler(self)
        
        // Listen for screen connections (AirPlay/HDMI plug-in)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenDidConnect),
                                               name: UIScreen.didConnectNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(screenDidDisconnect),
                                               name: UIScreen.didDisconnectNotification,
                                               object: nil)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startScanning":
            updateDevices()
            result(nil)
        case "stopScanning":
            result(nil)
        case "connectToDevice":
            if let args = call.arguments as? [String: Any] {
                currentTarget = args
            }
            result(nil)
        case "projectGameplayCanvas":
            projectGameplay()
            result(nil)
        case "sendFrame":
            // Frames are now pushed directly to the CALayer via C++ Engine
            result(nil)
        case "disconnect":
            externalWindow = nil
            currentTarget = nil
            imageView = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        updateDevices()
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    @objc private func screenDidConnect() {
        updateDevices()
    }
    
    @objc private func screenDidDisconnect() {
        externalWindow = nil
        updateDevices()
    }
    
    private func updateDevices() {
        var targets: [[String: Any]] = []
        
        // Check if secondary screen is connected (AirPlay/HDMI secondary display active)
        if UIScreen.screens.count > 1 {
            let secondaryScreen = UIScreen.screens[1]
            let target: [String: Any] = [
                "id": "airplay_screen_0",
                "name": "Apple TV / AirPlay Display (\(Int(secondaryScreen.bounds.width))x\(Int(secondaryScreen.bounds.height)))",
                "protocolType": "appleAirPlay"
            ]
            targets.append(target)
        }
        
        if let json = try? JSONSerialization.data(withJSONObject: targets, options: []),
           let jsonString = String(data: json, encoding: .utf8) {
            eventSink?(jsonString)
        }
    }
    
    private func projectGameplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard UIScreen.screens.count > 1 else { return }
            let secondaryScreen = UIScreen.screens[1]
            
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.screen == secondaryScreen }
            
            let extWindow: UIWindow
            if let scene = windowScene {
                extWindow = UIWindow(windowScene: scene)
            } else {
                let windowFrame = secondaryScreen.bounds
                extWindow = UIWindow(frame: windowFrame)
                extWindow.setValue(secondaryScreen, forKey: "screen")
            }
            
            let externalViewController = UIViewController()
            externalViewController.view.backgroundColor = .black
            
            let iv = UIImageView(frame: externalViewController.view.bounds)
            iv.contentMode = .scaleAspectFit
            iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            iv.layer.magnificationFilter = .linear // Bilinear filtering for smooth scaling
            iv.backgroundColor = .black
            
            externalViewController.view.addSubview(iv)
            self.imageView = iv
            
            extWindow.rootViewController = externalViewController
            extWindow.isHidden = false
            self.externalWindow = extWindow

            // Pass the CALayer to our C++ Native Render engine
            let unmanagedLayer = Unmanaged.passUnretained(iv.layer)
            set_global_tv_layer(unmanagedLayer.toOpaque())
        }
    }
}
