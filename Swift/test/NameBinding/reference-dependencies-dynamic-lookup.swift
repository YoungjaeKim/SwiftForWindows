// RUN: rm -rf %t && mkdir %t
// RUN: cp %s %t/main.swift
// RUN: %target-swift-frontend(mock-sdk: %clang-importer-sdk) -parse -primary-file %t/main.swift -emit-reference-dependencies-path - > %t.swiftdeps
// RUN: FileCheck %s < %t.swiftdeps
// RUN: FileCheck -check-prefix=NEGATIVE %s < %t.swiftdeps

// REQUIRES: objc_interop

import Foundation

// CHECK-LABEL: provides-dynamic-lookup:

@objc class Base : NSObject {
  // CHECK-DAG: - "foo"
  func foo() {}

  // CHECK-DAG: - "bar"
  func bar(_ x: Int, y: Int) {}
  
  // FIXME: We don't really need this twice, but de-duplicating is effort.
  // CHECK-DAG: - "bar"
  func bar(_ str: String) {}
    
  // CHECK-DAG: - "prop"
  var prop: String?

  // CHECK-DAG: - "unusedProp"
  var unusedProp: Int = 0
  
  // CHECK-DAG: - "classFunc"
  class func classFunc() {}
}

func getAnyObject() -> AnyObject? { return nil }

// CHECK-LABEL: depends-dynamic-lookup:

func testDynamicLookup(_ obj: AnyObject) {
  // CHECK-DAG: - !private "foo"
  obj.foo()
  // CHECK-DAG: - !private "bar"
  obj.bar(1, y: 2)
  obj.bar("abc")
  
  // CHECK-DAG: - !private "classFunc"
  obj.dynamicType.classFunc()
  
  // CHECK-DAG: - !private "prop"
  _ = obj.prop
  // CHECK-DAG: - !private "description"
  _ = obj.description
  // CHECK-DAG: - !private "method"
  _ = obj.method(5, with: 5.0 as Double)
  
  // CHECK-DAG: - !private "subscript"
  _ = obj[2] as AnyObject
  _ = obj[2] as AnyObject!
}

// CHECK-DAG: - "counter"
let globalUse = getAnyObject()?.counter

// NEGATIVE-LABEL: depends-dynamic-lookup:
// NEGATIVE-NOT: "cat1Method"
// NEGATIVE-NOT: "unusedProp"
