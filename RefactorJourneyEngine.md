# Refactor Plan Sanity Check & Considerations

## 1. Extract JourneyCommandValidator into a Reducer

**Verdict: Clean win. No concerns.**

The current `journeyCommandValidator` method on `JourneyEngine` is a ~80 line `switch` that mixes validation ("is this command valid given current state?") with execution ("now go do things"). Pulling it into a dedicated file as a pure function that takes `(JourneyCommand, JourneyState) -> [validated actions or effects]` would:
- Make it unit-testable without standing up the full engine
- Let you read the routing logic in isolation
- Mirror the existing `JourneyAction.reduce(state:)` pattern you already have

The empty `JourneyCommandValidator.swift` file is already scaffolded and ready.

---

## 2. Rate Limit Queue (20 req/min)

**Verdict: Good idea. A few design considerations.**

### How It Works
A sliding window queue. Every time an API call is made, push `Date()` onto the queue. Before making a new call, purge entries older than 60 seconds. If the queue still has 20+ entries, delay or drop the request.

### Where to Put It
You have two options:

**Option A: Inside `MBTAClient` (Recommended)**
Make the rate limiter a property of your `MBTAClient` dependency. Every method (`fetchTransitTimes`, `fetchVehicleData`, `fetchTripTrackingData`) passes through it before hitting the network. This means rate limiting is invisible to `JourneyEngine` and `UndergroundManager`—they just call the client and it handles throttling internally.

**Option B: Standalone queue passed around**
`JourneyEngine` owns a `RateLimitQueue` and passes it (or checks it) before calling `mbtaClient`. This is more explicit but means every caller needs to know about it.

### Considerations
- **Priority**: Not all API calls are equal. A `fetchVehicleData` call from `UndergroundManager` during `evaluatingDeparture` (5-second polling) is more critical than a background prediction refresh. If you hit the limit, you'd want to drop the low-priority refresh, not the departure check. Option A makes this harder to express unless you add priority tiers to the client.
- **Backpressure**: If the queue is full, do you delay (async wait until a slot opens) or drop? Delaying is safer but could cause stale data. Dropping is simpler but means you might miss a critical poll.
- **Current burn rate**: `UndergroundManager` polls every 15s in normal mode and every 5s during departure evaluation. That's 4-12 req/min just from underground tracking. `JourneyEngine`'s prediction refresh timer fires every 15s, adding another 4 req/min. Plus transfer predictions. You're likely already brushing up against 20 req/min during active tracking, which means this queue isn't just future-proofing—it's necessary.

---

## 3. Unified Vehicle Queue (Consolidating Surface + Transfer)

**Verdict: Correct. One queue is the right call.**

### Why One Queue Works
Your insight is exactly right: there is no scenario where you need to simultaneously track "which train am I boarding right now" AND "which transfer train just arrived at the next station." Those are sequential phases of the journey:

1. You're at a boarding/transfer stop → predictions show upcoming trains → one drops off → it goes into the queue → you board and exit → queue resolves which train you took.
2. Only AFTER you've exited and advanced to the next leg do you start watching transfer predictions.

Two queues was solving a problem that doesn't exist. One queue, reset when you advance to a new stop, is sufficient.

### Event-Based Eviction (Instead of 60s Timer)

**Verdict: Smart, but needs a safety valve.**

Your logic: "Only bump a train from the queue when another train drops from predictions, because that means the platform has cycled."

This is actually a much better signal than a rigid timer. Here's why it works:

- Train A arrives at Lechmere. It drops from `/predictions`. You push it into the queue.
- You're standing on the platform. 45 seconds pass. Under the old system, Train A has 15 seconds left before it's purged. Under your system, Train A stays in the queue because no other train has arrived yet. Good—you might still be boarding it.
- Train B arrives. It drops from `/predictions`. Now you know Train A has definitely left (or is about to). You can safely evict Train A and push Train B.
- If you triggered `executeExit` between Train A arriving and Train B arriving, you match to Train A. If you triggered it after Train B arrived, you match to Train B.

### Edge Cases to Handle

> [!WARNING]
> **End of Service / Long Gaps:** If it's 12:45 AM and the last Green Line train drops from predictions, no subsequent train will ever arrive to evict it. The queue entry would persist forever. You need a **safety valve**—a maximum TTL (maybe 3-5 minutes) that acts as a fallback. The event-based eviction is the *primary* mechanism; the TTL is the *fallback* for when the event never comes.

> [!IMPORTANT]
> **API Glitches / Empty Predictions:** If the MBTA API temporarily returns an empty predictions array (network blip, maintenance), your system would interpret every currently-predicted train as having "dropped off" and flood the queue. You should guard against this: if the predictions response is empty or errors out, do NOT run the eviction diff. Only diff against successful, non-empty responses.

> [!NOTE]
> **Multiple Trains Dropping Simultaneously:** At a busy station like Park Street, two trains on the same route could drop from predictions in the same poll cycle (one departing, one arriving). Your diff logic needs to handle this—push all newly-dropped vehicles into the queue, don't just track the first one.

### Suggested Queue Structure
```
struct RecentlyArrivedVehicle {
    let vehicleId: String
    let tripId: String
    let arrivedAt: Date          // When it dropped from predictions
    let routeId: String          // To match against the correct leg
}

// The queue itself
var recentVehicles: [RecentlyArrivedVehicle] = []

// On each successful, non-empty prediction response:
//   1. Diff against previous predictions
//   2. Any vehicle that was in previous but NOT in current → push to queue
//   3. If a NEW vehicle also dropped (i.e., queue already has entries), evict the oldest
//   4. Safety valve: also evict anything older than maxTTL
```

---

## Summary

| Change | Verdict | Risk |
|--------|---------|------|
| Extract CommandValidator | ✅ Clean win | None |
| Rate Limit Queue | ✅ Necessary | Priority ordering needs thought |
| Unified Vehicle Queue | ✅ Correct simplification | None |
| Event-Based Eviction | ✅ Better than timer | Needs TTL safety valve + empty-response guard |
