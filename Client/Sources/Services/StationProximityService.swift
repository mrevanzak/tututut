//
//  StationProximityService.swift
//  kreta
//
//  Created by AI Assistant
//

import CoreLocation
import Foundation
import OSLog
import UserNotifications

/// Service that manages location-based notifications for approaching train stations.
/// Creates geofence triggers for the 10 closest stations based on user location.
@MainActor
final class StationProximityService: NSObject, Sendable {
  static let shared = StationProximityService()
  
  private let notificationCenter = UNUserNotificationCenter.current()
  private let locationManager = CLLocationManager()
  private let logger = Logger(subsystem: "kreta", category: "StationProximityService")
  
  // Maximum number of geofence regions iOS supports per app
  private let maxRegions = 10
  
  // Notification radius around each station (in meters)
  private let stationRadius: CLLocationDistance = 1000 // 500 meters
  
  // Notification category identifier
  static let categoryIdentifier = "STATION_PROXIMITY"
  
  private var currentStations: [Station] = []
  private var lastUserLocation: CLLocationCoordinate2D?
  private var hasActiveJourney: Bool = false
  
  private override init() {
    super.init()
    locationManager.delegate = self
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }
  
  // MARK: - Public Interface
  
  /// Request location authorization for proximity monitoring
  func requestLocationAuthorization() {
    let status = locationManager.authorizationStatus
    
    switch status {
    case .notDetermined:
      logger.info("Requesting location authorization for proximity monitoring")
      // First request When In Use
      locationManager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      logger.info("Location authorized when in use, requesting Always for background monitoring")
      // Then request Always for background
      locationManager.requestAlwaysAuthorization()
    case .authorizedAlways:
      logger.info("Location authorization already granted for background: \(status.rawValue)")
    case .denied, .restricted:
      logger.warning("Location authorization denied or restricted")
    @unknown default:
      logger.warning("Unknown location authorization status")
    }
  }
  
  /// Update whether user currently has an active journey
  func updateJourneyStatus(hasActiveJourney: Bool) {
    let wasActive = self.hasActiveJourney
    self.hasActiveJourney = hasActiveJourney
    logger.info("Journey status updated: hasActiveJourney = \(hasActiveJourney)")
    
    // If journey just started, clear proximity notifications and regions IMMEDIATELY
    if hasActiveJourney && !wasActive {
      logger.info("Journey started - clearing proximity notifications and regions")
      
      // Clear regions synchronously - don't wait
      clearMonitoredRegions()
      
      // Clear notifications asynchronously
      Task {
        await clearProximityNotifications()
      }
    }
    // If journey just ended, re-enable proximity notifications
    else if !hasActiveJourney && wasActive {
      logger.info("Journey ended - re-enabling proximity notifications")
      Task {
        if !currentStations.isEmpty, let location = locationManager.location {
          await setupProximityNotifications(
            userLocation: location.coordinate,
            stations: currentStations
          )
        }
      }
    }
  }
  
  /// Register the notification category for station proximity alerts
  func registerNotificationCategory() {
    let category = UNNotificationCategory(
      identifier: Self.categoryIdentifier,
      actions: [],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    
    notificationCenter.getNotificationCategories { existingCategories in
      var categories = existingCategories
      categories.insert(category)
      self.notificationCenter.setNotificationCategories(categories)
      self.logger.info("Registered station proximity notification category")
    }
  }
  
  /// Update proximity triggers based on new station data
  /// - Parameter stations: Array of all available stations
  func updateProximityTriggers(for stations: [Station]) async {
    currentStations = stations
    
    // Don't schedule notifications if user is already tracking a journey
    guard !hasActiveJourney else {
      logger.info("⏭️ Skipping proximity trigger setup - user has active journey")
      // Clear any existing proximity notifications
      await clearProximityNotifications()
      clearMonitoredRegions()
      return
    }
    
    // Check authorization status
    let settings = await notificationCenter.notificationSettings()
    guard settings.authorizationStatus == .authorized else {
      logger.info("Notification authorization not granted, skipping proximity triggers")
      return
    }
    
    // Check location authorization
    let locationStatus = locationManager.authorizationStatus
    guard locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways else {
      logger.info("Location authorization not granted, skipping proximity triggers")
      return
    }
    
    // Request location to get current position
    if let location = locationManager.location {
      await setupProximityNotifications(userLocation: location.coordinate, stations: stations)
    } else {
      // Start location updates to get current position
      locationManager.requestLocation()
    }
  }
  
  /// Refresh proximity triggers when permissions change
  func refreshTriggersIfNeeded() async {
    guard !currentStations.isEmpty else { return }
    
    let settings = await notificationCenter.notificationSettings()
    guard settings.authorizationStatus == .authorized else {
      // Clear all pending proximity notifications
      await clearProximityNotifications()
      return
    }
    
    // Re-setup triggers with current location
    if let location = locationManager.location {
      await setupProximityNotifications(userLocation: location.coordinate, stations: currentStations)
    }
  }
  
  // MARK: - Private Methods
  
  private func setupProximityNotifications(
    userLocation: CLLocationCoordinate2D,
    stations: [Station]
  ) async {
    lastUserLocation = userLocation
    
    // Sort stations by distance from user
    let sortedStations = stations
      .map { station -> (station: Station, distance: CLLocationDistance) in
        let stationLocation = CLLocation(
          latitude: station.position.latitude,
          longitude: station.position.longitude
        )
        let userCLLocation = CLLocation(
          latitude: userLocation.latitude,
          longitude: userLocation.longitude
        )
        let distance = userCLLocation.distance(from: stationLocation)
        return (station, distance)
      }
      .sorted { $0.distance < $1.distance }
      .prefix(maxRegions)
    
    // Clear existing monitored regions
    clearMonitoredRegions()
    
    // Clear existing proximity notifications
    await clearProximityNotifications()
    
    // Start monitoring regions and create notifications for closest stations
    for (station, distance) in sortedStations {
      startMonitoringRegion(for: station)
      await scheduleProximityNotification(for: station, distance: distance)
    }
    
    logger.info("Updated proximity triggers for \(sortedStations.count) closest stations")
    logger.info("Monitoring \(self.locationManager.monitoredRegions.count) regions in background")
  }
  
  private func scheduleProximityNotification(for station: Station, distance: CLLocationDistance) async {
    let center = CLLocationCoordinate2D(
      latitude: station.position.latitude,
      longitude: station.position.longitude
    )
    
    let region = CLCircularRegion(
      center: center,
      radius: stationRadius,
      identifier: "station_\(station.code)"
    )
    region.notifyOnEntry = true
    region.notifyOnExit = false
    
    let trigger = UNLocationNotificationTrigger(
      region: region,
      repeats: false
    )
    
    let content = UNMutableNotificationContent()
    content.title = "Mau naik kereta?"
    content.body = "Yuk, track perjalananmu untuk pengalaman yang lebih nyaman. ✨"
    content.sound = .default
    content.categoryIdentifier = Self.categoryIdentifier
    
    // Add custom data
    content.userInfo = [
      "stationId": station.id ?? station.code,
      "stationCode": station.code,
      "stationName": station.name,
      "distance": distance
    ]
    
    let request = UNNotificationRequest(
      identifier: "proximity_\(station.code)",
      content: content,
      trigger: trigger
    )
    
    do {
      try await notificationCenter.add(request)
      logger.debug("Scheduled proximity notification for station \(station.code) at \(distance)m")
    } catch {
      logger.error("Failed to schedule proximity notification for \(station.code): \(error)")
    }
  }
  
  private func clearProximityNotifications() async {
    let pendingRequests = await notificationCenter.pendingNotificationRequests()
    let proximityIdentifiers = pendingRequests
      .filter { $0.identifier.hasPrefix("proximity_") }
      .map { $0.identifier }
    
    notificationCenter.removePendingNotificationRequests(withIdentifiers: proximityIdentifiers)
    logger.info("Cleared \(proximityIdentifiers.count) proximity notifications")
  }
  
  private func startMonitoringRegion(for station: Station) {
    let center = CLLocationCoordinate2D(
      latitude: station.position.latitude,
      longitude: station.position.longitude
    )
    
    let region = CLCircularRegion(
      center: center,
      radius: stationRadius,
      identifier: "station_\(station.code)"
    )
    region.notifyOnEntry = true
    region.notifyOnExit = false
    
    locationManager.startMonitoring(for: region)
    logger.debug("Started monitoring region for station \(station.code)")
  }
  
  private func clearMonitoredRegions() {
    let regionCount = locationManager.monitoredRegions.count
    var clearedCount = 0
    
    for region in locationManager.monitoredRegions {
      if region.identifier.hasPrefix("station_") {
        locationManager.stopMonitoring(for: region)
        clearedCount += 1
        logger.debug("❌ Stopped monitoring region: \(region.identifier)")
      }
    }
    logger.info("Cleared \(clearedCount) of \(regionCount) monitored regions")
  }
  
  // MARK: - Debug & Testing
  
  #if DEBUG
  /// Debug: List all pending proximity notifications
  func debugPendingNotifications() async {
    let pending = await notificationCenter.pendingNotificationRequests()
    let proximity = pending.filter { $0.identifier.hasPrefix("proximity_") }
    
    logger.info("=== PROXIMITY NOTIFICATIONS DEBUG ===")
    logger.info("Total proximity notifications: \(proximity.count)")
    logger.info("Total monitored regions: \(self.locationManager.monitoredRegions.count)")
    logger.info("🚂 Active journey: \(self.hasActiveJourney ? "YES - notifications DISABLED" : "NO - notifications ENABLED")")
    
    // Show monitored regions (for background geofencing)
    logger.info("--- MONITORED REGIONS (Background) ---")
    if locationManager.monitoredRegions.isEmpty {
      logger.info("   No regions currently monitored")
    } else {
      for region in locationManager.monitoredRegions {
        if let circularRegion = region as? CLCircularRegion {
          logger.info("🎯 \(region.identifier):")
          logger.info("   Location: \(circularRegion.center.latitude), \(circularRegion.center.longitude)")
          logger.info("   Radius: \(circularRegion.radius)m")
          logger.info("   Notify on entry: \(circularRegion.notifyOnEntry)")
        }
      }
    }
    
    // Show scheduled notifications
    logger.info("--- SCHEDULED NOTIFICATIONS ---")
    if proximity.isEmpty {
      logger.info("   No proximity notifications scheduled")
    } else {
      for request in proximity {
        if let trigger = request.trigger as? UNLocationNotificationTrigger {
          let region = trigger.region as! CLCircularRegion
          logger.info("📍 \(request.identifier):")
          logger.info("   Location: \(region.center.latitude), \(region.center.longitude)")
          logger.info("   Radius: \(region.radius)m")
          logger.info("   Content: \(request.content.body)")
        }
      }
    }
    
    if let userLoc = lastUserLocation {
      logger.info("📱 User location: \(userLoc.latitude), \(userLoc.longitude)")
    } else {
      logger.info("📱 User location: unknown")
    }
    
    let authStatus = locationManager.authorizationStatus
    logger.info("🔐 Location authorization: \(authStatus.rawValue) (\(authStatus == .authorizedAlways ? "Always - Background OK" : authStatus == .authorizedWhenInUse ? "When In Use - Background LIMITED" : "NOT AUTHORIZED"))")
    logger.info("=====================================")
  }
  
  /// Debug: Manually trigger a test notification for a specific station
  func testProximityNotification(stationCode: String) async {
    guard let station = currentStations.first(where: { $0.code == stationCode }) else {
      logger.error("Station \(stationCode) not found in current stations")
      return
    }
    
    // Schedule immediate notification (no location trigger)
    let content = UNMutableNotificationContent()
    content.title = "🧪 Test: Mendekati Stasiun"
    content.body = "Test notification untuk stasiun \(station.name) (\(station.code))"
    content.sound = .default
    content.categoryIdentifier = Self.categoryIdentifier
    content.userInfo = [
      "stationId": station.id ?? station.code,
      "stationCode": station.code,
      "stationName": station.name,
      "isTest": true
    ]
    
    let request = UNNotificationRequest(
      identifier: "test_proximity_\(station.code)_\(UUID().uuidString)",
      content: content,
      trigger: nil // Immediate delivery
    )
    
    do {
      try await notificationCenter.add(request)
      logger.info("✅ Test notification sent for \(station.name)")
    } catch {
      logger.error("❌ Failed to send test notification: \(error)")
    }
  }
  
  /// Debug: Force refresh proximity triggers with current location
  func forceRefresh() async {
    if let location = locationManager.location {
      logger.info("🔄 Forcing proximity refresh at: \(location.coordinate.latitude), \(location.coordinate.longitude)")
      await setupProximityNotifications(
        userLocation: location.coordinate,
        stations: currentStations
      )
    } else {
      logger.warning("⚠️ Cannot force refresh: no location available")
      locationManager.requestLocation()
    }
  }
  #endif
}

// MARK: - CLLocationManagerDelegate

extension StationProximityService: CLLocationManagerDelegate {
  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    
    Task { @MainActor in
      if !currentStations.isEmpty {
        await setupProximityNotifications(
          userLocation: location.coordinate,
          stations: currentStations
        )
      }
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      logger.error("Location manager failed: \(error.localizedDescription)")
    }
  }
  
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // Read the authorization status before hopping to the main actor to avoid sending 'manager'
    let statusRawValue = manager.authorizationStatus.rawValue
    Task { @MainActor in
      logger.info("Location authorization changed to: \(statusRawValue)")
      await refreshTriggersIfNeeded()
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    guard let circularRegion = region as? CLCircularRegion,
          region.identifier.hasPrefix("station_") else { return }
    
    let stationCode = region.identifier.replacingOccurrences(of: "station_", with: "")
    
    Task { @MainActor in
      logger.info("🎯 Entered region for station: \(stationCode)")
      logger.info("   Current journey status: hasActiveJourney = \(self.hasActiveJourney)")
      
      // Don't send notification if user is already tracking a journey
      guard !hasActiveJourney else {
        logger.info("⏭️ Skipping proximity notification - user has active journey")
        return
      }
      
      // Find station details
      guard let station = currentStations.first(where: { $0.code == stationCode }) else {
        logger.warning("Station \(stationCode) not found in current stations")
        return
      }
      
      // Send notification
      let content = UNMutableNotificationContent()
      content.title = "Mau naik kereta?"
      content.body = "Yuk, track perjalananmu untuk pengalaman yang lebih nyaman. ✨"
      content.sound = .default
      content.categoryIdentifier = Self.categoryIdentifier
      content.userInfo = [
        "stationId": station.id ?? station.code,
        "stationCode": station.code,
        "stationName": station.name,
        "triggeredBy": "geofence"
      ]
      
      let request = UNNotificationRequest(
        identifier: "proximity_triggered_\(stationCode)_\(Date().timeIntervalSince1970)",
        content: content,
        trigger: nil // Immediate delivery
      )
      
      do {
        try await notificationCenter.add(request)
        logger.info("✅ Proximity notification delivered for \(station.name)")
      } catch {
        logger.error("❌ Failed to send proximity notification: \(error)")
      }
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    let regionId = region.identifier
    Task { @MainActor in
      logger.debug("✅ Started monitoring region: \(regionId)")
    }
  }
  
  nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    let regionId = region?.identifier
    let errorDesc = error.localizedDescription
    Task { @MainActor in
      if let regionId = regionId {
        logger.error("❌ Monitoring failed for region \(regionId): \(errorDesc)")
      } else {
        logger.error("❌ Monitoring failed: \(errorDesc)")
      }
    }
  }
}
