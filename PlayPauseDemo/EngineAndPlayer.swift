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
import Atomics
@preconcurrency import AVFoundation
import Foundation
import OSLog

struct EngineAndPlayer : Sendable {

    static let preferredSampleRate : Double = 44_100
    static let format = AVAudioFormat(standardFormatWithSampleRate: preferredSampleRate, channels: 1)!
    static let preferredBufferDuration : TimeInterval = 0.5
    /// Use half second buffers
    static var framesPerBuffer : AVAudioFrameCount {
        AVAudioFrameCount(floor(format.sampleRate * preferredBufferDuration))
    }
    
    private let engine : AVAudioEngine
    private let player : AVAudioPlayerNode
    private let _playing = ManagedAtomic(false)

    var playing : Bool {
        get {
            return _playing.load(ordering: .sequentiallyConsistent)
        } nonmutating set(val) {
            _playing.store(val, ordering: .sequentiallyConsistent)
        }
    }

    init() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)

        engine.connect(player, to: engine.mainMixerNode, format: Self.format)

        // Note, this will sometimes fail with an NSException due to some sort of internal race
        // inside AVAudioEngine - production code should use objc to catch the exception and try it in a loop
        // with a delay, and possibly delay before the subsequent call to start, which can also sometimes
        // crash if called too soon after prepare().
        //
        // In production code we use objective c code to catch NSException and resurface it
        // as a Swift error to avoid surprise application aborts.
        engine.prepare()

        try! engine.start()
    }

    func makeNoise() {
        let actualBufferDuration = AVAudioSession.sharedInstance().ioBufferDuration
        let sessionPreferredBufferDuration = AVAudioSession.sharedInstance().preferredIOBufferDuration
        let actualFrames = AVAudioFrameCount(Self.preferredSampleRate * actualBufferDuration)
        
        let frames = Self.framesPerBuffer
        if frames != actualFrames {
            Logger.player.warning("Our preferred buffer size is \(frames); actual session buffer size is \(actualFrames). Session preferred is \(AVAudioFrameCount(sessionPreferredBufferDuration * Self.preferredSampleRate))")
        }
        let buf : AVAudioPCMBuffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frames)!;
        
        // Produces quiet white noise so this demo isn't a torture device
        if let channelData = buf.floatChannelData {
            let channel1 = channelData[0]
            for i in 0..<frames {
                channel1[Int(i)] = Float.random(in: 0...0.02)
            }
            buf.frameLength = buf.frameCapacity
        }
        maybeRescheduleBuffer(buf)
        // Occasionally crashes with "player did not see an IO cycle" - in production code we catch the NSException
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

private extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let player = Logger(subsystem: subsystem, category: "player")
}
