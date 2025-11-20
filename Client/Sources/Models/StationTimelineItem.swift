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

  private struct TrainStopLite {
    let stationId: String
    let stationCode: String
    let stationName: String
    let city: String?
    let arrivalTime: String?
    let departureTime: String?
  }

  private struct ParsedStop {
    let stop: TrainStopLite
    let arrival: Date?
    let departure: Date?

    var effectiveDeparture: Date? {
      departure ?? arrival
    }

    var effectiveArrival: Date? {
      arrival ?? departure
    }
  }

  private enum JourneyPhase {
    case futureDay
    case pastDay
    case beforeDeparture
    case enRoute
    case finished
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

      let calendar = Calendar.current
      let today = calendar.startOfDay(for: Date())
      let journeyDay = calendar.startOfDay(for: selectedDate)

      // Parse all times once
      let parsedStops: [ParsedStop] = schedule.stops.map { stop in
        // Support both concrete TrainStop types and dictionary-like payloads by accessing via key paths.
        let lite = TrainStopLite(
          stationId: stop.stationId,
          stationCode: stop.stationCode,
          stationName: stop.stationName,
          city: stop.city,
          arrivalTime: stop.arrivalTime,
          departureTime: stop.departureTime
        )
        let arrivalDate = lite.arrivalTime.flatMap { parseTimeString($0, on: selectedDate) }
        let departureDate = lite.departureTime.flatMap { parseTimeString($0, on: selectedDate) }
        return ParsedStop(stop: lite, arrival: arrivalDate, departure: departureDate)
      }

      guard !parsedStops.isEmpty else { return [] }

      // First and last meaningful times
      let firstTime =
        parsedStops
        .compactMap { $0.effectiveDeparture ?? $0.effectiveArrival }
        .first

      let lastTime =
        parsedStops
        .compactMap { $0.effectiveArrival ?? $0.effectiveDeparture }
        .last

      let now = Date()

      // Determine journey phase
      var phase: JourneyPhase
      if journeyDay > today {
        phase = .futureDay
      } else if journeyDay < today {
        phase = .pastDay
      } else {
        // Today
        if let first = firstTime, let last = lastTime {
          if now < first {
            phase = .beforeDeparture
          } else if now >= last {
            // 🔴 This is the case you mentioned: train has fully completed the route
            phase = .finished
          } else {
            phase = .enRoute
          }
        } else {
          // If no times, choose based on now vs today (should be today); default to future
          phase = now < today ? .pastDay : .futureDay
        }
      }

      // Determine current index if enRoute
      let currentIndex: Int? = {
        guard case .enRoute = phase else { return nil }

        // Try to find segment where "now" is between departure of i and arrival of i+1
        for (index, stop) in parsedStops.enumerated() where index < parsedStops.count - 1 {
          let currentDeparture = parsedStops[index].effectiveDeparture
          let nextArrival = parsedStops[index + 1].effectiveArrival

          if let dep = currentDeparture, let arr = nextArrival,
            now >= dep && now < arr
          {
            return index
          }
        }

        // Fallback: last stop whose effectiveDeparture is <= now
        if let idx = parsedStops.lastIndex(where: {
          ($0.effectiveDeparture ?? $0.effectiveArrival ?? .distantPast) <= now
        }) {
          return idx
        }

        return nil
      }()

      var items: [StationTimelineItem] = []

      for (index, parsed) in parsedStops.enumerated() {
        let stop = parsed.stop
        let arrivalDate = parsed.arrival
        let departureDate = parsed.departure

        // Decide state purely from phase + currentIndex
        let state: StationState = {
          switch phase {
          case .futureDay, .beforeDeparture:
            return .upcoming
          case .pastDay, .finished:
            return .completed
          case .enRoute:
            guard let currentIndex = currentIndex else {
              return .upcoming
            }
            if index < currentIndex {
              return .completed
            } else if index == currentIndex {
              return .current
            } else {
              return .upcoming
            }
          }
        }()

        // Progress to next
        var progressToNext: Double? = nil
        if index < parsedStops.count - 1 {
          let nextStop = parsedStops[index + 1]
          let fromTime = parsed.effectiveDeparture ?? parsed.effectiveArrival
          let toTime = nextStop.effectiveArrival ?? nextStop.effectiveDeparture

          switch phase {
          case .futureDay, .beforeDeparture:
            progressToNext = 0.0
          case .pastDay, .finished:
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
            arrivalTime: arrivalDate,
            departureTime: departureDate,
            state: state,
            isStop: true,
            progressToNext: progressToNext
          )
        )
      }

      // NOTE:
      // If you still want to use currentSegmentFromStationId or userDestinationStationId
      // for *visual emphasis* (e.g. bolding the user’s segment), do it in the View layer
      // or with extra properties, not by mutating `state`.

      return items

    } catch {
      print("Failed to build timeline from train stops: \(error)")
      return []
    }
  }

  /// Parse time string in "HH:MM:SS" format to Date (normalized to selected date)
  private static func parseTimeString(_ timeString: String, on date: Date) -> Date? {
    let components = timeString.split(separator: ":")
    guard components.count >= 2,
      let hour = Int(components[0]),
      let minute = Int(components[1]),
      let second = Int(components[2])
    else {
      return nil
    }

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)

    return calendar.date(bySettingHour: hour, minute: minute, second: second, of: startOfDay)
  }
}
