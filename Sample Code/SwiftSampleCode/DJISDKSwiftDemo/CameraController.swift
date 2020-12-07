//
//  CameraController.swift
//  DJISDKSwiftDemo
//
//  Created by Kilian Eisenegger on 07.12.20.
//  Copyright © 2020 DJI. All rights reserved.
//

import DJISDK

class CameraController {
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
    
    //MARK:- Start Shoot Photo
    func shootPhoto() {
        let camera = self.fetchCamera()
        if camera != nil {
            camera?.startShootPhoto(completion:{ (error: Error?) in
                if error != nil {
                    print("Error shooting photo")
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
