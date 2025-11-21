import Foundation
import SwiftUI

enum Destination: Hashable {
  // TODO: Add other destinations here
  case push(_ destination: PushDestination)
  case sheet(_ destination: SheetDestination)
  case fullScreen(_ destination: FullScreenDestination)
  case action(_ action: ActionDestination)
}

extension Destination: CustomStringConvertible {
  var description: String {
    switch self {
    case let .push(destination): ".push(\(destination))"
    case let .sheet(destination): ".sheet(\(destination))"
    case let .fullScreen(destination): ".fullScreen(\(destination))"
    case let .action(action): ".action(\(action))"
    }
  }
}

enum PushDestination: Hashable, CustomStringConvertible {
  case home

  var description: String {
    switch self {
    case .home: ".home"
    }
  }
}

enum SheetDestination: Hashable, CustomStringConvertible {
  case feedback
  case addTrain
  case shareJourney  // Add this new case
  case alarmConfiguration
  case stationSchedule
  case searchByStation

  var description: String {
    switch self {
    case .feedback: ".feedback"
    case .addTrain: ".addTrain"
    case .shareJourney: ".shareJourney"  // Add this
    case .alarmConfiguration: ".alarmConfiguration"
    case .stationSchedule: ".stationSchedule"
    case .searchByStation: ".searchByStation"
    }
  }
}

extension SheetDestination: Identifiable {
  var id: String {
    switch self {
    case .feedback: "feedback"
    case .addTrain: "addTrain"
    case .shareJourney: "shareJourney"  // Add this
    case .alarmConfiguration: "alarmConfiguration"
    case .stationSchedule: "stationSchedule"
    case .searchByStation: "searchByStation"
    }
  }
}

enum FullScreenDestination: Hashable {
  case arrival(stationCode: String, stationName: String)
  case permissionsOnboarding
}

extension FullScreenDestination: CustomStringConvertible {
  var description: String {
    switch self {
    case let .arrival(stationCode, stationName): ".arrival(\(stationCode), \(stationName))"
    case .permissionsOnboarding: ".permissionsOnboarding"
    }
  }
}

extension FullScreenDestination: Identifiable {
  var id: String {
    switch self {
    case let .arrival(stationCode, stationName): "\(stationCode)-\(stationName)"
    case .permissionsOnboarding: "permissionsOnboarding"
    }
  }
}

// MARK: - Action destinations (no UI presentation)

enum ActionDestination: Hashable {
  case startTrip(trainId: String, fromCode: String, toCode: String)
}

extension ActionDestination: CustomStringConvertible {
  var description: String {
    switch self {
    case let .startTrip(trainId, fromCode, toCode): ".startTrip(\(trainId), \(fromCode), \(toCode))"
    }
  }
}
