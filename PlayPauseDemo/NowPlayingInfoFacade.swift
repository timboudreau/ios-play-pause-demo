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
import Foundation
import OSLog
@preconcurrency import MediaPlayer
import SwiftUI
import Synchronization

/// Coalesces things that want to update now-playing data, and works around an iOS 26 bug
/// where the now playing info displayed in cars and on the lock screen never updates after the
/// first call unless the now playing info dictionary is replaced once with an empty dictionary
/// and then replaced with the desired properties.
public final class NowPlayingInfoFacade : Sendable, ObservableObject {
    private static let q = DispatchQueue(label: "now-playing", qos: .utility)
    public static let singleton = NowPlayingInfoFacade()
    
    /// The time delay before we actually update the now playing info, for multiple
    /// callers to get in line
    private static let latency : TimeInterval = 0.1
    private static let ios26HackEnabled : Atomic<Bool> = .init(false);
    
    /// Whether a job to call the stack of updaters has already been scheduled
    private let enqueued : Atomic<Bool> = .init(false);
    
    /// A lock which holds the current set of values we want `NowPlayingInfoCenter.nowPlayingInfo`
    /// to contain.
    private let pendingData : Cell<[String: Any]> = .init(constructor: {
        NowPlayingInfoFacade.nowPlayingInfo
    })
    
    /// A stack of functions which are enqueued to modify the data we are going to set on
    /// `NowPlayingInfoCenter.nowPlayingInfo`.
    private let updaters : TreiberishStack<@Sendable (inout [String: Any]) -> Void> = .init()

    /// In at least iOS 26.1, the now playing info map must be set first to an empty map
    /// and then to its contents, or the now playing view and automotive views are never
    /// updated after the first call
    private static let ios26workaround : Bool = {
        if ios26HackEnabled.load(ordering: .relaxed) {
            if #available(iOS 26, *) {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }()
    
    /// Binding so a toggle for the hack can be presented in the UI
    public static let enableHackBinding : Binding<Bool> = Binding {
        ios26HackEnabled.load(ordering: .relaxed)
    } set: { val in
        if ios26HackEnabled.exchange(val, ordering: .acquiringAndReleasing) != val {
            singleton.fire()
        }
    }

    static var center : MPNowPlayingInfoCenter {
        MPNowPlayingInfoCenter.default()
    }
    
    static var nowPlayingInfo: [String: Any] {
        center.nowPlayingInfo ?? [:]
    }
    
    private init(){}
    
    /// Pass a closure which will be called asynchronously to contribute contents to an updated
    /// `MPNowPlayingCenter.nowPlayingInfo`.
    public func update(_ f : @Sendable @escaping (inout [String: Any]) -> Void) {
        updaters.push(f)
        maybeEnqueue()
    }
    
    private func maybeEnqueue() {
        if enqueued.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged {
            Self.q.asyncAfter(deadline: .now() + Self.latency) {
                defer { self.enqueued.store(false, ordering: .sequentiallyConsistent) }
                self.update()
            }
        }
    }
    
    private func update() {
        let (update, count) = pendingData.withValue { data in
            var funcs = updaters.drain();
            let ct = funcs.count;
            funcs.reverse();
            for f in funcs {
                f(&data)
            }
            return (data, ct)
        }
        // don't do this part under the lock
        let ctr = Self.center;
        if Self.ios26workaround {
            ctr.nowPlayingInfo = [:]
            let holder = DataHolder(data: update);
            Self.q.async {
                NowPlayingInfoFacade.center.nowPlayingInfo = holder.data
            }
        } else {
            ctr.nowPlayingInfo = update
        }
        Logger.facade.trace("Performed \(count) media-info updates -> \(String(describing: update), privacy: .public)")
    }
    
    private func fire() {
        onMainThread {
            self.objectWillChange.send()
        }
    }
}

/// Sigh, needed to make the dictionary sendable
fileprivate class DataHolder : @unchecked Sendable {
    let data : [String : Any]
    
    init(data: [String : Any]) {
        self.data = data
    }
}

private extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let facade = Logger(subsystem: subsystem, category: "media-facade")
}
