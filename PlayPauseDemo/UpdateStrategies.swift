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
import SwiftUI
import MediaPlayer
import os

/// A strategy for how to alter a property in `MPNowPlayingInfoCenter.nowPlayingInfo` based on
/// playback state (playing or paused) and progress through the played audio.
protocol UpdateStrategy : Sendable, Equatable, Hashable, Identifiable, CustomStringConvertible, CaseIterable {
    static var current : Self { get set }
    static var binding : Binding<Self> { get }
    static var property : String { get }
}

enum PlaybackProgressUpdateStrategy : Int, Sendable, Equatable, Hashable, Identifiable, CustomStringConvertible, CaseIterable, UpdateStrategy {
    case KeepWhenPaused = 1
    case ZeroWhenPaused = 2
    case RemoveWhenPaused = 3
    
    static let defaultValue : Self = .KeepWhenPaused
    static let property : String = MPNowPlayingInfoPropertyPlaybackProgress
    
    var id : Int { self.rawValue }
    
    var description: String {
        switch self {
        case .KeepWhenPaused:
            "Keep When Paused"
        case .ZeroWhenPaused:
            "Zero When Paused"
        case .RemoveWhenPaused:
            "Remove When Paused"
        }
    }
    
    static var current : Self {
        get {
            .init(rawValue: UserDefaults.standard.integer(forKey: Self.property)) ?? .defaultValue
        } set(val) {
            UserDefaults.standard.set(val.rawValue, forKey: Self.property)
        }
    }
    
    static var binding : Binding<Self> {
        .init {
            Self.current
        } set: { value in
            Self.current = value
        }
    }
    
    func apply(playing: Bool, value : NSNumber, info : inout [String : Any]) {
        switch self {
        case .KeepWhenPaused:
            info[Self.property] = value
        case .ZeroWhenPaused:
            if playing {
                info[Self.property] = value
            } else {
                info[Self.property] = NSNumber(value: Float(0))
            }
        case .RemoveWhenPaused:
            if playing {
                info[Self.property] = value
            } else {
                let _ = info.removeValue(forKey: Self.property)
            }
        }
    }
}

enum ElapsedTimeUpdateStrategy : Int, Sendable, Equatable, Hashable, Identifiable, CustomStringConvertible, CaseIterable, UpdateStrategy {
    case KeepWhenPaused = 1
    case ZeroWhenPaused = 2
    case RemoveWhenPaused = 3
    
    static let defaultValue : Self = .KeepWhenPaused
    static let property : String = MPNowPlayingInfoPropertyElapsedPlaybackTime
    
    var id : Int { self.rawValue }
    
    var description: String  {
        switch self {
        case .KeepWhenPaused:
            "Keep When Paused"
        case .ZeroWhenPaused:
            "Zero When Paused"
        case .RemoveWhenPaused:
            "Remove When Paused"
        }
    }
    
    static var current : Self {
        get {
            .init(rawValue: UserDefaults.standard.integer(forKey: Self.property)) ?? .defaultValue
        } set(val) {
            UserDefaults.standard.set(val.rawValue, forKey: Self.property)
        }
    }
    
    static var binding : Binding<Self> {
        .init {
            Self.current
        } set: { value in
            Self.current = value
        }
    }
    
    func apply(playing: Bool, value : NSNumber, info : inout [String : Any]) {
        switch self {
        case .KeepWhenPaused:
            info[Self.property] = value
        case .ZeroWhenPaused:
            if playing {
                info[Self.property] = value
            } else {
                info[Self.property] = NSNumber(value: Double(0))
            }
        case .RemoveWhenPaused:
            if playing {
                info[Self.property] = value
            } else {
                let _ = info.removeValue(forKey: Self.property)
            }
        }
    }
}

enum PlaybackRateUpdateStrategy : Int, Sendable, Equatable, Hashable, Identifiable, CustomStringConvertible, CaseIterable, UpdateStrategy {
    case DontUpdateAtAll = 1
    case RemoveWhenPaused = 2
    case ZeroWhenPaused = 3
    case AlwaysOne = 4
    
    static let defaultValue : Self = .ZeroWhenPaused
    static let property : String = MPNowPlayingInfoPropertyPlaybackRate
    
    var id : Int { self.rawValue }
    
    var description: String {
        switch self {
        case .DontUpdateAtAll:
            "Dont Set/Update At All"
        case .RemoveWhenPaused:
            "Remove When Paused"
        case .ZeroWhenPaused:
            "Zero When Paused"
        case .AlwaysOne:
            "Always 1.0"
        }
    }
    
    static var current : Self {
        get {
            .init(rawValue: UserDefaults.standard.integer(forKey: Self.property)) ?? .defaultValue
        } set(val) {
            UserDefaults.standard.set(val.rawValue, forKey: Self.property)
        }
    }
    
    static var binding : Binding<Self> {
        .init {
            Self.current
        } set: { value in
            Self.current = value
        }
    }
    
    func apply(playing: Bool, info : inout [String : Any]) {
        switch self {
        case .DontUpdateAtAll:
            break
        case .ZeroWhenPaused:
            let value : Double = playing ? 1 : 0
            info[Self.property] = NSNumber(value: value)
        case .RemoveWhenPaused:
            if playing {
                info[Self.property] = NSNumber(value: Double(1))
            } else {
                let _ = info.removeValue(forKey: Self.property)
            }
        case .AlwaysOne:
            info[Self.property] = NSNumber(value: Double(1))
        }
    }
}

enum DefaultPlaybackRateUpdateStrategy : Int, Sendable, Equatable, Hashable, Identifiable, CustomStringConvertible, CaseIterable, UpdateStrategy {
    case DontUpdateAtAll = 1
    case RemoveWhenPaused = 2
    case ZeroWhenPaused = 3
    case AlwaysOne = 4
    
    static let defaultValue : Self = .ZeroWhenPaused
    static let property : String = MPNowPlayingInfoPropertyDefaultPlaybackRate
    
    var id : Int { self.rawValue }
    
    var description: String {
        switch self {
        case .DontUpdateAtAll:
            "Dont Set/Update At All"
        case .RemoveWhenPaused:
            "Remove When Paused"
        case .ZeroWhenPaused:
            "Zero When Paused"
        case .AlwaysOne:
            "Always 1.0"
        }
    }
    
    static var current : Self {
        get {
            .init(rawValue: UserDefaults.standard.integer(forKey: Self.property)) ?? .defaultValue
        } set(val) {
            UserDefaults.standard.set(val.rawValue, forKey: Self.property)
        }
    }
    
    static var binding : Binding<Self> {
        .init {
            Self.current
        } set: { value in
            Self.current = value
        }
    }
    
    func apply(playing: Bool, info : inout [String : Any]) {
        switch self {
        case .DontUpdateAtAll:
            break
        case .ZeroWhenPaused:
            let value : Double = playing ? 1 : 0
            info[Self.property] = NSNumber(value: value)
        case .RemoveWhenPaused:
            if playing {
                info[Self.property] = NSNumber(value: Double(1))
            } else {
                let _ = info.removeValue(forKey: Self.property)
            }
        case .AlwaysOne:
            info[Self.property] = NSNumber(value: Double(1))
        }
    }
}
