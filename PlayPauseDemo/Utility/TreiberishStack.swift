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

/// A thread-safe, lockless, concurrent sequence which can be appended to and drained.
/// This is not quite a Treiber stack in the sense that single elements cannot
/// be **popped** off of it - Treiber stacks rely on every interaction with a given memory
/// address being a *single atomic read, write or exchange operation*. The Swift atomics
/// package is a bit too anemic for that - we would need to be able to exchange a pointer
/// to the head cell with a pointer to the head cell's child (if any) without reading the
/// head pointer twice.  That's implementable in C or assembly and a memory offset,
/// but not with the access Swift atomics give us.
///
/// So in order to make this work, unlike a traditional treiber stack, we append to the
/// *tail* rather than swapping the head for a new head with the old head as its child
/// Iteration is in FIFO order.  So, Trieber-ish stack, not Treiber stack, and somewhat
/// more expensive since there are *multiple* atomics involved and we have to walk to
/// the tail of the stack to append.  And it is less than ideal as there *is* a latent
/// ABA problem - one thread is walking its way to the tail to append, while another
/// thread has already lopped off the head down to the tail, and finishes iterating and
/// discarding the cells before `next` is set on it.
///
/// Production code uses an alternate implementation that calls out to Rust code and implements
/// a correct Treiber stack; for this bug-demo, this will have to do or the project will get
/// very complicated.
///
public final class TreiberishStack<Element : Sendable> : Sendable {
    // IMPORTANT: If we don't use `ordering: .sequentiallyConsistent` here, we will encounter occasional
    // segfaults when setting the head to nil.
    private let _head : ManagedAtomic<TreiberCell<Element>?>
    private var head : TreiberCell<Element>? { _head.load(ordering: .sequentiallyConsistent) }
    public var first : Element? { head?.element }

    public var count : Int {
        var h = head
        var result = 0
        while let hh = h {
            result += 1
            h = hh.next
        }
        return result
    }
    
    /// isEmpty is constant time
    public var isEmpty : Bool { head == nil }
    
    public init() { _head  = .init(nil) }
    
    public init<S: Sequence<Element>>(_ sequence : S) where S.Iterator.Element == Element {
        var head : TreiberCell<Element>? = nil
        for element in sequence {
            if let h = head {
                h.push(TreiberCell(element))
            } else {
                head = TreiberCell(element)
            }
        }
        _head = .init(head)
    }
    
    /// Append an element
    public func push(_ element : Element) {
        let cell = TreiberCell(element)
        if let existingHead = _head.compareExchange(expected: nil, desired: cell, ordering: .sequentiallyConsistent).1 {
            existingHead.push(cell)
        }
    }
    
    public func drain() -> [Element] {
        var result : [Element] = []
        repeat {
            if let oldHead = _head.exchange(nil, ordering: .sequentiallyConsistent) {
                // Pending: analyze the compiled code and see if we were really getting
                // tail recursion here, in which case, put it back.
                var h : TreiberCell<Element>? = oldHead
                while let hh = h {
                    result.append(hh.element)
                    h = hh.next
                }
            }
        } while !isEmpty
        return result
    }
}

fileprivate final class TreiberCell<Element : Sendable> : Sendable, AtomicOptionalWrappable, AtomicReference {
    private let _next : ManagedAtomicLazyReference<TreiberCell<Element>> = .init()
    let element : Element
    var next : TreiberCell<Element>? { _next.load() }
    var count : Int { 1 + (next?.count ?? 0) }
    
    init(_ element: Element) { self.element = element }
    
    func visit(_ f : (Element) throws -> Void) rethrows {
        try f(element)
        if let next = self.next {
            try next.visit(f)
        }
    }
    
    func push(_ cell : TreiberCell<Element>) {
        var n : TreiberCell<Element>? = self
        while let nn = n {
            let c = nn._next.storeIfNilThenLoad(cell)
            if c === cell {
                break
            }
            n = c
        }
    }
}
