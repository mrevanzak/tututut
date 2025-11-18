import CloudKit
import Foundation
import OSLog

// MARK: - JourneyHistoryService

final class JourneyHistoryService: @unchecked Sendable {
  static let shared = JourneyHistoryService()

  // MARK: - Constants

  private enum Constants {
    static let recordType = "CompletedJourney"
  }

  // MARK: - Properties

  private let container: CKContainer
  private let database: CKDatabase
  private let logger = Logger(subsystem: "kreta", category: "JourneyHistoryService")

  // MARK: - Initialization

  private init() {
    // Use default container - container identifier will be configured in entitlements
    // by the user in step 1
    self.container = CKContainer(identifier: "iCloud.kreta")
    self.database = container.privateCloudDatabase
  }

  // MARK: - Save Journey

  func saveCompletedJourney(_ journey: CompletedJourney) async throws {
    logger.info(
      "Saving completed journey: \(journey.trainName, privacy: .public) from \(journey.fromStationName, privacy: .public) to \(journey.toStationName, privacy: .public)"
    )

    let record = try journeyToRecord(journey)

    do {
      let savedRecord = try await database.save(record)
      logger.info(
        "Successfully saved journey to CloudKit: \(savedRecord.recordID.recordName, privacy: .public)"
      )
    } catch let error as CKError {
      try handleCloudKitError(error, operation: "save")
      throw error
    } catch {
      logger.error(
        "Unexpected error saving journey: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  // MARK: - Fetch Journey History

  func fetchJourneyHistory(limit: Int = 50, offset: Int = 0) async throws -> [CompletedJourney] {
    logger.info("Fetching journey history: limit=\(limit), offset=\(offset)")

    let query = CKQuery(recordType: Constants.recordType, predicate: NSPredicate(value: true))
    query.sortDescriptors = [NSSortDescriptor(key: "actualArrivalTime", ascending: false)]

    do {
      // CloudKit doesn't support offset directly, so we fetch more and paginate manually
      // For offset support, we'd need to use cursor-based pagination in the future
      let fetchLimit = min(limit + offset, 100)  // CloudKit limit is typically 100
      let (matchResults, _) = try await database.records(
        matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: fetchLimit)

      var journeys: [CompletedJourney] = []
      for (_, result) in matchResults {
        switch result {
        case .success(let record):
          if let journey = try? recordToJourney(record) {
            journeys.append(journey)
          }
        case .failure(let error):
          logger.warning("Failed to fetch record: \(error.localizedDescription, privacy: .public)")
        }
      }

      // Apply pagination manually (CloudKit doesn't support offset directly)
      let paginatedJourneys = Array(journeys.dropFirst(offset).prefix(limit))
      logger.info("Fetched \(paginatedJourneys.count) journeys")
      return paginatedJourneys
    } catch let error as CKError {
      try handleCloudKitError(error, operation: "fetch")
      throw error
    } catch {
      logger.error(
        "Unexpected error fetching journey history: \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  func fetchJourneyHistory(from startDate: Date, to endDate: Date) async throws
    -> [CompletedJourney]
  {
    logger.info(
      "Fetching journey history from \(startDate, privacy: .public) to \(endDate, privacy: .public)"
    )

    let predicate = NSPredicate(
      format: "actualArrivalTime >= %@ AND actualArrivalTime <= %@",
      startDate as NSDate,
      endDate as NSDate
    )
    let query = CKQuery(recordType: Constants.recordType, predicate: predicate)
    query.sortDescriptors = [NSSortDescriptor(key: "actualArrivalTime", ascending: false)]

    do {
      let (matchResults, _) = try await database.records(
        matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 100)

      var journeys: [CompletedJourney] = []
      for (_, result) in matchResults {
        switch result {
        case .success(let record):
          if let journey = try? recordToJourney(record) {
            journeys.append(journey)
          }
        case .failure(let error):
          logger.warning("Failed to fetch record: \(error.localizedDescription, privacy: .public)")
        }
      }

      logger.info("Fetched \(journeys.count) journeys in date range")
      return journeys
    } catch let error as CKError {
      try handleCloudKitError(error, operation: "fetch")
      throw error
    } catch {
      logger.error(
        "Unexpected error fetching journey history: \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  // MARK: - Delete Journey

  func deleteJourney(id: String) async throws {
    logger.info("Deleting journey: \(id, privacy: .public)")

    let recordID = CKRecord.ID(recordName: id)

    do {
      try await database.deleteRecord(withID: recordID)
      logger.info("Successfully deleted journey: \(id, privacy: .public)")
    } catch let error as CKError {
      try handleCloudKitError(error, operation: "delete")
      throw error
    } catch {
      logger.error(
        "Unexpected error deleting journey: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  // MARK: - Sync (CloudKit handles automatically)

  func syncJourneyHistory() async throws {
    // CloudKit automatically syncs with iCloud
    // This method exists for future manual sync operations if needed
    logger.debug("Journey history sync is handled automatically by CloudKit")
  }

  // MARK: - Journey Building Helper

  /// Build a CompletedJourney from TrainJourneyData and ProjectedTrain
  static func buildCompletedJourney(
    from train: ProjectedTrain,
    journeyData: TrainJourneyData,
    actualArrivalTime: Date,
    completionType: String,
    wasTrackedUntilArrival: Bool
  ) -> CompletedJourney {
    let journeyDurationMinutes = Int(
      max(0, actualArrivalTime.timeIntervalSince(journeyData.userSelectedDepartureTime)) / 60
    )
    let routeIds = journeyData.segments.map { $0.routeId }

    return CompletedJourney(
      trainId: journeyData.trainId,
      trainCode: train.code,
      trainName: train.name,
      fromStationId: journeyData.userSelectedFromStation.id
        ?? journeyData.userSelectedFromStation.code,
      fromStationCode: journeyData.userSelectedFromStation.code,
      fromStationName: journeyData.userSelectedFromStation.name,
      toStationId: journeyData.userSelectedToStation.id ?? journeyData.userSelectedToStation.code,
      toStationCode: journeyData.userSelectedToStation.code,
      toStationName: journeyData.userSelectedToStation.name,
      selectedDate: journeyData.selectedDate,
      userSelectedDepartureTime: journeyData.userSelectedDepartureTime,
      userSelectedArrivalTime: journeyData.userSelectedArrivalTime,
      actualArrivalTime: actualArrivalTime,
      journeyDurationMinutes: journeyDurationMinutes,
      segmentCount: journeyData.segments.count,
      routeIds: routeIds,
      completionType: completionType,
      wasTrackedUntilArrival: wasTrackedUntilArrival
    )
  }

  // MARK: - Private Helpers

  private func journeyToRecord(_ journey: CompletedJourney) throws -> CKRecord {
    let recordID = CKRecord.ID(recordName: journey.id, zoneID: CKRecordZone.ID(zoneName: "default"))
    let record = CKRecord(recordType: Constants.recordType, recordID: recordID)

    record["trainId"] = journey.trainId
    record["trainCode"] = journey.trainCode
    record["trainName"] = journey.trainName
    record["fromStationId"] = journey.fromStationId
    record["fromStationCode"] = journey.fromStationCode
    record["fromStationName"] = journey.fromStationName
    record["toStationId"] = journey.toStationId
    record["toStationCode"] = journey.toStationCode
    record["toStationName"] = journey.toStationName
    record["selectedDate"] = journey.selectedDate
    record["userSelectedDepartureTime"] = journey.userSelectedDepartureTime
    record["userSelectedArrivalTime"] = journey.userSelectedArrivalTime
    record["actualArrivalTime"] = journey.actualArrivalTime
    record["journeyDurationMinutes"] = journey.journeyDurationMinutes
    record["segmentCount"] = journey.segmentCount
    record["routeIds"] = journey.routeIds.map { $0 ?? "" }
    record["completionType"] = journey.completionType
    record["wasTrackedUntilArrival"] = journey.wasTrackedUntilArrival

    return record
  }

  private func recordToJourney(_ record: CKRecord) throws -> CompletedJourney {
    guard let trainId = record["trainId"] as? String,
      let trainCode = record["trainCode"] as? String,
      let trainName = record["trainName"] as? String,
      let fromStationId = record["fromStationId"] as? String,
      let fromStationCode = record["fromStationCode"] as? String,
      let fromStationName = record["fromStationName"] as? String,
      let toStationId = record["toStationId"] as? String,
      let toStationCode = record["toStationCode"] as? String,
      let toStationName = record["toStationName"] as? String,
      let selectedDate = record["selectedDate"] as? Date,
      let userSelectedDepartureTime = record["userSelectedDepartureTime"] as? Date,
      let userSelectedArrivalTime = record["userSelectedArrivalTime"] as? Date,
      let actualArrivalTime = record["actualArrivalTime"] as? Date,
      let journeyDurationMinutes = record["journeyDurationMinutes"] as? Int,
      let segmentCount = record["segmentCount"] as? Int,
      let completionType = record["completionType"] as? String,
      let wasTrackedUntilArrival = record["wasTrackedUntilArrival"] as? Bool
    else {
      throw JourneyHistoryError.invalidRecordData
    }

    let routeIdsArray = record["routeIds"] as? [Any] ?? []
    let routeIds = routeIdsArray.map { item -> String? in
      if let string = item as? String {
        return string
      } else if item is NSNull {
        return nil
      }
      return nil
    }

    return CompletedJourney(
      id: record.recordID.recordName,
      trainId: trainId,
      trainCode: trainCode,
      trainName: trainName,
      fromStationId: fromStationId,
      fromStationCode: fromStationCode,
      fromStationName: fromStationName,
      toStationId: toStationId,
      toStationCode: toStationCode,
      toStationName: toStationName,
      selectedDate: selectedDate,
      userSelectedDepartureTime: userSelectedDepartureTime,
      userSelectedArrivalTime: userSelectedArrivalTime,
      actualArrivalTime: actualArrivalTime,
      journeyDurationMinutes: journeyDurationMinutes,
      segmentCount: segmentCount,
      routeIds: routeIds,
      completionType: completionType,
      wasTrackedUntilArrival: wasTrackedUntilArrival,
    )
  }

  private func handleCloudKitError(_ error: CKError, operation: String) throws {
    switch error.code {
    case .networkUnavailable:
      logger.warning("CloudKit network unavailable during \(operation)")
      // Don't throw - allow retry later
      throw error

    case .quotaExceeded:
      logger.error("CloudKit quota exceeded during \(operation)")
      // Log but don't block - user can't do anything about this
      throw error

    case .notAuthenticated:
      logger.info("User not authenticated with iCloud during \(operation) - silent failure")
      // Silent failure - user may not be signed into iCloud
      throw error

    case .partialFailure:
      if let partialErrors = error.partialErrorsByItemID {
        logger.error(
          "CloudKit partial failure during \(operation): \(partialErrors.count) items failed")
        for (_, itemError) in partialErrors {
          logger.error("Partial error: \(itemError.localizedDescription, privacy: .public)")
        }
      }
      throw error

    case .serverResponseLost, .serviceUnavailable, .requestRateLimited:
      logger.warning(
        "CloudKit service issue during \(operation): \(error.localizedDescription, privacy: .public)"
      )
      throw error

    default:
      logger.error(
        "CloudKit error during \(operation): \(error.localizedDescription, privacy: .public), code: \(error.code.rawValue)"
      )
      throw error
    }
  }
}

// MARK: - Errors

enum JourneyHistoryError: LocalizedError {
  case invalidRecordData

  var errorDescription: String? {
    switch self {
    case .invalidRecordData:
      return "Invalid CloudKit record data"
    }
  }
}
