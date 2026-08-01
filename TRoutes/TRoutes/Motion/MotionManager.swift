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
    
    private var gravityEstimate: (x: Double, y: Double, z: Double) = (0, 0, 0)
    private var magnitudeBuffer: [Double] = []
    private var joltStartTime: Date?
    
    // MARK: - Tuning Constants
    //   These are starting points. You will tune them by riding the T
    //   with the dashboard showing real magnitude and variance values.
    
    private let gravityFilterAlpha = 0.8
    private let magnitudeThreshold = 0.08  // in G — train departure is ~0.1-0.2G
    private let varianceCeiling = 0.008    // above this = walking
    private let requiredJoltDuration = 4.0 // seconds of sustained signal
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
        startAccelerometerUpdates()
    }
    
    func stopCommands() {
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        stopAccelerometerUpdates()
    }
    
    func startEvents() {
        startAccelerometerUpdates()
    }
    
    func stopEvents() {
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        stopAccelerometerUpdates()
    }
    
    func stopAllUpdates() {
        commandStreamContinuation?.finish()
        commandStreamContinuation = nil
        eventStreamContinuation?.finish()
        eventStreamContinuation = nil
        stopAccelerometerUpdates()
    }
    
    // MARK: - Accelerometer Lifecycle
    
    private func startAccelerometerUpdates() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / updateFrequency
        
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let data = data, let self = self else { return }
            // CMAccelerometerData is NOT Sendable — extract the raw doubles
            // here on the motionQueue before hopping into the actor.
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            Task { await self.processAccelerometerData(x: x, y: y, z: z) }
        }
    }
    
    private func stopAccelerometerUpdates() {
        motionManager.stopAccelerometerUpdates()
        resetJoltState()
    }
    
    private func resetJoltState() {
        gravityEstimate = (0, 0, 0)
        magnitudeBuffer.removeAll()
        joltStartTime = nil
    }
    
    // MARK: - The Math
    //
    // This function runs once per accelerometer tick (~50 times/second).
    // It processes raw accelerometer data through 4 steps to determine
    // if the user is experiencing a train departure.
    
    private func processAccelerometerData(x rawX: Double, y rawY: Double, z rawZ: Double) {
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 1: HIGH-PASS FILTER — Remove gravity from the raw signal
        // ──────────────────────────────────────────────────────────────────
        //
        // Problem: The accelerometer ALWAYS reports gravity (~1G) in the
        // readings. If the phone is flat on a table, z ≈ -1.0. If it's
        // upright in your pocket, y ≈ -1.0. The train's departure
        // acceleration is only ~0.1G — it's invisible under gravity's 1G.
        //
        // Solution: Exponential Moving Average (EMA). Gravity is the
        // "slow-moving" part of the signal (it barely changes). The EMA
        // tracks it by heavily weighting previous estimates:
        //
        //   gravity_new = 0.8 * gravity_old + 0.2 * raw_value
        //
        // With alpha=0.8, this says: "I'm 80% sure gravity is where it
        // was last frame, and only 20% influenced by this new reading."
        // This means sudden jolts (which are 100% in the new reading)
        // barely move the gravity estimate. After subtracting, what
        // remains is the "linear acceleration" — the actual movement.
        //
        // On the very first frame, gravityEstimate is (0,0,0), so the
        // filter takes ~10 frames (~0.2 seconds) to converge. That's
        // fine — we require 2.5 seconds of sustained signal anyway.
        
        let alpha = gravityFilterAlpha
        gravityEstimate.x = alpha * gravityEstimate.x + (1 - alpha) * rawX
        gravityEstimate.y = alpha * gravityEstimate.y + (1 - alpha) * rawY
        gravityEstimate.z = alpha * gravityEstimate.z + (1 - alpha) * rawZ
        
        let linearX = rawX - gravityEstimate.x
        let linearY = rawY - gravityEstimate.y
        let linearZ = rawZ - gravityEstimate.z
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 2: MAGNITUDE — Collapse 3 axes into 1 orientation-free number
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
        // is happening" regardless of direction. It's rotation-invariant
        // by definition — rotating the phone just redistributes the same
        // force across axes, but the magnitude stays identical.
        //
        // At rest: magnitude ≈ 0.0 (gravity was subtracted)
        // Walking: magnitude spikes rhythmically (0.1-0.5G peaks)
        // Train:   magnitude rises smoothly to ~0.1-0.2G and holds
        
        let magnitude = sqrt(linearX * linearX + linearY * linearY + linearZ * linearZ)
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 3: VARIANCE — Distinguish walking from train movement
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
        // joltStartTime tracks when we first entered the "possible jolt"
        // state. If conditions break, we reset it to nil.
        
        let isAboveThreshold = magnitude > magnitudeThreshold
        let isSmooth = variance < varianceCeiling
        
        var joltDuration = 0.0
        var isJoltDetected = false
        
        if isAboveThreshold && isSmooth {
            if joltStartTime == nil {
                joltStartTime = Date.now
            }
            joltDuration = Date.now.timeIntervalSince(joltStartTime!)
            
            if joltDuration >= requiredJoltDuration {
                isJoltDetected = true
                // TODO: yield .executeExit to commandStreamContinuation
                // commandStreamContinuation?.yield(.executeExit(stopId: ???))
            }
        } else {
            joltStartTime = nil
        }
        
        // MARK: - Classify State
        // Derive what the user is likely doing from the numbers we already computed.
        //   - High variance = rhythmic bouncing = walking or running
        //   - Low variance + above threshold = smooth sustained force = vehicle
        //   - Below threshold + low variance = not moving = unknown/stationary
        
        let state: MotionState
        if variance > 0.03 {
            state = .running
        } else if variance > varianceCeiling {
            state = .walking
        } else if isAboveThreshold && isJoltDetected {
            state = .vehicle
        } else {
            state = .unknown
        }
        
        // MARK: - Route to Streams
        
        let event = MotionEvent(
            state: state,
            magnitude: magnitude,
            variance: variance,
            joltDuration: joltDuration,
            isJoltDetected: isJoltDetected
        )
        
        eventStreamContinuation?.yield(event)
    }
}
