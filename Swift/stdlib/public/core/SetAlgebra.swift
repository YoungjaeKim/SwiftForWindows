//===--- SetAlgebra.swift - Protocols for set operations ------------------===//
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
//
//  
//
//===----------------------------------------------------------------------===//

/// A generalized set whose distinct elements are not necessarily
/// disjoint.
///
/// In a model of `SetAlgebra`, some elements may subsume other
/// elements, where
///
/// > `a` **subsumes** `b` iff `([a] as Self).isSupersetOf([b])`
///
/// In many models of `SetAlgebra` such as `Set<Element>`, `a`
/// *subsumes* `b` if and only if `a == b`, but that is not always the
/// case.  For example, option sets typically do not satisfy that
/// property.
///
/// Two elements are **disjoint** when neither one *subsumes* the other.
///
/// - SeeAlso: `OptionSet`.
///
/// - Axioms, where `S` conforms to `SetAlgebra`, `x` and `y` are
///   of type `S`, and `e` is of type `S.Element`:
///
///   - `S() == []`
///   - `x.intersect(x) == x`
///   - `x.intersect([]) == []`
///   - `x.union(x) == x`
///   - `x.union([]) == x`
///   - `x.contains(e)` implies `x.union(y).contains(e)`
///   - `x.union(y).contains(e)` implies `x.contains(e) || y.contains(e)`
///   - `x.contains(e) && y.contains(e)` iff `x.intersect(y).contains(e)`
///   - `x.isSubsetOf(y)` iff `y.isSupersetOf(x)`
///   - `x.isStrictSupersetOf(y)` iff `x.isSupersetOf(y) && x != y`
///   - `x.isStrictSubsetOf(y)` iff `x.isSubsetOf(y) && x != y`
public protocol SetAlgebra : Equatable, ArrayLiteralConvertible {
  /// A type for which `Self` provides a containment test.
  associatedtype Element
  
  /// Creates an empty set.
  ///
  /// - Equivalent to `[] as Self`
  init()
  
  /// Returns `true` if `self` contains `member`.
  ///
  /// - Equivalent to `self.intersect([member]) == [member]`
  @warn_unused_result
  func contains(_ member: Element) -> Bool

  /// Returns the set of elements contained in `self`, in `other`, or in
  /// both `self` and `other`.
  @warn_unused_result
  func union(_ other: Self) -> Self
  
  /// Returns the set of elements contained in both `self` and `other`.
  @warn_unused_result
  func intersect(_ other: Self) -> Self

  /// Returns the set of elements contained in `self` or in `other`,
  /// but not in both `self` and `other`.
  @warn_unused_result
  func exclusiveOr(_ other: Self) -> Self

  /// If `member` is not already contained in `self`, inserts it.
  ///
  /// - Equivalent to `self.unionInPlace([member])`
  /// - Postcondition: `self.contains(member)`
  mutating func insert(_ member: Element)
  
  /// If `member` is contained in `self`, removes and returns it.
  /// Otherwise, removes all elements subsumed by `member` and returns
  /// `nil`.
  ///
  /// - Postcondition: `self.intersect([member]).isEmpty`
  @discardableResult
  mutating func remove(_ member: Element) -> Element?

  /// Insert all elements of `other` into `self`.
  ///
  /// - Equivalent to replacing `self` with `self.union(other)`.
  /// - Postcondition: `self.isSupersetOf(other)`
  mutating func unionInPlace(_ other: Self)

  /// Removes all elements of `self` that are not also present in
  /// `other`.
  ///
  /// - Equivalent to replacing `self` with `self.intersect(other)`
  /// - Postcondition: `self.isSubsetOf(other)`
  mutating func intersectInPlace(_ other: Self)

  /// Replaces `self` with a set containing all elements contained in
  /// either `self` or `other`, but not both.
  ///
  /// - Equivalent to replacing `self` with `self.exclusiveOr(other)`
  mutating func exclusiveOrInPlace(_ other: Self)  

  //===--- Requirements with default implementations ----------------------===//
  /// Returns the set of elements contained in `self` but not in `other`.
  @warn_unused_result
  func subtract(_ other: Self) -> Self

  /// Returns `true` iff every element of `self` is contained in `other`.
  @warn_unused_result
  func isSubsetOf(_ other: Self) -> Bool

  /// Returns `true` iff `self.intersect(other).isEmpty`.
  @warn_unused_result
  func isDisjointWith(_ other: Self) -> Bool

  /// Returns `true` iff every element of `other` is contained in `self`.
  @warn_unused_result
  func isSupersetOf(_ other: Self) -> Bool

  /// Returns `true` iff `self.contains(e)` is `false` for all `e`.
  var isEmpty: Bool { get }
  
  /// Creates the set containing all elements of `sequence`.
  init<S : Sequence where S.Iterator.Element == Element>(_ sequence: S)

  /// Removes all elements of `other` from `self`.
  ///
  /// - Equivalent to replacing `self` with `self.subtract(other)`.
  mutating func subtractInPlace(_ other: Self)

  /// Returns `true` iff `a` subsumes `b`.
  ///
  /// - Equivalent to `([a] as Self).isSupersetOf([b])`
  @warn_unused_result
  static func element(_ a: Element, subsumes b: Element) -> Bool

  /// Returns `true` iff `a` is disjoint with `b`.
  ///
  /// Two elements are disjoint when neither one subsumes the other.
  ///
  /// - SeeAlso: `Self.element(_, subsumes:_)`
  @warn_unused_result
  static func element(_ a: Element, isDisjointWith b: Element) -> Bool
}

/// `SetAlgebra` requirements for which default implementations
/// are supplied.
///
/// - Note: A type conforming to `SetAlgebra` can implement any of
///   these initializers or methods, and those implementations will be
///   used in lieu of these defaults.
extension SetAlgebra {
  /// Creates the set containing all elements of `sequence`.
  public init<
    S : Sequence where S.Iterator.Element == Element
  >(_ sequence: S) {
    self.init()
    for e in sequence { insert(e) }
  }

  /// Creates a set containing all elements of the given `arrayLiteral`.
  ///
  /// This initializer allows an array literal containing
  /// `Self.Element` to represent an instance of the set, wherever it
  /// is implied by the type context.
  public init(arrayLiteral: Element...) {
    self.init(arrayLiteral)
  }

  /// Removes all elements of `other` from `self`.
  ///
  /// - Equivalent to replacing `self` with `self.subtract(other)`.
  public mutating func subtractInPlace(_ other: Self) {
    self.intersectInPlace(self.exclusiveOr(other))
  }

  /// Returns `true` iff every element of `self` is contained in `other`.
  @warn_unused_result
  public func isSubsetOf(_ other: Self) -> Bool {
    return self.intersect(other) == self
  }

  /// Returns `true` iff every element of `other` is contained in `self`.
  @warn_unused_result
  public func isSupersetOf(_ other: Self) -> Bool {
    return other.isSubsetOf(self)
  }

  /// Returns `true` iff `self.intersect(other).isEmpty`.
  @warn_unused_result
  public func isDisjointWith(_ other: Self) -> Bool {
    return self.intersect(other).isEmpty
  }

  /// Returns the set of elements contained in `self` but not in `other`.
  @warn_unused_result
  public func subtract(_ other: Self) -> Self {
    return self.intersect(self.exclusiveOr(other))
  }

  /// Returns `true` iff `self.contains(e)` is `false` for all `e`.
  public var isEmpty: Bool {
    return self == Self()
  }

  /// Returns `true` iff every element of `other` is contained in `self`
  /// and `self` contains an element that is not contained in `other`.
  @warn_unused_result
  public func isStrictSupersetOf(_ other: Self) -> Bool {
    return self.isSupersetOf(other) && self != other
  }

  /// Returns `true` iff every element of `self` is contained in `other`
  /// and `other` contains an element that is not contained in `self`.
  @warn_unused_result
  public func isStrictSubsetOf(_ other: Self) -> Bool {
    return other.isStrictSupersetOf(self)
  }

  /// Returns `true` iff `a` subsumes `b`.
  ///
  /// - Equivalent to `([a] as Self).isSupersetOf([b])`
  @warn_unused_result
  public static func element(_ a: Element, subsumes b: Element) -> Bool {
    return ([a] as Self).isSupersetOf([b])
  }

  /// Returns `true` iff `a` is disjoint with `b`.
  ///
  /// Two elements are disjoint when neither one subsumes the other.
  ///
  /// - SeeAlso: `Self.element(_, subsumes:_)`
  @warn_unused_result
  public static func element(_ a: Element, isDisjointWith b: Element) -> Bool {
    return ([a] as Self).isDisjointWith([b])
  }
}

@available(*, unavailable, renamed: "SetAlgebra")
public typealias SetAlgebraType = SetAlgebra

