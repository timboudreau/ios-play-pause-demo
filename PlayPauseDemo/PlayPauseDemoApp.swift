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
import SwiftUI

@main
struct PlayPauseDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @ObservedObject var fakePlayer = PlayPauseSimulator.singleton
    
    /// Needed so the toggle that sets the iOS 26 workaround on/off refreshes the ui on change
    @ObservedObject var facade = NowPlayingInfoFacade.singleton
    
    var body: some View {
        ScrollView(.vertical) {
            VStack {
                Text("Paused State Restore Demo").font(.title2)
                    .padding(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                
                Text("We are simulating restoring the app in a paused state.  *Press the lock button on your device **now** to see what it displays.\n\nThe way each `MPNowPlayingInfoCenter.nowPlayingInfo` property relevant to playing/paused state is updated can be customized by via the strategy edit button.\n\nWhat you will eventually discover is that there is *no* combination of strategies that actually works to get remote controls to show a **play** button rather than a pause button after startup.")
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                
                Text("Playback Position: \(fakePlayer.elapsed.minutesSeconds()) / \(PlayPauseSimulator.simulatedAudioLength.minutesSeconds())")
                HStack {
                    Button("Play") {
                        let _ = fakePlayer.onPlay()
                    }.disabled(fakePlayer.playing || !fakePlayer.ready)
                    Button("Pause") {
                        let _ = fakePlayer.onPause()
                    }.disabled(!fakePlayer.playing || !fakePlayer.ready)
                    StrategyEditorButton()
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                Text("**Before you do anything else:** After opening this app, the Now Playing panel on your device's lock screen should show audio as paused, with a play button visible.\n\nBut it won't.").font(.footnote)
                    .multilineTextAlignment(.leading)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                Divider()
                MediaStateView()
                Divider()
                if #available(iOS 26, *) {
                    Text("Some versions of iOS 26 have a bug where you *must* replace the now playing info map with an empty map and *then* with the properties you want, or media UIs only update on the first call. Select this to enable that workaround.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Enable iOS 26 Workaround", isOn: NowPlayingInfoFacade.enableHackBinding)
                        .controlSize(.small)
                        .padding(EdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 6))
                }
                
            }
        }
        .padding()
    }
}

