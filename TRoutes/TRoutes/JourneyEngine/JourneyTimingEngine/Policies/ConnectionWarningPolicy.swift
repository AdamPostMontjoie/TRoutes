//
//  ConnectionWarningPolicy.swift
//  TRoutes
//
//  Created by Adam Post on 9/13/26.
//

import Foundation

/// Maps the independent feasibility, reliability, and consequence facts for a
/// connection into the one warning category presented to the user.
struct ConnectionWarningPolicy {
    // MARK: - Warning policy to validate against journey scenarios

    func warning(for connection: TransferTiming) -> ConnectionWarning {
        guard connection.isPhysicallyPossible else { return .likelyMiss }

        switch (
            connection.meetsReliabilityBuffer,
            connection.isHighConsequence
        ) {
        case (true, false):
            return .none
        case (false, false):
            return .tight
        case (true, true):
            return .highConsequence
        case (false, true):
            return .tightHighConsequence
        }
    }
}

extension TransferTiming {
    var warning: ConnectionWarning {
        ConnectionWarningPolicy().warning(for: self)
    }
}
