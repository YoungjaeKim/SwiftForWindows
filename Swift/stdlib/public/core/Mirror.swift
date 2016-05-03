//===--- Mirror.swift -----------------------------------------------------===//
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
// FIXME: ExistentialCollection needs to be supported before this will work
// without the ObjC Runtime.

/// Representation of the sub-structure and optional "display style"
/// of any arbitrary subject instance.
///
/// Describes the parts---such as stored properties, collection
/// elements, tuple elements, or the active enumeration case---that
/// make up a particular instance.  May also supply a "display style"
/// property that suggests how this structure might be rendered.
///
/// Mirrors are used by playgrounds and the debugger.
public struct Mirror {
  /// Representation of descendant classes that don't override
  /// `customMirror`.
  ///
  /// Note that the effect of this setting goes no deeper than the
  /// nearest descendant class that overrides `customMirror`, which
  /// in turn can determine representation of *its* descendants.
  internal enum _DefaultDescendantRepresentation {
    /// Generate a default mirror for descendant classes that don't
    /// override `customMirror`.
    ///
    /// This case is the default.
    case generated

    /// Suppress the representation of descendant classes that don't
    /// override `customMirror`.
    ///
    /// This option may be useful at the root of a class cluster, where
    /// implementation details of descendants should generally not be
    /// visible to clients.
    case suppressed
  }

  /// Representation of ancestor classes.
  ///
  /// A `CustomReflectable` class can control how its mirror will
  /// represent ancestor classes by initializing the mirror with a
  /// `AncestorRepresentation`.  This setting has no effect on mirrors
  /// reflecting value type instances.
  public enum AncestorRepresentation {

    /// Generate a default mirror for all ancestor classes.
    ///
    /// This case is the default.
    ///
    /// - Note: This option generates default mirrors even for
    ///   ancestor classes that may implement `CustomReflectable`'s
    ///   `customMirror` requirement.  To avoid dropping an ancestor class
    ///   customization, an override of `customMirror` should pass
    ///   `ancestorRepresentation: .Customized(super.customMirror)` when
    ///   initializing its `Mirror`.
    case generated

    /// Use the nearest ancestor's implementation of `customMirror` to
    /// create a mirror for that ancestor.  Other classes derived from
    /// such an ancestor are given a default mirror.
    ///
    /// The payload for this option should always be
    /// "`{ super.customMirror }`":
    ///
    ///     var customMirror: Mirror {
    ///       return Mirror(
    ///         self,
    ///         children: ["someProperty": self.someProperty],
    ///         ancestorRepresentation: .Customized({ super.customMirror })) // <==
    ///     }
    case customized(() -> Mirror)

    /// Suppress the representation of all ancestor classes.  The
    /// resulting `Mirror`'s `superclassMirror` is `nil`.
    case suppressed
  }

  /// Reflect upon the given `subject`.
  ///
  /// If the dynamic type of `subject` conforms to `CustomReflectable`,
  /// the resulting mirror is determined by its `customMirror` property.
  /// Otherwise, the result is generated by the language.
  ///
  /// - Note: If the dynamic type of `subject` has value semantics,
  ///   subsequent mutations of `subject` will not observable in
  ///   `Mirror`.  In general, though, the observability of such
  /// mutations is unspecified.
  public init(reflecting subject: Any) {
    if case let customized as CustomReflectable = subject {
      self = customized.customMirror
    } else {
      self = Mirror(
        legacy: _reflect(subject),
        subjectType: subject.dynamicType)
    }
  }

  /// An element of the reflected instance's structure.  The optional
  /// `label` may be used when appropriate, e.g. to represent the name
  /// of a stored property or of an active `enum` case, and will be
  /// used for lookup when `String`s are passed to the `descendant`
  /// method.
  public typealias Child = (label: String?, value: Any)

  /// The type used to represent sub-structure.
  ///
  /// Depending on your needs, you may find it useful to "upgrade"
  /// instances of this type to `AnyBidirectionalCollection` or
  /// `AnyRandomAccessCollection`.  For example, to display the last
  /// 20 children of a mirror if they can be accessed efficiently, you
  /// might write:
  ///
  ///     if let b = AnyBidirectionalCollection(someMirror.children) {
  ///       for i in b.endIndex.advanced(by: -20, limit: b.startIndex)..<b.endIndex {
  ///          print(b[i])
  ///       }
  ///     }
  public typealias Children = AnyForwardCollection<Child>

  /// A suggestion of how a `Mirror`'s is to be interpreted.
  ///
  /// Playgrounds and the debugger will show a representation similar
  /// to the one used for instances of the kind indicated by the
  /// `DisplayStyle` case name when the `Mirror` is used for display.
  public enum DisplayStyle {
    case `struct`, `class`, `enum`, tuple, optional, collection
    case dictionary, `set`
  }

  @warn_unused_result
  static func _noSuperclassMirror() -> Mirror? { return nil }

  /// Returns the legacy mirror representing the part of `subject`
  /// corresponding to the superclass of `staticSubclass`.
  @warn_unused_result
  internal static func _legacyMirror(
    _ subject: AnyObject, asClass targetSuperclass: AnyClass) -> _Mirror? {
    
    // get a legacy mirror and the most-derived type
    var cls: AnyClass = subject.dynamicType
    var clsMirror = _reflect(subject)

    // Walk up the chain of mirrors/classes until we find staticSubclass
    while let superclass: AnyClass = _getSuperclass(cls) {
      guard let superclassMirror = clsMirror._superMirror() else { break }
      
      if superclass == targetSuperclass { return superclassMirror }
      
      clsMirror = superclassMirror
      cls = superclass
    }
    return nil
  }
  
  @warn_unused_result
  internal static func _superclassIterator<Subject : Any>(
    _ subject: Subject, _ ancestorRepresentation: AncestorRepresentation
  ) -> () -> Mirror? {

    if let subject = subject as? AnyObject,
      let subjectClass = Subject.self as? AnyClass,
      let superclass = _getSuperclass(subjectClass) {

      switch ancestorRepresentation {
      case .generated:
        return {
          self._legacyMirror(subject, asClass: superclass).map {
            Mirror(legacy: $0, subjectType: superclass)
          }
        }
      case .customized(let makeAncestor):
        return {
          Mirror(subject, subjectClass: superclass, ancestor: makeAncestor())
        }
      case .suppressed:
        break
      }
    }
    return Mirror._noSuperclassMirror
  }
  
  /// Represent `subject` with structure described by `children`,
  /// using an optional `displayStyle`.
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// is ignored.  Otherwise, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used.  By default, a
  /// representation is automatically generated and any `customMirror`
  /// implementation is bypassed.  To prevent bypassing customized
  /// ancestors, `customMirror` overrides should initialize the
  /// `Mirror` with:
  ///
  ///     ancestorRepresentation: .customized({ super.customMirror })
  ///
  /// - Note: The traversal protocol modeled by `children`'s indices
  ///   (`ForwardIndex`, `BidirectionalIndex`, or
  ///   `RandomAccessIndex`) is captured so that the resulting
  /// `Mirror`'s `children` may be upgraded later.  See the failable
  /// initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<
    Subject, C : Collection where C.Iterator.Element == Child
  >(
    _ subject: Subject,
    children: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) {
    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    self.children = Children(children)
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// Represent `subject` with child values given by
  /// `unlabeledChildren`, using an optional `displayStyle`.  The
  /// result's child labels will all be `nil`.
  ///
  /// This initializer is especially useful for the mirrors of
  /// collections, e.g.:
  ///
  ///     extension MyArray : CustomReflectable {
  ///       var customMirror: Mirror {
  ///         return Mirror(self, unlabeledChildren: self, displayStyle: .collection)
  ///       }
  ///     }
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// is ignored.  Otherwise, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used.  By default, a
  /// representation is automatically generated and any `customMirror`
  /// implementation is bypassed.  To prevent bypassing customized
  /// ancestors, `customMirror` overrides should initialize the
  /// `Mirror` with:
  ///
  ///     ancestorRepresentation: .Customized({ super.customMirror })
  ///
  /// - Note: The traversal protocol modeled by `children`'s indices
  ///   (`ForwardIndex`, `BidirectionalIndex`, or
  ///   `RandomAccessIndex`) is captured so that the resulting
  /// `Mirror`'s `children` may be upgraded later.  See the failable
  /// initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<
    Subject, C: Collection
  >(
    _ subject: Subject,
    unlabeledChildren: C,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) {
    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    self.children = Children(
      unlabeledChildren.lazy.map { Child(label: nil, value: $0) }
    )
    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// Represent `subject` with labeled structure described by
  /// `children`, using an optional `displayStyle`.
  ///
  /// Pass a dictionary literal with `String` keys as `children`.  Be
  /// aware that although an *actual* `Dictionary` is
  /// arbitrarily-ordered, the ordering of the `Mirror`'s `children`
  /// will exactly match that of the literal you pass.
  ///
  /// If `subject` is not a class instance, `ancestorRepresentation`
  /// is ignored.  Otherwise, `ancestorRepresentation` determines
  /// whether ancestor classes will be represented and whether their
  /// `customMirror` implementations will be used.  By default, a
  /// representation is automatically generated and any `customMirror`
  /// implementation is bypassed.  To prevent bypassing customized
  /// ancestors, `customMirror` overrides should initialize the
  /// `Mirror` with:
  ///
  ///     ancestorRepresentation: .customized({ super.customMirror })
  ///
  /// - Note: The resulting `Mirror`'s `children` may be upgraded to
  ///   `AnyRandomAccessCollection` later.  See the failable
  ///   initializers of `AnyBidirectionalCollection` and
  /// `AnyRandomAccessCollection` for details.
  public init<Subject>(
    _ subject: Subject,
    children: DictionaryLiteral<String, Any>,
    displayStyle: DisplayStyle? = nil,
    ancestorRepresentation: AncestorRepresentation = .generated
  ) {
    self.subjectType = Subject.self
    self._makeSuperclassMirror = Mirror._superclassIterator(
      subject, ancestorRepresentation)
      
    let lazyChildren = children.lazy.map { Child(label: $0.0, value: $0.1) }
    self.children = Children(lazyChildren)

    self.displayStyle = displayStyle
    self._defaultDescendantRepresentation
      = subject is CustomLeafReflectable ? .suppressed : .generated
  }

  /// The static type of the subject being reflected.
  ///
  /// This type may differ from the subject's dynamic type when `self`
  /// is the `superclassMirror` of another mirror.
  public let subjectType: Any.Type

  /// A collection of `Child` elements describing the structure of the
  /// reflected subject.
  public let children: Children

  /// Suggests a display style for the reflected subject.
  public let displayStyle: DisplayStyle?

  public var superclassMirror: Mirror? {
    return _makeSuperclassMirror()
  }

  internal let _makeSuperclassMirror: () -> Mirror?
  internal let _defaultDescendantRepresentation: _DefaultDescendantRepresentation
}

/// A type that explicitly supplies its own Mirror.
///
/// Instances of any type can be `Mirror(reflect:)`'ed upon, but if you are
/// not satisfied with the `Mirror` supplied for your type by default,
/// you can make it conform to `CustomReflectable` and return a custom
/// `Mirror`.
public protocol CustomReflectable {
  /// The `Mirror` for `self`.
  ///
  /// - Note: If `Self` has value semantics, the `Mirror` should be
  ///   unaffected by subsequent mutations of `self`.
  var customMirror: Mirror { get }
}

/// A type that explicitly supplies its own Mirror but whose
/// descendant classes are not represented in the Mirror unless they
/// also override `customMirror`.
public protocol CustomLeafReflectable : CustomReflectable {}

//===--- Addressing -------------------------------------------------------===//

/// A protocol for legitimate arguments to `Mirror`'s `descendant`
/// method.
///
/// Do not declare new conformances to this protocol; they will not
/// work as expected.
public protocol MirrorPath {}
extension IntMax : MirrorPath {}
extension Int : MirrorPath {}
extension String : MirrorPath {}

extension Mirror {
  internal struct _Dummy : CustomReflectable {
    var mirror: Mirror
    var customMirror: Mirror { return mirror }
  }

  /// Return a specific descendant of the reflected subject, or `nil`
  /// Returns a specific descendant of the reflected subject, or `nil`
  /// if no such descendant exists.
  ///
  /// A `String` argument selects the first `Child` with a matching label.
  /// An integer argument *n* select the *n*th `Child`.  For example:
  ///
  ///   var d = Mirror(reflecting: x).descendant(1, "two", 3)
  ///
  /// is equivalent to:
  ///
  ///     var d = nil
  ///     let children = Mirror(reflecting: x).children
  ///     let p0 = children.startIndex.advanced(by: 1, limit: children.endIndex)
  ///     if p0 != children.endIndex {
  ///       let grandChildren = Mirror(reflecting: children[p0].value).children
  ///       SeekTwo: for g in grandChildren {
  ///         if g.label == "two" {
  ///           let greatGrandChildren = Mirror(reflecting: g.value).children
  ///           let p1 = greatGrandChildren.startIndex.advanced(
  ///             by: 3,
  ///             limit: greatGrandChildren.endIndex)
  ///           if p1 != endIndex { d = greatGrandChildren[p1].value }
  ///           break SeekTwo
  ///         }
  ///       }
  ///
  /// As you can see, complexity for each element of the argument list
  /// depends on the argument type and capabilities of the collection
  /// used to initialize the corresponding subject's parent's mirror.
  /// Each `String` argument results in a linear search.  In short,
  /// this function is suitable for exploring the structure of a
  /// `Mirror` in a REPL or playground, but don't expect it to be
  /// efficient.
  @warn_unused_result
  public func descendant(
    _ first: MirrorPath, _ rest: MirrorPath...
  ) -> Any? {
    var result: Any = _Dummy(mirror: self)
    for e in [first] + rest {
      let children = Mirror(reflecting: result).children
      let position: Children.Index
      if case let label as String = e {
        position = children.index { $0.label == label } ?? children.endIndex
      }
      else if let offset = (e as? Int).map({ IntMax($0) }) ?? (e as? IntMax) {
        position = children.startIndex.advanced(
          by: offset, limit: children.endIndex)
      }
      else {
        _preconditionFailure(
          "Someone added a conformance to MirrorPath; that privilege is reserved to the standard library")
      }
      if position == children.endIndex { return nil }
      result = children[position].value
    }
    return result
  }
}

//===--- Legacy _Mirror Support -------------------------------------------===//
extension Mirror.DisplayStyle {
  /// Construct from a legacy `_MirrorDisposition`
  internal init?(legacy: _MirrorDisposition) {
    switch legacy {
    case .`struct`: self = .`struct`
    case .`class`: self = .`class`
    case .`enum`: self = .`enum`
    case .tuple: self = .tuple
    case .aggregate: return nil
    case .indexContainer: self = .collection
    case .keyContainer: self = .dictionary
    case .membershipContainer: self = .`set`
    case .container: preconditionFailure("unused!")
    case .optional: self = .optional
    case .objCObject: self = .`class`
    }
  }
}

@warn_unused_result
internal func _isClassSuperMirror(_ t: Any.Type) -> Bool {
#if  _runtime(_ObjC)
  return t == _ClassSuperMirror.self || t == _ObjCSuperMirror.self
#else
  return t == _ClassSuperMirror.self
#endif
}

extension _Mirror {
  @warn_unused_result
  internal func _superMirror() -> _Mirror? {
    if self.count > 0 {
      let childMirror = self[0].1
      if _isClassSuperMirror(childMirror.dynamicType) {
        return childMirror
      }
    }
    return nil
  }
}

/// When constructed using the legacy reflection infrastructure, the
/// resulting `Mirror`'s `children` collection will always be
/// upgradable to `AnyRandomAccessCollection` even if it doesn't
/// exhibit appropriate performance. To avoid this pitfall, convert
/// mirrors to use the new style, which only present forward
/// traversal in general.
internal extension Mirror {
  /// An adapter that represents a legacy `_Mirror`'s children as
  /// a `Collection` with integer `Index`.  Note that the performance
  /// characteristics of the underlying `_Mirror` may not be
  /// appropriate for random access!  To avoid this pitfall, convert
  /// mirrors to use the new style, which only present forward
  /// traversal in general.
  internal struct LegacyChildren : Collection {
    init(_ oldMirror: _Mirror) {
      self._oldMirror = oldMirror
    }

    var startIndex: Int {
      return _oldMirror._superMirror() == nil ? 0 : 1
    }

    var endIndex: Int { return _oldMirror.count }

    subscript(position: Int) -> Child {
      let (label, childMirror) = _oldMirror[position]
      return (label: label, value: childMirror.value)
    }

    internal let _oldMirror: _Mirror
  }

  /// Initialize for a view of `subject` as `subjectClass`.
  ///
  /// - parameter ancestor: A Mirror for a (non-strict) ancestor of
  ///   `subjectClass`, to be injected into the resulting hierarchy.
  ///
  /// - parameter legacy: Either `nil`, or a legacy mirror for `subject`
  ///    as `subjectClass`.
  internal init(
    _ subject: AnyObject,
    subjectClass: AnyClass,
    ancestor: Mirror,
    legacy legacyMirror: _Mirror? = nil
  ) {
    if ancestor.subjectType == subjectClass
      || ancestor._defaultDescendantRepresentation == .suppressed {
      self = ancestor
    }
    else {
      let legacyMirror = legacyMirror ?? Mirror._legacyMirror(
        subject, asClass: subjectClass)!
      
      self = Mirror(
        legacy: legacyMirror,
        subjectType: subjectClass,
        makeSuperclassMirror: {
          _getSuperclass(subjectClass).map {
            Mirror(
              subject,
              subjectClass: $0,
              ancestor: ancestor,
              legacy: legacyMirror._superMirror())
          }
        })
    }
  }

  internal init(
    legacy legacyMirror: _Mirror,
    subjectType: Any.Type,
    makeSuperclassMirror: (() -> Mirror?)? = nil
  ) {
    if let makeSuperclassMirror = makeSuperclassMirror {
      self._makeSuperclassMirror = makeSuperclassMirror
    }
    else if let subjectSuperclass = _getSuperclass(subjectType) {
      self._makeSuperclassMirror = {
        legacyMirror._superMirror().map {
          Mirror(legacy: $0, subjectType: subjectSuperclass) }
      }
    }
    else {
      self._makeSuperclassMirror = Mirror._noSuperclassMirror
    }
    self.subjectType = subjectType
    self.children = Children(LegacyChildren(legacyMirror))
    self.displayStyle = DisplayStyle(legacy: legacyMirror.disposition)
    self._defaultDescendantRepresentation = .generated
  }
}

//===--- QuickLooks -------------------------------------------------------===//

/// The sum of types that can be used as a quick look representation.
public enum PlaygroundQuickLook {
  /// Plain text.
  case text(String)

  /// An integer numeric value.
  case int(Int64)

  /// An unsigned integer numeric value.
  case uInt(UInt64)

  /// A single precision floating-point numeric value.
  case float(Float32)

  /// A double precision floating-point numeric value.
  case double(Float64)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// An image.
  case image(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A sound.
  case sound(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A color.
  case color(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A bezier path.
  case bezierPath(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// An attributed string.
  case attributedString(Any)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A rectangle.
  case rectangle(Float64, Float64, Float64, Float64)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A point.
  case point(Float64, Float64)

  // FIXME: Uses explicit coordinates to avoid coupling a particular Cocoa type.
  /// A size.
  case size(Float64, Float64)

  /// A boolean value.
  case bool(Bool)

  // FIXME: Uses explicit values to avoid coupling a particular Cocoa type.
  /// A range.
  case range(Int64, Int64)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A GUI view.
  case view(Any)

  // FIXME: Uses an Any to avoid coupling a particular Cocoa type.
  /// A graphical sprite.
  case sprite(Any)

  /// A Uniform Resource Locator.
  case url(String)

  /// Raw data that has already been encoded in a format the IDE understands.
  case _raw([UInt8], String)
}

extension PlaygroundQuickLook {
  /// Initialize for the given `subject`.
  ///
  /// If the dynamic type of `subject` conforms to
  /// `CustomPlaygroundQuickLookable`, returns the result of calling
  /// its `customPlaygroundQuickLook` property.  Otherwise, returns
  /// a `PlaygroundQuickLook` synthesized for `subject` by the
  /// language.  Note that in some cases the result may be
  /// `.Text(String(reflecting: subject))`.
  ///
  /// - Note: If the dynamic type of `subject` has value semantics,
  ///   subsequent mutations of `subject` will not observable in
  ///   `Mirror`.  In general, though, the observability of such
  /// mutations is unspecified.
  public init(reflecting subject: Any) {
    if let customized = subject as? CustomPlaygroundQuickLookable {
      self = customized.customPlaygroundQuickLook
    }
    else {
      if let q = _reflect(subject).quickLookObject {
        self = q
      }
      else {
        self = .text(String(reflecting: subject))
      }
    }
  }
}

/// A type that explicitly supplies its own PlaygroundQuickLook.
///
/// Instances of any type can be `PlaygroundQuickLook(reflect:)`'ed
/// upon, but if you are not satisfied with the `PlaygroundQuickLook`
/// supplied for your type by default, you can make it conform to
/// `CustomPlaygroundQuickLookable` and return a custom
/// `PlaygroundQuickLook`.
public protocol CustomPlaygroundQuickLookable {
  /// The `PlaygroundQuickLook` for `self`.
  ///
  /// - Note: If `Self` has value semantics, the `PlaygroundQuickLook`
  ///   should be unaffected by subsequent mutations of `self`.
  var customPlaygroundQuickLook: PlaygroundQuickLook { get }
}

//===--- General Utilities ------------------------------------------------===//
// This component could stand alone, but is used in Mirror's public interface.

/// Represent the ability to pass a dictionary literal in function
/// signatures.
///
/// A function with a `DictionaryLiteral` parameter can be passed a
/// Swift dictionary literal without causing a `Dictionary` to be
/// created.  This capability can be especially important when the
/// order of elements in the literal is significant.
///
/// For example:
///
///     struct IntPairs {
///       var elements: [(Int, Int)]
///       init(_ pairs: DictionaryLiteral<Int,Int>) {
///         elements = Array(pairs)
///       }
///     }
///
///     let x = IntPairs([1:2, 1:1, 3:4, 2:1])
///     print(x.elements)  // [(1, 2), (1, 1), (3, 4), (2, 1)]
public struct DictionaryLiteral<Key, Value> : DictionaryLiteralConvertible {
  /// Store `elements`.
  public init(dictionaryLiteral elements: (Key, Value)...) {
    self._elements = elements
  }
  internal let _elements: [(Key, Value)]
}

/// `Collection` conformance that allows `DictionaryLiteral` to
/// interoperate with the rest of the standard library.
extension DictionaryLiteral : Collection {
  /// The position of the first element in a non-empty `DictionaryLiteral`.
  ///
  /// Identical to `endIndex` in an empty `DictionaryLiteral`.
  ///
  /// - Complexity: O(1).
  public var startIndex: Int { return 0 }

  /// The `DictionaryLiteral`'s "past the end" position.
  ///
  /// `endIndex` is not a valid argument to `subscript`, and is always
  /// reachable from `startIndex` by zero or more applications of
  /// `successor()`.
  ///
  /// - Complexity: O(1).
  public var endIndex: Int { return _elements.endIndex }

  // FIXME: a typealias is needed to prevent <rdar://20248032>
  public typealias Element = (key: Key, value: Value)

  /// Access the element indicated by `position`.
  ///
  /// - Precondition: `position >= 0 && position < endIndex`.
  ///
  /// - complexity: O(1).
  public subscript(position: Int) -> Element {
    return _elements[position]
  }
}

extension String {
  /// Initialize `self` with the textual representation of `instance`.
  ///
  /// * If `Subject` conforms to `Streamable`, the result is obtained by
  ///   calling `instance.write(to: s)` on an empty string `s`.
  /// * Otherwise, if `Subject` conforms to `CustomStringConvertible`, the
  ///   result is `instance`'s `description`
  /// * Otherwise, if `Subject` conforms to `CustomDebugStringConvertible`,
  ///   the result is `instance`'s `debugDescription`
  /// * Otherwise, an unspecified result is supplied automatically by
  ///   the Swift standard library.
  ///
  /// - SeeAlso: `String.init<Subject>(reflecting: Subject)`
  public init<Subject>(_ instance: Subject) {
    self.init()
    _print_unlocked(instance, &self)
  }

  /// Initialize `self` with a detailed textual representation of
  /// `subject`, suitable for debugging.
  ///
  /// * If `Subject` conforms to `CustomDebugStringConvertible`, the result
  ///   is `subject`'s `debugDescription`.
  ///
  /// * Otherwise, if `Subject` conforms to `CustomStringConvertible`,
  ///   the result is `subject`'s `description`.
  ///
  /// * Otherwise, if `Subject` conforms to `Streamable`, the result is
  ///   obtained by calling `subject.write(to: s)` on an empty string `s`.
  ///
  /// * Otherwise, an unspecified result is supplied automatically by
  ///   the Swift standard library.
  ///
  /// - SeeAlso: `String.init<Subject>(Subject)`
  public init<Subject>(reflecting subject: Subject) {
    self.init()
    _debugPrint_unlocked(subject, &self)
  }
}

/// Reflection for `Mirror` itself.
extension Mirror : CustomStringConvertible {
  public var description: String {
    return "Mirror for \(self.subjectType)"
  }
}

extension Mirror : CustomReflectable {
  public var customMirror: Mirror {
    return Mirror(self, children: [:])
  }
}

@available(*, unavailable, renamed: "MirrorPath")
public typealias MirrorPathType = MirrorPath