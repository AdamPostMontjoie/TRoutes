# Single Stop Improvement Plan

## Goal

Improve the Single Stop tab with nearby-stop filtering, predictable API refresh behavior, Live Activity support, distance updates, and a clearer banner design.

## 1. Nearby Stop Filters

### Original proposal

Add a top bar above the nearby-stop list:

`All | Subway | Bus | Rail | Refresh`

- **All:** Every nearby stop, sorted by distance.
- **Subway:** Red, Orange, Blue, Green, and Mattapan lines.
- **Bus:** Regular buses and Silver Line routes.
- **Rail:** Commuter Rail routes.
- **Refresh:** Request a current location and rebuild the nearby-stop list from it.

### Recommended implementation

- Apply the filter only to the Nearby section; keep Pinned and Saved unchanged.
- Keep one unfiltered nearby collection and derive the displayed collection locally. Changing filters should not query the database or API.
- Consider naming the Rail option **CR** or **Commuter Rail** to distinguish it from subway service.
- Decide whether Ferry belongs only under All or receives its own filter.
- Add a one-shot location request for Refresh so it does not rely on a potentially stale cached coordinate.
- Correct Mattapan's current transit-type mapping before using it for filtering.

## 2. Prediction Cache And Refresh

### Original proposal

- A visible banner should refresh predictions when its data is at least 15 seconds old.
- Each direction should retain separate cached predictions and refresh timing.
- Swiping to a direction should fetch when that direction has no fresh data.
- Swiping back within 15 seconds should immediately show the cached predictions without another API request.
- Scrolling a banner off and back on screen should not repeatedly consume the API limit.

### Recommended implementation

Represent cached data with a key such as:

```swift
PredictionKey(stationID, routeID, directionID)
PredictionSnapshot(predictions, fetchedAt, loadingState)
```

- Use one screen-level scheduler rather than one repeating timer per banner.
- Refresh only the active direction of banners currently visible on the active Single Stop tab.
- Share cached and in-flight requests across duplicate stop banners in Pinned, Saved, Nearby, and search results.
- Coalesce requests with the same prediction key so only one API call is made.
- Tag responses with their prediction key so a response from the previous direction cannot overwrite the currently selected direction.
- Keep stale predictions visible while refreshing and if a refresh fails; show an unavailable state only when no cached data exists.
- Give nearby banners stable identity based on station and route instead of generating a new UUID after every location refresh.
- Cancel the scheduler when the Single Stop tab is inactive or the app is not active.

## 3. Stop Live Activity

### Original proposal

Allow each stop banner to launch a Live Activity showing that stop and its upcoming predictions.

### Recommended implementation

- Create separate `StopActivityAttributes` and a dedicated stop activity manager; do not reuse journey-specific attributes or state.
- Initially allow one active stop Live Activity at a time to keep ownership and UI clear.
- Store absolute arrival/departure dates where possible so ActivityKit can render a locally updating countdown.
- Update the activity opportunistically when the app is active or receives legitimate background execution time.
- Do not enable continuous background location solely to make prediction requests. A Live Activity does not keep the app running, and iOS does not guarantee 15-second background network refreshes.
- If reliable remote updates are eventually required, use ActivityKit push updates, which require a server.

## 4. Banner And Distance Improvements

### Original proposal

- Prevent long stop names from being cut off unnecessarily.
- Replace transit icons with route badges such as `1`, `GL`, `RL`, or `CR`.
- Give Commuter Rail routes their actual names, such as Newburyport/Rockport.
- Bring the visual hierarchy closer to `ActiveJourneyDisplayView`.
- Display live distance from the user to each nearby stop.
- Refresh the nearby-stop collection after the user moves 200 meters from the location used for the previous search.

### Recommended banner hierarchy

1. Route badge and stop name.
2. Direction or destination.
3. Distance as secondary metadata.
4. Predictions as the primary bottom row.
5. Pin, save, and Live Activity actions in a compact trailing group or menu.

Allow the stop name up to two lines and give it higher layout priority so action buttons do not force early truncation. Reuse the journey view's visual language, but extract shared route badge and route-label helpers rather than coupling the stop banner to journey presentation state.

### Route names

- Subway labels and most bus labels can be derived from MBTA route IDs.
- Silver Line IDs need the existing mapping to `SL1`, `SL2`, and so on.
- Commuter Rail display names are not currently stored correctly: `StationStop.routeName` receives the route ID.
- Import `route_short_name` and `route_long_name` from GTFS `routes.txt` so the UI can show stable route labels and full Commuter Rail names without extra API calls.

### Location behavior

Track two location values:

- **Current location:** Updated frequently enough to recalculate displayed distances.
- **Nearby search origin:** The location used to build the current nearby-stop collection.

Distance changes should update banner presentation only. Requery nearby stops when the user explicitly refreshes or moves at least 200 meters from the nearby search origin. Reject stale or low-accuracy location samples before using them.

## Recommended Build Order

1. Add stable banner identity and the shared direction-aware prediction cache.
2. Add request coalescing, the visibility scheduler, and stale/error handling.
3. Separate current location from nearby search origin and display distance.
4. Add nearby filters and one-shot manual refresh.
5. Import route metadata and redesign the banner around route badges.
6. Add the dedicated stop Live Activity with documented background limitations.
7. Add reducer tests for cache age, direction-switch races, duplicate requests, filtering, and the 200-meter refresh threshold.