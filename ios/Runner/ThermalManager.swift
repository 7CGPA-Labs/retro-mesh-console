import Foundation
import UIKit

@_silgen_name("set_thermal_scale")
func set_thermal_scale(_ scale: Float)

class ThermalManager {
    static let shared = ThermalManager()
    
    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        // Initial state
        updateThermalState(ProcessInfo.processInfo.thermalState)
    }
    
    @objc private func thermalStateChanged(notification: Notification) {
        if let processInfo = notification.object as? ProcessInfo {
            updateThermalState(processInfo.thermalState)
        }
    }
    
    private func updateThermalState(_ state: ProcessInfo.ThermalState) {
        var scale: Float = 1.0
        switch state {
        case .nominal:
            scale = 1.0
        case .fair:
            scale = 0.8
        case .serious:
            scale = 0.5
        case .critical:
            scale = 0.25
        @unknown default:
            scale = 1.0
        }
        
        print("Thermal state changed: \(state.rawValue). Setting scale to \(scale)")
        set_thermal_scale(scale)
    }
}
