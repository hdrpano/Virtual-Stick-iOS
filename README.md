# Virtual Stick Waypoints
We must add 2 listeners for the aircraft location and the aircraft heading

	self.aircraftLocation
	self.aircraftHeading

	if let locationKey = DJIFlightControllerKey(param: DJIFlightControllerParamAircraftLocation)  {
		DJISDKManager.keyManager()?.startListeningForChanges(on: locationKey, withListener: self) { [unowned self] (oldValue: DJIKeyedValue?, newValue: DJIKeyedValue?) in
		if newValue != nil {
		let newLocationValue = newValue!.value as! CLLocation

		if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
			self.aircraftLocation = newLocationValue.coordinate                   
		}
		}
	}
	DJISDKManager.keyManager()?.getValueFor(locationKey, withCompletion: { (value:DJIKeyedValue?, error:Error?) in
	if value != nil {
		let newLocationValue = value!.value as! CLLocation
		if CLLocationCoordinate2DIsValid(newLocationValue.coordinate) {
			self.aircraftLocation = newLocationValue.coordinate
		}
		}
		})
	}

We must add a timer to send continuous commands to the aircraft.
Mission Array like Litchi CVS
The simplified version without actions

	[[Double]]
	[[Waypoint]]
	[[lat,lon,alt,pitch]]

	var grid = [[Double]]

We can add action in the array or read Litchi CSV

	[[lat,lon,alt,pitch, action_type, POIlat, POIlon…]]

We must create the mission in an array before we start it in GCD
# GCD dispatch groups
We create for each GCD action one dispatch group

	 var queue = DispatchQueue(label: "ch.hdrpano.myqueue")
	 var photoDispatchGroup = DispatchGroup()
	 var aircraftDispatchGroup = DispatchGroup()
	 var gimbalDispatchGroup = DispatchGroup()
	 …
# Start virtual stick
When we use virtual stick, the remote controller will be out of service for the pilot. This is dangerous. For this reason, we pack all in async queue to stop the mission at any time we want and to stop virtual stick. We must handle the remaining power of the aircraft too. When the capacity is below 30% we must stop the mission and virtual stick. 

 self.vsController.prepareVirtualStick()
 self.vsController.startVirtualStick()
 self.vsController.startAdvancedVirtualStick()

We start the mission (split for multiple flight possible = battery capacity and DJI Mission limitation)
grid.count() will gives us the number of waypoints.

self.queue.asyncAfter(deadline: .now() + 1.0) {

for mP in grid {
let index = grid.firstIndex(of: mP) ?? 0
if index >= startIndex { // multiple flight index
let lat = mP[0]
let lon = mP[1]
let alt = mP[2]
let pitch = mP[3]

if CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) && alt < 250 && index - startIndex <= 90 {

Now we check the distance and the bearing from the aircraft towards the waypoint. If the aircraft heading points not towards the waypoint we must yaw the aircraft first. With high speed it is dangerous to yaw and fly forward at the same time for low speed aircrafts like the Mini. It will be no problem for a Phantom. 

If abs(aircraftHeading – bearing) > 14 {
	self.vsYaw(yaw: bearing)
}

self.vsMove(roll: speed, pitch: 0, yaw: bearing, vertical: alt)
}
# Speed optimization
We must adapt speed depending on the distance between 2 waypoints. If the distance is for example 10m you cannot use speed = 8m/s. We must start decelerating speed when we approach the next waypoint. To go smooth we need to start deceleration at the speed/2 when we are at the distance of the speed value. We can calculate the maximum speed = distance / 5. The latency of a small drone is too high when we move only in a few seconds. Acceleration <> Deceleration <> Stop.
