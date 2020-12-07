//  VirtualSticksViewController.swift
//  Created by Dennis Baldwin on 3/18/20.
//  Copyright © 2020 DroneBlocks, LLC. All rights reserved.
//
//  Make sure you know what you're doing before running this code. This code makes use of the Virtual Sticks API.
//  This code has only been tested on DJI Spark, but should work on other DJI platforms. I recommend doing this outdoors to get familiar with the
//  functionality. It can certainly be run indoors since Virtual Sticks do not make use of GPS. Please make sure your flight mode switch is in
//  the default position. If any point you need to take control the switch can be toggled out of the default position so you have manual control
//  again. Virtual Sticks DOES NOT allow you to add any manual input to the flight controller when this mode is enabled. Good luck and I hope
//  to experiment with other flight paths soon.

import UIKit
import DJISDK

enum FLIGHT_MODE {
    case ROLL_LEFT_RIGHT
    case PITCH_FORWARD_BACK
    case THROTTLE_UP_DOWN
    case HORIZONTAL_ORBIT
    case VERTICAL_ORBIT
    case VERTICAL_SINE_WAVE
    case HORIZONTAL_SINE_WAVE
    case GPS_ORBIT_POI
    case GPS_WAYPOINT
}

class VirtualSticksViewController: UIViewController {
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var bearingLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var xLabel: UILabel!
    @IBOutlet weak var yLabel: UILabel!
    @IBOutlet weak var zLabel: UILabel!
    @IBOutlet weak var gimbalPitchLabel: UILabel!
    
    var flightController: DJIFlightController?
    var timer: Timer?
    
    // MARK: GCD Variables
    var queue = DispatchQueue(label: "com.virtual.myqueue")
    var photoDispatchGroup = DispatchGroup()
    var aircraftDispatchGroup = DispatchGroup()
    var gimbalDispatchGroup = DispatchGroup()
    var GCDaircraft: Bool = true
    var GCDphoto: Bool = true
    var GCDgimbal: Bool = true
    var GCDvs: Bool = false
    var GCDProcess: Bool = false
    
    var radians: Float = 0.0
    let velocity: Float = 0.1
    var x: Float = 0.0
    var y: Float = 0.0
    var z: Float = 0.0
    var yaw: Float = 0.0
    var missionRadius: Float = 0.0
    
    //MARK: Variables
    var aircraftLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var homeLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var vsTargetLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var aircraftAltitude: Double = 0
    var aircraftHeading: Double = 0
    var vsTargetAltitude: Double = 0
    var vsTargetBearing: Double = 0
    var targetAircraftYaw: Double = 0
    var targetGimbalPitch: Double = 0
    var targetGimbalYaw: Double = 0
    var gimbalPitch: Double = 0
    let start = Date()
    var GCDaircraftFT: Double = 0
    var GCDgimbalFT: Double = 0
    var GCDvsFT: Double = 0
    var vsSpeed: Float = 0
    var GPSController = GPS()
    var vsController = VirtualSticksController()
    
    var flightMode: FLIGHT_MODE?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Grab a reference to the aircraft
        if let aircraft = DJISDKManager.product() as? DJIAircraft {
            
            // Grab a reference to the flight controller
            if let fc = aircraft.flightController {
                
                // Store the flightController
                self.flightController = fc
                
                print("We have a reference to the FC")
                
                // Default the coordinate system to ground
                self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.ground
                
                // Default roll/pitch control mode to velocity
                self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.velocity
                
                // Set control modes
                self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity
                
                // Prepare Virtual Stick
                let fcMode = DJIFlightOrientationMode.aircraftHeading
                self.flightController?.setFlightOrientationMode(fcMode, withCompletion: { (error: Error?) in
                    if error != nil {
                        print("Error setting FlightController Orientation Mode");
                    }
                })
                
                self.flightController?.setMultipleFlightModeEnabled(true, withCompletion: { (error: Error?) in
                    if error != nil {
                        print("Error setting multiple flight mode");
                    }
                })
                
                // Add the key listener for the aircraft
                self.addKeys()
            }
            
        }
    }
    
    // User clicks the enter virtual sticks button
    @IBAction func enableVirtualSticks(_ sender: Any) {
        toggleVirtualSticks(enabled: true)
    }
    
    // User clicks the exit virtual sticks button
    @IBAction func disableVirtualSticks(_ sender: Any) {
        toggleVirtualSticks(enabled: false)
    }
    
    // Handles enabling/disabling the virtual sticks
    private func toggleVirtualSticks(enabled: Bool) {
            
        // Let's set the VS mode
        self.flightController?.setVirtualStickModeEnabled(enabled, withCompletion: { (error: Error?) in
            
            // If there's an error let's stop
            guard error == nil else { return }
            
            print("Are virtual sticks enabled? \(enabled)")
            
        })
        
    }
    
    @IBAction func rollLeftRight(_ sender: Any) {
        setupFlightMode()
        flightMode = FLIGHT_MODE.ROLL_LEFT_RIGHT
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz
        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(timerLoop), userInfo: nil, repeats: true)
    }
    
    @IBAction func pitchForwardBack(_ sender: Any) {
        setupFlightMode()
        flightMode = FLIGHT_MODE.PITCH_FORWARD_BACK
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz
        // Note: changing the frequency will have an impact on the distance flown so BE CAREFUL
        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(timerLoop), userInfo: nil, repeats: true)
    }
    
    @IBAction func throttleUpDown(_ sender: Any) {
        setupFlightMode()
        flightMode = FLIGHT_MODE.THROTTLE_UP_DOWN
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz
        // Note: changing the frequency will have an impact on the distance flown so BE CAREFUL
        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(timerLoop), userInfo: nil, repeats: true)
    }
    
    @IBAction func horizontalOrbit(_ sender: Any) {
        setupFlightMode()
        flightMode = FLIGHT_MODE.HORIZONTAL_ORBIT
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz
        // Note: changing the frequency will have an impact on the distance flown so BE CAREFUL
        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(timerLoop), userInfo: nil, repeats: true)
    }
    
    @IBAction func verticalOrbit(_ sender: Any) {
        setupFlightMode()
        flightMode = FLIGHT_MODE.VERTICAL_ORBIT
        
        // Schedule the timer at 20Hz while the default specified for DJI is between 5 and 25Hz
        // Note: changing the frequency will have an impact on the distance flown so BE CAREFUL
        timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(timerLoop), userInfo: nil, repeats: true)
    }
    
    // Change the coordinate system between ground/body and observe the behavior
    // HIGHLY recommended to test first in the iOS simulator to observe the values in timerLoop and then test outdoors
    @IBAction func changeCoordinateSystem(_ sender: UISegmentedControl) {
        
        if sender.selectedSegmentIndex == 0 {
            self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.ground
        } else if sender.selectedSegmentIndex == 1 {
            self.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.body
        }
        
    }
    
    // Change the control mode between velocity/angle and observe the behavior
    // HIGHLY recommended to test first in the iOS simulator to observe the values in timerLoop and then test outdoors
    @IBAction func changeRollPitchControlMode(_ sender: UISegmentedControl) {
        
        if sender.selectedSegmentIndex == 0 {
            self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.velocity
        } else if sender.selectedSegmentIndex == 1 {
            self.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.angle
        }
    }
    
    // Change the yaw control mode between angular velocity and angle
    @IBAction func changeYawControlMode(_ sender: UISegmentedControl) {
        
        if sender.selectedSegmentIndex == 0 {
            self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angularVelocity
        } else if sender.selectedSegmentIndex == 1 {
            self.flightController?.yawControlMode = DJIVirtualStickYawControlMode.angle
        }
    }
    
    @IBAction func startVSMission(_ sender: UIButton) {
        self.startVSLinearNow()
    }
    
    // Timer loop to send values to the flight controller
    @objc func timerLoop() {
        
        // Add velocity to radians before we do any calculation
        radians += velocity
        
        // Determine the flight mode so we can set the proper values
        switch flightMode {
        case .ROLL_LEFT_RIGHT:
            x = cos(radians)
            y = 0
            z = 0
        case .PITCH_FORWARD_BACK:
            x = 0
            y = sin(radians)
            z = 0
        case .THROTTLE_UP_DOWN:
            x = 0
            y = 0
            z = sin(radians)
        case .HORIZONTAL_ORBIT:
            x = cos(radians)
            y = sin(radians)
            z = 0
        case .VERTICAL_ORBIT:
            x = cos(radians)
            y = 0
            z = sin(radians)
        case .VERTICAL_SINE_WAVE:
            break
        case .HORIZONTAL_SINE_WAVE:
            break
        case .GPS_ORBIT_POI:
            break
        case .GPS_WAYPOINT:
            break
        case .none:
            break
        }
        
        print("Sending x: \(x), y: \(y), z: \(z)")
        
        // Construct the flight control data object
        var controlData = DJIVirtualStickFlightControlData()
        controlData.verticalThrottle = z
        controlData.roll = x
        controlData.pitch = y
        controlData.yaw = yaw
        
        // Send the control data to the FC
        self.flightController?.send(controlData, withCompletion: { (error: Error?) in
            
            // There's an error so let's stop
            if error != nil {
                
                print("Error sending data")
                
                // Disable the timer
                self.timer?.invalidate()
            }
            
        })
    }
    
    //MARK: GCD Timer
    @objc func updateGCD() {
        if !self.GCDaircraft  { self.showAircraftYaw() }
        if !self.GCDgimbal  { self.showGimbal() }
        // if !self.GCDphoto  { self.showPhoto() }
        if !self.GCDvs { self.showVS() }
    }
    
    // Called before any new flight mode is initiated
    private func setupFlightMode() {
        
        // Reset radians
        radians = 0.0
        
        // Invalidate timer if necessary
        // This allows switching between flight modes
        if timer != nil {
            print("invalidating")
            timer?.invalidate()
        }
    }
    
    //MARK: Virtual Stick Yaw Aircraft
    func yawAircraft() {
        self.aircraftDispatchGroup.enter()
        self.GCDaircraft = false
        self.GCDaircraftFT = self.start.timeIntervalSinceNow * -1
        self.vsController.vsYaw(yaw: Float(self.targetAircraftYaw))
        self.aircraftDispatchGroup.wait()
    }
    
    //MARK: Virtual Stick Move Aircraft
    func moveAircraft() {
        self.aircraftDispatchGroup.enter()
        self.GCDvs = false
        self.GCDvsFT = self.start.timeIntervalSinceNow * -1
        self.aircraftDispatchGroup.wait()
    }
    
    //MARK: Move Gimbal GCD
    func moveGimbal() {
        self.gimbalDispatchGroup.enter()
        self.GCDgimbal = false
        self.GCDgimbalFT = self.start.timeIntervalSinceNow * -1
        self.vsController.moveGimbal(pitch: Float(self.targetGimbalPitch), roll: 0, yaw: 0, time: 1, rotationMode: .absoluteAngle)
        self.gimbalDispatchGroup.wait()
    }
    
    private func addKeys() {
        //MARK: Location Listener
        if let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation)  {
            DJISDKManager.keyManager()?.startListeningForChanges(on: locationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    let newLocationValue = newValue!.value as! CLLocation

                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.aircraftLocation = newLocationValue.coordinate
                        let gps = GPS()
                        
                        let distance = gps.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.homeLocation)
                        let bearing = gps.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.homeLocation)
                        self.distanceLabel.text = String((distance*10).rounded()/10) + " m"
                        self.bearingLabel.text = String((bearing*10).rounded()/10) + " m"
                    }
                }
            }
        }
        
        //MARK: Aircraft Attitude Listener
        if let aircraftAttitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAttitude) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: aircraftAttitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    let Vector = newValue!.value as! DJISDKVector3D // Double in degrees
                    self.xLabel.text = String((Vector.x*10).rounded()/10)
                    self.yLabel.text = String((Vector.y*10).rounded()/10)
                    self.zLabel.text = String((Vector.z*10).rounded()/10)
                    self.aircraftHeading = Vector.z
                }
            })
        }
        
        //MARK: Gimbal Attitude Listener
        if let gimbalAttitudeKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: gimbalAttitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    var gimbalAttitude = DJIGimbalAttitude() // Float in degrees

                    let nsvalue = newValue!.value as! NSValue
                    nsvalue.getValue(&gimbalAttitude)
                    self.gimbalPitchLabel.text = String((gimbalAttitude.pitch*10).rounded()/10)
                    self.gimbalPitch = Double(gimbalAttitude.pitch)
                }
            })
        }
        
        //MARK: Altitude Listener
        if let altitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAltitudeInMeters) {
           DJISDKManager.keyManager()?.startListeningForChanges(on: altitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if (newValue != nil) {
                    self.altitudeLabel.text = String((newValue!.doubleValue*10).rounded()/10)
                    self.aircraftAltitude = newValue!.doubleValue
                }
            })
        }
        
        //MARK: Home Location Listener
        if let homeLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamHomeLocation)  {
            DJISDKManager.keyManager()?.startListeningForChanges(on: homeLocationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    let newLocationValue = newValue!.value as! CLLocation
                    
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.homeLocation = newLocationValue.coordinate
                    }
                }
            }
        }
    }
        
    //MARK: Show Virtual Stick Move
    func showVS() {
        let bearing = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        let distance = self.GPSController.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        
        if distance <= Double(self.vsSpeed) {
            self.vsSpeed = Float(distance / 2)
            if distance < 2 {
                print("Close, slow speed \((self.vsSpeed*10).rounded()/10)m/s distance to target \((distance*10).rounded()/10)m")
            }
        } else {
            print("Move, distance to target \((distance*10).rounded()/10)m speed \((self.vsSpeed*10).rounded()/10)m/s")
        }
        
        if self.aircraftHeading != bearing {
            self.vsTargetBearing = bearing
            if self.aircraftHeading - bearing > 1 {
                print("Move correct heading \((self.aircraftHeading*10).rounded()/10) \(Int(self.vsTargetBearing))")
            }
        }
        
        if self.aircraftAltitude - self.vsTargetAltitude > 1 {
            print("Move vertical \(Int(self.aircraftAltitude)) target [\(Int(self.vsTargetAltitude))")
        }
        
        self.vsController.vsMove(pitch: 0, roll: self.vsSpeed, yaw: Float(self.vsTargetBearing), vertical: Float(self.vsTargetAltitude))
        
        if distance < 1.1 && self.aircraftAltitude - self.vsTargetAltitude < 1.1 {
            self.GCDvs = true
            self.aircraftDispatchGroup.leave()
            print("VS Mission step complete")
        }
    }
    
    //MARK: Show Aircraft Yaw
    func showAircraftYaw() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDaircraftFT
        if !self.GCDaircraft && time > 0.9 {
            var diff: Double = abs(self.self.aircraftHeading - self.targetAircraftYaw)
            if diff >= 180 { diff = abs(diff - 360) }
            if diff < 2 { // 1.5° - 3°
                print("Aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.GCDaircraft = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.aircraftDispatchGroup.leave()
                }
            } else {
                print("Wait on aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.vsController.vsYaw(yaw: Float(self.targetAircraftYaw)) // repeat between 5 and 20Hz perfect with the listener
            }
            if time > 5 && !self.GCDaircraft {
                self.aircraftDispatchGroup.leave()
                self.GCDaircraft = true
                print("Timeout on aircraft yaw!")
            }
        }
    }
    
    //MARK: Show Gimbal Yaw
    func showGimbal() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDgimbalFT
        if !self.GCDgimbal && time > 0.9 {
            let pitchDiff = abs(self.gimbalPitch - self.targetGimbalPitch)
            if pitchDiff < 2 { //  1.5° - 3°
                print("Gimbal pitch \((pitchDiff*10).rounded()/10) heading \((self.aircraftHeading*10).rounded()/10)")
                self.GCDgimbal = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.gimbalDispatchGroup.leave()
                }
            } else {
                print("Wait on gimbal pitch \(self.gimbalPitch) timeout \((time*10).rounded()/10)")
            }
            if time > 2 {
                self.GCDgimbal = true
                self.gimbalDispatchGroup.leave()
                print("Timeout on gimbal yaw!")
            }
        }
    }
    
    //MARK: Start 2D Virtual Stick Mission
    func startVSLinearNow() {
        var grid: Array = [[Double]]()
        let speed: Float = 8
        self.vsSpeed = speed
        
        let aircraftLocationStart:CLLocationCoordinate2D = self.aircraftLocation
        let altitude: Double = self.aircraftAltitude
        let pitch: Double = -90
       
        // self.panoController.setGimbalMode(gimbalMode: .yawFollow)
        // self.panoController.setYawSimultaneousFollow(enabled: true)
    
        if !self.vsController.isVirtualStick() { self.vsController.startVirtualStick() }
        if !self.vsController.isVirtualStickAdvanced() { self.vsController.startAdvancedVirtualStick() }
        
        let offset = 0.00000899321605956683 * 10 // 10m 0.00000899321605956683
        
        self.GCDvs = true
        self.GCDProcess = true
        
        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(updateGCD), userInfo: nil, repeats: true)
    
        self.queue.asyncAfter(deadline: .now() + 1.0) {
            
            grid = [[aircraftLocationStart.latitude + offset / 2, aircraftLocationStart.longitude + offset / 2, altitude, pitch],
                    [aircraftLocationStart.latitude + offset / 2, aircraftLocationStart.longitude - offset, altitude, pitch],
                    [aircraftLocationStart.latitude - offset, aircraftLocationStart.longitude - offset, altitude, pitch],
                    [aircraftLocationStart.latitude - offset, aircraftLocationStart.longitude + offset, altitude, pitch],
                    [aircraftLocationStart.latitude, aircraftLocationStart.longitude, altitude, pitch]]
            

            print("Mission count \(grid.count)")
            
            print(grid)
            
            self.targetGimbalPitch = 0
            self.moveGimbal()
            for mP in grid {
                let index = grid.firstIndex(of: mP) ?? 0
                if index >= 0 { // Later for multiple flights
                    let lat = mP[0]
                    let lon = mP[1]
                    let alt = mP[2]
                    let pitch = mP[3]
                    
                    if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
        
                        self.vsTargetLocation.latitude = lat
                        self.vsTargetLocation.longitude = lon
                        self.vsTargetAltitude = alt
                        self.targetGimbalPitch = pitch
                        
                        self.moveGimbal()
                        
                        let bearing:Float = Float(self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                        
                        if abs(Float(self.aircraftHeading) - bearing) > 14 {
                            print("VS yaw for smooth straight")
                            self.targetAircraftYaw = Double(bearing)
                            self.yawAircraft()
                        }
                        
                        print("VS move")
                        self.vsSpeed = speed
                        self.moveAircraft()
                        if self.GCDProcess == false { break }
                        
                        // print("Photo")
                        // self.takePhoto()
                        // if self.GCDProcess == false { break }
                    
                    }
                }
            }
            
            print("Stop VS")
            if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
            if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
            self.GCDProcess = false
            self.GCDvs = false
            if self.timer != nil { self.timer?.invalidate() }
        }
    }

}
