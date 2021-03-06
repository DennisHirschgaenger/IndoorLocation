//
//  IndoorLocationManager.swift
//  IndoorLocation
//
//  Created by Dennis Hirschgänger on 14.04.17.
//  Copyright © 2017 Hirschgaenger. All rights reserved.
//

import Accelerate

/**
 The type of filter that is used.
 ````
 case none
 case kalman
 case particle
 ````
 */
enum FilterType: Int {
    /// No filter. A linear least squares algorithm will be executed
    case none = 0
    
    /// Extended Kalman filter
    case kalman
    
    /// Particle filter
    case particle
}

/**
 The type of particle filter that is used
 ````
 case bootstrap
 case regularized
 ````
 */
enum ParticleFilterType: Int {
    /// Bootstrap filter. Plain SIR algorithm is executed
    case bootstrap = 0
    
    /// Regularized particle filter
    case regularized
}

/// Structure of an anchor having an id, a position and a flag indicating whether it is currently within range.
typealias Anchor = (id: Int, position: CGPoint, isActive: Bool)

/**
 A protocol to be implemented by a ViewController. It informs the delegate about updates for the GUI.
 */
protocol IndoorLocationManagerDelegate {
    func setAnchors(_ anchors: [Anchor])
    func updateActiveAnchors(_ anchors: [Anchor], distances: [Float], acceleration: [Float])
    func updatePosition(_ position: CGPoint)
    func updateCovariance(eigenvalue1: Float, eigenvalue2: Float, angle: Float)
    func updateParticles(_ particles: [Particle])
}

/**
 Class for managing positioning. It interacts with the NetworkManager and the ViewControllers to perform all essential tasks.
 */
class IndoorLocationManager {
    
    static let shared = IndoorLocationManager()
    
    var delegate: IndoorLocationManagerDelegate?
    
    var anchors: [Anchor]?
    var filter: BayesianFilter?
    var filterSettings: FilterSettings
    
    var position: CGPoint?
    var initialDistances: [Float]?
    
    var isCalibrated = false
    var isRanging = false
    
    var beginningOfMeasurement = Date()
    
    private init() {
        filterSettings = FilterSettings()
    }
    
    //MARK: Private API
    /**
     Parse data received from the Arduino.
     - Parameter stringData: Received data as String
     - Throws: In the case of a wrong received format
     - Returns: The received data parsed as dictionary
     */
    private func parseData(_ stringData: String) throws -> [String : Float] {
        
        // Remove carriage return
        guard let inlineStringData = stringData.components(separatedBy: "\r").first else {
            throw NSError(domain: "Error", code: 0, userInfo: [NSLocalizedDescriptionKey : "Received unexpected message from Arduino!"])
        }
        
        // Check that returned data is of expected format
        guard (inlineStringData.range(of: "([A-Za-z]+-?[0-9-]*=-?[0-9.]+&)*([A-Za-z]+-?[0-9.]*=-?[0-9.]+)", options: .regularExpression) == inlineStringData.startIndex..<inlineStringData.endIndex) else {
            throw NSError(domain: "Error", code: 0, userInfo: [NSLocalizedDescriptionKey : "Received unexpected message from Arduino!"])
        }
        
        // Split string at "&" characters
        let splitData = inlineStringData.components(separatedBy: "&")
        
        // Fill the dictionary
        var parsedData = [String : Float]()
        for component in splitData {
            let key = component.components(separatedBy: "=")[0]
            let value = Float(component.components(separatedBy: "=")[1])
            parsedData[key] = value!
        }
        return parsedData
    }
    
    /**
     A function to perform calibration. The calibration data is sent to the Arduino and the response is processed accordingly.
     - Parameter resultCallback: A closure that is called after calibration is completed or an error occurred
     - Parameter error: The error that occurred
     */
    func calibrate(resultCallback: @escaping (_ error: Error?) -> ()) {
        // Generate string of calibration data to send to the arduino.
        guard let anchors = anchors else {
            alertWithTitle("Error", message: "No anchors were specified!")
            return
        }
        var anchorStringData = ""
        for (i, anchor) in anchors.enumerated() {
            // Multiply coordinates by 10 to convert from cm to mm. Also mirror y axis.
            anchorStringData += "ID\(i)=\(anchor.id)&xPos\(i)=\(Int((anchor.position.x) * 10))&yPos\(i)=\(Int((-anchor.position.y) * 10))"
            if (i != anchors.count - 1) {
                anchorStringData += "&"
            }
        }
        
        // Send calibration data to Arduino to calibrate Pozyx tag
        NetworkManager.shared.networkTask(task: .calibrate, data: anchorStringData) { result in
            do {
                switch result {
                    
                case .success(let data):
                    // Process successful response
                    guard let data = data else {
                        throw NSError(domain: "Error", code: 0, userInfo: [NSLocalizedDescriptionKey : "No calibration data received!"])
                    }
                    
                    let stringData = String(data: data, encoding: String.Encoding.utf8)!
                    
                    var anchorDict = try self.parseData(stringData)
                    
                    var anchors = [Anchor]()
                    var distances = [Float]()
                    
                    // Retrieve data from anchorDict. Iterate from 0 to anchorDict.count / 4 because there are 4 values
                    // for every anchor: ID, xPos, yPos, dist
                    for i in 0..<anchorDict.count / 4 {
                        guard let id = anchorDict["ID\(i)"],
                            let xPos = anchorDict["xPos\(i)"],
                            let yPos = anchorDict["yPos\(i)"],
                            let dist = anchorDict["dist\(i)"] else {
                                fatalError("Error retrieving data from anchorDict")
                        }
                        
                        if dist != 0 {
                            // Divide all units by 10 to convert from mm to cm. Also mirror y axis
                            anchors.append(Anchor(id: Int(id), position: CGPoint(x: CGFloat(xPos / 10), y: CGFloat(-yPos / 10)), isActive: true))
                            distances.append(dist / 10)
                        } else {
                            anchors.append(Anchor(id: Int(id), position: CGPoint(x: CGFloat(xPos / 10), y: CGFloat(-yPos / 10)), isActive: false))
                        }
                    }
                    
                    self.anchors = anchors
                    
                    self.delegate?.setAnchors(anchors)
                    
                    self.initialDistances = distances
                    
                    self.isCalibrated = true
                    
                case .failure(let error):
                    throw error
                    
                }
            } catch let error {
                resultCallback(error)
            }
            
            resultCallback(nil)
        }
    }
    
    /**
     Function used to begin ranging on the Arduino.
     - Parameter resultCallback: A closure that is called after beginning to range is successful or an error occurred
     - Parameter error: The error that occurred
     */
    func beginRanging(resultCallback: @escaping (_ error: Error?) -> ()) {
        if isCalibrated {
            NetworkManager.shared.networkTask(task: .beginRanging) { result in
                switch result {
                case .failure(let error):
                    resultCallback(error)
                case .success(_):
                    self.isRanging = true
                    self.beginningOfMeasurement = Date()
                    resultCallback(nil)
                }
            }
        } else {
            let error = NSError(domain: "Error", code: 0, userInfo: [NSLocalizedDescriptionKey : "Calibration has to be executed first!"])
            resultCallback(error)
        }
    }
    
    /**
     Function used to stop ranging on the Arduino.
     - Parameter resultCallback: A closure that is called after stopping to range is successful or an error occurred
     - Parameter error: The error that occurred
     */
    func stopRanging(resultCallback: @escaping (Error?) -> ()) {
        NetworkManager.shared.networkTask(task: .stopRanging) { result in
            switch result {
            case .failure(let error):
                resultCallback(error)
            case .success(_):
                self.isRanging = false
                self.position = nil
                resultCallback(nil)
            }
        }
    }
    
    /**
     A function that is called by the NetworkManager when new measurement data from the Arduino is available. This function
     handles processing of received data, executes the selected filter to determine the position and tells the delegate to
     update the view accordingly.
     - Parameter data: The data that is received from the Arduino
     */
    func newRangingData(_ data: String?) {
        // Only process data if ranging is currently active. Otherwise discard data
        guard isRanging else {
            stopRanging() { _ in }
            return
        }
        
        guard let data = data,
            var anchors = anchors,
            var measurementDict = try? parseData(data) else { return }
        
        // Determine which anchors are active
        var distances = [Float]()
        for i in 0..<anchors.count {
            if let distance = measurementDict["dist\(anchors[i].id)"] {
                // Assume distance measurements are in the range of (0,40m).
                if distance > 0 && distance < 40000 {
                    // Divide distance by 10 to convert from mm to cm.
                    distances.append(distance / 10)
                    anchors[i].isActive = true
                } else {
                    anchors[i].isActive = false
                }
            } else {
                anchors[i].isActive = false
            }
        }
        
        // Check if distance measurements are available
        guard distances.count > 0 else {
            return
        }
        
        var acceleration = [Float]()
        if let xAcc = measurementDict["xAcc"] {
            if abs(xAcc) < 5000 {
                // Multiply acceleration by 0.981 to convert from mG to cm/s^2.
                acceleration.append(xAcc * 0.981)
            } else {
                acceleration.append(0)
            }
        } else {
            acceleration.append(0)
        }
        if let yAcc = measurementDict["yAcc"] {
            if abs(yAcc) < 5000 {
                // Multiply acceleration by 0.981 to convert from mG to cm/s^2.
                acceleration.append(yAcc * 0.981)
                
            } else {
                acceleration.append(0)
            }
        } else {
            acceleration.append(0)
        }
        
        // Execute the algorithm of the selected filter
        if let filter = filter {
            // Execute algorithm of filter
            filter.executeAlgorithm(anchors: anchors.filter({ $0.isActive }), distances: distances, acceleration: acceleration) { position in
                self.processResultWithPosition(position, anchors: anchors, distances: distances, acceleration: acceleration)
            }
        } else {
            // Execute least squares algorithm to determine position
            if let position = linearLeastSquares(anchors: anchors.filter({ $0.isActive }).map { $0.position }, distances: distances) {
                processResultWithPosition(position, anchors: anchors, distances: distances, acceleration: acceleration)
            }
        }
    }

    
    private func processResultWithPosition(_ position: CGPoint, anchors: [Anchor], distances: [Float], acceleration: [Float]) {
//        // Print timestamp, estimated position and acceleration for evaluation
//        let timestamp = Date().timeIntervalSince(self.beginningOfMeasurement)
//        if distances.count == 3 {
//            print("\(timestamp),\(position.x/100),\(position.y/100),\(acceleration[0]),\(acceleration[1]),\(distances[0]),\(distances[1]),\(distances[2]);")
//        } else {
//            print("\(timestamp),\(position.x/100),\(position.y/100),\(acceleration[0]),\(acceleration[1]),0,0,0;")
//        }
        self.position = position
        
        // Inform delegate about UI changes
        self.delegate?.updatePosition(position)
        self.delegate?.updateActiveAnchors(anchors, distances: distances, acceleration: acceleration)
        
        switch (self.filterSettings.filterType) {
        case .kalman:
            guard let filter = self.filter as? ExtendedKalmanFilter else { return }
            let positionCovariance = [filter.P[0], filter.P[1], filter.P[filter.stateDim], filter.P[filter.stateDim + 1]]
            let (eigenvalues, eigenvectors) = positionCovariance.computeEigenvalueDecomposition()
            let angle = atan(eigenvectors[2] / eigenvectors[0])
            self.delegate?.updateCovariance(eigenvalue1: eigenvalues[0], eigenvalue2: eigenvalues[1], angle: angle)
        case .particle:
            guard let filter = self.filter as? ParticleFilter else { return }
            self.delegate?.updateParticles(filter.particles)
        default:
            break
        }
    }
    
    //MARK: Public API
    /**
     Function to add an anchor with specified parameters.
     - Parameter id: ID of the anchor as Int
     - Parameter x: x-Coordinate of the anchor
     - Parameter y: y-Coordinate of the anchor
     */
    func addAnchorWithID(_ id: Int, x: Int, y: Int) {
        if anchors != nil {
            anchors?.append(Anchor(id: id, position: CGPoint(x: x, y: y), isActive: false))
        } else {
            anchors = [Anchor(id: id, position: CGPoint(x: x, y: y), isActive: false)]
        }
    }
    
    /**
     Removes the anchor with the specified ID.
     - Parameter id: The id of the anchor to be removed
     */
    func removeAnchorWithID(_ id: Int) {
        anchors = anchors?.filter({ $0.id != id })
    }
}
