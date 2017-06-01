//
//  BayesianFilter.swift
//  IndoorLocation
//
//  Created by Dennis Hirschgänger on 14.04.17.
//  Copyright © 2017 Hirschgaenger. All rights reserved.
//

import Accelerate

class BayesianFilter {
        
    func predict() {}
    
    func update(measurements: [Double], successCallback: (CGPoint) -> Void) {
        // Least squares algorithm:
        guard let anchors = IndoorLocationManager.shared.anchors else {
            print("Not yet calibrated")
            return
        }
        
        // Drop acceleration measurements
        let distances = Array(measurements.dropLast(2))
        
        // Compute least squares algorithm
        let position = leastSquares(anchors: Array(anchors.values), distances: distances)
        
        successCallback(position)
    }
}
