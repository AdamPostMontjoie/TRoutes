//
//  JourneySelectionPolicy.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Keeps the recommendation decision separate from the actual-journey ETA
/// decision. Both operate on the same complete journeys from the same snapshot.
struct JourneySelectionPolicy {
    // MARK: - Selection policy to validate against journey scenarios

    func selectRecommendation(from journeys: [TimedJourney]) -> TimedJourney? {
        journeys.min { candidate, current in
            isPreferredRecommendation(candidate, over: current)
        }
    }

    func selectActualJourney(from journeys: [TimedJourney]) -> TimedJourney? {
        journeys.min { candidate, current in
            isPreferredActualJourney(candidate, over: current)
        }
    }

    /// Step 5 uses this only when two partial paths have the same first and
    /// current-final options. Keeping the more reliable path cannot remove a
    /// first-leg anchor needed later by the at-stop ETA policy.
    func isPreferredPartialJourney(_ candidate: TimedJourney, over current: TimedJourney) -> Bool {
        let candidateBuffered = meetsEveryReliabilityBuffer(candidate)
        let currentBuffered = meetsEveryReliabilityBuffer(current)
        if candidateBuffered != currentBuffered {
            return candidateBuffered
        }

        let candidateSlack = lowestBufferSlack(candidate)
        let currentSlack = lowestBufferSlack(current)
        if candidateSlack != currentSlack {
            return candidateSlack > currentSlack
        }

        return journeySignature(candidate) < journeySignature(current)
    }

    /// Before the first stop, a complete buffered journey is preferred over an
    /// unbuffered one. Within that class, arrive earliest and take the latest
    /// feeder that preserves the selected downstream service.
    private func isPreferredRecommendation(_ candidate: TimedJourney, over current: TimedJourney) -> Bool {
        let candidateBuffered = meetsEveryReliabilityBuffer(candidate)
        let currentBuffered = meetsEveryReliabilityBuffer(current)
        if candidateBuffered != currentBuffered {
            return candidateBuffered
        }

        if candidate.destinationArrival != current.destinationArrival {
            return candidate.destinationArrival < current.destinationArrival
        }

        if !candidateBuffered {
            let candidateSlack = lowestBufferSlack(candidate)
            let currentSlack = lowestBufferSlack(current)
            if candidateSlack != currentSlack {
                return candidateSlack > currentSlack
            }
        }

        if candidate.originDeparture != current.originDeparture {
            return candidate.originDeparture > current.originDeparture
        }

        return journeySignature(candidate) < journeySignature(current)
    }

    /// After the first stop, the first leg is already assumed or fixed. The
    /// main ETA follows the earliest physically possible complete journey;
    /// reliability changes its connection warning rather than hiding it.
    private func isPreferredActualJourney(_ candidate: TimedJourney, over current: TimedJourney) -> Bool {
        if candidate.destinationArrival != current.destinationArrival {
            return candidate.destinationArrival < current.destinationArrival
        }

        let candidateBuffered = meetsEveryReliabilityBuffer(candidate)
        let currentBuffered = meetsEveryReliabilityBuffer(current)
        if candidateBuffered != currentBuffered {
            return candidateBuffered
        }

        return journeySignature(candidate) < journeySignature(current)
    }

    private func meetsEveryReliabilityBuffer(_ journey: TimedJourney) -> Bool {
        journey.transfers.allSatisfy(\.meetsReliabilityBuffer)
    }

    private func lowestBufferSlack(_ journey: TimedJourney) -> TimeInterval {
        journey.transfers.map(\.bufferSlack).min() ?? .greatestFiniteMagnitude
    }

    private func journeySignature(_ journey: TimedJourney) -> String {
        journey.legs.map(\.id).joined(separator: "|")
    }
}
