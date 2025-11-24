//
//  StationTimelineItem.swift
//  kreta
//
//  Created by AI Assistant
//

import Foundation

// MARK: - Station Timeline Item

/// Represents a station in the journey timeline with its state and timing
struct StationTimelineItem: Identifiable, Equatable {
  let id: String
  let station: Station
  let arrivalTime: Date?
  let departureTime: Date?
  let state: StationState
  let isStop: Bool  // Whether train stops at this station
  var progressToNext: Double?  // Progress from this station to next (0.0 - 1.0)

  enum StationState: Equatable {
    case completed  // Train has passed this station
    case current  // Train is currently at or approaching this station
    case upcoming  // Train hasn't reached this station yet
  }

  /// Calculate progress between two stations based on current time
  /// Note: If departure/arrival are on a future date, progress will be 0.0
  /// Note: Times should already be normalized by the server
  static func calculateProgress(from departure: Date?, to arrival: Date?) -> Double? {
    guard let departure = departure, let arrival = arrival else {
      return nil
    }

    // Server already normalized times, use directly
    let now = Date()
    let calendar = Calendar.current

    // Check if the journey is on a future date (not today)
    // Compare just the date components, not the time
    let departureDay = calendar.startOfDay(for: departure)
    let today = calendar.startOfDay(for: now)

    // If journey is on a future date, no progress yet
    if departureDay > today {
      return 0.0
    }

    // If before departure, progress is 0
    if now < departure {
      return 0.0
    }

    // If after arrival, progress is 1
    if now >= arrival {
      return 1.0
    }

    // Calculate progress between 0 and 1
    let totalDuration = arrival.timeIntervalSince(departure)
    let elapsed = now.timeIntervalSince(departure)

    return min(max(elapsed / totalDuration, 0.0), 1.0)
  }
}

// MARK: - Timeline Builder

extension StationTimelineItem {

  private enum JourneyPhase {
    case futureDay       // Journey is on a future date
    case beforeDeparture // Journey is today but hasn't started
    case enRoute         // Journey is currently in progress
    case finished        // Journey has completed
  }

  static func buildTimelineFromStops(
    trainCode: String,
    currentSegmentFromStationId: String?,
    trainStopService: TrainStopService,
    selectedDate: Date = Date(),
    userDestinationStationId: String? = nil
  ) async -> [StationTimelineItem] {
    do {
      guard let schedule = try await trainStopService.getTrainSchedule(trainCode: trainCode) else {
        return []
      }

      guard !schedule.stops.isEmpty else { return [] }
      
      var calendar = Calendar.current
      calendar.timeZone = TimeZone.current // Use local timezone
      let now = Date()
      let today = calendar.startOfDay(for: now)
      
      // CRITICAL: For overnight trains, we need to determine the actual journey start day
      // Strategy: Try both selectedDate and (selectedDate - 1 day), pick the one where first departure <= now
      let selectedDay = calendar.startOfDay(for: selectedDate)
      let previousDay = calendar.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
      
      // Get first departure time string to test both scenarios
      let firstDepartureTimeStr = schedule.stops.first?.departureTime ?? schedule.stops.first?.arrivalTime
      guard let firstTimeStr = firstDepartureTimeStr else { return [] }
      
      // Parse first departure on both days
      let firstDepOnSelected = parseTimeString(firstTimeStr, on: selectedDay)
      let firstDepOnPrevious = parseTimeString(firstTimeStr, on: previousDay)
      
      // Determine actual journey day:
      // If first departure on previous day is in the past but on selected day is in the future,
      // the journey actually started on previous day (overnight scenario)
      let journeyDay: Date
      if let prevDep = firstDepOnPrevious, let selDep = firstDepOnSelected,
         prevDep <= now && selDep > now {
        // Journey started yesterday (overnight train)
        journeyDay = previousDay
        print("🌙 Overnight train detected: journey started on \(previousDay)")
      } else {
        // Normal case: journey is on selected day
        journeyDay = selectedDay
      }
      
      print("🕐 now: \(now), journeyDay: \(journeyDay), today: \(today), selectedDate: \(selectedDate), timezone: \(calendar.timeZone.identifier)")
      
      // Parse all stops with their times, handling overnight journeys
      var parsedStops: [(stop: TrainStopService.TrainStop, arrival: Date?, departure: Date?)] = []
      var currentDay = journeyDay
      var previousTime: Date? = nil
      
      for stop in schedule.stops {
        let arrivalDate = stop.arrivalTime.flatMap { parseTimeString($0, on: currentDay) }
        let departureDate = stop.departureTime.flatMap { parseTimeString($0, on: currentDay) }
        
        let effectiveTime = departureDate ?? arrivalDate
        
        // Detect day rollover: if current time is earlier than previous time, we crossed midnight
        if let prevTime = previousTime, let currTime = effectiveTime, currTime < prevTime {
          currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay
          // Re-parse times on new day
          let newArrival = stop.arrivalTime.flatMap { parseTimeString($0, on: currentDay) }
          let newDeparture = stop.departureTime.flatMap { parseTimeString($0, on: currentDay) }
          parsedStops.append((stop, newArrival, newDeparture))
          previousTime = newDeparture ?? newArrival
        } else {
          parsedStops.append((stop, arrivalDate, departureDate))
          previousTime = effectiveTime
        }
      }
      
      guard !parsedStops.isEmpty else { return [] }

      // Get first departure and last arrival
      let firstDeparture = parsedStops.first?.departure
      let lastArrival = parsedStops.last?.arrival
      
      // Determine journey status
      // CRITICAL: Use selectedDay (user's intent) for future check, not journeyDay (calculated start)
      let journeyStatus: JourneyPhase
      if selectedDay > today {
        // User selected a future date - journey is in the future
        journeyStatus = .futureDay
      } else if let firstDep = firstDeparture, now < firstDep {
        // Today but hasn't started
        journeyStatus = .beforeDeparture
      } else if let lastArr = lastArrival, now >= lastArr {
        // Journey completed
        journeyStatus = .finished
      } else {
        // Currently in journey
        journeyStatus = .enRoute
      }
      
      // Find current station index (only matters if enRoute)
      var currentStationIndex: Int? = nil
      if case .enRoute = journeyStatus {
        // Find the segment we're currently in
        for i in 0..<parsedStops.count - 1 {
          let currentDeparture = parsedStops[i].departure
          let nextArrival = parsedStops[i + 1].arrival
          
          if let dep = currentDeparture, let arr = nextArrival, now >= dep && now < arr {
            currentStationIndex = i
            break
          }
        }
        
        // Fallback: find last departed station
        if currentStationIndex == nil {
          currentStationIndex = parsedStops.lastIndex { parsed in
            if let dep = parsed.departure {
              return now >= dep
            }
            return false
          }
        }
      }

      var items: [StationTimelineItem] = []

      for (index, parsed) in parsedStops.enumerated() {
        let stop = parsed.stop
        
        // Determine state
        let state: StationState
        switch journeyStatus {
        case .futureDay, .beforeDeparture:
          state = .upcoming
        case .finished:
          state = .completed
        case .enRoute:
          if let currentIdx = currentStationIndex {
            if index < currentIdx {
              state = .completed
            } else if index == currentIdx {
              state = .current
            } else {
              state = .upcoming
            }
          } else {
            state = .upcoming
          }
        }
        
        // Calculate progress to next station
        var progressToNext: Double? = nil
        if index < parsedStops.count - 1 {
          let fromTime = parsed.departure ?? parsed.arrival
          let toTime = parsedStops[index + 1].arrival ?? parsedStops[index + 1].departure
          
          switch journeyStatus {
          case .futureDay, .beforeDeparture:
            progressToNext = 0.0
          case .finished:
            progressToNext = 1.0
          case .enRoute:
            progressToNext = calculateProgress(from: fromTime, to: toTime)
          }
        }

        // Build Station model
        let station = Station(
          id: stop.stationId,
          code: stop.stationCode,
          name: stop.stationName,
          position: Position(latitude: 0, longitude: 0),
          city: stop.city
        )

        items.append(
          StationTimelineItem(
            id: stop.stationId,
            station: station,
            arrivalTime: parsed.arrival,
            departureTime: parsed.departure,
            state: state,
            isStop: true,
            progressToNext: progressToNext
          )
        )
      }
      
      return items

    } catch {
      print("Failed to build timeline from train stops: \(error)")
      return []
    }
  }

  /// Parse time string in "HH:MM:SS" format to Date on the given day
  private static func parseTimeString(_ timeString: String, on date: Date) -> Date? {
    let components = timeString.split(separator: ":")
    guard components.count >= 2,
      let hour = Int(components[0]),
      let minute = Int(components[1])
    else {
      return nil
    }
    
    let second = components.count >= 3 ? Int(components[2]) ?? 0 : 0
    
    var calendar = Calendar.current
    calendar.timeZone = TimeZone.current // Use local timezone
    return calendar.date(bySettingHour: hour, minute: minute, second: second, of: date)
  }
}
