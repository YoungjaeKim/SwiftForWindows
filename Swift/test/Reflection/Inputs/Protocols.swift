public protocol P1 {
  associatedtype Inner
}

public protocol P2 {
  associatedtype Outer : P1
}

public protocol P3 {
  associatedtype First
  associatedtype Second
}

public protocol ClassBoundP: class {
  associatedtype Inner
}
