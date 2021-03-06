//===--- Stride.swift - Components for stride(...) iteration --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Conforming types are notionally continuous, one-dimensional
/// values that can be offset and measured.
public protocol Strideable : Comparable {
  // FIXME: We'd like to name this type "Distance" but for
  // <rdar://problem/17619038>
  /// A type that can represent the distance between two values of `Self`.
  associatedtype Stride : SignedNumber

  /// Returns a stride `x` such that `self.advanced(by: x)` approximates
  /// `other`.
  ///
  /// - Complexity: O(1).
  ///
  /// - SeeAlso: `RandomAccessIndex`'s `distance(to:)`, which provides a
  ///   stronger semantic guarantee.
  @warn_unused_result
  func distance(to other: Self) -> Stride

  /// Returns a `Self` `x` such that `self.distance(to: x)` approximates
  /// `n`.
  ///
  /// - Complexity: O(1).
  ///
  /// - SeeAlso: `RandomAccessIndex`'s `advanced(by:)`, which
  ///   provides a stronger semantic guarantee.
  @warn_unused_result
  func advanced(by n: Stride) -> Self
}


/// Compare two `Strideable`s.
public func < <T : Strideable>(x: T, y: T) -> Bool {
  return x.distance(to: y) > 0
}

public func == <T : Strideable>(x: T, y: T) -> Bool {
  return x.distance(to: y) == 0
}

@warn_unused_result
public func + <T : Strideable>(lhs: T, rhs: T.Stride) -> T {
  return lhs.advanced(by: rhs)
}

@warn_unused_result
public func + <T : Strideable>(lhs: T.Stride, rhs: T) -> T {
  return rhs.advanced(by: lhs)
}

@warn_unused_result
public func - <T : Strideable>(lhs: T, rhs: T.Stride) -> T {
  return lhs.advanced(by: -rhs)
}

@warn_unused_result
public func - <T : Strideable>(lhs: T, rhs: T) -> T.Stride {
  return rhs.distance(to: lhs)
}

public func += <T : Strideable>(lhs: inout T, rhs: T.Stride) {
  lhs = lhs.advanced(by: rhs)
}

public func -= <T : Strideable>(lhs: inout T, rhs: T.Stride) {
  lhs = lhs.advanced(by: -rhs)
}

//===--- Deliberately-ambiguous operators for UnsignedIntegerTypes --------===//
// The UnsignedIntegerTypes all have a signed Stride type.  Without these     //
// overloads, expressions such as UInt(2) + Int(3) would compile.             //
//===----------------------------------------------------------------------===//

public func + <T : UnsignedInteger>(
  lhs: T, rhs: T._DisallowMixedSignArithmetic
) -> T {
  _sanityCheckFailure("Should not be callable.")
}

public func + <T : UnsignedInteger>(
  lhs: T._DisallowMixedSignArithmetic, rhs: T
) -> T {
  _sanityCheckFailure("Should not be callable.")
}

public func - <T : _DisallowMixedSignArithmetic>(
  lhs: T, rhs: T._DisallowMixedSignArithmetic
) -> T {
  _sanityCheckFailure("Should not be callable.")
}

public func - <T : _DisallowMixedSignArithmetic>(
  lhs: T, rhs: T
) -> T._DisallowMixedSignArithmetic {
  _sanityCheckFailure("Should not be callable.")
}

public func += <T : UnsignedInteger>(
  lhs: inout T, rhs: T._DisallowMixedSignArithmetic
) {
  _sanityCheckFailure("Should not be callable.")
}

public func -= <T : UnsignedInteger>(
  lhs: inout T, rhs: T._DisallowMixedSignArithmetic
) {
  _sanityCheckFailure("Should not be callable.")
}

//===----------------------------------------------------------------------===//

/// An iterator for the result of `stride(to:...)`.
public struct StrideToIterator<Element : Strideable> : IteratorProtocol {
  internal var _current: Element
  internal let _end: Element
  internal let _stride: Element.Stride

  /// Advance to the next element and return it, or `nil` if no next
  /// element exists.
  public mutating func next() -> Element? {
    if _stride > 0 ? _current >= _end : _current <= _end {
      return nil
    }
    let result = _current
    _current += _stride
    return result
  }
}

/// A `Sequence` of values formed by striding over a half-open interval.
public struct StrideTo<Element : Strideable> : Sequence, CustomReflectable {
  // FIXME: should really be a CollectionType, as it is multipass

  /// Returns an iterator over the elements of this sequence.
  ///
  /// - Complexity: O(1).
  public func makeIterator() -> StrideToIterator<Element> {
    return StrideToIterator(_current: _start, _end: _end, _stride: _stride)
  }

  internal init(_start: Element, end: Element, stride: Element.Stride) {
    _precondition(stride != 0, "stride size must not be zero")
    // Unreachable endpoints are allowed; they just make for an
    // already-empty Sequence.
    self._start = _start
    self._end = end
    self._stride = stride
  }

  internal let _start: Element
  internal let _end: Element
  internal let _stride: Element.Stride

  public var customMirror: Mirror {
    return Mirror(self, children: ["from": _start, "to": _end, "by": _stride])
  }
}

/// Returns the sequence of values (`self`, `self + stride`, `self +
/// stride + stride`, ... *last*) where *last* is the last value in
/// the progression that is less than `end`.
@warn_unused_result
public func stride<T : Strideable>(
  from start: T, to end: T, by stride: T.Stride
) -> StrideTo<T> {
  return StrideTo(_start: start, end: end, stride: stride)
}

/// An `IteratorProtocol` for `StrideThrough<Element>`.
public struct StrideThroughIterator<Element : Strideable> : IteratorProtocol {
  internal var _current: Element
  internal let _end: Element
  internal let _stride: Element.Stride
  internal var _done: Bool = false

  /// Advance to the next element and return it, or `nil` if no next
  /// element exists.
  public mutating func next() -> Element? {
    if _done {
      return nil
    }
    if _stride > 0 ? _current >= _end : _current <= _end {
      if _current == _end {
        _done = true
        return _current
      }
      return nil
    }
    let result = _current
    _current += _stride
    return result
  }
}

/// A `Sequence` of values formed by striding over a closed interval.
public struct StrideThrough<
  Element : Strideable
> : Sequence, CustomReflectable {
  // FIXME: should really be a CollectionType, as it is multipass

  /// Returns an iterator over the elements of this sequence.
  ///
  /// - Complexity: O(1).
  public func makeIterator() -> StrideThroughIterator<Element> {
    return StrideThroughIterator(
      _current: _start, _end: _end, _stride: _stride, _done: false)
  }

  internal init(_start: Element, end: Element, stride: Element.Stride) {
    _precondition(stride != 0, "stride size must not be zero")
    self._start = _start
    self._end = end
    self._stride = stride
  }

  internal let _start: Element
  internal let _end: Element
  internal let _stride: Element.Stride

  public var customMirror: Mirror {
    return Mirror(self,
      children: ["from": _start, "through": _end, "by": _stride])
  }
}

/// Returns the sequence of values (`self`, `self + stride`, `self +
/// stride + stride`, ... *last*) where *last* is the last value in
/// the progression less than or equal to `end`.
///
/// - Note: There is no guarantee that `end` is an element of the sequence.
@warn_unused_result
public func stride<T : Strideable>(
  from start: T, through end: T, by stride: T.Stride
) -> StrideThrough<T> {
  return StrideThrough(_start: start, end: end, stride: stride)
}

@available(*, unavailable, renamed: "StrideToIterator")
public struct StrideToGenerator<Element : Strideable> {}

@available(*, unavailable, renamed: "StrideThroughIterator")
public struct StrideThroughGenerator<Element : Strideable> {}

extension Strideable {
  @available(*, unavailable, message: "Use stride(from:to:by:) free function instead")
  public func stride(to end: Self, by stride: Stride) -> StrideTo<Self> {
    fatalError("unavailable function can't be called")
  }

  @available(*, unavailable, message: "Use stride(from:through:by:) free function instead")
  public func stride(
    through end: Self, by stride: Stride
  ) -> StrideThrough<Self> {
    fatalError("unavailable function can't be called")
  }
}
