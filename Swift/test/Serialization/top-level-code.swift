// RUN: rm -rf %t && mkdir %t
// RUN: %target-swift-frontend -emit-module -o %t %s -module-name Test
// RUN: llvm-bcanalyzer %t/Test.swiftmodule | FileCheck %s

// RUN: cp %s %t/main.swift
// RUN: %target-swift-frontend -parse -verify %t/main.swift -primary-file %S/Inputs/top-level-code-other.swift

// CHECK-NOT: UnknownCode

let a: Int? = 1
guard let b = a else {
  fatalError()
}
