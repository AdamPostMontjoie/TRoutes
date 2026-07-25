//
//  MotionManager.swift
//  TRoutes
//
//  Created by Adam Post on 7/24/26.
//
import CoreMotion

public enum MotionActivityState: String, Sendable {
    case walking = "Walking"
    case running = "Running"
    case automotive = "Automotive"
    case cycling = "Cycling"
    case stationary = "Stationary"
    case unknown = "Unknown"
}

public struct MotionEvent: Sendable {
    public let state: MotionActivityState
    public let confidence: String
}

actor MotionManager {
    static let shared = MotionManager()
    private let motionManager = CMMotionManager()
    private var streamContinuation: AsyncStream<MotionEvent>.Continuation?

    func makeEventStream() -> AsyncStream<MotionEvent> {
        let (stream, continuation) = AsyncStream<MotionEvent>.makeStream()
        self.streamContinuation = continuation
        
        continuation.onTermination = { [weak self] _ in
        //    Task { await self?.stopActivityUpdates() }
        }
        
        return stream
    }

    func startAccelerationUpdates() {
        
    
        
//        motionManager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] activity,<#arg#>  in
//            guard let activity = activity else { return }
//            print("RAW MOTION: \(activity)")
//            
//            // 1. Ignore low confidence updates to prevent jitter
//            guard activity.confidence != .low else { return }
//            
//            var state: MotionActivityState = .unknown
//            
//            // 2. The properties are not mutually exclusive.
//            // When ALL properties are false, it means "unclassified movement" 
//            // (e.g. holding the phone in your hand while sitting).
//            if activity.walking { state = .walking }
//            else if activity.running { state = .running }
//            else if activity.automotive { state = .automotive }
//            else if activity.cycling { state = .cycling }
//            else if activity.stationary { state = .stationary }
//            else { state = .unknown } // Unclassified movement
//            
//            let confidenceName = activity.confidence == .high ? "High" : "Medium"
//            
//            let event = MotionEvent(state: state, confidence: confidenceName)
//            self?.streamContinuation?.yield(event)
//        }
    }
    

    func stopAccelerationUpdates() {
        motionManager.stopActivityUpdates()
        streamContinuation?.finish()
        streamContinuation = nil
    }
}
