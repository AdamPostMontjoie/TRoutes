//
//  MotionManager.swift
//  TRoutes
//
//  Created by Adam Post on 7/24/26.
//
import CoreMotion
import ComposableArchitecture

public enum MotionState: String, Sendable {
    case walking = "Walking"
    case running = "Running"
    case vehicle = "Vehicle"
    case unknown = "Unknown"
}

public struct MotionEvent: Sendable {
    public let state: MotionState
    public let magnitude: Double
    public let variance: Double
    public let joltDuration: Double  // seconds since jolt started, 0 if no jolt
    public let isJoltDetected: Bool
}

actor MotionManager {
    static let shared = MotionManager()
    
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    
    private var eventStreamContinuation: AsyncStream<MotionEvent>.Continuation?
    private var commandStreamContinuation: AsyncStream<JourneyCommand>.Continuation?
    
    @Shared(.isDebugEnabled) var isDebugEnabled = true
    @Shared(.isMotionEventsEnabled) var isMotionEventsEnabled = true
    
    // MARK: - Jolt Detection State
    //
    // These three properties are the minimum local state needed to detect
    // a train departure from raw accelerometer data. Here's why each exists:
    //
    // gravityEstimate: The accelerometer always reports gravity (~1G) mixed into
    //   every reading. We need to subtract it to see the tiny ~0.1G train signal.
    //   This tuple tracks our running estimate of where gravity is pointing.
    //
    // magnitudeBuffer: A rolling window of recent filtered magnitudes (last ~1 second).
    //   We need history because a single frame tells us nothing — walking and trains
    //   both produce acceleration. But walking has HIGH variance (rhythmic bouncing)
    //   and trains have LOW variance (smooth ramp). We need the buffer to calculate
    //   that variance.
    //
    // joltStartTime: When we first see "above threshold + low variance," we note the
    //   time. If it STAYS that way for 2.5 seconds, we fire the jolt. If the signal
    //   drops, we reset this to nil. Without this, a single bump would trigger a
    //   false positive.
    
    private var magnitudeBuffer: [Double] = []
    private var stateBuffer: [MotionState] = []
    private var joltScore: Double = 0.0
    
    // MARK: - Tuning Constants
    //   These are starting points. You will tune them by riding the T
    //   with the dashboard showing real magnitude and variance values.
    
    private let magnitudeThreshold = 0.08  // in G — train departure is ~0.1-0.2G
    private let varianceCeiling = 0.008    // above this = walking
    private let requiredJoltDuration = 10.0 // seconds of sustained signal
    private let bufferSize = 50            // samples (~1 second at 50Hz)
    private let updateFrequency = 50.0     // Hz
    
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
        startDeviceMotionUpdates()
    }
    
    func stopCommands() {
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        stopDeviceMotionUpdates()
    }
    
    func startEvents() {
        startDeviceMotionUpdates()
    }
    
    func stopEvents() {
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        stopDeviceMotionUpdates()
    }
    
    func stopAllUpdates() {
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        stopDeviceMotionUpdates()
    }
    
    // MARK: - Device Motion Lifecycle
    
    private func startDeviceMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / updateFrequency
        
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let motion = motion, let self = self else { return }
            let accel = motion.userAcceleration
            Task { await self.processAccelerometerData(x: accel.x, y: accel.y, z: accel.z) }
        }
    }
    
    private func stopDeviceMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        resetJoltState()
    }
    
    private func resetJoltState() {
        magnitudeBuffer.removeAll()
        stateBuffer.removeAll()
        joltScore = 0.0
    }
    
    // MARK: - The Math
    //
    // This function runs once per accelerometer tick (~50 times/second).
    // It processes raw accelerometer data through 4 steps to determine
    // if the user is experiencing a train departure.
    
    private func processAccelerometerData(x rawX: Double, y rawY: Double, z rawZ: Double) {
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 1: MAGNITUDE — Collapse 3 axes into 1 orientation-free number
        // ──────────────────────────────────────────────────────────────────
        //
        // Problem: The phone could be in any orientation in your pocket.
        // If the train accelerates "forward," that might show up on the
        // x-axis, y-axis, or some combination — depending on how the
        // phone is rotated.
        //
        // Solution: Calculate the vector magnitude:
        //   magnitude = sqrt(x² + y² + z²)
        //
        // This is a single number representing "how much total acceleration
        // is happening" regardless of direction. Because we are using 
        // CMDeviceMotion's `userAcceleration`, Apple's sensor fusion has 
        // ALREADY used the gyroscope to completely subtract gravity, even 
        // if the phone is tilted.
        //
        // At rest: magnitude ≈ 0.0
        // Walking: magnitude spikes rhythmically (0.1-0.5G peaks)
        // Train:   magnitude rises smoothly to ~0.1-0.2G and holds
        
        let magnitude = sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ)
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 2: VARIANCE — Distinguish walking from train movement
        // ──────────────────────────────────────────────────────────────────
        //
        // Problem: Both walking and a train departure produce magnitude
        // above our threshold. A single magnitude reading can't tell
        // them apart.
        //
        // Solution: Look at how STABLE the magnitude is over the last
        // second. Variance measures "how much do the values bounce around
        // their average?"
        //
        //   variance = average of (each_value - mean)²
        //
        // Walking: The magnitude spikes UP with each footstep and drops
        //   DOWN between steps. This creates a saw-tooth pattern with
        //   HIGH variance (values are far from the mean).
        //
        // Train: The magnitude rises smoothly and holds steady. Values
        //   cluster tightly around the mean. LOW variance.
        //
        // So: high variance = walking (veto the jolt).
        //     low variance  = smooth sustained force (could be a train).
        
        magnitudeBuffer.append(magnitude)
        if magnitudeBuffer.count > bufferSize {
            magnitudeBuffer.removeFirst()
        }
        
        // Don't calculate until we have a full window of data
        guard magnitudeBuffer.count == bufferSize else {
            // Still filling the buffer — send a "warming up" event to dashboard
            eventStreamContinuation?.yield(
                MotionEvent(state: .unknown, magnitude: magnitude, variance: 0, joltDuration: 0, isJoltDetected: false)
            )
            return
        }
        
        let mean = magnitudeBuffer.reduce(0, +) / Double(magnitudeBuffer.count)
        let variance = magnitudeBuffer.reduce(0) { sum, val in
            sum + (val - mean) * (val - mean)
        } / Double(magnitudeBuffer.count)
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 4: THRESHOLD + DURATION — Confirm it's a real departure
        // ──────────────────────────────────────────────────────────────────
        //
        // We now have two numbers:
        //   magnitude: "how hard is the phone accelerating right now?"
        //   variance:  "is this acceleration smooth or bouncy?"
        //
        // A train departure satisfies BOTH:
        //   magnitude > 0.08G   (something is actually moving)
        //   variance  < 0.008   (and it's smooth, not footsteps)
        //
        // But even that isn't enough — a single gust of wind could
        // satisfy both for one frame. So we add a DURATION requirement:
        // both conditions must hold for 2.5 consecutive seconds.
        //
        // ──────────────────────────────────────────────────────────────────
        // STEP 3: LEAKY BUCKET — Confidence Score Tracking
        // ──────────────────────────────────────────────────────────────────
        //
        // Add points for perfect frames, subtract points for bouncy/stationary
        // frames.
        
        let maxJoltScore = requiredJoltDuration * 50.0 // 50Hz
        let isAboveThreshold = magnitude > magnitudeThreshold
        let isSmooth = variance < varianceCeiling
        
        if isAboveThreshold && isSmooth {
            // Train accelerating perfectly
            joltScore += 1.0
        } else if isAboveThreshold && !isSmooth {
            // Moving horizontally, but bouncy (walking/shuffling)
            joltScore -= 0.5
        } else {
            // Not moving horizontally (stationary or slowing down)
            joltScore -= 2.0
        }
        
        // Clamp the score between 0 and max
        joltScore = max(0, min(joltScore, maxJoltScore))
        
        let isJoltDetected = (joltScore >= maxJoltScore)
        let joltDuration = joltScore / 50.0 // Convert score back to a 'seconds' duration for the dashboard
        
        // MARK: - Classify State
        // Derive what the user is likely doing from the numbers we already computed.
        //   - High variance = rhythmic bouncing = walking or running
        //   - Low variance + above threshold = smooth sustained force = vehicle
        //   - Below threshold + low variance = not moving = unknown/stationary
        
        let instantState: MotionState
        if variance > 0.03 {
            instantState = .running
        } else if variance > varianceCeiling {
            instantState = .walking
        } else if isAboveThreshold {
            instantState = .vehicle
        } else {
            instantState = .unknown
        }
        
        stateBuffer.append(instantState)
        if stateBuffer.count > 75 { // 1.5 seconds of history at 50Hz
            stateBuffer.removeFirst()
        }
        
        // Find the most frequent state in the buffer (the mode) to prevent flickering
        var stateCounts: [MotionState: Int] = [:]
        for s in stateBuffer {
            stateCounts[s, default: 0] += 1
        }
        let smoothedState = stateCounts.max(by: { $0.value < $1.value })?.key ?? .unknown
        
        // MARK: - Route to Streams
        
        let event = MotionEvent(
            state: smoothedState,
            magnitude: magnitude,
            variance: variance,
            joltDuration: joltDuration,
            isJoltDetected: isJoltDetected
        )
        
        eventStreamContinuation?.yield(event)
    }
}
