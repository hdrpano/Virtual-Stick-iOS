//
//  CameraController.swift
//  DJISDKSwiftDemo
//
//  Created by Kilian Eisenegger on 07.12.20.
//  Copyright © 2020 hdrpano. All rights reserved.
//

import DJISDK

class CameraController {
    //MARK: Set Camera Mode
    func setCameraMode(cameraMode: DJICameraMode = .shootPhoto) {
        let camera = self.fetchCamera()
        camera?.setMode(cameraMode, withCompletion: { (error: Error?) in
            if error != nil {
                NSLog("Error set mode photo/video");
            }
        })
    }
    
    //MARK:- Get SD Card Count
    func getSDPhotoCount() -> Int {
        guard let sdCountKey = DJICameraKey(param: DJICameraParamSDCardAvailablePhotoCount) else {
            return 0
        }
        guard let sdCount = DJISDKManager.keyManager()?.getValueFor(sdCountKey) else {
            return 0
        }
        let sdCountValue = sdCount.integerValue
        return sdCountValue
    }
    
    //MARK:- Get Ratio
    func getRatio() -> DJICameraPhotoAspectRatio {
        guard let ratioKey = DJICameraKey(param: DJICameraParamPhotoAspectRatio) else {
            return DJICameraPhotoAspectRatio.ratioUnknown
        }
        guard let ratio = DJISDKManager.keyManager()?.getValueFor(ratioKey) else {
            return DJICameraPhotoAspectRatio.ratioUnknown
        }
        let ratioValue = ratio.intValue
        switch ratioValue {
        case 0:
            return DJICameraPhotoAspectRatio.ratio4_3
        case 1:
            return DJICameraPhotoAspectRatio.ratio16_9
        case 2:
            return DJICameraPhotoAspectRatio.ratio3_2
        default:
            return DJICameraPhotoAspectRatio.ratio4_3
        }
    }
    
    //MARK:- Start Shoot Photo
    func startShootPhoto() {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.startShootPhoto(completion:{ (error: Error?) in
                if error != nil {
                    NSLog("Error shooting photo")
                }
            })
        }
    }
    
    //MARK:- Stop Shoot Photo
    func stopShootPhoto() {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.stopShootPhoto(completion:{ (error: Error?) in
                if error != nil {
                    NSLog("Error stop shooting photo")
                }
            })
        }
    }
    
    //MARK:- Start Record Video
    func startRecordVideo() {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.startRecordVideo(completion:{ (error: Error?) in
                if error != nil {
                    NSLog("Error recording video")
                }
            })
        }
    }
    
    //MARK:- Stop Record Video
    func stopRecordVideo() {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.stopRecordVideo(completion:{ (error: Error?) in
                if error != nil {
                    NSLog("Error stop recording video")
                }
            })
        }
    }
    
    //MARK:- Set Shoot Mode Single AEB ...
    func setShootMode(shootMode: DJICameraShootPhotoMode = .single) {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.setShootPhotoMode(shootMode, withCompletion: { (error: Error?) in
                if error != nil {
                    NSLog("Error set camera shoot mode .single .AEB .panorama .hyperLight");
                }
            })
        }
    }
    
    //MARK:- Set Time Intervall
    func setTimeIntervall(interval: UInt16 = 2, count: UInt8 = 255) {
        let camera = self.fetchCamera()
        var settings = DJICameraPhotoTimeIntervalSettings()
        settings.captureCount = count
        settings.timeIntervalInSeconds = interval
        if camera != nil {
            camera?.setPhotoTimeIntervalSettings(settings, withCompletion: { (error: Error?) in
                if error != nil {
                    NSLog("Error set time interval and count");
                }
            })
        }
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
}
