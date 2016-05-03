// RUN: %target-run-stdlib-swift
// REQUIRES: executable_test

import StdlibUnittest
import StdlibCollectionUnittest


var tests = TestSuite("Iterator")

// Check to make sure we are actually getting Optionals out of this
// IteratorProtocol
tests.test("Range") {
  var w = (1..<2).makeIterator()
  var maybe_one = w.next()
  expectType(Optional<Int>.self, &maybe_one)
  expectEqual(1, maybe_one)
  expectEmpty(w.next())
}

tests.test("RangeIteratorConformsToSequence") {
  for x in (1..<2).makeIterator() {
    expectEqual(1, x)
  }
}

// Test round-trip IteratorProtocol/IteratorProtocol adaptation
tests.test("IteratorSequence") {
  var r = 1..<7
  var x = MinimalIterator(Array(r))
  for a in IteratorSequence(x) {
    expectEqual(r.startIndex, a)
    r.startIndex = r.startIndex.successor()
  }
  expectEqual(r.startIndex, r.endIndex)
}

struct MyIterator : IteratorProtocol {
  var i = 0
  mutating func next() -> Int? {
    if i >= 10 { return nil }
    i += 1
    return i-1
  }
}

extension MyIterator : Sequence {}
tests.test("IteratorsModelSequenceByDeclaration") {
  var n = 0
  for i in MyIterator() {
    expectEqual(n, i)
    n += 1
  }
}

runAllTests()
