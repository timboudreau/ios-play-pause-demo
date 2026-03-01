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

// Extends a few built-in types with some conveniences to make the code less verbose and more consistent.

fileprivate enum TimeValues {
    static let secsPerMin = 60
    static let secsPerHour = Self.secsPerMin * 60
    static let nanosPerSecond = 1e9
}

extension TimeInterval {
    
    static func minutes<B : BinaryFloatingPoint>(_ count : B) -> Self {
        TimeInterval(count) * TimeInterval(TimeValues.secsPerMin)
    }
    
    /// Returns this time interval in milliseconds if it is positive, 0 if negative.
    var milliseconds : UInt64 {
        UInt64(max(0, self) * 1_000)
    }

    /// Flexibly convert this `TimeInterval` to a sane, human-friendly string representation, handling a few
    /// quirky corner-cases.
    func minutesSeconds(explicitSeconds : Bool = false) -> String {
        if self < 1.0 {
            if self == 0.0 {
                return "0:00"
            }
            let mil = milliseconds
            if mil == 0 {
                let nanos = UInt64(max(0, self) * 1e+9)
                if nanos == 0 {
                    return "0:00"
                }
                if nanos > 1_000_000 {
                    let ms = nanos / 1_000_000
                    return "\(ms) ms"
                }
                if nanos > 100_000 {
                    let ms = TimeInterval(nanos) / 1_000_000
                    return String(format: "%.3f ms", ms)
                }
                return "\(nanos) ns"
            }
            return "\(mil) ms"
        }
        
        var seconds = Int(ceil(self))
        var hours = 0
        var mins = 0
        
        if seconds > TimeValues.secsPerHour {
            hours = seconds / TimeValues.secsPerHour
            seconds -= hours * TimeValues.secsPerHour
        }
        
        if seconds > TimeValues.secsPerMin {
            mins = seconds / TimeValues.secsPerMin
            seconds -= mins * TimeValues.secsPerMin
        }
        
        if explicitSeconds && mins == 0 && hours == 0 {
            if seconds < 1 {
                return "\(seconds.description) sec"
            }
            return "\(String(format: "%02d", seconds)) sec"
        }
        
        var formattedString : String
        
        if hours > 24 {
            var days = hours / 24
            hours = hours % 24
            if days > 365 {
                let years = days / 365
                days = days % 365
                if days > 0 {
                    formattedString = "\(years)y \(days)d "
                } else {
                    formattedString = "\(years)y "
                }
            } else {
                hours = hours % 24
                formattedString = "\(days)d "
            }
        } else {
            formattedString = ""
        }
        
        if hours > 0 {
            if mins < 10 {
                formattedString += "0\(String(format: "%02d", hours)):"
            } else {
                formattedString += "\(String(format: "%02d", hours)):"
            }
        }
        formattedString += "\(String(format: "%01d", mins)):\(String(format: "%02d", seconds))"
        return formattedString
    }
}

extension DispatchTime {
    /// Returns a positive interval or zero for any two `DispatchTime`s, or zero if they are the same
    func interval(_ other : DispatchTime) -> TimeInterval {
        let a = self.uptimeNanoseconds
        let b = other.uptimeNanoseconds
        if a == b {
            return 0
        }
        return TimeInterval(max(a, b) - min(a, b)) * 1e-9
    }
    
    var age : TimeInterval {
        (TimeInterval(Self.now().uptimeNanoseconds) - TimeInterval(self.uptimeNanoseconds)) / TimeValues.nanosPerSecond
    }
}
