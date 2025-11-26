import CoreLocation
import Foundation

enum TrainProjector {
  private static let dayInMilliseconds: Double = 86_400_000
  private static let defaultBearingSampleCm: Double = 2_000

  // MARK: - Journey leg extraction helpers

  /// Extract leg indices for a journey from departure to arrival stations
  /// Returns (startIndex, endIndex) if a contiguous leg exists, nil otherwise
  static func legIndices(
    in journey: TrainJourney,
    from dep: String,
    to arr: String
  ) -> (Int, Int)? {
    guard let startIndex = journey.segments.firstIndex(where: { $0.fromStationId == dep }) else {
      return nil
    }

    var endIndex: Int?
    for i in startIndex..<journey.segments.count {
      if journey.segments[i].toStationId == arr {
        endIndex = i
        break
      }
    }

    guard let endIndex else { return nil }
    return (startIndex, endIndex)
  }

  // MARK: - Normalization helpers

  private static func positiveModulo(_ value: Double, modulus: Double) -> Double {
    guard modulus != 0 else { return value }
    let remainder = value.truncatingRemainder(dividingBy: modulus)
    return remainder >= 0 ? remainder : remainder + modulus
  }

  /// Extract hour:minute components from a normalized Date and convert to milliseconds since midnight
  private static func timeComponents(from date: Date) -> (
    hour: Int, minute: Int, millisecond: Double
  ) {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    let second = components.second ?? 0
    let millisecond = Double(hour * 3_600_000 + minute * 60_000 + second * 1_000)
    return (hour, minute, millisecond)
  }

  /// Mirrors the React Native implementation: bring `timestamp`, `start`, and `end`
  /// into a comparable window while preserving cycle length.
  static func normalizeTimeWindow(
    timestamp: Double,
    startMs: Double,
    endMs: Double
  ) -> (timeMs: Double, startMs: Double, endMs: Double, cycle: Double) {
    var normalizedStart = startMs
    var normalizedEnd = endMs

    if normalizedEnd < normalizedStart {
      normalizedStart = positiveModulo(normalizedStart, modulus: dayInMilliseconds)
      normalizedEnd = positiveModulo(normalizedEnd, modulus: dayInMilliseconds) + dayInMilliseconds
    }

    let cycles = max(1, ceil(normalizedEnd / dayInMilliseconds))
    let cycle = cycles * dayInMilliseconds
    let timeMs = positiveModulo(timestamp, modulus: cycle)

    return (timeMs, normalizedStart, normalizedEnd, cycle)
  }

  static func isWithin(_ timeMs: Double, startMs: Double, endMs: Double) -> Bool {
    let normalized = normalizeTimeWindow(timestamp: timeMs, startMs: startMs, endMs: endMs)
    return normalized.startMs <= normalized.timeMs && normalized.timeMs <= normalized.endMs
  }

  // MARK: - Geometry helpers

  private static func lerp(
    _ from: CLLocationCoordinate2D,
    _ to: CLLocationCoordinate2D,
    t: Double
  ) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: from.latitude + (to.latitude - from.latitude) * t,
      longitude: from.longitude + (to.longitude - from.longitude) * t
    )
  }

  private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double? {
    if abs(from.latitude - to.latitude) < .ulpOfOne
      && abs(from.longitude - to.longitude) < .ulpOfOne
    {
      return nil
    }

    let lat1 = from.latitude * .pi / 180
    let lon1 = from.longitude * .pi / 180
    let lat2 = to.latitude * .pi / 180
    let lon2 = to.longitude * .pi / 180

    let y = sin(lon2 - lon1) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
    var angle = atan2(y, x) * 180 / .pi
    if angle < 0 { angle += 360 }
    return angle
  }

  private static func coordinateOnRoute(distanceCm: Double, route: Route) -> CLLocationCoordinate2D?
  {
    let clamped = max(0, min(distanceCm, route.totalLengthCm))
    return route.coordinateAt(distanceCm: clamped)
  }

  // MARK: - Data helpers

  /// Extract time components from segment dates (compute once per segment)
  private struct SegmentTimeComponents {
    let departureMs: Double
    let arrivalMs: Double
  }

  private static func extractTimeComponents(from segment: JourneySegment) -> SegmentTimeComponents {
    let departureMs = timeComponents(from: segment.departure).millisecond
    let arrivalMs = timeComponents(from: segment.arrival).millisecond
    return SegmentTimeComponents(departureMs: departureMs, arrivalMs: arrivalMs)
  }

  /// Pick the active segment, or if between segments (stopped at station), return the next segment
  private static func pickActiveSegment(timeMs: Double, segments: [JourneySegment])
    -> JourneySegment?
  {
    // First try to find a segment where train is actively moving
    if let activeSegment = segments.first(where: { seg in
      let times = extractTimeComponents(from: seg)
      return isWithin(timeMs, startMs: times.departureMs, endMs: times.arrivalMs)
    }) {
      return activeSegment
    }

    // If no active segment, train is stopped at a station between segments
    // Find the next segment that will depart after current time
    for i in 0..<segments.count {
      let seg = segments[i]

      // Check if we're after this segment's arrival but before next segment's departure
      if i < segments.count - 1 {
        let nextSeg = segments[i + 1]
        let segTimes = extractTimeComponents(from: seg)
        let nextSegTimes = extractTimeComponents(from: nextSeg)

        // Normalize the time window between this segment's arrival and next segment's departure
        let waitWindow = normalizeTimeWindow(
          timestamp: timeMs,
          startMs: segTimes.arrivalMs,
          endMs: nextSegTimes.departureMs
        )

        // If we're in the waiting period, return the next segment (but we'll show stopped state)
        if waitWindow.startMs <= waitWindow.timeMs && waitWindow.timeMs < waitWindow.endMs {
          return nextSeg
        }
      }
    }

    return nil
  }

  private static func resolveJourneyDates(
    startMs: Double,
    endMs: Double,
    nowMs: Double,
    timeMs: Double,
    cycle: Double,
    now: Date
  ) -> (departure: Date, arrival: Date) {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    
    // Calculate offset from current time-of-day to target times
    let offsetToDeparture = startMs - timeMs
    let offsetToArrival = endMs - timeMs
    
    // Convert milliseconds to seconds and add to today's start
    var departureMs = nowMs + offsetToDeparture
    var arrivalMs = nowMs + offsetToArrival
    
    // Ensure arrival is after departure within the same cycle
    if arrivalMs < departureMs { arrivalMs += cycle }
    
    // If the computed departure is already in the past relative to now,
    // roll both departure and arrival forward by one cycle (next day)
    if departureMs < nowMs {
      departureMs += cycle
      // Keep arrival after (potentially updated) departure
      if arrivalMs < departureMs { arrivalMs += cycle }
    }
    
    // Convert from milliseconds since midnight to actual Date
    let departureSeconds = departureMs / 1_000
    let arrivalSeconds = arrivalMs / 1_000
    
    return (
      todayStart.addingTimeInterval(departureSeconds),
      todayStart.addingTimeInterval(arrivalSeconds)
    )
  }

  private static func resolveSegmentDates(
    seg: JourneySegment,
    times: SegmentTimeComponents,
    nowMs: Double,
    timeMs: Double,
    cycle: Double,
    now: Date
  ) -> (start: Date, arrival: Date, departure: Date) {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    
    // Calculate offset from current time-of-day to target times
    let offsetToDeparture = times.departureMs - timeMs
    let offsetToArrival = times.arrivalMs - timeMs
    
    var startAbs = nowMs + offsetToDeparture
    var arrivalAbs = nowMs + offsetToArrival
    
    // Ensure arrival is after start within the same cycle
    if arrivalAbs < startAbs { arrivalAbs += cycle }
    
    // If the computed start (departure) is already in the past relative to now,
    // roll both start and arrival forward by one cycle (next day)
    if startAbs < nowMs {
      startAbs += cycle
      if arrivalAbs < startAbs { arrivalAbs += cycle }
    }
    let departureAbs = startAbs

    // Convert from milliseconds since midnight to actual Date
    let startSeconds = startAbs / 1_000
    let arrivalSeconds = arrivalAbs / 1_000
    let departureSeconds = departureAbs / 1_000
    
    return (
      todayStart.addingTimeInterval(startSeconds),
      todayStart.addingTimeInterval(arrivalSeconds),
      todayStart.addingTimeInterval(departureSeconds)
    )
  }

  // MARK: - Public projection API

  static func projectTrain(
    now: Date,
    journey: TrainJourney,
    stationsById: [String: Station],
    routesById: [String: Route],
    selectedDate: Date = Date() // Date the journey is scheduled for
  ) -> ProjectedTrain? {
    // Check if journey date has arrived yet
    let calendar = Calendar.current
    let journeyDay = calendar.startOfDay(for: selectedDate)
    let today = calendar.startOfDay(for: now)
    
    // If journey is scheduled for a future date (after today), don't project yet
    if journeyDay > today {
      return nil
    }
    
    // Journey date has arrived (is today or in the past) - proceed with projection
    // Extract current time-of-day in milliseconds since midnight
    let nowTimeComponents = timeComponents(from: now)
    let nowMs = nowTimeComponents.millisecond
    
    guard let first = journey.segments.first, let last = journey.segments.last else { return nil }

    // Extract time components once for journey boundaries
    let firstTimes = extractTimeComponents(from: first)
    let lastTimes = extractTimeComponents(from: last)
    let journeyWindow = normalizeTimeWindow(
      timestamp: nowMs,
      startMs: firstTimes.departureMs,
      endMs: lastTimes.arrivalMs
    )
    let timeMs = journeyWindow.timeMs

    guard let seg = pickActiveSegment(timeMs: timeMs, segments: journey.segments) else {
      return nil
    }

    // Extract time components once for the active segment
    let segTimes = extractTimeComponents(from: seg)

    let segmentDates = resolveSegmentDates(
      seg: seg,
      times: segTimes,
      nowMs: nowMs,
      timeMs: timeMs,
      cycle: journeyWindow.cycle,
      now: now
    )
    let journeyDates = resolveJourneyDates(
      startMs: journeyWindow.startMs,
      endMs: journeyWindow.endMs,
      nowMs: nowMs,
      timeMs: timeMs,
      cycle: journeyWindow.cycle,
      now: now
    )

    let fromStation = stationsById[seg.fromStationId]
    let toStation = stationsById[seg.toStationId] ?? fromStation

    // Check if train is stopped at station:
    // 1. Before segment departure time (waiting at departure station)
    // 2. At exact arrival time (just arrived at destination station)
    let isBeforeDeparture =
      timeMs < segTimes.departureMs
      || !isWithin(timeMs, startMs: segTimes.departureMs, endMs: segTimes.arrivalMs)
    let isStopped = isBeforeDeparture

    let position: Position
    let moving: Bool
    let resolvedBearing: Double?
    let speedKph: Double?
    let progress: Double?

    if isStopped {
      // Train is stopped at station waiting for departure
      // Show train at the departure station (fromStation) of this segment
      guard let station = fromStation else { return nil }
      let coord = station.coordinate
      position = Position(latitude: coord.latitude, longitude: coord.longitude)
      moving = false
      speedKph = nil
      progress = 0
      let rbearing: Double?
      if let origin = fromStation?.coordinate, let destination = toStation?.coordinate {
        rbearing = bearing(from: origin, to: destination)
      } else {
        rbearing = nil
      }
      resolvedBearing = rbearing

      return ProjectedTrain(
        id: journey.id,
        code: journey.code,
        name: journey.name,
        position: position,
        moving: moving,
        bearing: resolvedBearing,
        routeIdentifier: nil,
        speedKph: speedKph,
        fromStation: fromStation,
        toStation: toStation,
        segmentDeparture: segmentDates.departure,
        segmentArrival: segmentDates.arrival,
        progress: progress,
        journeyDeparture: journeyDates.departure,
        journeyArrival: journeyDates.arrival
      )
    } else {
      let route = seg.routeId.flatMap { routesById[$0] }
      if let route {
        // Check if route needs to be reversed based on station proximity
        // Strategy: Compare distances from BOTH route endpoints to BOTH stations
        var isRouteReversed = false
        if let routeStart = route.path.first,
          let routeEnd = route.path.last,
          let fromCoord = fromStation?.coordinate,
          let toCoord = toStation?.coordinate
        {
          // Calculate all four distance combinations
          let routeStartLoc = CLLocation(latitude: routeStart.latitude, longitude: routeStart.longitude)
          let routeEndLoc = CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude)
          let fromStationLoc = CLLocation(latitude: fromCoord.latitude, longitude: fromCoord.longitude)
          let toStationLoc = CLLocation(latitude: toCoord.latitude, longitude: toCoord.longitude)
          
          let startToFrom = routeStartLoc.distance(from: fromStationLoc)
          let startToTo = routeStartLoc.distance(from: toStationLoc)
          let endToFrom = routeEndLoc.distance(from: fromStationLoc)
          let endToTo = routeEndLoc.distance(from: toStationLoc)
          
          // Forward direction: route start is near departure, route end is near arrival
          let forwardScore = startToFrom + endToTo
          // Reverse direction: route end is near departure, route start is near arrival
          let reverseScore = endToFrom + startToTo
          
          // If reverse has lower total distance, the route is reversed
          isRouteReversed = reverseScore < forwardScore
        }

        let movementWindow = normalizeTimeWindow(
          timestamp: timeMs,
          startMs: segTimes.departureMs,
          endMs: segTimes.arrivalMs
        )
        let duration = max(movementWindow.endMs - movementWindow.startMs, 1)
        let elapsed = max(0, movementWindow.timeMs - movementWindow.startMs)
        let clampedProgress = max(0, min(1, elapsed / duration))

        // Calculate distance along route, reversing if needed
        let distanceForward = (route.totalLengthCm / duration) * elapsed
        let routedDistance: Double
        if isRouteReversed {
          // If route is reversed, travel from END to START (reverse direction)
          routedDistance = route.totalLengthCm - min(route.totalLengthCm, max(0, distanceForward))
        } else {
          // Normal: travel from START to END
          routedDistance = min(route.totalLengthCm, max(0, distanceForward))
        }

        guard let coordinate = coordinateOnRoute(distanceCm: routedDistance, route: route) else {
          return nil
        }

        // Calculate bearing using adaptive sampling based on progress
        // Use smaller delta near endpoints to prevent overshooting
        let progressFactor = min(clampedProgress, 1.0 - clampedProgress) * 2.0 // 0 at ends, 1 in middle
        let adaptiveDelta = max(500, min(defaultBearingSampleCm * progressFactor, defaultBearingSampleCm))
        
        let neighborDistance: Double
        if isRouteReversed {
          // Moving backward along route: sample behind us
          neighborDistance = max(0, routedDistance - adaptiveDelta)
        } else {
          // Moving forward along route: sample ahead of us
          neighborDistance = min(route.totalLengthCm, routedDistance + adaptiveDelta)
        }
        
        let neighborCoordinate = coordinateOnRoute(distanceCm: neighborDistance, route: route)

        // Calculate bearing in direction of travel
        let heading = neighborCoordinate.flatMap { neighbor in
          if isRouteReversed {
            // Reversed: bearing from neighbor (behind) to current (calculating backwards)
            bearing(from: neighbor, to: coordinate)
          } else {
            // Forward: bearing from current to neighbor (ahead)
            bearing(from: coordinate, to: neighbor)
          }
        }

        let distanceKm = route.totalLengthCm / 100_000
        let segmentDurationSeconds = max(
          segmentDates.arrival.timeIntervalSince(segmentDates.start), 1)
        let speed = segmentDurationSeconds > 0 ? distanceKm / (segmentDurationSeconds / 3_600) : nil

        position = Position(latitude: coordinate.latitude, longitude: coordinate.longitude)
        moving = true
        progress = clampedProgress
        resolvedBearing = heading
        speedKph = speed

        return ProjectedTrain(
          id: journey.id,
          code: journey.code,
          name: journey.name,
          position: position,
          moving: moving,
          bearing: resolvedBearing,
          routeIdentifier: route.id,
          speedKph: speedKph,
          fromStation: fromStation,
          toStation: toStation,
          segmentDeparture: segmentDates.start,
          segmentArrival: segmentDates.arrival,
          progress: progress,
          journeyDeparture: journeyDates.departure,
          journeyArrival: journeyDates.arrival
        )
      } else {
        // Straight line fallback
        guard let origin = fromStation?.coordinate, let destination = toStation?.coordinate else {
          return nil
        }
        let movementWindow = normalizeTimeWindow(
          timestamp: timeMs,
          startMs: segTimes.departureMs,
          endMs: segTimes.arrivalMs
        )
        let duration = max(movementWindow.endMs - movementWindow.startMs, 1)
        let elapsed = max(0, movementWindow.timeMs - movementWindow.startMs)
        let clampedProgress = max(0, min(1, elapsed / duration))

        let coordinate = lerp(origin, destination, t: clampedProgress)
        let distanceMeters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
          .distance(
            from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        let durationSeconds = max(segmentDates.arrival.timeIntervalSince(segmentDates.start), 1)
        let speed = durationSeconds > 0 ? (distanceMeters / 1_000) / (durationSeconds / 3_600) : nil

        position = Position(latitude: coordinate.latitude, longitude: coordinate.longitude)
        moving = true
        progress = clampedProgress
        speedKph = speed
        resolvedBearing = bearing(from: origin, to: destination)

        return ProjectedTrain(
          id: journey.id,
          code: journey.code,
          name: journey.name,
          position: position,
          moving: moving,
          bearing: resolvedBearing,
          routeIdentifier: nil,
          speedKph: speedKph,
          fromStation: fromStation,
          toStation: toStation,
          segmentDeparture: segmentDates.start,
          segmentArrival: segmentDates.arrival,
          progress: progress,
          journeyDeparture: journeyDates.departure,
          journeyArrival: journeyDates.arrival
        )
      }
    }
  }
}
