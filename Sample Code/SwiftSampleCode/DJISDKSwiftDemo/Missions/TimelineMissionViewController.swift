//
//  TimelineMissionViewController.swift
//  SDK Swift Sample
//
//  Created by Arnaud Thiercelin on 3/22/17.
//  Copyright © 2017 DJI. All rights reserved.
//

import UIKit
import DJISDK

enum TimelineElementKind: String {
    case takeOff = "Take Off"
    case goTo = "Go To"
    case goHome = "Go Home"
    case gimbalAttitude = "Gimbal Attitude"
    case singleShootPhoto = "Single Photo"
    case continuousShootPhoto = "Continuous Photo"
    case recordVideoDuration = "Record Duration"
    case recordVideoStart = "Start Record"
    case recordVideoStop = "Stop Record"
    case waypointMission = "Waypoint Mission"
    case hotpointMission = "Hotpoint Mission"
    case aircraftYaw = "Aircraft Yaw"
}

class TimelineMissionViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, MKMapViewDelegate {

    @IBOutlet weak var availableElementsView: UICollectionView!
    var availableElements = [TimelineElementKind]()
    
    @IBOutlet weak var simulatorSwitch: UISwitch!
    @IBOutlet weak var mapView: MKMapView!
    
    var homeAnnotation = DJIImageAnnotation(identifier: "homeAnnotation")
    var aircraftAnnotation = DJIImageAnnotation(identifier: "aircraftAnnotation")
    var aircraftAnnotationView: MKAnnotationView!
    
    @IBOutlet weak var timelineView: UICollectionView!
    var scheduledElements = [TimelineElementKind]()
    
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    
    fileprivate var _isSimulatorActive: Bool = false
    public var isSimulatorActive: Bool {
        get {
            return _isSimulatorActive
        }
        set {
            _isSimulatorActive = newValue
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.availableElementsView.delegate = self
        self.availableElementsView.dataSource = self
        
        self.timelineView.delegate = self
        self.timelineView.dataSource = self
        
        self.availableElements.append(contentsOf: [.takeOff, .goTo, .goHome, .gimbalAttitude, .singleShootPhoto, .continuousShootPhoto, .recordVideoDuration, .recordVideoStart, .recordVideoStop, .waypointMission, .hotpointMission, .aircraftYaw])
        
        self.mapView.delegate = self
        weak var weakSelf = self
        if let isSimulatorActiveKey = DJIFlightControllerKey(param: DJIFlightControllerParamIsSimulatorActive) {
            let simulatorActiveValue : DJIKeyedValue? = DJISDKManager.keyManager()?.getValueFor(isSimulatorActiveKey)
            if simulatorActiveValue != nil{
                weakSelf?.simulatorSwitch.isOn = (simulatorActiveValue?.boolValue)!
                weakSelf?._isSimulatorActive = (simulatorActiveValue?.boolValue)!
            }
            DJISDKManager.keyManager()?.startListeningForChanges(on: isSimulatorActiveKey, withListener: self, andUpdate: { (oldValue: DJIKeyedValue?, newValue : DJIKeyedValue?) in
                if newValue?.boolValue != nil {
                    weakSelf?._isSimulatorActive = (newValue?.boolValue)!
                    weakSelf?.simulatorSwitch.isOn = (newValue?.boolValue)!
                }
            })
        }
        
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DJISDKManager.missionControl()?.addListener(self, toTimelineProgressWith: { (event: DJIMissionControlTimelineEvent, element: DJIMissionControlTimelineElement?, error: Error?, info: Any?) in
            
            switch event {
            case .started:
                self.didStart()
            case .stopped:
                self.didStop()
            case .paused:
                self.didPause()
            case .resumed:
                self.didResume()
            default:
                break
            }
        })
        
        self.mapView.addAnnotations([self.aircraftAnnotation, self.homeAnnotation])
        
        if let aircarftLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation)  {
            DJISDKManager.keyManager()?.startListeningForChanges(on: aircarftLocationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if newValue != nil {
                    let newLocationValue = newValue!.value as! CLLocation
                    
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.aircraftAnnotation.coordinate = newLocationValue.coordinate
                    }
                }
            }
            DJISDKManager.keyManager()?.getValueFor(aircarftLocationKey, withCompletion: { (value:DJIKeyedValue?, error:Error?) in
                if value != nil {
                    let newLocationValue = value!.value as! CLLocation
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                            self.aircraftAnnotation.coordinate = newLocationValue.coordinate
                        }
                    }
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
        
        if let homeLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamHomeLocation) {
            DJISDKManager.keyManager()?.startListeningForChanges(on: homeLocationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
                if (newValue != nil) {
                    let newLocationValue = newValue!.value as! CLLocation
                    
                    if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
                        self.homeAnnotation.coordinate = newLocationValue.coordinate
                    }
                }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        DJISDKManager.missionControl()?.removeListener(self)
        DJISDKManager.keyManager()?.stopAllListening(ofListeners: self)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: - MKMapViewDelegate
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        var image: UIImage!
        
        if annotation.isEqual(self.aircraftAnnotation) {
            image = #imageLiteral(resourceName: "drone")
        } else if annotation.isEqual(self.homeAnnotation) {
            image = #imageLiteral(resourceName: "navigation_poi_pin")
        }
        
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
    
    fileprivate var started = false
    fileprivate var paused = false
    
    @IBAction func playButtonAction(_ sender: Any) {
        if self.paused {
            DJISDKManager.missionControl()?.resumeTimeline()
        } else if self.started {
            DJISDKManager.missionControl()?.pauseTimeline()
        } else {
            DJISDKManager.missionControl()?.startTimeline()
        }
    }
    
    @IBAction func stopButtonAction(_ sender: Any) {
        DJISDKManager.missionControl()?.stopTimeline()
    }
    
    
    @IBAction func onSimulatorSwitchValueChanged(_ sender: UISwitch) {
        startSimulatorButtonAction()
    }
    
    func startSimulatorButtonAction() {
        //If no gps, the aircrfat location value will be nil.
//        guard let droneLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
//            return
//        }
//        guard let droneLocationValue = DJISDKManager.keyManager()?.getValueFor(droneLocationKey) else {
//            return
//        }
//
//        let droneLocation = droneLocationValue.value as! CLLocation
//        let droneCoordinates = droneLocation.coordinate
        
        weak var weakSelf = self
        let location = CLLocationCoordinate2DMake(22.53, 114);
        if let aircraft = DJISDKManager.product() as? DJIAircraft {
            if _isSimulatorActive {
                aircraft.flightController?.simulator?.stop(completion: nil)
            } else {
                aircraft.flightController?.simulator?.start(withLocation: location,
                                                                      updateFrequency: 30,
                                                                      gpsSatellitesNumber: 12,
                                                                      withCompletion: { (error) in
                    if (error != nil) {
                        weakSelf?.simulatorSwitch.isOn = false
                        DJIAlert.show(title: "", msg: "start simulator failed:" + (error?.localizedDescription)!, fromVC: weakSelf! as UIViewController)
                        NSLog("Start Simulator Error: \(error.debugDescription)")
                    }else{
                        DJIAlert.show(title: "", msg: "start simulator Successful!" , fromVC: weakSelf! as UIViewController)
                                                                        }
                })
            }
        }
    }
    
    func didStart() {
        self.started = true
        DispatchQueue.main.async {
            self.stopButton.isEnabled = true
            self.playButton.setTitle("⏸", for: .normal)
        }
    }
    
    func didPause() {
        self.paused = true
        DispatchQueue.main.async {
            self.playButton.setTitle("▶️", for: .normal)
        }
    }
    
    func didResume() {
        self.paused = false
        DispatchQueue.main.async {
            self.playButton.setTitle("⏸", for: .normal)
        }
    }
    
    func didStop() {
        self.started = false
        DispatchQueue.main.async {
            self.stopButton.isEnabled = false
            self.playButton.setTitle("▶️", for: .normal)
        }
    }
    
    //MARK: OutlineView Delegate & Datasource
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == self.availableElementsView {
            return self.availableElements.count
        } else if collectionView == self.timelineView {
            return self.scheduledElements.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "elementCell", for: indexPath) as! TimelineElementCollectionViewCell
        
        if collectionView == self.availableElementsView {
            cell.label.text = self.availableElements[indexPath.row].rawValue
        } else if collectionView == self.timelineView {
            cell.label.text = self.scheduledElements[indexPath.row].rawValue
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.isEqual(self.availableElementsView) {
            let elementKind = self.availableElements[indexPath.row]
            
            guard let element = self.timelineElementForKind(kind: elementKind) else {
                return;
            }
            let error = DJISDKManager.missionControl()?.scheduleElement(element)
            
            if error != nil {
                NSLog("Error scheduling element \(String(describing: error))")
                return;
            }
            
            self.scheduledElements.append(elementKind)
            DispatchQueue.main.async {
                self.timelineView.reloadData()
            }
        } else if collectionView.isEqual(self.timelineView) {
            if self.started == false {
                DJISDKManager.missionControl()?.unscheduleElement(at: UInt(indexPath.row))
                self.scheduledElements.remove(at: indexPath.row)
                DispatchQueue.main.async {
                    self.timelineView.reloadData()
                }
            }
        }
    }
    
    // MARK : Timeline Element 
    
    func timelineElementForKind(kind: TimelineElementKind) -> DJIMissionControlTimelineElement? {
        switch kind {
            case .takeOff:
                return DJITakeOffAction()
            case .goTo:
                return DJIGoToAction(altitude: 30)
            case .goHome:
                return DJIGoHomeAction()
            case .gimbalAttitude:
                return self.defaultGimbalAttitudeAction()
            case .singleShootPhoto:
                return DJIShootPhotoAction(singleShootPhoto: ())
            case .continuousShootPhoto:
                return DJIShootPhotoAction(photoCount: 10, timeInterval: 3.0, waitUntilFinish: false)
            case .recordVideoDuration:
                return DJIRecordVideoAction(duration: 10)
            case .recordVideoStart:
                return DJIRecordVideoAction(startRecordVideo: ())
            case .recordVideoStop:
                return DJIRecordVideoAction(stopRecordVideo: ())
            case .waypointMission:
                return self.defaultWaypointMission()
            case .hotpointMission:
                return self.defaultHotPointAction()
            case .aircraftYaw:
                return DJIAircraftYawAction(relativeAngle: 36, andAngularVelocity: 30)
        }
    }
    
    
    func defaultGimbalAttitudeAction() -> DJIGimbalAttitudeAction? {
        let attitude = DJIGimbalAttitude(pitch: 30.0, roll: 0.0, yaw: 0.0)
        
        return DJIGimbalAttitudeAction(attitude: attitude)
    }
    
    func defaultWaypointMission() -> DJIWaypointMission? {
        var grid: Array = [[Double]]()
        let mission = DJIMutableWaypointMission()
        mission.maxFlightSpeed = 15
        mission.autoFlightSpeed = 8
        mission.finishedAction = .noAction
        mission.headingMode = .auto
        mission.flightPathMode = .normal
        mission.rotateGimbalPitch = true
        mission.exitMissionOnRCSignalLost = true
        mission.gotoFirstWaypointMode = .pointToPoint
        mission.repeatTimes = 1
        
        guard let droneLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            return nil
        }
        
        guard let droneLocationValue = DJISDKManager.keyManager()?.getValueFor(droneLocationKey) else {
            return nil
        }
        
        let droneLocation = droneLocationValue.value as! CLLocation
        let droneCoordinates = droneLocation.coordinate
        
        if !CLLocationCoordinate2DIsValid(droneCoordinates) {
            return nil
        }
        
        mission.pointOfInterest = droneCoordinates
        let offset = 0.00000899321605956683 * 10 // 10m 0.00000899321605956683
        
        grid = [[droneCoordinates.latitude + offset / 4, droneCoordinates.longitude + offset / 2, 25, 0],
                [droneCoordinates.latitude + offset / 4, droneCoordinates.longitude - offset / 2, 26, -90],
                [droneCoordinates.latitude - offset / 4, droneCoordinates.longitude - offset / 2, 27, 0],
                [droneCoordinates.latitude - offset / 4, droneCoordinates.longitude + offset / 2, 28, -90],
                [droneCoordinates.latitude, droneCoordinates.longitude, 25, 0]]
        
        for mP in grid {
            let index = grid.firstIndex(of: mP) ?? 0
            if index >= 0 { // Later for multiple flights
                let lat = mP[0]
                let lon = mP[1]
                let alt = mP[2]
                let pitch = mP[3]
                
                if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 {
                    
                    let waypoint = DJIWaypoint(coordinate: CLLocationCoordinate2DMake(lat, lon))
                    waypoint.altitude = Float(alt)
                    waypoint.heading = 0
                    waypoint.actionRepeatTimes = 1
                    waypoint.actionTimeoutInSeconds = 60
                    waypoint.cornerRadiusInMeters = 5
                    waypoint.turnMode = .clockwise
                    waypoint.gimbalPitch = Float(pitch)
                    
                    mission.add(waypoint)
                }
            }
        }
        
        return DJIWaypointMission(mission: mission)
    }
    
    func defaultHotPointAction() -> DJIHotpointAction? {
        let mission = DJIHotpointMission()
        
        guard let droneLocationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation) else {
            return nil
        }
        
        guard let droneLocationValue = DJISDKManager.keyManager()?.getValueFor(droneLocationKey) else {
            return nil
        }
        
        let droneLocation = droneLocationValue.value as! CLLocation
        let droneCoordinates = droneLocation.coordinate
        
        if !CLLocationCoordinate2DIsValid(droneCoordinates) {
            return nil
        }

        let offset = 0.0000899322

        mission.hotpoint = CLLocationCoordinate2DMake(droneCoordinates.latitude + offset, droneCoordinates.longitude)
        mission.altitude = 15
        mission.radius = 15
        DJIHotpointMissionOperator.getMaxAngularVelocity(forRadius: Double(mission.radius), withCompletion: {(velocity:Float, error:Error?) in
            mission.angularVelocity = velocity
        })
        mission.startPoint = .nearest
        mission.heading = .alongCircleLookingForward
        
        return DJIHotpointAction(mission: mission, surroundingAngle: 180)
    }
    
    // MARK: - Convenience
    
    func degreesToRadians(_ degrees: Double) -> Double {
        return Double.pi / 180 * degrees
    }

}
