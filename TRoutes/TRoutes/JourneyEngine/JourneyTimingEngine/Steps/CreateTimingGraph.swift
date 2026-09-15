//
//  CreateTimingGraph.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

struct OptionConnectionKey: Hashable {
    let arrivingOptionId: String
    let departingOptionId: String
}

/// Retains every assessed adjacent-leg connection. The solver asks for only
/// physically possible edges, while Step 6 may inspect an impossible edge to
/// keep a likely-miss warning current across later refreshes.
struct TimingConnectionGraph {
    let connectionsByOption: [OptionConnectionKey: TransferTiming]

    func connection(
        from arrivingOption: LegTripOption,
        to departingOption: LegTripOption
    ) -> TransferTiming? {
        connectionsByOption[
            OptionConnectionKey(
                arrivingOptionId: arrivingOption.id,
                departingOptionId: departingOption.id
            )
        ]
    }

    func feasibleTransfer(
        from arrivingOption: LegTripOption,
        to departingOption: LegTripOption
    ) -> TransferTiming? {
        guard let connection = connection(
            from: arrivingOption,
            to: departingOption
        ), connection.isPhysicallyPossible else {
            return nil
        }
        return connection
    }
}

// MARK: - Step 4: connect adjacent legs

extension JourneyTimingEngine {
    func connectAdjacentLegs(
        remainingLegs: [ResolvedLeg],
        optionsByLeg: [UUID: [LegTripOption]]
    ) -> TimingConnectionGraph {
        guard remainingLegs.count > 1 else {
            print("4/6 Created Timing Graph")
            return TimingConnectionGraph(connectionsByOption: [:])
        }

        let connectionPolicy = ConnectionTimingPolicy()
        var connectionsByOption: [OptionConnectionKey: TransferTiming] = [:]

        for legIndex in 0..<(remainingLegs.count - 1) {
            let arrivingLeg = remainingLegs[legIndex]
            let departingLeg = remainingLegs[legIndex + 1]
            let arrivingOptions = optionsByLeg[arrivingLeg.id] ?? []
            let departingOptions = optionsByLeg[departingLeg.id] ?? []
            let requirement = connectionPolicy.transferRequirement(
                from: arrivingLeg,
                to: departingLeg
            )

            for (optionIndex, departingOption) in departingOptions.enumerated() {
                let nextAlternativeDeparture = nextAlternativeDeparture(
                    after: optionIndex,
                    in: departingOptions
                )
                let isLastService = departingOption.origin.isLastTrip == true
                    && nextAlternativeDeparture == nil
                let isHighConsequence = connectionPolicy.isHighConsequence(
                    departure: departingOption.departure,
                    nextAlternativeDeparture: nextAlternativeDeparture,
                    isLastService: isLastService
                )

                for arrivingOption in arrivingOptions {
                    let connection = TransferTiming(
                        arrivingLegId: arrivingLeg.id,
                        departingLegId: departingLeg.id,
                        stationId: departingLeg.startStop.stationId,
                        arrival: arrivingOption.arrival,
                        departure: departingOption.departure,
                        requirement: requirement,
                        nextAlternativeDeparture: nextAlternativeDeparture,
                        isHighConsequence: isHighConsequence,
                        isLastService: isLastService
                    )

                    connectionsByOption[
                        OptionConnectionKey(
                            arrivingOptionId: arrivingOption.id,
                            departingOptionId: departingOption.id
                        )
                    ] = connection
                }
            }
        }

        print("4/6 Created Timing Graph")
        return TimingConnectionGraph(
            connectionsByOption: connectionsByOption
        )
    }

    func nextAlternativeDeparture(
        after optionIndex: Int,
        in options: [LegTripOption]
    ) -> Date? {
        let selectedDeparture = options[optionIndex].departure
        return options.dropFirst(optionIndex + 1)
            .first { $0.departure > selectedDeparture }?
            .departure
    }
}
