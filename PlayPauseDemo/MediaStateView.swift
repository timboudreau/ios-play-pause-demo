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
import MediaPlayer
import OSLog

/// Displays the table of values read from NowPlayingInfoCenter.nowPlayingInfo
struct MediaStateView : View {
    private static var q = DispatchQueue(label: "refresh-mpnp-info", qos: .background)
    @State private var properties : [MediaProperty] = []
    @State private var visible : Bool = false
    
    private var contents : [MediaProperty] {
        properties.sorted { a, b in
            a.id < b.id
        }
    }

    var body : some View {
        VStack {
            Text("Media Player And Now Playing Properties").bold()
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            Grid (verticalSpacing: 8) {
                ForEach(properties) { prop in
                    GridRow {
                        Text(prop.id)
                            .font(.caption)
                            .bold()
                            .gridColumnAlignment(.leading)
                        Text(prop.description)
                            .font(.caption)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .onAppear {
            visible = true
            refresh()
        }
        .onDisappear {
            visible = false
        }
    }
    
    func refresh() {
        if !visible {
            return
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            let refreshed = Self.mpnpProperties()
            onMainThread {
                self.properties = refreshed
                if self.visible {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: self.refresh)
                }
            }
        }
    }
    
    private static nonisolated let nowPlayingProperties : [String] = [
//        MPMediaItemPropertyTitle,
//        MPMediaItemPropertyArtist,
        MPMediaItemPropertyPlaybackDuration,
        MPNowPlayingInfoPropertyPlaybackProgress,
        MPNowPlayingInfoPropertyPlaybackRate,
        MPNowPlayingInfoPropertyElapsedPlaybackTime,
    ];
    
    private nonisolated static func mpnpProperties() -> [MediaProperty] {
        var result : [MediaProperty?] = []
        let center = MPNowPlayingInfoCenter.default()
        
        if let info = center.nowPlayingInfo {
            for property in Self.nowPlayingProperties {
                let prop = MediaProperty.from(property, info[property])
                result.append(prop)
                if prop == nil {
                    Logger.mv.debug("No property for \(property, privacy: .public) with \(String(describing: info[property]), privacy: .public)")
                }
            }
        }
        let cmds = MPRemoteCommandCenter.shared()
        result.append(MediaProperty("Play Command Enabled", cmds.playCommand.isEnabled.description.description))
        result.append(MediaProperty("Pause Command Enabled", cmds.pauseCommand.isEnabled.description.description))
        result.append(MediaProperty("Stop Command Enabled", cmds.stopCommand.isEnabled.description.description))
        result.append(MediaProperty("Toggle Play Pause Enabled", cmds.togglePlayPauseCommand.isEnabled.description))
        return result.compactMap({ prop in prop })
    }
}

fileprivate func coerce(_ value : Any?) -> String? {
    if let a = value {
        if let value = a as? CustomStringConvertible {
            return value.description
        }
        return String(describing: a)
    }
    return nil
}

/// Just an identifiable / hashable / equatable wrapper for random stuff we're interested in to make it easy
/// to use SwiftUI's `ForEach`.
fileprivate struct MediaProperty : Sendable, Equatable, Hashable, Identifiable {
    let id : String
    let description : String
    
    init(_ id: String, _ description: String) {
        self.id = id
        self.description = description
    }
    
    static func from(_ string : String, _ value : Any?) -> Self? {
        if let text = coerce(value) {
            Self(string, text)
        } else {
            nil
        }
    }
}

private extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let mv = Logger(subsystem: subsystem, category: "media-state-view")
}
