import { v } from "convex/values";
import { query } from "./_generated/server";

/**
 * Query all stops for a specific train by train code
 * Use case: Display complete train schedule
 */
export const getTrainSchedule = query({
  args: {
    trainCode: v.string(),
  },
  handler: async (ctx, { trainCode }) => {
    const stops = await ctx.db
      .query("trainStops")
      .withIndex("by_trainCode", (q) => q.eq("trainCode", trainCode))
      .collect();

    if (stops.length === 0) {
      return null;
    }

    // Sort by stop sequence
    const sortedStops = stops.sort((a, b) => a.stopSequence - b.stopSequence);
    
    const firstStop = sortedStops[0];
    if (!firstStop) {
      return null;
    }

    return {
      trainCode: firstStop.trainCode,
      trainName: firstStop.trainName,
      trainId: firstStop.trainId,
      route: {
        origin: firstStop.routeOriginName,
        destination: firstStop.routeDestinationName,
      },
      totalStops: firstStop.totalStops,
      stops: sortedStops.map((stop) => ({
        sequence: stop.stopSequence,
        stationId: stop.stationId,
        stationCode: stop.stationCode,
        stationName: stop.stationName,
        city: stop.city,
        arrivalTime: stop.arrivalTime,
        departureTime: stop.departureTime,
        isOrigin: stop.isOrigin,
        isDestination: stop.isDestination,
      })),
    };
  },
});

/**
 * Find all trains that travel from departure station to arrival station
 * Use case: Search for trains between two stations
 */
export const findTrainsByRoute = query({
  args: {
    departureStationId: v.string(),
    arrivalStationId: v.string(),
  },
  handler: async (ctx, { departureStationId, arrivalStationId }) => {
    // Get all trains that stop at departure station
    const departureStops = await ctx.db
      .query("trainStops")
      .withIndex("by_stationId", (q) => q.eq("stationId", departureStationId))
      .collect();

    // Get all trains that stop at arrival station
    const arrivalStops = await ctx.db
      .query("trainStops")
      .withIndex("by_stationId", (q) => q.eq("stationId", arrivalStationId))
      .collect();

    // Find trains that stop at both stations
    const departureTrainIds = new Set(
      departureStops.map((stop) => stop.trainId)
    );
    const arrivalTrainIds = new Set(arrivalStops.map((stop) => stop.trainId));
    const commonTrainIds = [...departureTrainIds].filter((id) =>
      arrivalTrainIds.has(id)
    );

    // Check sequence and build journey details
    const journeys = [];
    for (const trainId of commonTrainIds) {
      const depStop = departureStops.find((s) => s.trainId === trainId);
      const arrStop = arrivalStops.find((s) => s.trainId === trainId);

      if (!depStop || !arrStop) continue;

      // Ensure departure comes before arrival
      if (depStop.stopSequence < arrStop.stopSequence) {
        journeys.push({
          trainId: depStop.trainId,
          trainCode: depStop.trainCode,
          trainName: depStop.trainName,
          departureStation: {
            id: depStop.stationId,
            code: depStop.stationCode,
            name: depStop.stationName,
            city: depStop.city,
          },
          departureTime: depStop.departureTime,
          departureSequence: depStop.stopSequence,
          arrivalStation: {
            id: arrStop.stationId,
            code: arrStop.stationCode,
            name: arrStop.stationName,
            city: arrStop.city,
          },
          arrivalTime: arrStop.arrivalTime,
          arrivalSequence: arrStop.stopSequence,
          stopsBetween: arrStop.stopSequence - depStop.stopSequence - 1,
        });
      }
    }

    return journeys;
  },
});

/**
 * Get detailed route information for a specific journey
 * Use case: Show intermediate stops between departure and arrival
 */
export const getRouteDetails = query({
  args: {
    trainCode: v.string(),
    departureStationId: v.string(),
    arrivalStationId: v.string(),
  },
  handler: async (ctx, { trainCode, departureStationId, arrivalStationId }) => {
    // Get all stops for this train
    const allStops = await ctx.db
      .query("trainStops")
      .withIndex("by_trainCode", (q) => q.eq("trainCode", trainCode))
      .collect();

    if (allStops.length === 0) {
      return null;
    }

    const sortedStops = allStops.sort(
      (a, b) => a.stopSequence - b.stopSequence
    );

    // Find departure and arrival stops
    const depStop = sortedStops.find(
      (s) => s.stationId === departureStationId
    );
    const arrStop = sortedStops.find((s) => s.stationId === arrivalStationId);

    if (!depStop || !arrStop || depStop.stopSequence >= arrStop.stopSequence) {
      return null;
    }

    // Get intermediate stops
    const routeStops = sortedStops.filter(
      (s) =>
        s.stopSequence >= depStop.stopSequence &&
        s.stopSequence <= arrStop.stopSequence
    );

    return {
      trainCode: depStop.trainCode,
      trainName: depStop.trainName,
      trainId: depStop.trainId,
      journey: {
        from: depStop.stationName,
        to: arrStop.stationName,
        departureTime: depStop.departureTime,
        arrivalTime: arrStop.arrivalTime,
        totalStops: routeStops.length,
      },
      stops: routeStops.map((stop) => ({
        sequence: stop.stopSequence,
        stationName: stop.stationName,
        city: stop.city,
        arrivalTime: stop.arrivalTime,
        departureTime: stop.departureTime,
      })),
    };
  },
});

/**
 * Get all trains (summary)
 * Use case: List all available trains
 */
export const listAllTrains = query({
  args: {},
  handler: async (ctx) => {
    // Get only origin stops (one per train)
    const originStops = await ctx.db
      .query("trainStops")
      .filter((q) => q.eq(q.field("isOrigin"), true))
      .collect();

    return originStops.map((stop) => ({
      trainId: stop.trainId,
      trainCode: stop.trainCode,
      trainName: stop.trainName,
      origin: stop.routeOriginName,
      destination: stop.routeDestinationName,
      totalStops: stop.totalStops,
    }));
  },
});

/**
 * Get all trains that stop at a specific station
 * Use case: Show train schedule for a station
 */
export const getTrainsAtStation = query({
  args: {
    stationId: v.string(),
  },
  handler: async (ctx, { stationId }) => {
    // Get all stops at this station
    const stops = await ctx.db
      .query("trainStops")
      .withIndex("by_stationId", (q) => q.eq("stationId", stationId))
      .collect();

    if (stops.length === 0) return [];

    // Preload all origin + destination station codes
    const originIds = [...new Set(stops.map((s) => s.routeOriginId))];
    const destIds = [...new Set(stops.map((s) => s.routeDestinationId))];

    const [originStations, destinationStations] = await Promise.all([
      Promise.all(
        originIds.map((id) =>
          ctx.db
            .query("stations")
            .withIndex("by_customId", (q) => q.eq("id", id))
            .unique()
        )
      ),
      Promise.all(
        destIds.map((id) =>
          ctx.db
            .query("stations")
            .withIndex("by_customId", (q) => q.eq("id", id))
            .unique()
        )
      ),
    ]);

    const originCodeMap = new Map(
      originStations
        .filter(Boolean)
        .map((s) => [s.id, s.code])
    );

    const destinationCodeMap = new Map(
      destinationStations
        .filter(Boolean)
        .map((s) => [s.id, s.code])
    );

    // Sort by departure time (or arrival if no departure)
    const sortedStops = stops.sort((a, b) => {
      const timeA = a.departureTime || a.arrivalTime || "";
      const timeB = b.departureTime || b.arrivalTime || "";
      return timeA.localeCompare(timeB);
    });

    return sortedStops.map((stop) => ({
      trainId: stop.trainId,
      trainCode: stop.trainCode,
      trainName: stop.trainName,
      stationId: stop.stationId,
      stationCode: stop.stationCode,
      stationName: stop.stationName,
      city: stop.city,
      arrivalTime: stop.arrivalTime,
      departureTime: stop.departureTime,
      stopSequence: stop.stopSequence,

      // Existing
      origin: stop.routeOriginName,
      destination: stop.routeDestinationName,
      isOrigin: stop.isOrigin,
      isDestination: stop.isDestination,

      // ➕ Added: station codes
      originStationCode: originCodeMap.get(stop.routeOriginId),
      destinationStationCode: destinationCodeMap.get(stop.routeDestinationId),
    }));
  },
});

/**
 * Get all stations connected to a given station
 * Use case: Find where you can travel from a specific station
 * 
 * A station is considered "connected" if there is at least one train
 * that stops at both the queried station and the returned station.
 */
export const getConnectedStations = query({
  args: {
    stationId: v.string(),
  },
  handler: async (ctx, { stationId }) => {
    // Get all trains that stop at the queried station
    const stopsAtStation = await ctx.db
      .query("trainStops")
      .withIndex("by_stationId", (q) => q.eq("stationId", stationId))
      .collect();

    if (stopsAtStation.length === 0) {
      return [];
    }

    // Get unique train IDs that stop at this station
    const trainIds = [...new Set(stopsAtStation.map((stop) => stop.trainId))];

    // Get all stops for these trains
    const allStopsForTrains = await Promise.all(
      trainIds.map((trainId) =>
        ctx.db
          .query("trainStops")
          .withIndex("by_trainId", (q) => q.eq("trainId", trainId))
          .collect()
      )
    );

    // Flatten and collect unique connected stations
    const connectedStationsMap = new Map<
      string,
      {
        stationId: string;
        stationCode: string;
        stationName: string;
        city: string;
        trainIds: string[];
        trainCount: number;
      }
    >();

    for (const stops of allStopsForTrains) {
      for (const stop of stops) {
        // Skip the queried station itself
        if (stop.stationId === stationId) continue;

        const existing = connectedStationsMap.get(stop.stationId);
        if (existing) {
          // Add train ID if not already included
          if (!existing.trainIds.includes(stop.trainId)) {
            existing.trainIds.push(stop.trainId);
            existing.trainCount = existing.trainIds.length;
          }
        } else {
          // Add new connected station
          connectedStationsMap.set(stop.stationId, {
            stationId: stop.stationId,
            stationCode: stop.stationCode,
            stationName: stop.stationName,
            city: stop.city,
            trainIds: [stop.trainId],
            trainCount: 1,
          });
        }
      }
    }

    // Convert to array and sort by train count (most connected first)
    return Array.from(connectedStationsMap.values()).sort(
      (a, b) => b.trainCount - a.trainCount
    );
  },
});
