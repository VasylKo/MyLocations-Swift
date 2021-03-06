//
//  FirstViewController.swift
//  MyLocations
//
//  Created by Vasyl Kotsiuba on 1/5/16.
//  Copyright © 2016 Vasiliy Kotsiuba. All rights reserved.
//

import UIKit
import CoreLocation
import CoreData
import QuartzCore //for Core Animation
import AudioToolbox //for audio playing

class CurrentLocationViewController: UIViewController, CLLocationManagerDelegate {

  //MARK: - Outlets
  @IBOutlet weak var messageLabel: UILabel!
  @IBOutlet weak var latitudeLabel: UILabel!
  @IBOutlet weak var longitudeLabel: UILabel!
  @IBOutlet weak var addressLabel: UILabel!
  @IBOutlet weak var tagButton: UIButton!
  @IBOutlet weak var getButton: UIButton!
  @IBOutlet weak var latitudeTextLabel: UILabel!
  @IBOutlet weak var longitudeTextLabel: UILabel!
  @IBOutlet weak var containerView: UIView!
  
  //MARK: - Ivars
  let locationManager = CLLocationManager()
  var location: CLLocation?
  var updatingLocation = false
  var lastLocationError: NSError?
  
  let geocoder = CLGeocoder()
  var placemark: CLPlacemark?
  var performingReverseGeocoding = false
  var lastGeocodingError: NSError?
  var timer: NSTimer?
  var managedObjectContext: NSManagedObjectContext!
  var logoVisible = false
  lazy var logoButton: UIButton = {
    let button = UIButton(type: .Custom)
    button.setBackgroundImage(UIImage(named: "Logo"), forState: .Normal)
    button.sizeToFit()
    button.addTarget(self, action: Selector("getLocation"), forControlEvents: .TouchUpInside)
    button.center.x = CGRectGetMidX(self.view.bounds)
    button.center.y = 220
    return button
  }()
  var soundID: SystemSoundID = 0
  
  //MARK: - View life cycle
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    updateLabels()
    configureGetButton()
    
    //Load sound
    loadSoundEffect("Sound.caf")
  }

  //MARK: - Actions
  @IBAction func getLocation() {
    let authStatus = CLLocationManager.authorizationStatus()
    if authStatus == .NotDetermined {
      locationManager.requestWhenInUseAuthorization()
      return
    }
    
    if authStatus == .Denied || authStatus == .Restricted {
      showLocationServicesDeniedAlert()
      return
    }
    
    if logoVisible { hideLogoView()
    }
    
    if updatingLocation {
      stopLocationManager()
    } else {
      location = nil
      lastLocationError = nil
      placemark = nil
      lastGeocodingError = nil
      startLocationManager()
    }
    
    updateLabels()
    configureGetButton()
  }
  
  //MARK: - UI staff
  func updateLabels() {
    if let location = location {
      latitudeLabel.text = String(format: "%.8f", location.coordinate.latitude)
      longitudeLabel.text = String(format: "%.8f", location.coordinate.longitude)
      tagButton.hidden = false
      messageLabel.text = ""
      
      //Handel adress label
      if let placemark = placemark {
        addressLabel.text = stringFromPlacemark(placemark)
      } else if performingReverseGeocoding {
         addressLabel.text = "Searching for Address..."
      } else if lastGeocodingError != nil {
        addressLabel.text = "Error Finding Adress"
      } else {
        addressLabel.text = "No Address Found"
      }
      
      latitudeTextLabel.hidden = false
      longitudeTextLabel.hidden = false
    } else {
      latitudeLabel.text = ""
      longitudeLabel.text = ""
      tagButton.hidden = true
      
      let statusMessage: String
      if let error = lastLocationError {
        if error.domain == kCLErrorDomain && error.code == CLError.Denied.rawValue {
          statusMessage = "Location Services Disabled"
        } else {
          statusMessage = "Error Getting Location"
        }
      } else if !CLLocationManager.locationServicesEnabled() {
        statusMessage = "Location Services Disabled"
      } else if updatingLocation {
        statusMessage = "Searching..."
      } else {
        statusMessage = ""
        showLogoView()
      }
      
      messageLabel.text = statusMessage
      
      latitudeTextLabel.hidden = true
      longitudeTextLabel.hidden = true
    }
    
  }
  
  func configureGetButton() {
    let spinnerTag = 1000
    
    if updatingLocation {
      getButton.setTitle("Stop", forState: .Normal)
      
      if view.viewWithTag(spinnerTag) == nil {
        let spinner = UIActivityIndicatorView(activityIndicatorStyle: .White)
        spinner.center = messageLabel.center
        spinner.center.y += spinner.bounds.size.height / 2 + 15
        spinner.startAnimating()
        spinner.tag = spinnerTag
        containerView.addSubview(spinner)
      }
    } else {
      getButton.setTitle("Get My Location", forState: .Normal)
      
      if let spinner = view.viewWithTag(spinnerTag) {
        spinner.removeFromSuperview()
      }
    }
  }
  
  // MARK: - Logo View
  func showLogoView() {
    if !logoVisible {
      logoVisible = true
      containerView.hidden = true
      view.addSubview(logoButton)
    }
  }
  
  func hideLogoView() {
    if !logoVisible { return }
    
    logoVisible = false
    containerView.hidden = false
    containerView.center.x = view.bounds.size.width * 2
    containerView.center.y = 40 + containerView.bounds.size.height / 2
    
    let centerX = CGRectGetMidX(view.bounds)
    
    let panelMover = CABasicAnimation(keyPath: "position")
    panelMover.removedOnCompletion = false
    panelMover.fillMode = kCAFillModeForwards
    panelMover.duration = 0.6
    panelMover.fromValue = NSValue(CGPoint: containerView.center)
    panelMover.toValue = NSValue(CGPoint: CGPoint(x: centerX, y: containerView.center.y))
    panelMover.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
    panelMover.delegate = self
    
    containerView.layer.addAnimation(panelMover, forKey: "panelMover")
    
    let logoMover = CABasicAnimation(keyPath: "position")
    logoMover.removedOnCompletion = false
    logoMover.fillMode = kCAFillModeForwards
    logoMover.duration = 0.5
    logoMover.fromValue = NSValue(CGPoint: logoButton.center)
    logoMover.toValue = NSValue(CGPoint: CGPoint(x: -centerX, y: logoButton.center.y))
    logoMover.timingFunction = CAMediaTimingFunction( name: kCAMediaTimingFunctionEaseIn)
    
    logoButton.layer.addAnimation(logoMover, forKey: "logoMover")
    
    
    let logoRotator = CABasicAnimation(keyPath: "transform.rotation.z")
    logoRotator.removedOnCompletion = false
    logoRotator.fillMode = kCAFillModeForwards
    logoRotator.duration = 0.5
    logoRotator.fromValue = 0.0
    logoRotator.toValue = -2 * M_PI
    logoRotator.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
    
    logoButton.layer.addAnimation(logoRotator, forKey: "logoRotator")
  }
  
  override func animationDidStop(anim: CAAnimation, finished flag: Bool) {
      containerView.layer.removeAllAnimations()
      containerView.center.x = view.bounds.size.width / 2
      containerView.center.y = 40 + containerView.bounds.size.height / 2
      logoButton.layer.removeAllAnimations()
      logoButton.removeFromSuperview()
  }
  
  //MARK: - Geocoding
  func stringFromPlacemark(placemark: CLPlacemark) -> String {
    var line1 = ""
    
    line1.addText(placemark.subThoroughfare)
    line1.addText(placemark.thoroughfare, withSeparator: " ")
    
    var line2 = ""
    line2.addText(placemark.locality)
    line2.addText(placemark.administrativeArea, withSeparator: " ")
    line2.addText(placemark.postalCode, withSeparator: " ")
    
    line1.addText(line2, withSeparator: "\n")
    return line1
  }
  
  //MARK: - Location manager
  func stopLocationManager() {
    if updatingLocation {
      if let timer = timer {
        timer.invalidate()
      }
      locationManager.delegate = nil
      updatingLocation = false
    }
  }
  
  func startLocationManager() {
    if CLLocationManager.locationServicesEnabled() {
      locationManager.delegate = self
      locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
      locationManager.startUpdatingLocation()
      updatingLocation = true
      
      timer = NSTimer.scheduledTimerWithTimeInterval(60, target: self, selector: Selector("didTimeOut"), userInfo: nil, repeats: false)
    }
  }
  
  func showLocationServicesDeniedAlert() {
    let alert = UIAlertController(title: "Location Services Disabled", message: "Please enable location services for this app in Settings.", preferredStyle: .Alert)
    let okAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
    alert.addAction(okAction)
    presentViewController(alert, animated: true, completion: nil)
  }
  
  func didTimeOut() {
    print("*** Time out")
    if location == nil {
      stopLocationManager()
      lastLocationError = NSError(domain: "MyLocationsErrorDomain", code: 1, userInfo: nil)
      updateLabels()
      configureGetButton()
    }
  }
  
  // MARK: - Navigation
  override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    if segue.identifier == "TagLocation" {
      let navigationController = segue.destinationViewController as! UINavigationController
      let controller = navigationController.topViewController as! LocationDetailsViewController
      
      controller.coordinate = location!.coordinate
      controller.placemark = placemark
      controller.managedObjectContext = managedObjectContext
    }
  }
  
  
  // MARK: - CLLocationManagerDelegate
  func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
    print("Location error: \(error.localizedDescription)")
    
    if error.code == CLError.LocationUnknown.rawValue {
      return
    }
    
    lastLocationError = error
    stopLocationManager()
    updateLabels()
    configureGetButton()
  }
  
  func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

    let newLocation = locations.last!
    print("Did update location \(newLocation)")
    
    if newLocation.timestamp.timeIntervalSinceNow < -5 {
      return
    }
    
    if newLocation.horizontalAccuracy < 0 {
      return
    }
      
    var distance = CLLocationDistance(DBL_MAX)
    if let location = location {
    distance = newLocation.distanceFromLocation(location)
    }
      
    if location == nil || location!.horizontalAccuracy > newLocation.horizontalAccuracy {
      lastLocationError = nil
      location = newLocation
      updateLabels()
      
      if newLocation.horizontalAccuracy <= locationManager.desiredAccuracy {
        print("*** We're done")
        stopLocationManager()
        configureGetButton()
      
        if distance > 0 {
          performingReverseGeocoding = false
        }
      }
      
      //Geocoding coordinates
      if !performingReverseGeocoding {
        print("*** Going to geocode")
        
        performingReverseGeocoding = true
        geocoder.reverseGeocodeLocation(newLocation, completionHandler: { (placemarks, error) -> Void in
          print("*** Found placemarks: \(placemarks), error: \(error)")
          self.lastLocationError = error
          if error == nil, let p = placemarks where !p.isEmpty {
            //Play sound effect
            if self.placemark == nil {
              print("FIRST TIME")
              self.playSoundEffect()
            }
            
            self.placemark = p.last!
          } else {
            self.placemark = nil
          }
          
          self.performingReverseGeocoding = false
          self.updateLabels()
          
          })
      }
    //End geocoding
    
    } else if distance < 1.0 { //for cases where location accuracy is less than desired accuracy after more than 10 sec location update
      let timeInterval = newLocation.timestamp.timeIntervalSinceDate(location!.timestamp)
      if timeInterval > 10 {
        print("*** Force done!")
        stopLocationManager()
        updateLabels()
        configureGetButton()
      }
    }
  }
  
  // MARK: - Sound Effect
  func loadSoundEffect(name: String) {
    if let path = NSBundle.mainBundle().pathForResource(name, ofType: nil) {
    
      let fileURL = NSURL.fileURLWithPath(path, isDirectory: false)
      let error = AudioServicesCreateSystemSoundID(fileURL, &soundID)
      if error != kAudioServicesNoError {
        print("Error code \(error) loading sound at path: \(path)")
      }
    }
  }
  
  func unloadSoundEffect() {
    AudioServicesDisposeSystemSoundID(soundID)
    soundID = 0
  }
  
  func playSoundEffect() {
    AudioServicesPlaySystemSound(soundID)
  }
  
  
}

