//
//  SearchCompletePath.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

private struct PartialJourneyKey: Hashable {
    let firstOptionId: String
    let finalOptionId: String
}

// MARK: - Step 5: search complete paths

extension JourneyTimingEngine {
    /// Dynamic programming keeps one best path for each first/final option
    /// pair. Preserving the first option is required because an at-stop ETA is
    /// anchored to the first boardable trip rather than the recommendation.
    func solveJourneys(
        remainingLegs: [ResolvedLeg],
        optionsByLeg: [UUID: [LegTripOption]],
        connectionGraph: TimingConnectionGraph
    ) -> [TimedJourney] {
        guard let firstLeg = remainingLegs.first else {
            print("5/6 Searched Complete Timing Paths")
            return []
        }

        let selectionPolicy = JourneySelectionPolicy()
        var bestPathByOptions: [PartialJourneyKey: TimedJourney] = [:]
        for option in optionsByLeg[firstLeg.id] ?? [] {
            if let path = TimedJourney(
                legs: [option],
                transfers: [],
                warnings: []
            ) {
                bestPathByOptions[
                    PartialJourneyKey(
                        firstOptionId: option.id,
                        finalOptionId: option.id
                    )
                ] = path
            }
        }

        for leg in remainingLegs.dropFirst() {
            var nextBestPathByOptions: [PartialJourneyKey: TimedJourney] = [:]

            for option in optionsByLeg[leg.id] ?? [] {
                for path in bestPathByOptions.values {
                    guard let firstOption = path.legs.first,
                          let previousOption = path.legs.last,
                          let transfer = connectionGraph.feasibleTransfer(
                            from: previousOption,
                            to: option
                          ),
                          let candidate = TimedJourney(
                            legs: path.legs + [option],
                            transfers: path.transfers + [transfer],
                            warnings: []
                          ) else {
                        continue
                    }

                    let key = PartialJourneyKey(
                        firstOptionId: firstOption.id,
                        finalOptionId: option.id
                    )
                    if let current = nextBestPathByOptions[key] {
                        if selectionPolicy.isPreferredPartialJourney(
                            candidate,
                            over: current
                        ) {
                            nextBestPathByOptions[key] = candidate
                        }
                    } else {
                        nextBestPathByOptions[key] = candidate
                    }
                }
            }

            bestPathByOptions = nextBestPathByOptions
            if bestPathByOptions.isEmpty {
                print("5/6 Searched Complete Timing Paths")
                return []
            }
        }

        print("5/6 Searched Complete Timing Paths")
        return Array(bestPathByOptions.values)
    }
}
