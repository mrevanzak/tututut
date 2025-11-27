import { internalAction, mutation } from "./_generated/server";
import { v } from "convex/values";
import { stationValidator } from "./validators";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";

// Schedule an arrival alert 2 minutes before arrival time
export const scheduleArrivalAlert = mutation({
  args: {
    deviceToken: v.string(),
    trainId: v.union(v.string(), v.null()),
    trainName: v.string(),
    arrivalTime: v.number(), // milliseconds since epoch
    destinationStation: stationValidator,
  },
  handler: async (ctx, args) => {
    const offset = await ctx.runQuery(internal.appConfig.getArrivalAlert);

    const notificationTimeMs = args.arrivalTime - offset * 1000;
    const nowMs = Date.now();

    if (notificationTimeMs <= nowMs) {
      throw new Error(
        "Cannot schedule arrival alert: notification time is in the past"
      );
    }

    const schedulerId: Id<"_scheduled_functions"> = await ctx.scheduler.runAt(
      notificationTimeMs,
      internal.notifications.sendArrivalAlert,
      {
        deviceToken: args.deviceToken,
        trainId: args.trainId,
        trainName: args.trainName,
        destinationStation: args.destinationStation,
        offset,
      }
    );

    return schedulerId;
  },
});

// Internal action to send the actual arrival alert push
export const sendArrivalAlert = internalAction({
  args: {
    deviceToken: v.string(),
    trainId: v.union(v.string(), v.null()),
    trainName: v.string(),
    destinationStation: stationValidator,
    offset: v.number(),
  },
  handler: async (ctx, args) => {
    const stationName = args.destinationStation.name;
    const stationCode = args.destinationStation.code;
    const deeplink = `kreta://arrival?code=${encodeURIComponent(stationCode)}&name=${encodeURIComponent(stationName)}`;

    const title = "Segera Turun!";
    const body = `${Math.round(args.offset / 60)} menit lagi tiba di ${stationName}`;

    await ctx.runAction(internal.push.sendArrivalPush, {
      deviceToken: args.deviceToken,
      title,
      body,
      deeplink,
      stationCode,
      stationName,
      trainId: args.trainId,
    });
  },
});
