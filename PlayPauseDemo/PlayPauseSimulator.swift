/*
 Copyright 2026 Tim Boudreau

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 documentation files (the “Software”), deal in the Software without restriction, including without limitation
 the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions
 of the Software.

 THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
 TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 DEALINGS IN THE SOFTWARE.
 */
import AVFoundation
import Foundation
import MediaPlayer
import OSLog
import SwiftUI
import Synchronization

/// Manages setting up the player, initiating and stopping playback, and plumbing command handlers for
/// `MPRemoteCommandCenter`.
///
@MainActor final class PlayPauseSimulator : NSObject, ObservableObject {
    static let singleton = PlayPauseSimulator()
    // Since we have two bits of mutable state that must be thread-safe, we use an atomic u8 and a bitmask
    // for these
    private nonisolated static let readyBit: UInt8 = 1 << 0
    private nonisolated static let playingBit: UInt8 = 1 << 1
    
    nonisolated static let simulatedAudioLength : TimeInterval = 210 // 3:30

    private static let updateInterval : TimeInterval = 5.0
    private nonisolated let player = EngineAndPlayer()
    private nonisolated let state = Atomic<UInt8>(0)
    
    // Since commands from the remote are not guaranteed to arrive on the main thread,
    // we need this to be thread-safe, while the methods need to be able to respond synchronously
    // based on the player's state.
    nonisolated var playing : Bool {
        get {
            state.load(ordering: .acquiring) & Self.playingBit != 0
        } set(val) {
            if updatePlaying(to: val) {
                defer { onMainThread { self.objectWillChange.send() } }
                Logger.simulator.info("Set playing to \(val)")
                self.player.playing = val
                let cmds = MPRemoteCommandCenter.shared()
                cmds.playCommand.isEnabled = !val
                cmds.pauseCommand.isEnabled = val
                cmds.stopCommand.isEnabled = val
                onMainThread { [weak self] in
                    guard let self else { return }
                    self.timer.isPaused = !val
                    if val {
                        self.elapsed = 0.0
                        self.startedAt = DispatchTime.now()
                        do {
                            let sess = AVAudioSession.sharedInstance()
                            try sess.setActive(true)
                        } catch {
                            Logger.simulator.critical("Error reactivating session for play: \(error)")
                            return
                        }
                        self.player.makeNoise()
                    } else {
                        // Do a final update after things have settled to ensure
                        // the media center is updated to the post playback state, as the timer
                        // that was calling tick() is now stopped
                        self.tick()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                            guard let self else { return }
                            self.objectWillChange.send()
                        }
                    }
                }
            }
        }
    }

    nonisolated var ready : Bool {
        get {
            state.load(ordering: .acquiring) & Self.readyBit != 0
        } set(val) {
            if val {
                if state.bitwiseOr(Self.readyBit, ordering: .releasing).oldValue & Self.readyBit == 0 {
                    onMainThread { self.objectWillChange.send() }
                }
            } else {
                if state.bitwiseAnd(~Self.readyBit, ordering: .releasing).oldValue & Self.readyBit != 0 {
                    onMainThread { self.objectWillChange.send() }
                }
            }
        }
    }
    
    // Returns true if the value changed
    nonisolated func updatePlaying(to val : Bool) -> Bool {
        if val {
            if state.bitwiseOr(Self.playingBit, ordering: .releasing).oldValue & Self.playingBit == 0 {
                onMainThread { self.objectWillChange.send() }
                return true
            }
        } else {
            if state.bitwiseAnd(~Self.playingBit, ordering: .releasing).oldValue & Self.playingBit != 0 {
                onMainThread { self.objectWillChange.send() }
                return true
            }
        }
        return false
    }
    
    @Published var elapsed : TimeInterval = 0.0

    // We are simulating app restore in a *paused* state, so we start pretending
    // we have been paused 15 seconds into the audio.
    private var startedAt = DispatchTime.now() - 15.0
    
    // Ensure the constructor's call to `tick()` to initialize the media info properties
    // succeeds - we use this to throttle media center updates
    private var lastMediaCenterUpdate : DispatchTime = DispatchTime.now() - (updateInterval + 1)

    private var intervalSinceStart : TimeInterval {
        return Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) * 1e-9
    }

    private lazy var timer = {
        let result = CADisplayLink(target: self, selector: #selector(tick))
        result.add(to: .current, forMode: .default)
        result.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 5, preferred: 3)
        result.isPaused = true
        return result
    }()

    override init() {
        super.init()
        // Take over audio output so the media center will pay attention to us
        // Activating the session early startup can race with something in the bowels
        // of AVFoundation and fail, so delay this, and use a retry loop.
        //
        // Also we want this out of the critical path of application launch.
        //
        // We are not dealing with the many ways this can fail (e.g. app launches during a phone call)
        // for this.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 1.5) { [weak self] in
            guard let self else { return }
            for i in 0...5 {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback)
                    try session.setPreferredSampleRate(EngineAndPlayer.preferredSampleRate)
                    try session.setPreferredIOBufferDuration(EngineAndPlayer.preferredBufferDuration)
                    try session.setPrefersInterruptionOnRouteDisconnect(false)
                    try session.setPrefersNoInterruptionsFromSystemAlerts(true)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    Logger.simulator.info("Init session success on attempt \(i + 1)")
                    self.ready = true
                    self.connectToRemoteCommandCenter()
                    return
                } catch {
                    Logger.simulator.error("Failed to initialize av session: \(error, privacy: .public)")
                    Thread.sleep(forTimeInterval: 0.25)
                }
            }
            fatalError("Could not init audio session after five attempts. Aborting.")
        }
    }
    
    nonisolated func connectToRemoteCommandCenter() {
        // Callbacks for remote playback buttons
        let cmds = MPRemoteCommandCenter.shared()
        cmds.playCommand.addTarget(self, action: #selector(self.onPlay))
        cmds.pauseCommand.addTarget(self, action: #selector(self.onPause))
        cmds.togglePlayPauseCommand.addTarget(self, action: #selector(self.onToggle))
        cmds.stopCommand.addTarget(self, action: #selector(self.onStop))

        cmds.playCommand.isEnabled = true
        cmds.pauseCommand.isEnabled = false
        cmds.stopCommand.isEnabled = false
        cmds.togglePlayPauseCommand.isEnabled = true
        
        Logger.simulator.info("Attached command handlers to MPRemoteCommandCenter")
        // Initialize the now playing info
        onMainThread(tick)
    }

    @objc func onPlay() -> MPRemoteCommandHandlerStatus {
        let wasPlaying = playing
        Logger.simulator.trace("Remote play invoked on \(Thread.current) - was playing? \(wasPlaying)")
        playing = true
        return !wasPlaying ? .success : .noActionableNowPlayingItem
    }
    
    @objc func onStop() -> MPRemoteCommandHandlerStatus {
        let wasPlaying = playing
        Logger.simulator.trace("Remote stop invoked on \(Thread.current) - was playing? \(wasPlaying)")
        return implOnPause(wasPlaying)
    }

    @objc func onPause() -> MPRemoteCommandHandlerStatus {
        let wasPlaying = playing
        Logger.simulator.trace("Remote pause invoked on \(Thread.current) - was playing? \(wasPlaying)")
        return implOnPause(wasPlaying)
    }
    
    private func implOnPause(_ wasPlaying: Bool) -> MPRemoteCommandHandlerStatus {
        playing = false
        return wasPlaying ? .success : .noActionableNowPlayingItem
    }

    @objc func onToggle() -> MPRemoteCommandHandlerStatus {
        Logger.simulator.trace("Remote toggle play/pause invoked on \(Thread.current) playing is \(self.playing)")
        playing.toggle()
        return .success
    }

    private nonisolated var mpData : [String : Any] {
        // These values are always the same and always placed in the now playing info map.
        [
            MPMediaItemPropertyTitle : "Fake Audio Demo",
            MPMediaItemPropertyArtist : "Demo",
            MPMediaItemPropertyMediaType : MPMediaType.music.rawValue,
            MPMediaItemPropertyPlaybackDuration : NSNumber(value: Self.simulatedAudioLength),
        ]
    }

    @objc func tick() {
        assert(Thread.isMainThread, "Tick called off main thread") // @objc = nonisolated - no guarantee otherwise
        
        // keep the progress bar looping through the simulated audio length by taking the remainder.
        
        // We could get AVAudioTime from the player, but doing that right is a LOT of fussy code to handle
        // corner cases like negative offsets into the buffer.
        let elapsed = intervalSinceStart.truncatingRemainder(dividingBy: Self.simulatedAudioLength)
        self.elapsed = elapsed
        
        let elapsedFraction = elapsed / Self.simulatedAudioLength
        let playing = playing
        
//        Logger.simulator.trace("Tick playing \(playing) @ \(elapsedFraction)")

        // The docs advise not to update this too often - in fact, we are doing it more often than
        // we should, but it will do.
        if lastMediaCenterUpdate.age > Self.updateInterval {
            NowPlayingInfoFacade.singleton.update { data in
                for (k, v) in self.mpData {
                    data[k] = v
                }
                PlaybackProgressUpdateStrategy.current.apply(playing: playing, value: NSNumber(value: Float(elapsedFraction)), info: &data)
                ElapsedTimeUpdateStrategy.current.apply(playing: playing, value: NSNumber(value: Double(elapsed)), info: &data)
                PlaybackRateUpdateStrategy.current.apply(playing: playing, info: &data)
            }
            lastMediaCenterUpdate = DispatchTime.now()
            Logger.simulator.trace("Updated Now Playing info")
        }
        objectWillChange.send()
    }
}

private extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let simulator = Logger(subsystem: subsystem, category: "simulator")
}
