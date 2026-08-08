//
//  MotionManager.swift
//  TRoutes
//
//  Created by Adam Post on 7/24/26.
//
import CoreMotion
import ComposableArchitecture
import UserNotifications

public enum MotionState: String, Sendable {
    case walking = "Walking"
    case running = "Running"
    case vehicle = "Accelerating"
    case unknown = "Stationary"
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
    private var vectorBuffer: [(x: Double, y: Double, z: Double)] = []
    private var stateBuffer: [MotionState] = []
    private var joltScore: Double = 0.0
    private var hasYieldedJolt: Bool = false
    
    // MARK: - Tuning Constants
    //   These are starting points. You will tune them by riding the T
    //   with the dashboard showing real magnitude and variance values.
    
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
        vectorBuffer.removeAll()
        stateBuffer.removeAll()
        joltScore = 0.0
        hasYieldedJolt = false
    }
    
    // MARK: - The Math
    //
    // This function runs once per accelerometer tick (~50 times/second).
    // It processes raw accelerometer data through 4 steps to determine
    // if the user is experiencing a train departure.
    
    private func processAccelerometerData(x rawX: Double, y rawY: Double, z rawZ: Double) {
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 1: LOW-PASS VECTOR AVERAGING — Eliminate Walking Noise
        // ──────────────────────────────────────────────────────────────────
        //
        // Problem: Human walking acts like an inverted pendulum. With every step,
        // the body accelerates forward (+0.1G) and then decelerates backward (-0.1G).
        // If we calculate the Magnitude on every frame, we square the negative signs, 
        // turning both directions into a positive +0.1G. This tricks the math into 
        // seeing constant acceleration.
        //
        // Solution: Buffer the raw (X, Y, Z) vectors over a 1-second window. 
        // A walking human's +0.1G and -0.1G vectors will cancel each other out, 
        // dropping the average magnitude to ~0.0G. A departing train's constant 
        // +0.1G will survive the average intact.
        
        vectorBuffer.append((x: rawX, y: rawY, z: rawZ))
        if vectorBuffer.count > bufferSize {
            vectorBuffer.removeFirst()
        }
        
        let rawMagnitude = sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ)
        magnitudeBuffer.append(rawMagnitude)
        if magnitudeBuffer.count > bufferSize {
            magnitudeBuffer.removeFirst()
        }
        
        guard vectorBuffer.count == bufferSize else {
            // Still filling the buffer — send a "warming up" event to dashboard
            eventStreamContinuation?.yield(
                MotionEvent(state: .unknown, magnitude: rawMagnitude, variance: 0, joltDuration: 0, isJoltDetected: false)
            )
            return
        }
        
        let sumX = vectorBuffer.reduce(0) { $0 + $1.x }
        let sumY = vectorBuffer.reduce(0) { $0 + $1.y }
        let sumZ = vectorBuffer.reduce(0) { $0 + $1.z }
        
        let avgX = sumX / Double(bufferSize)
        let avgY = sumY / Double(bufferSize)
        let avgZ = sumZ / Double(bufferSize)
        
        let averagedMagnitude = sqrt(avgX * avgX + avgY * avgY + avgZ * avgZ)
        
        // ──────────────────────────────────────────────────────────────────
        // STEP 2: VARIANCE — Distinguish walking from train movement
        // ──────────────────────────────────────────────────────────────────
        //
        // Variance is calculated on the RAW magnitudes to measure instantaneous 
        // "bounciness" of the signal.
        
        let meanRawMag = magnitudeBuffer.reduce(0, +) / Double(bufferSize)
        let variance = magnitudeBuffer.reduce(0) { sum, val in
            sum + (val - meanRawMag) * (val - meanRawMag)
        } / Double(bufferSize)
        
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
        let isAboveThreshold = averagedMagnitude > magnitudeThreshold
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
        
        //MARK: Temporary notification
        if isJoltDetected && !hasYieldedJolt {
            hasYieldedJolt = true
            let content = UNMutableNotificationContent()
            content.title = "DEPARTURE DETECTED!"
            content.body = "MotionManager triggered a departure."
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        
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
            magnitude: averagedMagnitude,
            variance: variance,
            joltDuration: joltDuration,
            isJoltDetected: isJoltDetected
        )
        
        eventStreamContinuation?.yield(event)
    }
}
