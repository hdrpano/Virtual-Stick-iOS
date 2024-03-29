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
    @IBOutlet weak var fpvView: UIView!
    @IBOutlet weak var fpvRatio: NSLayoutConstraint!
    @IBOutlet weak var remainingChargeSlider: UIProgressView!
    @IBOutlet weak var distanceTrigger: UIProgressView!
    
    //MARK: MKMapView
    var homeAnnotation = DJIImageAnnotation(identifier: "homeAnnotation")
    var aircraftAnnotation = DJIImageAnnotation(identifier: "aircraftAnnotation")
    var waypointAnnotation = DJIImageAnnotation(identifier: "waypointAnnotation")
    var aircraftAnnotationView: MKAnnotationView!
    
    var flightController: DJIFlightController?
    var timer: Timer?
    var photoTimer: Timer?
    
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
    var aircraftLocationBefore: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var homeLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var vsTargetLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    var aircraftAltitude: Double = 0
    var aircraftHeading: Double = 0
    var vsTargetAltitude: Double = 0
    var vsTargetAircraftYaw: Double = 0
    var vsTargetGimbalPitch: Double = 0
    var vsTargetGimbalYaw: Double = 0
    var gimbalPitch: Double = 0
    let start = Date()
    var vsSpeed: Float = 0
    var sdCardCount: Int = 0
    var photoCount: Int = 0
    var bracketing: Int = 1
    var nearTargetDistance: Double = 0.5
    var intervall: Bool = false
    var distanceBetweenTwoPhotos: Double = 15
    var triggerDistance: Double = 0
    
    var GPSController = GPS()
    var vsController = VirtualSticksController()
    var camController = CameraController()
    
    var adapter: VideoPreviewerAdapter?
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent;
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.mapView.delegate = self
        
        DJIVideoPreviewer.instance()?.start()
        
        self.adapter = VideoPreviewerAdapter.init()
        self.adapter?.start()
        adapter?.setupFrameControlHandler()

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
                
                // Reset fpv View
                self.camController.setCameraMode(cameraMode: .shootPhoto)
                
                //MARK: ajust fpv view
                switch self.camController.getRatio() {
                case DJICameraPhotoAspectRatio.ratio4_3:
                    fpvRatio.constant = 4/3
                case DJICameraPhotoAspectRatio.ratio3_2:
                    fpvRatio.constant = 3/2
                case DJICameraPhotoAspectRatio.ratio16_9:
                    fpvRatio.constant = 16/9
                default:
                    fpvRatio.constant = 4/3
                }
                
                // Get remaining charge
                self.remainingChargeSlider.setProgress(Float(self.vsController.getChargeRemainingInPercent())/100, animated: false)
                self.missionButton.setTitle("Start Mission", for: .normal)
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.mapView.addAnnotations([self.aircraftAnnotation, self.homeAnnotation])
        self.addKeys()
        DJIVideoPreviewer.instance()?.setView(self.fpvView)
    }
    
    //MARK: View Did Disappear
    override func viewDidDisappear(_ animated: Bool) {
        if self.vsController.isVirtualStick() { self.vsController.stopVirtualStick() }
        if self.vsController.isVirtualStickAdvanced() { self.vsController.stopAdvancedVirtualStick() }
        if self.timer != nil { self.timer?.invalidate() }
    }
    
    @IBAction func startVSMission(_ sender: UIButton) {
        self.timer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(updateGCD), userInfo: nil, repeats: true)
        self.photoTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(distancePhotoTrigger), userInfo: nil, repeats: true)
        self.sdCardCount = self.camController.getSDPhotoCount()
        self.photoCount = 0
        self.GCDProcess = true
        
        if !self.vsController.isVirtualStick() { self.vsController.startVirtualStick() }
        if !self.vsController.isVirtualStickAdvanced() { self.vsController.startAdvancedVirtualStick() }
        
        self.camController.setShootMode(shootMode: .single)
        
        self.deleteAnnotations()
        self.missionButton.setTitleColor(UIColor.red, for: .normal)
        self.missionButton.setTitle("Fly VS Star...", for: .normal)
        self.aircraftLocationBefore = self.aircraftLocation
        self.triggerDistance = 0
        
        let grid = self.GPSController.star(radius: 50, points: 10, latitude: self.aircraftLocation.latitude, longitude: self.aircraftLocation.longitude,
                                           altitude: self.aircraftAltitude, pitch: -90)
        
        self.addWaypoints(grid: grid)
        
        self.startVSStarNow(grid: grid, speed: 4)
    }
    
    @IBAction func intervallSwitchAction(_ sender: UISwitch) {
        self.intervall = sender.isOn
    }
    
    //MARK: GCD Timer Dispatch Management
    @objc func updateGCD() {
        if !self.GCDaircraftYaw  { self.showAircraftYaw() }
        if !self.GCDgimbal  { self.showGimbal() }
        if !self.GCDphoto  { self.showPhoto() }
        if !self.GCDvs { self.showVS() }
    }
    
    //MARK: GCD Timer Dispatch Management
    @objc func distancePhotoTrigger() {
        if self.aircraftLocationBefore.latitude != self.aircraftLocation.latitude || self.aircraftLocationBefore.longitude != self.aircraftLocation.longitude {
            let distance = self.GPSController.getDistanceBetweenTwoPoints(point1: self.aircraftLocationBefore, point2: self.aircraftLocation)
            self.triggerDistance += distance
            self.aircraftLocationBefore = self.aircraftLocation
        }
        
        if self.intervall {self.distanceTrigger.setProgress(Float(self.triggerDistance/self.distanceBetweenTwoPhotos), animated: false)}
        if self.triggerDistance >= self.distanceBetweenTwoPhotos && self.intervall {
            self.triggerDistance = 0
            DispatchQueue.main.async() {
                self.camController.startShootPhoto()
            }
        }
        self.remainingChargeSlider.setProgress(Float(self.vsController.getChargeRemainingInPercent())/100, animated: false)
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
        self.vsController.moveGimbal(pitch: Float(self.vsTargetGimbalPitch), roll: 0, yaw: 0, time: 1, rotationMode: .absoluteAngle)
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
                        self.aircraftAnnotation.coordinate = newLocationValue.coordinate
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
                    self.speedLabel.text = String((self.vsController.velocity() * 10).rounded()/10) + "m/s"
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
            
            DJISDKManager.keyManager()?.getValueFor(homeLocationKey, withCompletion: { (newValue:DJIKeyedValue?, error:Error?) in
                if newValue != nil {
                    let newLocationValue = newValue!.value as! CLLocation
                    
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.homeLocation = newLocationValue.coordinate
                        self.homeAnnotation.coordinate = newLocationValue.coordinate
                    }
                }
            })
        }
        
        //MARK: SD Card Count Listener
        if let sdCountKey = DJICameraKey(param: DJICameraParamSDCardAvailablePhotoCount) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: sdCountKey, withListener: self , andUpdate: { (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    self.photoCount += 1
                    self.missionButton.setTitle("Photo count \(self.photoCount)", for: .normal)
                    if self.intervall {
                        let annotation = DJIImageAnnotation(identifier: "Photo")
                        annotation.title = "Photo"
                        let gps = self.GPSController.coordinateString(self.aircraftLocation.latitude, self.aircraftLocation.longitude)
                        annotation.subtitle = "\(gps)\n\(self.aircraftAltitude)m"
                        annotation.coordinate = self.aircraftLocation
                        self.mapView?.addAnnotation(annotation)
                    }
                }
            })
        }
    }
        
    //MARK: Show Virtual Stick Move Action
    func showVS() {
        var bearing = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        let distance = self.GPSController.getDistanceBetweenTwoPoints(point1: self.aircraftLocation, point2: self.vsTargetLocation)
        
        // Slow down the aircraft when distance to target is close
        if distance <= Double(self.vsSpeed) && distance > self.nearTargetDistance {
            self.vsSpeed = max(Float(distance / 3), 0.2)
            if distance < self.nearTargetDistance * 2 {
                print("Close, slow speed \((self.vsSpeed*10).rounded()/10)m/s distance to target \((distance*10).rounded()/10)m")
            }
        } else {
            print("Move, distance to target \((distance*10).rounded()/10)m speed \((self.vsSpeed*10).rounded()/10)m/s")
        }
        
        // Move to the target altitude, control bearing to target bearing
        if self.aircraftAltitude - self.vsTargetAltitude > self.nearTargetDistance && distance < self.nearTargetDistance {
            bearing = self.vsTargetAircraftYaw
            print("Move vertical \(Int(self.aircraftAltitude)) target [\(Int(self.vsTargetAltitude))")
        }
        
        // Virtual Stick send command
        // Use pitch instead of roll for POI
        self.vsController.vsMove(pitch: 0, roll: self.vsSpeed, yaw: Float(bearing), vertical: Float(self.vsTargetAltitude))
        
        // We reach the waypoint
        if distance < self.nearTargetDistance && self.aircraftAltitude - self.vsTargetAltitude < self.nearTargetDistance {
            self.vsController.vsMove(pitch: 0, roll: 0, yaw: Float(bearing), vertical: Float(self.vsTargetAltitude))
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
        var velocity: Float = 45
        var direction: Double = 1
        if !self.GCDaircraftYaw {
            var diff: Double = abs(self.aircraftHeading - self.vsTargetAircraftYaw)
            if self.GPSController.yawControl(yaw: Float(self.vsTargetAircraftYaw  - self.aircraftHeading)) < 0 {
                direction = -1
            } else {
                direction = 1
            }
            if diff >= 180 { diff = abs(diff - 360) }
            if diff < 2 { // 1.5° - 3°
                print("**** Aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                self.GCDaircraftYaw = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.yawDispatchGroup.leave()
                }
            } else {
                print("**** Wait on aircraft yaw \(Int(diff*10)/10) yaw \(Int(self.aircraftHeading*10)/10) timeout \((time*10).rounded()/10)")
                if diff < 15 {
                    velocity = Float(diff * direction)
                } else {
                    velocity = velocity * Float(direction)
                }
                self.vsController.vsYaw(velocity: velocity)
            }
            // Timeout call on velocity 45°/s
            if time > 360 / 45 + 1 {
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
            let pitchDiff = abs(self.gimbalPitch - self.vsTargetGimbalPitch)
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
        if self.photoTimer != nil { self.photoTimer?.invalidate() }
        self.missionButton.setTitleColor(UIColor.white, for: .normal)
        self.missionButton.setTitle("Start Mission", for: .normal)
    }
    
    //MARK: Start 2D Virtual Stick Mission
    func startVSStarNow(grid: [[Double]], speed: Float = 4) {
        self.vsSpeed = speed
        
        // Trigger the LED lights
        self.vsController.frontLed(frontLEDs: false)
        
        self.queue.asyncAfter(deadline: .now() + 1.0) {

            for mP in grid {
                let lat = mP[0]
                let lon = mP[1]
                let alt = mP[2]
                let pitch = mP[3]
                
                if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
    
                    self.vsTargetLocation.latitude = lat
                    self.vsTargetLocation.longitude = lon
                    self.vsTargetAltitude = alt
                    self.vsTargetGimbalPitch = pitch
                    self.vsTargetAircraftYaw = self.GPSController.getBearingBetweenTwoPoints(point1: self.aircraftLocation, point2:self.vsTargetLocation)
                    self.moveGimbal()
                    
                    if abs(self.aircraftHeading - self.vsTargetAircraftYaw) > 5 {
                        self.yawAircraft()
                        if self.GCDProcess == false { break } // Exit point for dispatch group
                    }
                    
                    self.vsSpeed = speed
                    self.moveAircraft()
                    if self.GCDProcess == false { break } // Exit point for dispatch group
                    
                }
            }
            
            self.vsTargetGimbalPitch = 0
            self.moveGimbal()
            
            // Trigger the LED lights
            self.vsController.frontLed(frontLEDs: true)
            
            print("Stop VS Star")
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
        
        if annotation.isEqual(self.aircraftAnnotation) {
            image = #imageLiteral(resourceName: "drone")
        } else if annotation.isEqual(self.homeAnnotation) {
            image = #imageLiteral(resourceName: "home_point")
        } else {
            image = #imageLiteral(resourceName: "navigation_poi_pin")
        }
        
        let imageAnnotation = annotation as! DJIImageAnnotation
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: imageAnnotation.identifier)

        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: imageAnnotation.identifier)
        }
        
        if imageAnnotation.identifier == "Photo" {
            image = #imageLiteral(resourceName: "camera")
        }
        
        annotationView?.image = image
        
        if annotation.isEqual(self.aircraftAnnotation) {
            if annotationView != nil {
                self.aircraftAnnotationView = annotationView!
            }
        }
        
        return annotationView
        
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
                let annotation = DJIImageAnnotation(identifier: "Waypoint")
                annotation.title = "Waypoint"
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
