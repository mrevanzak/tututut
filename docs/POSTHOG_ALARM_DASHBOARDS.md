# PostHog Alarm Analytics Dashboards

This document provides an overview of the alarm analytics dashboards in PostHog, explaining key metrics, how to interpret results, and action items based on the data.

## Dashboard Overview

Five dedicated dashboards have been created to track alarm feature performance:

1. **Alarm Adoption** - Track how users adopt and enable alarm features
2. **Alarm Effectiveness** - Measure alarm performance and user engagement
3. **Alarm Timing & Preferences** - Analyze user preferences for alarm timing
4. **Alarm Reliability** - Monitor system reliability and failure rates
5. **Alarm User Journey** - Complete user flow analysis

## Accessing Dashboards

All dashboards are available in PostHog:

- Navigate to Dashboards in the PostHog sidebar
- Look for dashboards prefixed with "Alarm"
- Each dashboard URL is accessible directly from the dashboard list

## Dashboard Details

### 1. Alarm Adoption Dashboard

**Purpose:** Track how many users enable and use alarm features.

**Key Insights:**

- **Alarm Authorization Granted (Daily)**: Daily count of users granting AlarmKit permission
- **Alarm Adoption Rate**: Ratio of `alarm_authorization_granted` to `journey_started` events
- **Alarm Enablement Rate**: Percentage of journeys started with `has_alarm_enabled=true`
- **First-Time Alarm Setup Funnel**: Conversion funnel from authorization request → grant → configuration

**How to Interpret:**

- **High adoption rate (>80%)**: Most users are enabling alarms - feature is well-received
- **Low adoption rate (<50%)**: Users may not understand the value or encounter friction
- **Funnel drop-offs**: Identify where users abandon the setup process
  - High drop-off at authorization → may need better permission explanation
  - High drop-off at configuration → setup flow may be too complex

**Action Items:**

- If adoption is low: Review onboarding flow, improve permission request messaging
- If funnel has high drop-off: Simplify setup process, add tooltips/help text
- Monitor trends: Track adoption over time to measure impact of improvements

### 2. Alarm Effectiveness Dashboard

**Purpose:** Measure how well alarms perform and whether they help users.

**Key Insights:**

- **Alarm Trigger Rate**: Ratio of `alarm_triggered` to `alarm_scheduled` events
  - Ideal: Close to 100% (all scheduled alarms should trigger)
  - Low rate: Alarms may be cancelled before triggering or system issues

**How to Interpret:**

- **High trigger rate (>95%)**: Alarms are reliably firing
- **Low trigger rate (<80%)**: Many alarms cancelled before triggering - investigate why
- **Alarm-to-arrival correlation**: Time between alarm and actual arrival
  - Good: Alarm fires 5-15 minutes before arrival (as configured)
  - Bad: Large discrepancy suggests timing calculation issues

**Action Items:**

- If trigger rate is low: Investigate cancellation reasons (see Reliability dashboard)
- If timing is off: Review alarm time calculation logic
- Monitor dismissal rates: High dismissal may indicate alarms are too early/late

### 3. Alarm Timing & Preferences Dashboard

**Purpose:** Understand user preferences for alarm timing.

**Key Insights:**

- **Alarm Offset Distribution**: Histogram showing most common offset values (1-60 minutes)
- **Average Alarm Offset**: Trend of average offset over time
- **Alarm Configuration Changes**: Timeline of when users change preferences

**How to Interpret:**

- **Peak offset values**: Most users prefer specific offsets (e.g., 10 minutes)
  - Use this to set better defaults
- **Average offset trends**:
  - Increasing: Users want more warning time
  - Decreasing: Users want less warning time
- **Configuration change frequency**:
  - Low: Users are satisfied with defaults
  - High: Default may not be optimal

**Action Items:**

- Update default offset: If distribution shows clear preference, update default
- A/B test defaults: Try different defaults for new users
- Monitor changes: If users frequently change, consider per-journey customization

### 4. Alarm Reliability Dashboard

**Purpose:** Monitor system health and identify issues.

**Key Insights:**

- **Alarm Scheduling Failure Rate**: Ratio of `alarm_scheduling_failed` to total scheduling attempts
- **Authorization Denial Rate**: Percentage of authorization requests denied
- **Alarm Cancellation Reasons**: Breakdown by reason (journey_ended, user_cancelled, manual_cancel, rescheduled)

**How to Interpret:**

- **Scheduling failure rate**:
  - <1%: System is healthy
  - > 5%: Investigate error reasons, check AlarmKit integration
- **Authorization denial rate**:
  - <10%: Normal user behavior
  - > 30%: Users may not understand value, improve messaging
- **Cancellation reasons**:
  - High "journey_ended": Normal - alarms cancelled when journey completes
  - High "user_cancelled": Users may be disabling alarms manually
  - High "rescheduled": Users frequently changing preferences

**Action Items:**

- If failure rate is high: Review error logs, check AlarmKit API status
- If denial rate is high: Improve permission request UX, explain benefits
- If many manual cancellations: Investigate why users are disabling alarms

### 5. Alarm User Journey Dashboard

**Purpose:** Complete flow analysis from journey start to completion.

**Key Insights:**

- **Complete Alarm Flow Funnel**:
  - Journey Started (with alarm) → Alarm Scheduled → Alarm Triggered → Alarm Dismissed → Journey Completed
- **Time to Alarm from Journey Start**: Average time between journey start and alarm scheduling
- **Alarm Rescheduling Frequency**: How often users reschedule alarms

**How to Interpret:**

- **Funnel conversion rates**:
  - Each step should have high conversion (>90%)
  - Low conversion at any step indicates a problem
- **Time to alarm**:
  - Should be immediate (<1 minute) - alarms scheduled right after journey starts
  - Delays may indicate system issues
- **Rescheduling frequency**:
  - Low: Users are satisfied with defaults
  - High: Defaults may need adjustment

**Action Items:**

- Identify funnel bottlenecks: Focus improvements on steps with low conversion
- Optimize scheduling: Ensure alarms are scheduled immediately after journey start
- Reduce rescheduling: If frequent, improve default offset selection

## Key Metrics Summary

### Health Indicators

- **Adoption Rate**: >70% of journeys should have alarms enabled
- **Trigger Rate**: >95% of scheduled alarms should trigger
- **Failure Rate**: <1% of scheduling attempts should fail
- **Authorization Rate**: >80% of requests should be granted

### Warning Signs

- Adoption rate dropping over time
- Trigger rate <80%
- Failure rate >5%
- High cancellation rate for non-journey reasons
- Frequent rescheduling (>20% of users)

## Using the Data

### Weekly Review

1. Check Alarm Adoption dashboard for trends
2. Review Alarm Reliability for system health
3. Examine Alarm Effectiveness for user satisfaction
4. Use Alarm Timing & Preferences to inform product decisions

### Monthly Analysis

1. Compare adoption rates month-over-month
2. Identify patterns in user preferences
3. Review cancellation reasons for insights
4. Update defaults based on distribution data

### Product Decisions

- **Default Offset**: Use distribution data to set optimal default
- **Onboarding**: Improve setup flow based on funnel drop-offs
- **Feature Prioritization**: Focus on areas with low conversion rates
- **Bug Fixes**: Prioritize issues causing high failure rates

## Dashboard URLs

All dashboards are accessible in PostHog:

- Alarm Adoption: Dashboard ID 777010
- Alarm Effectiveness: Dashboard ID 777011
- Alarm Timing & Preferences: Dashboard ID 777012
- Alarm Reliability: Dashboard ID 777013
- Alarm User Journey: Dashboard ID 777014

## Related Documentation

- [Analytics Events Guide](./analytics-events.md) - Complete event catalog
- [Product Documentation](../PRODUCT_DOCUMENTATION.md) - Feature overview
