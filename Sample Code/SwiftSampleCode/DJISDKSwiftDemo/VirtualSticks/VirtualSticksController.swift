//
//  VirtualSticksController.swift
//  DJISDKSwiftDemo
//
//  Created by Kilian Eisenegger on 03.12.20.
//  Copyright © 2020 hdrpano. All rights reserved.
//

class VirtualSticksController {
    //MARK:- Start Virtual Stick
    func startVirtualStick(enabled: Bool = true) {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickControlModeEnabled) else {
            return;
        }
        
        DJISDKManager.keyManager()?.setValue(NSNumber(value: enabled), for: virtualStickKey, withCompletion: { (error: Error?) in
            if error != nil {
                NSLog("Error start virtual stick")
            }
            NSLog("Start virtual stick \(enabled)")
        })
    }
    
    //MARK:- Start Advanced Virtual Stick
    func startAdvancedVirtualStick(enabled: Bool = true) {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickAdvancedControlModeEnabled) else {
            return;
        }
        
        DJISDKManager.keyManager()?.setValue(NSNumber(value: enabled), for: virtualStickKey, withCompletion: { (error: Error?) in
            if error != nil {
                NSLog("Error start advanced virtual stick")
            }
            NSLog("Start advanced virtual stick \(enabled)")
        })
    }
    
    //MARK:- Stop Virtual Stick
    func stopVirtualStick() {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickControlModeEnabled) else {
            return;
        }
        
        DJISDKManager.keyManager()?.setValue(NSNumber(value: false), for: virtualStickKey, withCompletion: { (error: Error?) in
            if error != nil {
                NSLog("Error stop virtual stick")
            }
            NSLog("Stop virtual stick")
        })
    }
    
    //MARK:- Stop Advanced Virtual Stick
    func stopAdvancedVirtualStick() {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickAdvancedControlModeEnabled) else {
            return;
        }
        
        DJISDKManager.keyManager()?.setValue(NSNumber(value: false), for: virtualStickKey, withCompletion: { (error: Error?) in
            if error != nil {
                NSLog("Error stop advanced virtual stick")
            }
            NSLog("Stop advanced virtual stick")
        })
    }
    
    //MARK:- Is Virtual Stick
    func isVirtualStick() -> Bool {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickControlModeEnabled) else {
            return false
        }
        
        guard let vs = DJISDKManager.keyManager()?.getValueFor(virtualStickKey) else {
            return false
        }
        
        let vsValue = vs.boolValue
        NSLog("Virtual Stick on: \(vsValue)")
        
        return vsValue
    }
    
    //MARK:- Is Advanced Virtual Stick
    func isVirtualStickAdvanced() -> Bool {
        guard let virtualStickKey = DJIFlightControllerKey(param: DJIFlightControllerParamVirtualStickAdvancedControlModeEnabled) else {
            return false
        }
        
        guard let vs = DJISDKManager.keyManager()?.getValueFor(virtualStickKey) else {
            return false
        }
        
        let vsValue = vs.boolValue
        NSLog("Advanced Virtual Stick on: \(vsValue)")
        
        return vsValue
    }
    
    //MARK:- Move Gimbal
    func moveGimbal(pitch: Float, roll: Float = 0, yaw: Float = 0, time: Double = 1.0, rotationMode: DJIGimbalRotationMode = DJIGimbalRotationMode.absoluteAngle) {
        // Rotation is relative to aicraft heading where 0 degrees is nose of aircraft, realitve means to the last position, absolut means to the heading
        let rotation: DJIGimbalRotation = DJIGimbalRotation.init(pitchValue: pitch as NSNumber, rollValue: roll as NSNumber, yawValue: yaw as NSNumber, time: time as TimeInterval, mode: rotationMode, ignore: true)
        let gimbal = self.fetchGimbal()
        if gimbal != nil {
            gimbal?.rotate(with: rotation, completion: { (error: Error?) in
                if error != nil {
                    NSLog("Error rotating gimbal");
                }
            })
        }
        if rotationMode == .absoluteAngle {
            NSLog("Move gimbal absolute with \(yaw) pitch \(pitch)")
        }
    }
    
    //MARK:- Yaw Aircraft Virtual Stick
    func vsYaw(yaw: Float) {
        let fc = self.fetchFlightController()
        fc?.rollPitchCoordinateSystem = .ground
        fc?.yawControlMode = .angle
        fc?.verticalControlMode = .velocity

        let ctrlData: DJIVirtualStickFlightControlData = DJIVirtualStickFlightControlData.init(pitch: 0, roll: 0, yaw: yaw, verticalThrottle: 0)
        fc?.send(ctrlData, withCompletion: {
            (error) in
            if let error = error {
                NSLog("Unable to yaw aircraft \(error)")
            }
        })
    }
    
    //MARK:- Virtual Stick Move
    func vsMove(pitch: Float, roll: Float, yaw: Float, vertical: Float) {
        let fc = fetchFlightController()
        fc?.rollPitchCoordinateSystem = .body
        fc?.rollPitchControlMode = .velocity
        fc?.yawControlMode = .angle
        fc?.verticalControlMode = .position

        let ctrlData: DJIVirtualStickFlightControlData = DJIVirtualStickFlightControlData.init(pitch: pitch, roll: roll, yaw: yaw, verticalThrottle: vertical)
        fc?.send(ctrlData, withCompletion: {
            (error) in
            if let error = error {
                NSLog("Unable to virtual stick aircraft \(error)")
            }
        })
    }
    
    //MARK:- Front LEDs On Off
    func frontLed(frontLEDs: Bool) {
        let FC = self.fetchFlightController()
        if FC != nil {
            //let rotation: DJIGimbalRotation = DJIGimbalRotation.init(pitchValue: 0, rollValue: 0, yawValue: 0, time: 1.0, mode: rotationMode)
            let led: DJIMutableFlightControllerLEDsSettings = DJIMutableFlightControllerLEDsSettings.init()
            led.frontLEDsOn = frontLEDs
            FC?.setLEDsEnabledSettings(led, withCompletion: { (error: Error?) in
                if error != nil {
                    NSLog("Error set front Led \(frontLEDs)")
                } else {
                    NSLog("Set front Led \(frontLEDs)")
                }
            })
        }
    }
    
    //MARK:- Is Advanced Virtual Stick
    func velocity() -> Double {
        guard let velocityKey = DJIFlightControllerKey(param: DJIFlightControllerParamVelocity) else {
            return 0
        }
        
        guard let velocity = DJISDKManager.keyManager()?.getValueFor(velocityKey) else {
            return 0
        }
        
        let Vector = velocity.value as! DJISDKVector3D
        
        let speed = pow((pow(Vector.x,2) + pow(Vector.y,2)),0.5)
       
        // NSLog("Velocity \((speed*10).rounded()/10)")
        
        return speed
    }
    
    //MARK:- Get Remaining Power
    func getChargeRemainingInPercent() -> Int {
        guard let chargeKey = DJIBatteryKey(param: DJIBatteryParamChargeRemainingInPercent) else {
            return 0
        }
        guard let charge = DJISDKManager.keyManager()?.getValueFor(chargeKey) else {
            return 0
        }
        let chargeValue = charge.integerValue
        return chargeValue
    }
    
    //MARK:- Flight Gimbal
    func fetchGimbal() -> DJIGimbal? {
        
        if DJISDKManager.product() == nil {
            return nil
        }
        
        if DJISDKManager.product() is DJIAircraft {
            return (DJISDKManager.product() as! DJIAircraft).gimbal
        } else if DJISDKManager.product() is DJIHandheld {
            return (DJISDKManager.product() as! DJIHandheld).gimbal
        }
        
        return nil
    }
    
    //MARK:- Camera
    func fetchCamera() -> DJICamera? {
        
        if DJISDKManager.product() == nil {
            return nil
        }
        
        if DJISDKManager.product() is DJIAircraft {
            return (DJISDKManager.product() as! DJIAircraft).camera
        } else if DJISDKManager.product() is DJIHandheld {
            return (DJISDKManager.product() as! DJIHandheld).camera
        }
        
        return nil
    }
    
    //MARK:- Flight Controller
    func fetchFlightController() -> DJIFlightController? {
        
        if DJISDKManager.product() == nil {
            return nil
        }
        
        if DJISDKManager.product() is DJIAircraft {
            return (DJISDKManager.product() as! DJIAircraft).flightController
        }
        return nil
    }
}
