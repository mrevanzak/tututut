# Analytics & Telemetry Guide

This document describes the analytics and error telemetry implemented in the iOS client, with a focus on journey lifecycle events, round-trip detection, and engagement tracking. Analytics is powered by PostHog via the app-wide `Telemetry` abstraction.

## Quick start

- Destination: PostHog (`Constants.PostHog.host`), API key from `POSTHOG_API_KEY` (env or Info.plist).
- SDK setup happens in `AppDelegate` at launch. Screen auto-capture is disabled by default.
- Base context added to every event:
  - `app_env`: development | production
  - `app_release`: e.g. `ios@1.0(1)`

## Event catalog

### Core journey

- `journey_started`: Live Activity is started for a selected journey
- `journey_completed`: Journey reached destination (arrival screen or scheduled arrival time)
- `journey_cancelled`: Journey ended before expected arrival
- `round_trip_completed`: A second journey completed within 7 days of a prior journey

### User engagement

- `train_search_initiated`: AddTrain flow opened and bootstrapped
- `station_selected`: User picked a departure or arrival station
- `train_selected`: User selected a specific train from results
- `arrival_confirmed`: User tapped the confirmation on arrival screen

### Live Activity / alarms

- `live_activity_state_changed`: Activity transitioned to a new journey state (onBoard, prepareToDropOff)
- `alarm_authorization_requested`: User is prompted for AlarmKit permission
- `alarm_authorization_granted`: AlarmKit permission granted
- `alarm_authorization_denied`: AlarmKit permission denied
- `alarm_scheduled`: AlarmKit alarm was scheduled for arrival
- `alarm_scheduling_failed`: Alarm scheduling failed (error tracking)
- `alarm_triggered`: Alarm fired prior to arrival
- `alarm_cancelled`: Alarm was cancelled (journey ended, user cancelled, or rescheduled)
- `alarm_rescheduled`: Alarm was rescheduled for existing activity
- `alarm_dismissed`: User dismissed the alarm alert
- `alarm_interacted`: User interacted with alarm (if actions are added)
- `alarm_configured`: User configured alarm settings (offset, validation)
- `alarm_preference_changed`: Global alarm preferences changed (enabled/disabled, offset)

### Technical

- `deep_link_opened`: App handled a deep link (with parsed params)
- `notification_interaction`: User interacted with a push notification

## Event properties schema

Unless noted, all dates use ISO8601 strings.

- `journey_started`

  - `train_id` (String)
  - `train_name` (String)
  - `from_station_id` (String)
  - `from_station_name` (String)
  - `to_station_id` (String)
  - `to_station_name` (String)
  - `departure_time` (ISO8601)
  - `arrival_time` (ISO8601)
  - `journey_duration_minutes` (Int)
  - `time_until_departure_minutes` (Int)
  - `has_alarm_enabled` (Bool)

- `journey_completed`

  - `train_id` (String, when available)
  - `from_station_id` (String, when available)
  - `to_station_id` (String)
  - `journey_duration_actual_minutes` (Int)
  - `completion_type` ("arrival_screen" | "scheduled_arrival")
  - `was_tracked_until_arrival` (Bool)
  - `completed_at` (ISO8601)

- `journey_cancelled`

  - `train_id` (String)
  - `reason` (String, optional)
  - Additional context (optional): `expected_arrival_time` (ISO8601), `train_name` (String)

- `round_trip_completed`

  - `days_between_trips` (Int)
  - `is_reverse_direction` (Bool)
  - `previous_journey_id` (String; composed reference)

- `station_selected`

  - `station_id` (String)
  - `station_name` (String)
  - `selection_type` ("departure" | "arrival")

- `train_selected`

  - `train_id` (String)
  - `train_code` (String)
  - `train_name` (String)
  - `from_station_id` (String)
  - `to_station_id` (String)
  - `departure_time` (ISO8601)
  - `arrival_time` (ISO8601)

- `arrival_confirmed`

  - `station_code` (String)
  - `station_name` (String)

- `live_activity_state_changed`

  - `activity_id` (String)
  - `state` (String; e.g. "onBoard", "prepareToDropOff")
  - `train_name` (String)

- `alarm_authorization_requested`

  - `requested_at` (ISO8601)
  - `previous_state` (String; "notDetermined" | "denied" | "authorized")

- `alarm_authorization_granted`

  - `granted_at` (ISO8601)
  - `is_first_time` (Bool)

- `alarm_authorization_denied`

  - `denied_at` (ISO8601)
  - `was_previously_denied` (Bool)

- `alarm_scheduled`

  - `activity_id` (String)
  - `arrival_time` (ISO8601)
  - `alarm_offset_minutes` (Int)
  - `destination_code` (String)
  - `train_name` (String, optional)
  - `destination_name` (String, optional)
  - `alarm_time` (ISO8601, optional)
  - `time_until_alarm_minutes` (Int, optional)

- `alarm_scheduling_failed`

  - `activity_id` (String)
  - `error_reason` (String)
  - `arrival_time` (ISO8601)
  - `offset_minutes` (Int)
  - `attempted_at` (ISO8601)

- `alarm_triggered`

  - `activity_id` (String)
  - `triggered_at` (ISO8601)
  - `train_name` (String, optional)
  - `destination_name` (String, optional)
  - `offset_minutes` (Int, optional)
  - `actual_time_until_arrival_minutes` (Int, optional)

- `alarm_cancelled`

  - `activity_id` (String)
  - `cancellation_reason` (String; "journey_ended" | "user_cancelled" | "manual_cancel" | "rescheduled")
  - `was_triggered` (Bool)
  - `time_until_alarm_minutes` (Int, optional)

- `alarm_rescheduled`

  - `activity_id` (String)
  - `previous_offset_minutes` (Int)
  - `new_offset_minutes` (Int)
  - `previous_alarm_time` (ISO8601)
  - `new_alarm_time` (ISO8601)

- `alarm_dismissed`

  - `activity_id` (String)
  - `dismissed_at` (ISO8601)
  - `time_since_triggered_seconds` (Int)

- `alarm_interacted`

  - `activity_id` (String)
  - `action_type` (String)
  - `interacted_at` (ISO8601)

- `alarm_configured`

  - `alarm_offset_minutes` (Int)
  - `is_valid` (Bool)
  - `validation_failure_reason` (String, optional)
  - `configured_at` (ISO8601)
  - `is_initial_setup` (Bool, optional)
  - `previous_offset_minutes` (Int, optional)
  - `journey_duration_minutes` (Int, optional)
  - `validation_warnings` (Array<String>, optional)

- `alarm_preference_changed`

  - `preference_type` (String; "enabled" | "offset_minutes")
  - `previous_value` (Any)
  - `new_value` (Any)
  - `changed_at` (ISO8601)

- `deep_link_opened`

  - `url` (String)
  - Parsed parameters flattened into event properties (e.g. `code`, `name`)

- `notification_interaction`
  - `notification_identifier` (String?)
  - `category` (String?)
  - `action` (String?)

## Where events are emitted

- `Client/Sources/Stores/TrainMapStore.swift`

  - `selectTrain(_:journeyData:)` → `journey_started`
  - `clearSelectedTrain()` → `journey_cancelled` (before arrival) or `journey_completed` (at/after ETA)

- `Client/Sources/Services/TrainAlarmService.swift`

  - `requestAuthorization()` → `alarm_authorization_requested`, `alarm_authorization_granted`, `alarm_authorization_denied`
  - `scheduleArrivalAlarm(...)` → `alarm_scheduling_failed` (on error)
  - `cancelArrivalAlarm(...)` → `alarm_cancelled`
  - `cancelAllAlarms(...)` → `alarm_cancelled` (for each activity)

- `Client/Sources/Services/TrainLiveActivityService.swift`

  - `transitionToOnBoard(activityId:)` → `live_activity_state_changed` (onBoard)
  - `transitionToPrepareToDropOff(activityId:)` → `live_activity_state_changed` (prepareToDropOff)
  - `scheduleAlarmIfEnabled(...)` → `alarm_scheduled`
  - `handleAlarmTriggered(for:)` → `alarm_triggered` (enhanced with context)
  - `refreshAlarmConfiguration(...)` → `alarm_rescheduled`
  - `end(activityId:)` → `alarm_cancelled` (via TrainAlarmService)

- `Client/Sources/Utility/AlarmPreferences.swift`

  - `defaultAlarmEnabled` setter → `alarm_preference_changed`
  - `defaultAlarmOffsetMinutes` setter → `alarm_preference_changed`

- `Client/Sources/Stores/TrainMapStore.swift`

  - `applyAlarmConfiguration(...)` → `alarm_configured` (enhanced with context)

- `Client/Sources/Screens/TrainArriveScreen.swift`

  - `onAppear` → screen view (`Telemetry.screen`)
  - Arrival button → `arrival_confirmed` and `journey_completed` (minimal)

- `Client/Sources/View Models/AddTrainViewModel.swift`

  - `bootstrap(allStations:)` → `train_search_initiated`
  - `selectStation(_:)` → `station_selected` (with selection type)
  - `didSelect(_:)` → `train_selected`

- `Client/Sources/Navigation/Deep Linking/DeepLinkParser.swift`

  - Deep link parsers → `deep_link_opened`

- `Client/Sources/AppDelegate.swift`
  - `userNotificationCenter(_:didReceive:)` → `notification_interaction`

## Round-trip detection

- A round trip is recorded when a completed journey occurs within 7 days of a prior journey.
- Reverse direction is flagged when the route is the inverse (A→B then B→A).
- Storage: last 10 `JourneyRecord`s persisted in `UserDefaults` under `analytics.journeyHistory`.
- Emitted event: `round_trip_completed` with `days_between_trips`, `is_reverse_direction`, and a composed `previous_journey_id` reference.

## Verification checklist

Use a DEBUG build and the PostHog dashboard to verify:

- Start a journey → `journey_started` with full context appears
- End before ETA → `journey_cancelled`
- End at/after ETA or confirm arrival → `journey_completed`
- Two completions within 7 days → `round_trip_completed` (reverse direction flagged if applicable)
- Navigate AddTrain flow → `train_search_initiated`, `station_selected`, `train_selected`
- Request alarm permission → `alarm_authorization_requested`, `alarm_authorization_granted`/`denied`
- Configure alarm → `alarm_configured` (with validation context)
- Trigger alarm lifecycle → `alarm_scheduled`, `alarm_triggered`, `alarm_cancelled`
- Change alarm preferences → `alarm_preference_changed`
- Reschedule alarm → `alarm_rescheduled`
- Open via deep link → `deep_link_opened`
- Tap a notification → `notification_interaction`

## Privacy & performance notes

- Session replay is disabled (no screenshots, masked inputs/images).
- Centralized through `Telemetry` abstraction to enable future consent gating.
- Do not include PII in event properties; prefer IDs/codes.

## Configuration

- Set `POSTHOG_API_KEY` in the run scheme (env) or Info.plist.
- Ensure `CONVEX_URL` and optional `SENTRY_DSN` are also configured per environment.

## Change log

- Introduced comprehensive analytics for launch (journey lifecycle, round-trip, engagement, deep links, notifications).
- Enhanced alarm analytics: authorization tracking, scheduling failures, cancellations, rescheduling, preference changes, and enhanced context for all alarm events.
