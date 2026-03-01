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
import Combine
import SwiftUI

struct StrategyEditorButton : View {
    @State var popupOpen : Bool = false
    @State var restartPopupOpen : Bool = false
    @State var lastKnownStrategies : (PlaybackProgressUpdateStrategy, ElapsedTimeUpdateStrategy, PlaybackRateUpdateStrategy, DefaultPlaybackRateUpdateStrategy) = (.current, .current, .current, .current)
    
    var body : some View {
        Button("Edit Now Playing Update Strategies") {
            popupOpen.toggle()
        }
        .controlSize(.mini)
        .popover(isPresented: $popupOpen, content: { StrategyEditor(open: $popupOpen) })
        .onChange(of: popupOpen) { oldValue, newValue in
            if oldValue && !newValue {
                let newSnapshot : (PlaybackProgressUpdateStrategy, ElapsedTimeUpdateStrategy, PlaybackRateUpdateStrategy, DefaultPlaybackRateUpdateStrategy) = (.current, .current, .current, .current)
                if newSnapshot != lastKnownStrategies {
                    lastKnownStrategies = newSnapshot
                    restartPopupOpen = true
                }
            }
        }
        .confirmationDialog("Strategies Changed", isPresented: $restartPopupOpen, titleVisibility: .visible) {
            Button("Exit App", role: .destructive) {
                exit(0)
            }
            Button("Not Now", role: .cancel) {
                restartPopupOpen = false
            }
        } message: {
            Text("To see the effect of this strategy at **startup time**, the app must be restarted. Exit it now?")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct StrategyEditor : View {
    @Binding var open : Bool
    // We need *something* to change so the UI refreshes when the menu changes things
    @ObservedObject fileprivate var refresher = Refresher.singleton
    
    private func onUpdate() {
        refresher.tick()
    }
    
    var body : some View {
        VStack(spacing: 24){
            Text("Update Strategies").font(.title3)
            Text("`NowPlayingInfoCenter`'s `nowPlayingInfo` dictionary is updated on a timer during playback, and once on pause/stop.\n\nHere you can choose how the three properties that are relative to presenting the state of playback are updated when that happens.")
                .padding()
                .multilineTextAlignment(.leading)
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            StrategyMenu<PlaybackProgressUpdateStrategy>(onUpdate)
            StrategyMenu<ElapsedTimeUpdateStrategy>(onUpdate)
            StrategyMenu<PlaybackRateUpdateStrategy>(onUpdate)
            StrategyMenu<DefaultPlaybackRateUpdateStrategy>(onUpdate)
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    PlaybackProgressUpdateStrategy.current = .defaultValue
                    ElapsedTimeUpdateStrategy.current = .defaultValue
                    PlaybackRateUpdateStrategy.current = .defaultValue
                    DefaultPlaybackRateUpdateStrategy.current = .defaultValue
                    open = false
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .controlSize(.mini)
    }
}

fileprivate struct StrategyMenu<S : UpdateStrategy> : View {
    @Binding private var strategy : S
    private let onChange : () -> Void
    
    init(_ onChange: @escaping () -> Void) {
        _strategy = S.binding
        self.onChange = onChange
    }
    
    var body : some View {
        VStack {
            Text(S.property)
                .font(.footnote)
            Menu(strategy.description) {
                ForEach(S.allCases.map({$0})) { item in
                    Button(item.description) {
                        strategy = item
                        onChange()
                    }
                }
            }
        }
    }
}

/// Used to force refresh of the menu text after a change - otherwise
/// the menu does update the property, but the UI paints the old value,
/// since the binding on `StrategyMenu` does not lead back to anything
/// that is `@State` in some parent view.
@MainActor fileprivate final class Refresher : ObservableObject {
    static let singleton = Refresher()
    func tick() {
        objectWillChange.send()
    }
}
