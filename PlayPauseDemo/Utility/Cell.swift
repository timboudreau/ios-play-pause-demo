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
import os

/// Just a simple value wrapped in an `OSAllocatedUnfairLock` for thread-safe access, which
/// is created once on first request.
public struct Cell<T> : @unchecked Sendable {
    private let constructor : () -> T
    private let _value : OSAllocatedUnfairLock<T?>
    
    public init(constructor : @escaping () -> T) {
        self.constructor = constructor
        self._value = .init(uncheckedState: nil)
    }
    
    public init(_ value : T) {
        self.constructor = { value }
        self._value = OSAllocatedUnfairLock<T?>(uncheckedState: value)
    }
    
    
    /// Take the exclusive lock on the value and allow it to be modified by the passed function.
    /// This is a blocking, non-reentrant call.
    @discardableResult public func withValue<V>(_ f : (inout T) throws -> V) rethrows -> V {
        try slowLockBenchmark {
            try _value.withLockUnchecked { curr in
                if var v = curr {
                    let result = try f(&v)
                    curr = v
                    return result
                } else {
                    var nue = constructor()
                    defer {
                        curr = nue
                    }
                    let result = try f(&nue)
                    return result
                }
            }
        }
    }
}

fileprivate func slowLockBenchmark<T>(_ f : () throws -> T) rethrows -> T {
    // Stubbed this - in production debug mode code, this will log a stack if
    // the lock is held for more than 100ms
    try f()
}
