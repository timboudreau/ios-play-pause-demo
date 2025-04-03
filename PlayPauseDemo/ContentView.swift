import Atomics
import AVFoundation
import SwiftUI
import MediaPlayer

struct ContentView: View {
    @ObservedObject var fakePlayer = PlayPauseSimulator.singleton

    var body: some View {
        VStack(alignment: .leading) {
            Text("Playing or Paused?").font(.title2)
            Text("\(fakePlayer.elapsed.minutesSeconds()) / \(PlayPauseSimulator.simulatedAudioLength.minutesSeconds())")
            HStack {
                Button("Play") {
                    let _ = fakePlayer.onPlay()
                }.disabled(fakePlayer.playing || !fakePlayer.ready)
                Button("Pause") {
                    let _ = fakePlayer.onPause()
                }.disabled(!fakePlayer.playing || !fakePlayer.ready)
            }
            Text("After opening this app, the Now Playing panel on your device's lock screen should show audio as paused.").font(.footnote)
                .multilineTextAlignment(.leading)
        }
        .padding()
    }
}

final class PlayPauseSimulator : NSObject, ObservableObject {
    static let singleton = PlayPauseSimulator()

    private static let updateInterval : TimeInterval = 5.0
    static let simulatedAudioLength : TimeInterval = 210 // 3:30

    // Evidently we need to create an AVAudioEngine or the system ignores our
    // manipulation of things
    private var uselessButNecessaryPlayer = EngineAndPlayer()

    @Published var _playing : Bool = false
    @Published var elapsed : Double = 0.0
    @Published var ready = false

    var startedAt = DispatchTime.now()
    var lastMediaCenterUpdate : DispatchTime = DispatchTime.now() - 30.0

    var intervalSinceStart : TimeInterval {
        return Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) * 1e-9
    }

    lazy var timer = {
        let result = CADisplayLink(target: self, selector: #selector(tick))
        result.add(to: .current, forMode: .default)
        result.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        result.isPaused = true
        return result
    }()

    var playing : Bool { 
        get {
            return _playing
        } set(val) {
            if val != _playing {
                _playing = val
                if val {
                    elapsed = 0.0
                    startedAt = DispatchTime.now()
                }
                self.uselessButNecessaryPlayer.playing = val
                let cmds = MPRemoteCommandCenter.shared()
                cmds.playCommand.isEnabled = !val
                cmds.pauseCommand.isEnabled = val
                timer.isPaused = !val
            }
        }
    }

    static var defaultCategoryOptions : AVAudioSession.CategoryOptions {
        var options = AVAudioSession.CategoryOptions()
        options.insert(.interruptSpokenAudioAndMixWithOthers)
//        options.insert(.allowAirPlay)
//        options.insert(.allowBluetooth)
        return options
    }

    private var mpData : [String : Any] {
        [
            MPMediaItemPropertyTitle : "Fake Audio Demo",
            MPMediaItemPropertyArtist : "Demo",
            MPMediaItemPropertyMediaType : MPMediaType.music.rawValue,
            MPMediaItemPropertyPlaybackDuration : Self.simulatedAudioLength,
            MPNowPlayingInfoPropertyPlaybackProgress : elapsed / Self.simulatedAudioLength
        ]
    }

    override init() {
        super.init()
        // Take over audio output so the media center will pay attention to us
        let session = AVAudioSession.sharedInstance()
        // Activating the session early startup can race with something in the bowels
        // of AVFoundation and fail, so delay this
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.5) {
            for i in 0...5 {
                do {
                    try session.setCategory(.playback)
//                    try! session.setCategory(.playback, mode: .default, options: Self.defaultCategoryOptions)
                    try session.setPreferredSampleRate(44100.0)
                    try session.setPrefersInterruptionOnRouteDisconnect(false)
                    try session.setPrefersNoInterruptionsFromSystemAlerts(true)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    print("Init session success on attempt \(i + 1)")
                    self.ready = true
                    return
                } catch {
                    print(" \(error)")
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
            fatalError("Could not init audio session. Aborting.")
        }

        // Callbacks for remote playback buttons
        let cmds = MPRemoteCommandCenter.shared()
        cmds.playCommand.addTarget(self, action: #selector(onPlay))
        cmds.pauseCommand.addTarget(self, action: #selector(onPause))
        cmds.togglePlayPauseCommand.addTarget(self, action: #selector(onToggle))

        cmds.playCommand.isEnabled = true
        cmds.pauseCommand.isEnabled = false

        // Set a fake song title and initial position
        let ctr = MPNowPlayingInfoCenter.default()
        ctr.nowPlayingInfo = mpData
    }

    @objc func onPlay() -> MPRemoteCommandHandlerStatus {
        print("Play")
        let wasPlaying = playing
        playing = true
        if !wasPlaying {
            do {
                let sess = AVAudioSession.sharedInstance()
                try sess.setActive(true)
            } catch {
                print("Error reactivating session for play: \(error)")
            }
            uselessButNecessaryPlayer.makeNoise()
            return .success
        }
        return .noActionableNowPlayingItem
    }

    @objc func onPause() -> MPRemoteCommandHandlerStatus {
        print("Pause")
        let wasPlaying = playing
        playing = false
        return wasPlaying ? .success : .noActionableNowPlayingItem
    }

    @objc func onToggle() -> MPRemoteCommandHandlerStatus{
        playing.toggle()
        return .success
    }

    @objc func tick() {
        // keep looping through simulated audio length
        elapsed = intervalSinceStart.truncatingRemainder(dividingBy: Self.simulatedAudioLength)

        // The docs advise not to update this too often
        let now = DispatchTime.now()
        if TimeInterval(now.uptimeNanoseconds - lastMediaCenterUpdate.uptimeNanoseconds) * 1e-9 < Self.updateInterval {
            let ctr = MPNowPlayingInfoCenter.default()
            ctr.nowPlayingInfo = mpData
            lastMediaCenterUpdate = now
        }
    }
}

extension TimeInterval {
    func minutesSeconds(explicitSeconds : Bool = false) -> String {
        if self < 1.0 {
            if self == 0.0 {
                return "0:00"
            }
            let mil = UInt64(self / 1_000_000)
            if mil == 0 {
                let nanos = UInt64(self * 1e-9)
                return "\(nanos) ns"
            }
            return "\(mil) ms"
        }

        var seconds = Int(ceil(self))
        var hours = 0
        var mins = 0

        if seconds > 3600 {
            hours = seconds / 3600
            seconds -= hours * 3600
        }

        if seconds > 60 {
            mins = seconds / 60
            seconds -= mins * 60
        }

        var formattedString = ""
        if hours > 0 {
            formattedString = "\(String(format: "%02d", hours)):"
        }
        if explicitSeconds && mins == 0 {
            if seconds < 1 {
                return "\(seconds.description) sec"
            }
            return "\(String(format: "%02d", seconds)) sec"
        }
        formattedString += "\(String(format: "%01d", mins)):\(String(format: "%02d", seconds))"
        return formattedString
    }
}

extension DispatchTime {
    func interval(_ other : DispatchTime) -> TimeInterval {
        var a = self.uptimeNanoseconds
        var b = other.uptimeNanoseconds
        if a == b {
            return 0
        }
        return TimeInterval(max(a, b) - min(a, b)) * 1e-9
    }
}

fileprivate struct EngineAndPlayer {

    private static let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let engine : AVAudioEngine
    private let player : AVAudioPlayerNode
    private let _playing = ManagedAtomic(false)

    var playing : Bool {
        get {
            return _playing.load(ordering: .sequentiallyConsistent)
        } set(val) {
            _playing.store(val, ordering: .sequentiallyConsistent)
        }
    }

    init() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)

        engine.connect(player, to: engine.mainMixerNode, format: Self.fmt)

        // Note, this will sometimes fail with an NSException due to some sort of internal race
        // inside AVAudioEngine - real code should use objc to catch the exception and try it in a loop
        // with a delay, and possibly delay before the subsequent call to start, which can also sometimes
        // crash if called too soon after prepare()
        engine.prepare()

        try! engine.start()
    }

    func makeNoise() {
        // half second buffer
        let frames = 44100 / 2
        let buf : AVAudioPCMBuffer = AVAudioPCMBuffer(pcmFormat: Self.fmt, frameCapacity: AVAudioFrameCount(frames))!;
        if let channelData = buf.floatChannelData {
            let channel1 = channelData[0]
            for i in 0..<frames {
                // Quiet white noise so this demo isn't a torture device
                channel1[i] = Float.random(in: 0...0.02)
            }
            buf.frameLength = buf.frameCapacity
        }
        maybeRescheduleBuffer(buf)
        player.play()
    }

    func maybeRescheduleBuffer(_ buf : AVAudioPCMBuffer) {
        player.scheduleBuffer(buf, completionCallbackType: .dataConsumed) { _ in
            if self.playing {
                maybeRescheduleBuffer(buf)
            }
        }
    }
}
