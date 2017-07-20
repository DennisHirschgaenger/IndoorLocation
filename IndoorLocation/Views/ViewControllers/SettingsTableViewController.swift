//
//  SettingsTableViewController.swift
//  IndoorLocation
//
//  Created by Dennis Hirschgänger on 29.05.17.
//  Copyright © 2017 Hirschgaenger. All rights reserved.
//

import UIKit

protocol SettingsTableViewControllerDelegate {
    func toggleFloorplanVisible(_ isFloorPlanVisible: Bool)
    func toggleMeasurementsVisible(_ areMeasurementsVisible: Bool)
    func changeFilterType(_ filterType: FilterType)
}

class SettingsTableViewController: UITableViewController, AnchorTableViewCellDelegate, ButtonTableViewCellDelegate, SegmentedControlTableViewCellDelegate, SliderTableViewCellDelegate, SwitchTableViewCellDelegate {
    
    enum SettingsTableViewSection: Int {
        case view = 0
        case calibration
        case filter
    }
    
    enum SliderType: Int {
        case accelerationUncertainty = 0
        case distanceUncertainty
        case processingUncertainty
        case numberOfParticles
    }
    
    enum SwitchType: Int {
        case floorplanVisible = 0
        case measurementsVisible
    }
    
    let tableViewSections = [SettingsTableViewSection.view.rawValue,
                             SettingsTableViewSection.calibration.rawValue,
                             SettingsTableViewSection.filter.rawValue]
    
    let filterSettings = IndoorLocationManager.shared.filterSettings
    var settingsDelegate: SettingsTableViewControllerDelegate?
    
    var calibrationPending = false
    
    //MARK: ViewController lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        let titleLabel = UILabel(frame: CGRect(x: 0, y: 12.5, width: 200, height: 25))
        LabelHelper.setupLabel(titleLabel, withText: "Settings", fontSize: 20, alignment: .center)
        headerView.addSubview(titleLabel)
        tableView.tableHeaderView = headerView
        tableView.bounces = false
        tableView.showsVerticalScrollIndicator = false
        
        tableView.register(AnchorTableViewCell.self, forCellReuseIdentifier: String(describing: AnchorTableViewCell.self))
        tableView.register(ButtonTableViewCell.self, forCellReuseIdentifier: String(describing: ButtonTableViewCell.self))
        tableView.register(SegmentedControlTableViewCell.self, forCellReuseIdentifier: String(describing: SegmentedControlTableViewCell.self))
        tableView.register(SliderTableViewCell.self, forCellReuseIdentifier: String(describing: SliderTableViewCell.self))
        tableView.register(SwitchTableViewCell.self, forCellReuseIdentifier: String(describing: SwitchTableViewCell.self))
        
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        
        // Tap gesture recognizer for dismissing keyboard when touching outside of UITextFields
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGestureRecognizer.cancelsTouchesInView = false
        self.view.addGestureRecognizer(tapGestureRecognizer)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        // Initialize Filter
        switch filterSettings.filterType {
        case .none:
            IndoorLocationManager.shared.filter = BayesianFilter()
        case .kalman:
            guard let initialDistances = IndoorLocationManager.shared.initialDistances else { return }
            IndoorLocationManager.shared.filter = KalmanFilter(distances: initialDistances)
        case .particle:
            guard let initialDistances = IndoorLocationManager.shared.initialDistances else { return }
            IndoorLocationManager.shared.filter = ParticleFilter(distances: initialDistances)
        }
        
        if calibrationPending {
            alertWithTitle("Attention", message: "The specified anchors have not been calibrated. Changes for ranging are only visible after calibration.")
        }
    }

    // MARK: Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return tableViewSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        guard let tableViewSection = SettingsTableViewSection(rawValue: section) else {
            fatalError("Could not retrieve section")
        }
        
        switch tableViewSection {
        case .view:
            return 2
        case .calibration:
            if filterSettings.calibrationModeIsAutomatic {
                return 2
            } else {
                var numAnchorCells = IndoorLocationManager.shared.anchors?.count ?? 0
                if numAnchorCells < 6 {
                    numAnchorCells += 1
                }
                return 2 + numAnchorCells
            }
        case .filter:
            switch filterSettings.filterType {
            case .none:
                return 1
            case .kalman:
                return 4
            case .particle:
                return 5
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell
        
        guard let tableViewSection = SettingsTableViewSection(rawValue: indexPath.section) else {
            fatalError("Could not retrieve section")
        }
        
        switch tableViewSection {
        case .view:
            cell = tableView.dequeueReusableCell(withIdentifier: String(describing: SwitchTableViewCell.self), for: indexPath)
        case .calibration:
            if (indexPath.row == 0) {
                cell = tableView.dequeueReusableCell(withIdentifier: String(describing: SegmentedControlTableViewCell.self), for: indexPath)
            } else if filterSettings.calibrationModeIsAutomatic {
                cell = tableView.dequeueReusableCell(withIdentifier: String(describing: ButtonTableViewCell.self), for: indexPath)
            } else {
                var numAnchorCells = IndoorLocationManager.shared.anchors?.count ?? 0
                if numAnchorCells < 6 {
                    // Add an empty cell if less than 6 anchors are entered
                    numAnchorCells += 1
                }
                if (indexPath.row <= numAnchorCells) {
                    cell = tableView.dequeueReusableCell(withIdentifier: String(describing: AnchorTableViewCell.self), for: indexPath)
                } else {
                    cell = tableView.dequeueReusableCell(withIdentifier: String(describing: ButtonTableViewCell.self), for: indexPath)
                }
            }
        case .filter:
            if (indexPath.row == 0) {
                cell = tableView.dequeueReusableCell(withIdentifier: String(describing: SegmentedControlTableViewCell.self), for: indexPath)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: String(describing: SliderTableViewCell.self), for: indexPath)
            }
        }
        
        configureCell(cell, forIndexPath: indexPath)
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        guard let tableViewSection = SettingsTableViewSection(rawValue: section) else {
            fatalError("Could not retrieve section")
        }
        
        switch tableViewSection {
        case .view:
            return "View"
        case .calibration:
            return "Calibration"
        case .filter:
            return "Filter"
        }
    }
        
    //MARK: SegmentedControlTableViewCellDelegate
    func onSegmentedControlValueChanged(_ sender: UISegmentedControl) {
        
        guard let tableViewSection = SettingsTableViewSection(rawValue: sender.tag) else {
            fatalError("Could not retrieve section")
        }
        
        switch tableViewSection {
        case .calibration:
            filterSettings.calibrationModeIsAutomatic = sender.selectedSegmentIndex == 0
            calibrationPending = true
            tableView.reloadData()
        case .filter:
            filterSettings.filterType = FilterType(rawValue: sender.selectedSegmentIndex) ?? .none
            tableView.reloadData()
            settingsDelegate?.changeFilterType(filterSettings.filterType)
        default:
            break
        }
    }
    
    //MARK: SliderTableViewCellDelegate
    func onSliderValueChanged(_ sender: UISlider) {
        
        guard let sliderType = SliderType(rawValue: sender.tag) else {
            fatalError("Could not retrieve slider type")
        }
        
        switch sliderType {
        case .accelerationUncertainty:
            filterSettings.accelerationUncertainty = Int(sender.value)
        case .distanceUncertainty:
            filterSettings.distanceUncertainty = Int(sender.value)
        case .processingUncertainty:
            filterSettings.processingUncertainty = Int(sender.value)
        case .numberOfParticles:
            filterSettings.numberOfParticles = Int(sender.value)
        }
    }
    
    //MARK: ButtonTableViewCellDelegate
    func onButtonTapped(_ sender: UIButton) {
        IndoorLocationManager.shared.calibrate()
        calibrationPending = false
    }
    
    //MARK: AnchorTableViewCellDelegate
    func onAddAnchorButtonTapped(_ sender: UIButton, id: Int, x: Int, y: Int) {
        IndoorLocationManager.shared.addAnchorWithID(id, x: x, y: y)
        calibrationPending = true
        tableView.reloadData()
    }
    
    func onRemoveAnchorButtonTapped(_ sender: UIButton, id: Int) {
        IndoorLocationManager.shared.removeAnchorWithID(id)
        calibrationPending = true
        tableView.reloadData()
    }
    
    //MARK: SwitchTableViewCellDelegate
    func onSwitchTapped(_ sender: UISwitch) {
        
        guard let switchType = SwitchType(rawValue: sender.tag) else {
            fatalError("Could not retrieve switch type")
        }
        
        switch switchType {
        case .floorplanVisible:
            filterSettings.floorplanVisible = sender.isOn
            settingsDelegate?.toggleFloorplanVisible(sender.isOn)
        case .measurementsVisible:
            filterSettings.measurementsVisible = sender.isOn
            settingsDelegate?.toggleMeasurementsVisible(sender.isOn)
        }
    }
    
    //MARK: Private API
    private func configureCell(_ cell: UITableViewCell, forIndexPath indexPath: IndexPath) {
        
        guard let tableViewSection = SettingsTableViewSection(rawValue: indexPath.section) else {
            fatalError("Could not retrieve section")
        }
        
        switch tableViewSection {
        case .view:
            if let cell = cell as? SwitchTableViewCell {
                switch indexPath.row {
                case 0:
                    cell.setupWithText("Floorplan", isOn: filterSettings.floorplanVisible, delegate: self, tag: SwitchType.floorplanVisible.rawValue)
                case 1:
                    cell.setupWithText("Measurements", isOn: filterSettings.measurementsVisible, delegate: self, tag: SwitchType.measurementsVisible.rawValue)
                default:
                    break
                }
            }
            
        case .calibration:
            if let cell = cell as? SegmentedControlTableViewCell {
                let selectedSegmentIndex = filterSettings.calibrationModeIsAutomatic ? 0 : 1
                
                cell.setupWithSegments(["Automatic", "Manual"], selectedSegmentIndex: selectedSegmentIndex, delegate: self, tag: tableViewSection.rawValue)
            } else if let cell = cell as? ButtonTableViewCell {
                cell.setupWithText("Calibrate!", delegate: self)
            } else if let cell = cell as? AnchorTableViewCell {
                if let anchors = IndoorLocationManager.shared.anchors {
                    let index = indexPath.row - 1
                    if index < anchors.count {
                        cell.setupWithDelegate(self, anchor: anchors[index])
                    } else {
                        cell.setupWithDelegate(self)
                    }
                } else {
                    cell.setupWithDelegate(self)
                }
            }
            
        case .filter:
            if let cell = cell as? SegmentedControlTableViewCell {
                let selectedSegmentIndex = filterSettings.filterType.rawValue
                
                cell.setupWithSegments(["None", "Kalman", "Particle"], selectedSegmentIndex: selectedSegmentIndex, delegate: self, tag: tableViewSection.rawValue)
            } else if let cell = cell as? SliderTableViewCell {
                switch filterSettings.filterType {
                case .kalman:
                    switch indexPath.row {
                    case 1:
                        cell.setupWithValue(filterSettings.accelerationUncertainty, minValue: 1, maxValue: 100, text: "Acc. uncertainty:", delegate: self, tag: SliderType.accelerationUncertainty.rawValue)
                    case 2:
                        cell.setupWithValue(filterSettings.distanceUncertainty, minValue: 1, maxValue: 100, text: "Dist. uncertainty:", delegate: self, tag: SliderType.distanceUncertainty.rawValue)
                    case 3:
                        cell.setupWithValue(filterSettings.processingUncertainty, minValue: 0, maxValue: 100, text: "Proc. uncertainty:", delegate: self, tag: SliderType.processingUncertainty.rawValue)
                    default:
                        break
                    }
                case .particle:
                    switch indexPath.row {
                    case 1:
                        cell.setupWithValue(filterSettings.accelerationUncertainty, minValue: 1, maxValue: 100, text: "Acc. uncertainty:", delegate: self, tag: SliderType.accelerationUncertainty.rawValue)
                    case 2:
                        cell.setupWithValue(filterSettings.distanceUncertainty, minValue: 1, maxValue: 100, text: "Dist. uncertainty:", delegate: self, tag: SliderType.distanceUncertainty.rawValue)
                    case 3:
                        cell.setupWithValue(filterSettings.processingUncertainty, minValue: 0, maxValue: 100, text: "Proc. uncertainty:", delegate: self, tag: SliderType.processingUncertainty.rawValue)
                    case 4:
                        cell.setupWithValue(filterSettings.numberOfParticles, minValue: 1, maxValue: 1000, text: "Particles:", delegate: self, tag: SliderType.numberOfParticles.rawValue)
                    default:
                        break
                        
                    }
                default:
                    break
                }
            }
        }
    }
    
    func dismissKeyboard() {
        self.view.endEditing(true)
    }
}
