//  VirtualSticksViewController.swift
//
//  GPS Virtual Stick added by Kilian Eisenegger 01.12.2020
//  This is a project from Dennis Baldwin and Kilian Eisenegger
//  Copyright © 2020 DroneBlocks & hdrpano. All rights reserved.
//

import UIKit
import DJISDK

class VirtualSticksViewController: UIViewController, MKMapViewDelegate  {
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var bearingLabel: UILabel!
    @IBOutlet weak var altitudeLabel: UILabel!
    @IBOutlet weak var xLabel: UILabel!
    @IBOutlet weak var yLabel: UILabel!
    @IBOutlet weak var zLabel: UILabel!
    @IBOutlet weak var gimbalPitchLabel: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var missionButton: UIButton!
    
    var homeAnnotation = DJIImageAnnotation(identifier: "homeAnnotation")
    var aircraftAnnotation = DJIImageAnnotation(identifier: "aircraftAnnotation")
    var waypointAnnotation = DJIImageAnnotation(identifier: "waypointAnnotation")
    var aircraftAnnotationView: MKAnnotationView!
    
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
    
    //MARK: GPS Variables
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
    var GCDphotoFT: Double = 0
    var vsSpeed: Float = 0
    var sdCardCount: Int = 0
    var photoCount: Int = 0
    // var photoCount: Int = 0
    var GPSController = GPS()
    var vsController = VirtualSticksController()
    var camController = CameraController()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent;
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.mapView.delegate = self

        // Grab a reference to the aircraft
        if let aircraft = DJISDKManager.product() as? DJIAircraft {
            
            // Grab a reference to the flight controller
            if let fc = aircraft.flightController {
                
                // Store the flightController
                self.flightController = fc
                
                // stop Virtual Stick if somebody touches the sticks
                // We get into real Pro stuff with this (C) Kilian Eisenegger
                let rc = aircraft.remoteController
                if rc != nil {
                    rc?.delegate = self
                }
                
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
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.mapView.addAnnotations([self.aircraftAnnotation, self.homeAnnotation])
        self.addKeys()
    }
    
    //MARK: View Did Disappear
    override func viewDidDisappear(_ animated: Bool) {
        if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
        if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
        if self.timer != nil { self.timer?.invalidate() }
    }
    
    @IBAction func startVSMission(_ sender: UIButton) {
        self.startVSLinearNow()
    }
    
    //MARK: GCD Timer Dispatch Management
    @objc func updateGCD() {
        if !self.GCDaircraft  { self.showAircraftYaw() }
        if !self.GCDgimbal  { self.showGimbal() }
        if !self.GCDphoto  { self.showPhoto() }
        if !self.GCDvs { self.showVS() }
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
    
    //MARK: Take Photo GCD
    func takePhoto() {
        self.photoDispatchGroup.enter()
        self.GCDphoto = false
        self.GCDphotoFT = self.start.timeIntervalSinceNow * -1
        self.camController.startShootPhoto()
        self.photoDispatchGroup.wait()
    }
    
    //MARK: Add Key Listener
    private func addKeys() {
        //MARK: Location Listener
        if let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation)  {
            DJISDKManager.keyManager()?.startListeningForChanges(on: locationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    let newLocationValue = newValue!.value as! CLLocation

                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.aircraftLocation = newLocationValue.coordinate
                        let gps = GPS()
                        
                        self.aircraftAnnotation.coordinate = newLocationValue.coordinate
                        
                        if !self.GCDvs {
                            let distance = gps.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
                            let bearing = gps.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
                            self.distanceLabel.text = String((distance*10).rounded()/10) + " m"
                            self.bearingLabel.text = String((bearing*10).rounded()/10) + " m"
                        }
                    }
                }
            }
            //MARK: Focus on MapView
            DJISDKManager.keyManager()?.getValueFor(locationKey, withCompletion: { (value:DJIKeyedValue?, error:Error?) in
                if value != nil {
                    let newLocationValue = value!.value as! CLLocation
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.aircraftLocation = newLocationValue.coordinate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            let viewRegion = MKCoordinateRegion(center: self.aircraftLocation, latitudinalMeters: 200, longitudinalMeters: 200)
                            self.mapView.setRegion(viewRegion, animated: true)
                            self.mapView.setNeedsDisplay()
                        }
                    }
                }
            })
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
        
        if let aircraftHeadingKey = DJIFlightControllerKey(param: DJIFlightControllerParamCompassHeading) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: aircraftHeadingKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if (newValue != nil) {
                    self.aircraftAnnotation.heading = newValue!.doubleValue
                    if (self.aircraftAnnotationView != nil) {
                        self.aircraftAnnotationView.transform = CGAffineTransform(rotationAngle: CGFloat(self.degreesToRadians(Double(self.aircraftAnnotation.heading))))
                    }
                }
            }
        }
        
        //MARK: Gimbal Attitude Listener
        if let gimbalAttitudeKey = DJIGimbalKey(param: DJIGimbalParamAttitudeInDegrees) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: gimbalAttitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    var gimbalAttitude = DJIGimbalAttitude() // Float in degrees

                    let nsvalue = newValue!.value as! NSValue
                    nsvalue.getValue(&gimbalAttitude)
                    self.gimbalPitchLabel.text = String((gimbalAttitude.pitch*10).rounded()/10) + " °"
                    self.gimbalPitch = Double(gimbalAttitude.pitch)
                }
            })
        }
        
        //MARK: Altitude Listener
        if let altitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAltitudeInMeters) {
           DJISDKManager.keyManager()?.startListeningForChanges(on: altitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if (newValue != nil) {
                    self.altitudeLabel.text = String((newValue!.doubleValue*10).rounded()/10) + " m"
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
                        self.homeAnnotation.coordinate = newLocationValue.coordinate
                    }
                }
            }
        }
        
        //MARK: SD Card Count Listener
        if let sdCountKey = DJICameraKey(param: DJICameraParamSDCardAvailablePhotoCount) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: sdCountKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    self.missionButton.setTitle("Photo count \(self.photoCount)", for: .normal)
                }
            })
        }
    }
        
    //MARK: Show Virtual Stick Move Action
    func showVS() {
        // let time = self.start.timeIntervalSinceNow * -1 - self.GCDvsFT // for timeout GCD
        let bearing = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        let distance = self.GPSController.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        
        self.bearingLabel.text = String((bearing*10).rounded()/10) + " m"
        self.distanceLabel.text = String((distance*10).rounded()/10) + " m"
        
        // Slow down the aircraft
        if distance <= Double(self.vsSpeed) {
            self.vsSpeed = Float(distance / 2)
            if distance < 2 {
                print("Close, slow speed \((self.vsSpeed*10).rounded()/10)m/s distance to target \((distance*10).rounded()/10)m")
            }
        } else {
            print("Move, distance to target \((distance*10).rounded()/10)m speed \((self.vsSpeed*10).rounded()/10)m/s")
        }
        
        // Turn heading
        if self.aircraftHeading != bearing {
            self.vsTargetBearing = bearing
            if self.aircraftHeading - bearing > 1 {
                print("Move correct heading \((self.aircraftHeading*10).rounded()/10) \(Int(self.vsTargetBearing))")
            }
        }
        
        // Move to the target altitude
        if self.aircraftAltitude - self.vsTargetAltitude > 1 {
            print("Move vertical \(Int(self.aircraftAltitude)) target [\(Int(self.vsTargetAltitude))")
        }
        
        // Virtual Stick send command
        self.vsController.vsMove(pitch: 0, roll: self.vsSpeed, yaw: Float(self.vsTargetBearing), vertical: Float(self.vsTargetAltitude))
        
        // We reach the waypoint
        if distance < 1.1 && self.aircraftAltitude - self.vsTargetAltitude < 1.1 {
            self.GCDvs = true
            print("VS Mission step complete")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.aircraftDispatchGroup.leave()
            }
        }
    }
    
    //MARK: Show Aircraft Yaw Action
    func showAircraftYaw() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDaircraftFT
        if !self.GCDaircraft && time > 0.9 {
            var diff: Double = abs(self.self.aircraftHeading - self.targetAircraftYaw)
            if diff >= 180 { diff = abs(diff - 360) }
            if diff < 2 { // 1.5° - 3°
                print("Aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.GCDaircraft = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.aircraftDispatchGroup.leave()
                }
            } else {
                print("Wait on aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.vsController.vsYaw(yaw: Float(self.targetAircraftYaw)) // repeat between 5 and 20Hz perfect with the listener
            }
            // Timeout call
            if time > 5 && !self.GCDaircraft {
                self.aircraftDispatchGroup.leave()
                self.GCDaircraft = true
                print("Timeout on aircraft yaw!")
            }
        }
    }
    
    //MARK: Show Gimbal Yaw Action
    func showGimbal() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDgimbalFT
        if !self.GCDgimbal && time > 0.9 {
            let pitchDiff = abs(self.gimbalPitch - self.targetGimbalPitch)
            if pitchDiff < 2 { //  1.5° - 3°
                print("Gimbal pitch \((pitchDiff*10).rounded()/10) heading \((self.aircraftHeading*10).rounded()/10)")
                self.GCDgimbal = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.gimbalDispatchGroup.leave()
                }
            } else {
                print("Wait on gimbal pitch \(self.gimbalPitch) timeout \((time*10).rounded()/10)")
            }
            // Timeout call
            if time > 2 {
                self.GCDgimbal = true
                self.gimbalDispatchGroup.leave()
                print("Timeout on gimbal yaw!")
            }
        }
    }
    
    //MARK: Show Photo Action
    func showPhoto() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDphotoFT
        if !self.GCDphoto && time > 0.9 {
            print("Photo finished \(self.camController.getSDPhotoCount()) \(self.sdCardCount) \(time)")
            if time > 3 || self.sdCardCount - self.camController.getSDPhotoCount() > 0 {
                self.GCDphoto = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 ) {
                    self.photoDispatchGroup.leave() // send closure
                }
            }
        }
    }
    
    func stopVS() {
        if !self.GCDphoto { self.photoDispatchGroup.leave(); self.GCDphoto = false }
        if !self.GCDgimbal { self.gimbalDispatchGroup.leave(); self.GCDgimbal = false }
        if !self.GCDaircraft { self.aircraftDispatchGroup.leave(); self.GCDaircraft = false }
        if !self.GCDvs { self.aircraftDispatchGroup.leave(); self.GCDvs = false }
        if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
        if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
        self.GCDProcess = false
        if self.timer != nil { self.timer?.invalidate() }
    }
    
    //MARK: Start 2D Virtual Stick Mission
    func startVSLinearNow() {
        var grid: Array = [[Double]]()
        let distance: Double = 50
        let speed: Float = min(Float(distance) / 7, 4)
        self.vsSpeed = speed
        let aircraftLocationStart:CLLocationCoordinate2D = self.aircraftLocation
        let altitude: Double = max(self.aircraftAltitude, 10)
        let pitch: Double = -90
        let offset: Double = 0.00000899321605956683 * distance // 10m 0.00000899321605956683

        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(updateGCD), userInfo: nil, repeats: true)
        self.sdCardCount = self.camController.getSDPhotoCount()
        self.photoCount = 0
        self.GCDvs = true
        self.GCDProcess = true
        
        if !self.vsController.isVirtualStick() { self.vsController.startVirtualStick() }
        if !self.vsController.isVirtualStickAdvanced() { self.vsController.startAdvancedVirtualStick() }
        
        self.deleteAnnotations()
        self.camController.setCameraMode(cameraMode: .shootPhoto)
        self.camController.setShootMode(shootMode: .single)
        self.missionButton.setTitleColor(UIColor.red, for: .normal)
        
        grid = [[aircraftLocationStart.latitude + offset / 4, aircraftLocationStart.longitude + offset / 2, altitude, pitch, 1],
                [aircraftLocationStart.latitude + offset / 4, aircraftLocationStart.longitude - offset / 2, altitude, pitch, 1],
                [aircraftLocationStart.latitude - offset / 4, aircraftLocationStart.longitude - offset / 2, altitude, pitch, 1],
                [aircraftLocationStart.latitude - offset / 4, aircraftLocationStart.longitude + offset / 2, altitude, pitch, 1],
                [aircraftLocationStart.latitude, aircraftLocationStart.longitude, altitude, pitch, 1]]
        
        self.addWaypoints(grid: grid)
        
        self.queue.asyncAfter(deadline: .now() + 1.0) {
            self.targetGimbalPitch = -90
            self.moveGimbal()
            
            for mP in grid {
                let index = grid.firstIndex(of: mP) ?? 0
                if index >= 0 { // Later for multiple flights
                    let lat = mP[0]
                    let lon = mP[1]
                    let alt = mP[2]
                    let pitch = mP[3]
                    let action = mP[4] // 1 single photo, 2 AEB3 photo, 3 AEB5 photo, 4 hyperlight
                    // let curve = mP[5]
                    // let POIlat = mP[6]
                    // let POIlon = mP[7]
                    
                    
                    if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
        
                        self.vsTargetLocation.latitude = lat
                        self.vsTargetLocation.longitude = lon
                        self.vsTargetAltitude = alt
                        self.targetGimbalPitch = pitch
                        
                        self.moveGimbal()
                        
                        let bearing:Float = Float(self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2:self.vsTargetLocation))
                        
                        if abs(Float(self.aircraftHeading) - bearing) > 14 {
                            self.targetAircraftYaw = Double(bearing)
                            self.yawAircraft()
                        }
                        
                        print("VS move")
                        self.vsSpeed = speed
                        self.moveAircraft()
                        if self.GCDProcess == false { break }
                        
                        if index < grid.count - 1 && action == 1 {
                            print("Photo \(index) \(grid.count)")
                            self.photoCount += 1
                            self.takePhoto()
                            self.sdCardCount = self.camController.getSDPhotoCount()
                            if self.GCDProcess == false { break }
                        }
                    
                    }
                }
            }
            
            print("Stop VS")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.stopVS()
                self.missionButton.setTitleColor(UIColor.white, for: .normal)
                self.missionButton.setTitle("GPS Fly VS Mission", for: .normal)
            }
        }
    }
    
    func degreesToRadians(_ degrees: Double) -> Double {
        return Double.pi / 180 * degrees
    }
    
    // MARK: MKMapViewDelegate mixed
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        var image: UIImage!
        var DJI:Bool = false
        
        if annotation.isEqual(self.aircraftAnnotation) {
            image = #imageLiteral(resourceName: "drone")
            DJI = true
        } else if annotation.isEqual(self.homeAnnotation) {
            image = #imageLiteral(resourceName: "navigation_poi_pin")
            DJI = true
        }
        
        if annotation is MKPointAnnotation && !DJI {
            image = #imageLiteral(resourceName: "navigation_poi_pin")
            let identifier = "Annotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView!.canShowCallout = true
            } else {
                annotationView!.annotation = annotation
            }
            
            annotationView?.image = image

            return annotationView
            
        } else {
        
            let imageAnnotation = annotation as! DJIImageAnnotation
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: imageAnnotation.identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: imageAnnotation.identifier)
            }
            
            annotationView?.image = image
            
            if annotation.isEqual(self.aircraftAnnotation) {
                if annotationView != nil {
                    self.aircraftAnnotationView = annotationView!
                }
            }
            
            return annotationView
        }

        
    }
    
    //MARK: Delete Annotations
    func deleteAnnotations() {
        self.mapView?.annotations.forEach {
            if ($0 is MKPointAnnotation) {
                let title: String = $0.title! ?? ""
                if title.lowercased().range(of:"photo") != nil {
                     self.mapView?.removeAnnotation($0)
                }
            }
        }
    }
    
    func addWaypoints(grid: [[Double]]) {
        for mP in grid {
           
            let lat = mP[0]
            let lon = mP[1]
            let alt = mP[2]
            
            if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
                self.waypointAnnotation.coordinate = CLLocationCoordinate2DMake(lat, lon)
                let annotation = MKPointAnnotation()
                annotation.title = "Photo"
                let gps = self.GPSController.coordinateString(lat, lon)
                annotation.subtitle = "\(gps)\n\(alt)m"
                annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                self.mapView?.addAnnotation(annotation)
                NSLog("Add annotation \(gps)")
            }
            
        }
    }
    
}

//MARK: Remote Controller Delegate
extension VirtualSticksViewController: DJIRemoteControllerDelegate {
    func remoteController(_ remoteController: DJIRemoteController, didUpdate  state: DJIRCHardwareState) {
        if self.GCDvs && (state.leftStick.verticalPosition != 0 || state.rightStick.verticalPosition != 0) {
            NSLog("Stop VS")
            self.stopVS()
        }
    }
}
