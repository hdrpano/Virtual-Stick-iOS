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
    @IBOutlet weak var speedLabel: UILabel!
    
    //MARK: MKMapView
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
    var yawDispatchGroup = DispatchGroup()
    var gimbalDispatchGroup = DispatchGroup()
    var GCDaircraftYaw: Bool = true
    var GCDphoto: Bool = true
    var GCDgimbal: Bool = true
    var GCDvs: Bool = true
    var GCDProcess: Bool = false
    var GCDaircraftYawFT: Double = 0
    var GCDgimbalFT: Double = 0
    var GCDvsFT: Double = 0
    var GCDphotoFT: Double = 0
    
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
    var vsSpeed: Float = 0
    var sdCardCount: Int = 0
    var photoCount: Int = 0
    var bracketing: Int = 1
    var nearTargetDistance: Double = 0.5
    
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
            
            // Debug Virtual Stick if it still on
            if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
            if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
            
            // Grab a reference to the flight controller
            if let fc = aircraft.flightController {
                
                // Store the flightController
                self.flightController = fc
                
                // Stop Virtual Stick if somebody touches the sticks
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
        if !self.GCDaircraftYaw  { self.showAircraftYaw() }
        if !self.GCDgimbal  { self.showGimbal() }
        if !self.GCDphoto  { self.showPhoto() }
        if !self.GCDvs { self.showVS() }
    }
    
    //MARK: Virtual Stick Yaw Aircraft
    func yawAircraft() {
        self.yawDispatchGroup.enter()
        self.GCDaircraftYaw = false
        self.GCDaircraftYawFT = self.start.timeIntervalSinceNow * -1
        self.yawDispatchGroup.wait()
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
                            if distance < 1000 {self.distanceLabel.text = String((distance*10).rounded()/10) + "m"}
                            self.bearingLabel.text = String((bearing*10).rounded()/10) + " °"
                            if self.vsSpeed != 0 {self.speedLabel.text = String((self.vsSpeed*10).rounded()/10) + "m/s"}
                            
                            let viewRegion = MKCoordinateRegion(center: self.aircraftLocation, latitudinalMeters: 100, longitudinalMeters: 100)
                            self.mapView.setRegion(viewRegion, animated: true)
                            self.mapView.setNeedsDisplay()
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
                    self.xLabel.text = String((Vector.x*10).rounded()/10) + "°"
                    self.yLabel.text = String((Vector.y*10).rounded()/10) + "°"
                    self.zLabel.text = String((Vector.z*10).rounded()/10) + "°"
                    self.aircraftHeading = Vector.z
                    self.aircraftAnnotation.heading = Vector.z
                    if (self.aircraftAnnotationView != nil) {
                        self.aircraftAnnotationView.transform = CGAffineTransform(rotationAngle: CGFloat(self.degreesToRadians(Double(self.aircraftAnnotation.heading))))
                    }
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
                    self.gimbalPitchLabel.text = String((gimbalAttitude.pitch*10).rounded()/10) + "°"
                    self.gimbalPitch = Double(gimbalAttitude.pitch)
                }
            })
        }
        
        //MARK: Altitude Listener
        if let altitudeKey = DJIFlightControllerKey(param: DJIFlightControllerParamAltitudeInMeters) {
           DJISDKManager.keyManager()?.startListeningForChanges(on: altitudeKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if (newValue != nil) {
                    self.altitudeLabel.text = String((newValue!.doubleValue*10).rounded()/10) + "m"
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
                    self.photoCount += 1
                    self.missionButton.setTitle("Photo count \(self.photoCount)", for: .normal)
                }
            })
        }
    }
        
    //MARK: Show Virtual Stick Move Action
    func showVS() {
        let bearing = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        let distance = self.GPSController.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        
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
            if abs(self.aircraftHeading - bearing) > 1 {
                print("Move correct heading \((self.aircraftHeading*10).rounded()/10) \(Int(self.vsTargetBearing))")
            }
        }
        
        // Move to the target altitude
        if self.aircraftAltitude - self.vsTargetAltitude > self.nearTargetDistance {
            print("Move vertical \(Int(self.aircraftAltitude)) target [\(Int(self.vsTargetAltitude))")
        }
        
        // Virtual Stick send command
        self.vsController.vsMove(pitch: 0, roll: self.vsSpeed, yaw: Float(self.vsTargetBearing), vertical: Float(self.vsTargetAltitude))
        
        // We reach the waypoint
        if distance < self.nearTargetDistance && self.aircraftAltitude - self.vsTargetAltitude < self.nearTargetDistance {
            self.GCDvs = true
            print("VS Mission step complete")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.aircraftDispatchGroup.leave()
            }
        }
    }
    
    //MARK: Show Aircraft Yaw Action
    func showAircraftYaw() {
        let time = self.start.timeIntervalSinceNow * -1 - self.GCDaircraftYawFT
        if !self.GCDaircraftYaw {
            var diff: Double = abs(self.self.aircraftHeading - self.targetAircraftYaw)
            if diff >= 180 { diff = abs(diff - 360) }
            if diff < 2 { // 1.5° - 3°
                print("Aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.GCDaircraftYaw = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.yawDispatchGroup.leave()
                }
            } else {
                print("Wait on aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.vsController.vsYaw(yaw: Float(self.targetAircraftYaw)) // repeat between 5 and 20Hz perfect with the listener
            }
            // Timeout call
            if time > 5 {
                self.GCDaircraftYaw = true
                self.yawDispatchGroup.leave()
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
        self.GCDProcess = false
        self.camController.stopShootPhoto()
        if !self.GCDphoto { self.GCDphoto = true ; self.photoDispatchGroup.leave() }
        if !self.GCDgimbal { self.GCDgimbal = true; self.gimbalDispatchGroup.leave() }
        if !self.GCDaircraftYaw { self.GCDaircraftYaw = true; self.yawDispatchGroup.leave() }
        if !self.GCDvs { self.GCDvs = true; self.aircraftDispatchGroup.leave() }
        if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
        if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
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
        let offsety: Double = 0.00000899321605956683 * distance
        let offsetx: Double = offsety / cos(aircraftLocationStart.latitude * .pi / 180)

        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(updateGCD), userInfo: nil, repeats: true)
        self.sdCardCount = self.camController.getSDPhotoCount()
        self.photoCount = 0
        self.GCDProcess = true
        
        if !self.vsController.isVirtualStick() { self.vsController.startVirtualStick() }
        if !self.vsController.isVirtualStickAdvanced() { self.vsController.startAdvancedVirtualStick() }
        
        self.deleteAnnotations()
        self.camController.setCameraMode(cameraMode: .shootPhoto)
        self.missionButton.setTitleColor(UIColor.red, for: .normal)
        self.missionButton.setTitle("Fly VS Mission...", for: .normal)
        
        // Star Mission array
        grid = [[aircraftLocationStart.latitude + offsety / 2, aircraftLocationStart.longitude + offsetx / 2, altitude + 2, pitch, 1],
                [aircraftLocationStart.latitude + offsety * 1.5, aircraftLocationStart.longitude, altitude + 4, pitch, 1],
                [aircraftLocationStart.latitude + offsety / 2, aircraftLocationStart.longitude - offsetx / 2, altitude + 4, pitch, 1],
                [aircraftLocationStart.latitude, aircraftLocationStart.longitude - offsetx * 1.5, altitude + 4, pitch, 1],
                [aircraftLocationStart.latitude - offsety / 2, aircraftLocationStart.longitude - offsetx / 2, altitude + 6, pitch, 1],
                [aircraftLocationStart.latitude - offsety * 1.5, aircraftLocationStart.longitude, altitude + 4, pitch, 1],
                [aircraftLocationStart.latitude - offsety / 2, aircraftLocationStart.longitude + offsetx / 2, altitude + 8, pitch, 1],
                [aircraftLocationStart.latitude, aircraftLocationStart.longitude + offsetx * 1.5, altitude + 4, pitch, 1],
                [aircraftLocationStart.latitude + offsety / 2, aircraftLocationStart.longitude + offsetx / 2, altitude + 2, pitch, 1],
                [aircraftLocationStart.latitude, aircraftLocationStart.longitude, altitude, 0, 1]]
        
        self.addWaypoints(grid: grid)
        
        // Virtual Stick Missions works with AEB or else
        switch grid[0][4] {
        case 1:
            self.camController.setShootMode(shootMode: .single)
        case 2:
            self.camController.setShootMode(shootMode: .AEB)
        case 3:
            self.camController.setShootMode(shootMode: .hyperLight)
        case 4:
            self.camController.setShootMode(shootMode: .interval)
            self.camController.setTimeIntervall(interval: 2, count: 255)
        default:
            self.camController.setShootMode(shootMode: .single)
        }
            
        self.queue.asyncAfter(deadline: .now() + 1.0) {

            for mP in grid {
                let index = grid.firstIndex(of: mP) ?? 0
                if index >= 0 { // Later for multiple flights
                    let lat = mP[0]
                    let lon = mP[1]
                    let alt = mP[2]
                    let pitch = mP[3]
                    let action = mP[4]
                    // let curve = mP[5]
                    // let POIlat = mP[6]
                    // let POIlon = mP[7]
                    if action == 4 {
                        self.camController.startShootPhoto() // For .intervall photos
                    }
                    
                    if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
        
                        self.vsTargetLocation.latitude = lat
                        self.vsTargetLocation.longitude = lon
                        self.vsTargetAltitude = alt
                        self.targetGimbalPitch = pitch
                        self.targetAircraftYaw = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2:self.vsTargetLocation)
                        
                        self.moveGimbal()
                        if self.GCDProcess == false { break } // Exit point for dispatch group
                        
                        if abs(self.aircraftHeading - self.targetAircraftYaw) > 5 {
                            self.yawAircraft()
                            if self.GCDProcess == false { break } // Exit point for dispatch group
                        }
                        
                        self.vsSpeed = speed
                        self.moveAircraft()
                        if self.GCDProcess == false { break } // Exit point for dispatch group
                        
                        if index < grid.count - 1 && action == 1 {
                            print("Photo \(index) \(grid.count)")
                            self.takePhoto()
                            self.sdCardCount = self.camController.getSDPhotoCount()
                            if self.GCDProcess == false { break } // Exit point for dispatch group
                        }
                    
                    }
                }
            }
            
            print("Stop VS")
            if grid[0][4] == 4 {
                self.camController.stopShootPhoto()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self.GCDProcess { self.stopVS() }
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
            // annotationView?.centerOffset = CGPoint(x: -17.5, y: -17.5)
            
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
    
    //MARK: Add Annotations
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
        if self.GCDProcess && (state.leftStick.verticalPosition != 0 || (state.leftStick.horizontalPosition != 0 || state.rightStick.verticalPosition != 0 || state.rightStick.horizontalPosition != 0) || state.goHomeButton.isClicked.boolValue) {
            NSLog("Stop VS \(state.leftStick) \(state.rightStick)")
            self.missionButton.setTitle("VS Remote Interrupt", for: .normal)
            self.stopVS()
        }
    }
}
