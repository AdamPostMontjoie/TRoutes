//
//  MotionManager.swift
//  TRoutes
//
//  Created by Adam Post on 7/24/26.
//
import CoreMotion
import ComposableArchitecture

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
    private var eventStreamContinuation: AsyncStream<MotionEvent>.Continuation?
    private var commandStreamContinuation: AsyncStream<JourneyCommand>.Continuation?
    
    private var isCommandsStarted = false
    private var isEventsExplicitlyStarted = false
    
    @Shared(.isDebugEnabled) var isDebugEnabled = true
    @Shared(.isMotionEventsEnabled) var isMotionEventsEnabled = true
    
    // MARK: - Streams
    
    func makeCommandStream() -> AsyncStream<JourneyCommand> {
        let (stream, continuation) = AsyncStream<JourneyCommand>.makeStream()
        self.commandStreamContinuation = continuation
        
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopCommands() }
        }
        return stream
    }
    
    func makeEventStream() -> AsyncStream<MotionEvent> {
        let (stream, continuation) = AsyncStream<MotionEvent>.makeStream()
        self.eventStreamContinuation = continuation
        
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopEvents() }
        }
        return stream
    }
    
    // MARK: - Controls
    
    func startCommands() {
        isCommandsStarted = true
        evaluateHardwareState()
    }
    
    func stopCommands() {
        isCommandsStarted = false
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        evaluateHardwareState()
    }
    
    func startEvents() {
        isEventsExplicitlyStarted = true
        evaluateHardwareState()
    }
    
    func stopEvents() {
        isEventsExplicitlyStarted = false
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        evaluateHardwareState()
    }
    
    func stopAllUpdates() {
        isCommandsStarted = false
        isEventsExplicitlyStarted = false
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        evaluateHardwareState()
    }
    
    // MARK: - Hardware Lifecycle
    
    private func evaluateHardwareState() {
        let shouldStreamEvents = isEventsExplicitlyStarted || (isCommandsStarted && isDebugEnabled && isMotionEventsEnabled)
        let shouldHardwareRun = isCommandsStarted || shouldStreamEvents
        
        if shouldHardwareRun {
            if !motionManager.isDeviceMotionActive {
                startHardware()
            }
        } else {
            if motionManager.isDeviceMotionActive {
                motionManager.stopDeviceMotionUpdates()
            }
        }
    }
    
    private func startHardware() {
        // TODO: Implement CMMotionManager startDeviceMotionUpdates and route to handleMotion
    }
    
    // private func handleMotion(...) {
    //     if self.isCommandsStarted {
    //         // calculate math, yield to commandStream
    //     }
    //     let shouldStreamEvents = isEventsExplicitlyStarted || (isCommandsStarted && isDebugMode && isMotionEventsEnabled)
    //     if shouldStreamEvents {
    //         // format math, yield to eventStream
    //     }
    // }
}
