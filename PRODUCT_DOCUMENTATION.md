# Kreta - Product Documentation for Product Owners & Managers

## Table of Contents

1. [Product Overview](#product-overview)
2. [Key Features](#key-features)
3. [User Journeys](#user-journeys)
4. [Analytics & Metrics](#analytics--metrics)
5. [Technical Architecture](#technical-architecture)
6. [Current Capabilities](#current-capabilities)
7. [Business Requirements](#business-requirements)
8. [Success Metrics](#success-metrics)
9. [Known Limitations](#known-limitations)
10. [Future Considerations](#future-considerations)

---

## Product Overview

**Product Name:** Kreta (Indonesian for "Train")

**Platform:** iOS (iOS 26.0+ required for full feature set, iOS 16.1+ for Live Activities)

**Target Market:** Indonesian railway passengers who need real-time train tracking and journey management

**Value Proposition:**

- Real-time train position tracking on interactive maps
- Proactive arrival notifications to prevent missing stops
- Live journey updates directly on the lock screen
- Journey planning with station-to-station search
- User feedback system for continuous improvement

**Business Model:** To be defined (current implementation appears to be end-user focused)

---

## Key Features

### 1. Real-Time Train Tracking

**Status:** ✅ Implemented

- **What:** Users can search for and track Indonesian trains in real-time on an interactive map
- **How:** Train positions are projected using journey data and displayed with moving markers
- **User Benefit:** Know exactly where your train is during the journey
- **Technical:** Uses ConvexMobile SDK for real-time data synchronization

### 2. Journey Management

**Status:** ✅ Implemented

**Components:**

- **Station Search:** Users can search from thousands of Indonesian railway stations
- **Connected Routes:** System shows only valid routes between stations
- **Date/Time Selection:** Users select departure date and time
- **Train Selection:** Available trains are displayed with schedules and journey details

**User Flow:**

1. Select departure station
2. Select arrival station (filtered to connected routes only)
3. Choose departure date
4. Select specific train from available options
5. Start tracking

### 3. Live Activities (Lock Screen Widget)

**Status:** ✅ Implemented

**What:** iOS Live Activities show journey progress on the lock screen and Dynamic Island

**Information Displayed:**

- Current journey state (idle, on board, prepare to drop off, arrived)
- Train name and route
- Departure and arrival stations
- Estimated times
- Journey progress indicator

**States:**

- **Idle:** Journey hasn't started yet
- **On Board:** Currently traveling
- **Prepare to Drop Off:** Approaching destination (triggered by alarm)
- **Arrived:** Journey completed

**Business Value:**

- Keeps users engaged without opening the app
- Reduces anxiety about missing stops
- Premium iOS experience

### 4. Arrival Alarms

**Status:** ✅ Implemented (using AlarmKit)

**What:** Critical alerts that notify users before arriving at their destination

**Features:**

- Configurable advance warning time (default: 10 minutes before arrival)
- Uses AlarmKit for prominent, override-silent notifications
- Per-journey alarm preferences
- Automatically transitions Live Activity to "Prepare to Drop Off" state
- Alarms can be enabled/disabled per journey

**User Benefit:** Prevents missing your station even if you fall asleep or get distracted

**Technical Note:** Requires iOS 26.0+ and user authorization for AlarmKit

### 5. Arrival Confirmation

**Status:** ✅ Implemented

**What:** Dedicated arrival screen when users reach their destination

**Features:**

- Visual celebration of journey completion
- "Sip!" (Indonesian slang for "got it!") confirmation button
- Automatic deep linking from notifications
- Pulsing animation for attention

**Business Value:** Completes the user journey loop, provides opportunity for cross-sell or feedback

### 6. Feedback System

**Status:** ✅ Implemented

**What:** Users can submit and view feedback about the app

**Features:**

- Public feedback board showing all submissions
- Categorized feedback (general, journey, accuracy, UI/UX, performance, feature request, bug report)
- Upvoting system for prioritization
- Detailed feedback cards with user information
- Real-time updates via Convex

**Business Value:**

- Direct channel for user insights
- Community-driven feature prioritization
- Transparent product development

### 7. Analytics & Event Tracking

**Status:** ✅ Implemented (Recent Addition)

**What:** Comprehensive analytics instrumentation using PostHog

**Events Tracked:**

- Journey lifecycle (started, cancelled, completed)
- User engagement (searches, selections, confirmations)
- Technical events (deep links, notifications, Live Activity states)
- Alarms (scheduled, triggered)
- Round-trip detection (coming back within 7 days)

**See [Analytics & Metrics](#analytics--metrics) section for details**

---

## User Journeys

### Primary Journey: Track a Train Journey

```
1. User opens app
   ↓
2. Taps "Add Train" or searches for journey
   ↓
3. Selects departure station
   ↓
4. Selects arrival station
   ↓
5. Chooses departure date
   ↓
6. Selects specific train from list
   ↓
7. Journey starts → Live Activity appears on lock screen
   ↓
8. [Optional] Alarm is scheduled (10 min before arrival)
   ↓
9. User travels while app projects train position
   ↓
10. [Alarm fires] → Live Activity transitions to "Prepare to Drop Off"
    ↓
11. Arrival notification → Deep links to arrival screen
    ↓
12. User confirms arrival with "Sip!" button
    ↓
13. Journey complete → Analytics recorded
```

**Drop-off Points:**

- User cancels journey (tracked as `journey_cancelled`)
- User doesn't start journey after selection
- Network connectivity issues

### Secondary Journey: Browse Feedback

```
1. User navigates to Feedback tab
   ↓
2. Views community feedback cards
   ↓
3. [Optional] Upvotes feedback they agree with
   ↓
4. [Optional] Submits new feedback
```

### Administrative Journey: Monitor Analytics

```
1. PM/Manager accesses PostHog dashboard
   ↓
2. Reviews key metrics:
   - Journey completion rate
   - Alarm usage
   - Round-trip frequency
   - Feature adoption
   ↓
3. Identifies optimization opportunities
   ↓
4. Prioritizes roadmap items
```

---

## Analytics & Metrics

### Event Taxonomy

The app tracks a comprehensive set of events through `AnalyticsEventService`. All events are sent to PostHog and Sentry.

#### 1. Core Journey Events

| Event Name             | Trigger                                     | Key Properties                                                                               | Business Value                                   |
| ---------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `journey_started`      | User starts tracking a train                | train_id, train_name, from/to stations, departure/arrival times, duration, has_alarm_enabled | Measures journey initiation rate, alarm adoption |
| `journey_cancelled`    | User ends journey before arrival            | train_id, reason, context                                                                    | Understand why users abandon journeys            |
| `journey_completed`    | Journey reaches destination                 | train_id, stations, duration, completion_type, was_tracked_until_arrival                     | Core success metric - completed journeys         |
| `round_trip_completed` | User completes return journey within 7 days | days_between_trips, is_reverse_direction                                                     | Measure repeat usage and commuter behavior       |

#### 2. Engagement Events

| Event Name               | Trigger                       | Key Properties                                               | Business Value                  |
| ------------------------ | ----------------------------- | ------------------------------------------------------------ | ------------------------------- |
| `train_search_initiated` | User starts adding a train    | -                                                            | Measure feature discoverability |
| `station_selected`       | User picks a station          | station_id, station_name, selection_type (departure/arrival) | Track station popularity        |
| `train_selected`         | User chooses a train          | train_id, code, name, stations, times                        | Measure train popularity        |
| `arrival_confirmed`      | User dismisses arrival screen | station_code, station_name                                   | Journey completion confirmation |

#### 3. Live Activity & Alarm Events

| Event Name                    | Trigger                    | Key Properties                                         | Business Value                        |
| ----------------------------- | -------------------------- | ------------------------------------------------------ | ------------------------------------- |
| `live_activity_state_changed` | Activity transitions state | activity_id, state, train_name                         | Track engagement with Live Activities |
| `alarm_scheduled`             | Alarm set for journey      | activity_id, arrival_time, offset_minutes, destination | Measure alarm usage                   |
| `alarm_triggered`             | Alarm fires                | activity_id, triggered_at                              | Validate alarm reliability            |

#### 4. Technical Events

| Event Name                 | Trigger                          | Key Properties               | Business Value                     |
| -------------------------- | -------------------------------- | ---------------------------- | ---------------------------------- |
| `deep_link_opened`         | User taps notification/link      | url, params                  | Track notification engagement      |
| `notification_interaction` | User interacts with notification | identifier, category, action | Measure notification effectiveness |

### Journey History Storage

The app maintains a rolling history of the last 10 completed journeys for each user, enabling:

- **Round-trip detection:** Identifies when users make return journeys within 7 days
- **Travel pattern analysis:** Understand commuter vs. occasional traveler behavior
- **Personalization opportunities:** Future feature to suggest frequent routes

---

## Technical Architecture

### High-Level Stack

```
┌─────────────────────────────────────────┐
│           iOS Native App                │
│         (Swift + SwiftUI)               │
├─────────────────────────────────────────┤
│  - Train Tracking UI                    │
│  - Live Activities Widget               │
│  - AlarmKit Integration                 │
│  - Analytics Service                    │
└─────────────────┬───────────────────────┘
                  │
                  │ Real-time WebSocket + HTTP
                  │
┌─────────────────▼───────────────────────┐
│      Convex Backend (Bun Runtime)       │
├─────────────────────────────────────────┤
│  - Journey Data Queries                 │
│  - Station & Route Data                 │
│  - Feedback Storage                     │
│  - Push Notification Dispatch           │
└─────────────────────────────────────────┘
```

### Key Technologies

**Frontend (iOS):**

- **Language:** Swift 5.9+ with SwiftUI
- **State Management:** Observation framework (`@Observable`)
- **Real-time Data:** ConvexMobile SDK
- **Analytics:** PostHog (events), Sentry (errors)
- **Notifications:** AlarmKit (critical alarms), UserNotifications (standard)
- **Maps:** MapKit with custom train projection

**Backend:**

- **Runtime:** Bun v1.2+
- **Database:** Convex (real-time, cloud-hosted)
- **Push Notifications:** Apple Push Notification Service (APNs)

**Data Flow:**

1. User actions → Analytics events sent to PostHog
2. UI interactions → Swift Observation updates → SwiftUI re-renders
3. Journey data → Convex queries/subscriptions → Real-time UI updates
4. Alarms → AlarmKit schedules → System triggers → App handles
5. Feedback → Convex mutations → Real-time board updates

### Architecture Patterns

- **MVVM:** View Models contain UI logic, Stores manage state, Services handle business logic
- **Dependency Injection:** Centralized `Dependencies` singleton for shared services
- **Reactive:** Convex subscriptions + SwiftUI Observation for real-time updates
- **Offline-First:** Local caching via `TrainMapCacheService` + Disk framework

---

## Current Capabilities

### ✅ Implemented Features

1. **Journey Management**

   - Multi-step station and train selection
   - Connected route validation
   - Date-based journey planning
   - Real-time train position projection

2. **Live Activities**

   - Lock screen widget with journey progress
   - Dynamic Island integration (iPhone 17 Pro)
   - State machine (idle → on board → prepare to drop off → arrived)
   - Automatic state transitions

3. **Arrival Alarms**

   - AlarmKit integration for critical alerts
   - Configurable offset (default 10 minutes before arrival)
   - Per-journey and global preferences
   - Automatic Live Activity synchronization

4. **Deep Linking**

   - URL scheme: `kreta://`
   - Notification-driven navigation
   - Arrival screen deep linking

5. **Analytics Instrumentation**

   - Full journey lifecycle tracking
   - Round-trip detection
   - Engagement event tracking
   - Technical event monitoring

6. **Feedback System**
   - Public feedback board
   - Categorized submissions
   - Upvoting for prioritization
   - Real-time updates

### 🚧 Partially Implemented

1. **Error Handling**

   - Network error recovery present but could be enhanced
   - User-facing error messages standardized via `showMessage` environment action

2. **Onboarding**
   - No first-time user experience flow
   - No feature discovery or tutorial

### ❌ Not Yet Implemented

1. **User Accounts**

   - No authentication or user profiles
   - No journey history storage (beyond analytics)
   - No saved favorite stations

2. **Offline Mode**

   - Caching exists but full offline experience not complete
   - No offline queue for analytics events

3. **Payments/Monetization**

   - No premium features or subscriptions
   - No in-app purchases

4. **Social Features**

   - No journey sharing
   - No social media integration
   - Feedback is public but not commentable

5. **Advanced Journey Features**
   - No multi-leg journeys (transfers)
   - No seat selection or class preferences
   - No delay notifications or schedule changes

---

## Business Requirements

### Must-Have for Public Launch

1. **Privacy Compliance**

   - ✅ AlarmKit usage description in Info.plist
   - ✅ Location permission handling
   - ⚠️ Privacy policy needs creation
   - ⚠️ Data retention policy definition
   - ⚠️ GDPR compliance audit (if targeting EU)

2. **Error Handling**

   - ✅ Network error recovery
   - ⚠️ User-friendly error messages need review
   - ❌ Offline mode needs completion

3. **Onboarding**

   - ❌ First-time user tutorial
   - ❌ Feature highlight tour
   - ❌ Permission request explanations

4. **Analytics Dashboard**

   - ✅ Event instrumentation complete
   - ⚠️ Dashboard setup needed in PostHog
   - ⚠️ Key metric alerts/monitoring

5. **Testing**
   - ✅ Unit tests for core services
   - ⚠️ UI/Integration tests needed
   - ⚠️ Beta testing program

### Nice-to-Have

1. **User Accounts** - Enable personalization and journey history
2. **Push Notification Opt-in Flow** - Improve alarm adoption
3. **Multi-language Support** - Currently English/Indonesian mixed
4. **Accessibility Audit** - Ensure VoiceOver, Dynamic Type support
5. **Feedback Response System** - Allow team to respond to feedback

---

## Success Metrics

### North Star Metric

**Completed Journeys per Active User per Week**

- Measures core product value delivery
- Target: TBD (establish baseline first)

### Primary Metrics

| Metric                      | Definition                                    | Target                        | Current Status       |
| --------------------------- | --------------------------------------------- | ----------------------------- | -------------------- |
| **Journey Completion Rate** | (completed_journeys / started_journeys) × 100 | >85%                          | 🔍 Needs measurement |
| **Alarm Adoption Rate**     | (journeys_with_alarm / total_journeys) × 100  | >70%                          | 🔍 Needs measurement |
| **Round-Trip Rate**         | (users_with_round_trip / active_users) × 100  | >40%                          | 🔍 Needs measurement |
| **D1/D7/D30 Retention**     | % users returning after 1/7/30 days           | D1: >40%, D7: >20%, D30: >10% | 🔍 Needs measurement |

### Secondary Metrics

- **Time to First Journey:** From app install to first `journey_started`
- **Live Activity Engagement:** % of journeys with Live Activity viewed
- **Station Search Success Rate:** % searches resulting in journey start
- **Feedback Submission Rate:** % active users submitting feedback
- **Alarm Trigger Accuracy:** % alarms firing within expected window

### Technical Health Metrics

- **Crash-Free Rate:** >99.5%
- **API Response Time (p95):** <2 seconds
- **Real-time Sync Latency:** <1 second
- **Battery Impact:** <5% per hour during active tracking

---

## Known Limitations

### Technical Limitations

1. **iOS Version Requirements**

   - AlarmKit requires iOS 26.0+ (very new, limits audience)
   - Live Activities require iOS 16.1+
   - Observation framework requires iOS 17+
   - **Recommendation:** Monitor iOS adoption rates for iOS 26

2. **Real-Time Position Accuracy**

   - Train positions are _projected_ based on schedule, not actual GPS
   - No integration with real-time train location APIs
   - **Impact:** Position may be inaccurate if train is delayed
   - **Recommendation:** Investigate Indonesian railway real-time data APIs

3. **Offline Limitations**

   - Requires network connection for train search and journey start
   - Live Activity updates won't work offline
   - **Recommendation:** Implement offline journey continuation

4. **AlarmKit Authorization**
   - Users must explicitly grant AlarmKit permission
   - Permission flow may be confusing to users
   - **Recommendation:** Create clear educational flow

### Business Limitations

1. **No Revenue Model**

   - Free app with no monetization currently
   - **Recommendation:** Define business model before scale

2. **Single Market**

   - Indonesia-specific railway data only
   - **Opportunity:** Could expand to other Southeast Asian countries

3. **No Ticket Integration**

   - Users must purchase tickets elsewhere
   - **Opportunity:** Partner with Indonesian railway ticketing system

4. **Limited Journey Types**
   - No support for multi-leg journeys or transfers
   - **Impact:** Limits usefulness for complex trips

---

## Future Considerations

### Short-Term Opportunities (0-3 months)

1. **Onboarding Flow**

   - First-time user tutorial highlighting key features
   - Permission request education (especially AlarmKit)
   - **Effort:** Medium | **Impact:** High (improves activation)

2. **Analytics Dashboard Setup**

   - Configure PostHog dashboards for key metrics
   - Set up alerts for anomalies
   - **Effort:** Low | **Impact:** High (enables data-driven decisions)

3. **Error Recovery Improvements**

   - Better offline experience
   - Retry logic for failed operations
   - **Effort:** Medium | **Impact:** Medium (reduces frustration)

4. **Journey History**
   - Show users their past journeys
   - Quick-restart previous journeys
   - **Effort:** Medium | **Impact:** Medium (increases engagement)

### Mid-Term Opportunities (3-6 months)

1. **User Accounts**

   - Authentication system
   - Cross-device journey sync
   - Favorite stations
   - **Effort:** High | **Impact:** High (enables personalization)

2. **Real-Time Train Data Integration**

   - Replace projected positions with actual GPS data
   - Show delay information
   - **Effort:** High (depends on API availability) | **Impact:** Very High (core value)

3. **Multi-Leg Journey Support**

   - Plan journeys with transfers
   - Coordinate alarms for transfers
   - **Effort:** High | **Impact:** Medium (serves complex trips)

4. **Social Features**
   - Share journey with friends/family
   - Journey completion achievements
   - **Effort:** Medium | **Impact:** Medium (viral growth potential)

### Long-Term Opportunities (6+ months)

1. **Ticket Integration**

   - In-app ticket purchase
   - QR code ticket storage
   - **Effort:** Very High (requires partnerships) | **Impact:** Very High (platform play)

2. **Premium Features**

   - Ad-free experience
   - Advanced notifications
   - Priority support
   - **Effort:** Medium | **Impact:** High (revenue generation)

3. **Regional Expansion**

   - Add Malaysian railways
   - Add Thai railways
   - **Effort:** High | **Impact:** High (market expansion)

4. **AI-Powered Features**
   - Smart delay predictions
   - Journey recommendations based on history
   - Crowd-sourced delay reporting
   - **Effort:** Very High | **Impact:** Medium (differentiation)

---

## Appendices

### A. Key Terminology

- **Live Activity:** iOS lock screen widget showing real-time updates
- **AlarmKit:** iOS framework for critical, time-sensitive alerts that override silent mode
- **Deep Link:** URL that opens specific app content (e.g., `kreta://arrival?code=PSE`)
- **Convex:** Real-time database backend with WebSocket subscriptions
- **Journey State:** Current phase of travel (idle, on board, prepare to drop off, arrived)
- **Projected Train:** Calculated train position based on schedule interpolation

### B. Important File Locations

**Analytics:**

- `Client/Sources/Services/AnalyticsEventService.swift` - All analytics event definitions
- `Client/kretaTests/AnalyticsEventServiceTests.swift` - Analytics tests

**Core Services:**

- `Client/Sources/Stores/TrainMapStore.swift` - Main train tracking state
- `Client/Sources/Services/TrainLiveActivityService.swift` - Live Activity management
- `Client/Sources/Services/TrainAlarmService.swift` - Alarm scheduling
- `Client/Sources/View Models/AddTrainViewModel.swift` - Journey selection flow

**Backend:**

- `Server/convex/journeys.ts` - Journey data queries
- `Server/convex/station.ts` - Station data
- `Server/convex/feedback.ts` - Feedback system
- `Server/convex/push.ts` - Push notification dispatch

### C. Contact Information

**Development Team:** [To be filled]
**Product Owner:** [To be filled]
**Analytics Access:** PostHog dashboard (URL to be configured)
**Error Monitoring:** Sentry dashboard (configured in Constants.swift)

---

## Document Version

**Version:** 1.0
**Last Updated:** November 5, 2025
**Next Review:** December 5, 2025

**Change Log:**

- v1.0 (2025-11-05): Initial documentation created with comprehensive analytics instrumentation details

---

## Questions for Product Strategy

1. **Business Model:** What is the intended revenue model for Kreta?

   - Freemium with premium features?
   - Advertising-supported?
   - Partnership/commission with railway operators?

2. **Target Audience:** Who is the primary user?

   - Daily commuters?
   - Occasional travelers?
   - Tourists?
   - All of the above?

3. **Market Position:** What is our competitive advantage?

   - Only real-time tracking app?
   - Better UX than competitors?
   - Integration with ticketing?

4. **Growth Strategy:** How will we acquire users?

   - App Store optimization?
   - Social media?
   - Railway station promotions?
   - Word of mouth?

5. **Priority:** Which limitation should we address first?
   - Real-time GPS data integration?
   - User accounts and personalization?
   - Onboarding and education?
   - Monetization features?

**Recommendation:** Schedule a product strategy session to answer these questions and prioritize the roadmap accordingly.
