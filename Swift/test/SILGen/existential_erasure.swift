// RUN: %target-swift-frontend -emit-silgen %s | FileCheck %s

protocol P {
  func downgrade(_ m68k: Bool) -> Self
  func upgrade() throws -> Self
}
protocol Q {}

struct X: P, Q {
  func downgrade(_ m68k: Bool) -> X {
    return self
  }

  func upgrade() throws -> X {
    return self
  }
}

func makePQ() -> protocol<P,Q> { return X() }

func useP(_ x: P) { }

func throwingFunc() throws -> Bool { return true }

// CHECK-LABEL: sil hidden @_TF19existential_erasure5PQtoPFT_T_ : $@convention(thin) () -> () {
func PQtoP() {
  // CHECK: [[PQ_PAYLOAD:%.*]] = open_existential_addr [[PQ:%.*]] : $*protocol<P, Q> to $*[[OPENED_TYPE:@opened(.*) protocol<P, Q>]]
  // CHECK: [[P_PAYLOAD:%.*]] = init_existential_addr [[P:%.*]] : $*P, $[[OPENED_TYPE]]
  // CHECK: copy_addr [take] [[PQ_PAYLOAD]] to [initialization] [[P_PAYLOAD]]
  // CHECK: deinit_existential_addr [[PQ]]
  // CHECK-NOT: destroy_addr [[P]]
  // CHECK-NOT: destroy_addr [[P_PAYLOAD]]
  // CHECK-NOT: destroy_addr [[PQ]]
  // CHECK-NOT: destroy_addr [[PQ_PAYLOAD]]
  useP(makePQ())
}

// Make sure uninitialized existentials are properly deallocated when we
// have an early return.

// CHECK-LABEL: sil hidden @_TF19existential_erasure19openExistentialToP1FzPS_1P_T_
func openExistentialToP1(_ p: P) throws {
// CHECK: bb0(%0 : $*P):
// CHECK:   [[OPEN:%.*]] = open_existential_addr %0 : $*P to $*[[OPEN_TYPE:@opened\(.*\) P]]
// CHECK:   [[RESULT:%.*]] = alloc_stack $P
// CHECK:   [[RESULT_ADDR:%.*]] = init_existential_addr [[RESULT]] : $*P, $[[OPEN_TYPE]]
// CHECK:   [[METHOD:%.*]] = witness_method $[[OPEN_TYPE]], #P.downgrade!1, [[OPEN]]
// CHECK:   [[FUNC:%.*]] = function_ref @_TF19existential_erasure12throwingFuncFzT_Sb
// CHECK:   try_apply [[FUNC]]()
//
// CHECK: bb1([[SUCCESS:%.*]] : $Bool):
// CHECK:   apply [[METHOD]]<[[OPEN_TYPE]]>([[RESULT_ADDR]], [[SUCCESS]], [[OPEN]])
// CHECK:   dealloc_stack [[RESULT]]
// CHECK:   destroy_addr %0
// CHECK:   return
//
// CHECK: bb2([[FAILURE:%.*]] : $ErrorProtocol):
// CHECK:   deinit_existential_addr [[RESULT]]
// CHECK:   dealloc_stack [[RESULT]]
// CHECK:   destroy_addr %0
// CHECK:   throw [[FAILURE]]
//
  try useP(p.downgrade(throwingFunc()))
}

// CHECK-LABEL: sil hidden @_TF19existential_erasure19openExistentialToP2FzPS_1P_T_
func openExistentialToP2(_ p: P) throws {
// CHECK: bb0(%0 : $*P):
// CHECK:   [[OPEN:%.*]] = open_existential_addr %0 : $*P to $*[[OPEN_TYPE:@opened\(.*\) P]]
// CHECK:   [[RESULT:%.*]] = alloc_stack $P
// CHECK:   [[RESULT_ADDR:%.*]] = init_existential_addr [[RESULT]] : $*P, $[[OPEN_TYPE]]
// CHECK:   [[METHOD:%.*]] = witness_method $[[OPEN_TYPE]], #P.upgrade!1, [[OPEN]]
// CHECK:   try_apply [[METHOD]]<[[OPEN_TYPE]]>([[RESULT_ADDR]], [[OPEN]])
//
// CHECK: bb1
// CHECK:  dealloc_stack [[RESULT]]
// CHECK:  destroy_addr %0
// CHECK:  return
//
// CHECK: bb2([[FAILURE:%.*]]: $ErrorProtocol):
// CHECK:  deinit_existential_addr [[RESULT]]
// CHECK:  dealloc_stack [[RESULT]]
// CHECK:  destroy_addr %0
// CHECK:  throw [[FAILURE]]
//
  try useP(p.upgrade())
}

// Same as above but for boxed existentials

extension ErrorProtocol {
  func returnOrThrowSelf() throws -> Self {
    throw self
  }
}

// CHECK-LABEL: sil hidden @_TF19existential_erasure12errorHandlerFzPs13ErrorProtocol_PS0__
func errorHandler(_ e: ErrorProtocol) throws -> ErrorProtocol {
// CHECK: bb0(%0 : $ErrorProtocol):
// CHECK:  debug_value %0 : $ErrorProtocol
// CHECK:  [[OPEN:%.*]] = open_existential_box %0 : $ErrorProtocol to $*[[OPEN_TYPE:@opened\(.*\) ErrorProtocol]]
// CHECK:  [[RESULT:%.*]] = alloc_existential_box $ErrorProtocol, $[[OPEN_TYPE]]
// CHECK:  [[ADDR:%.*]] = project_existential_box $[[OPEN_TYPE]] in [[RESULT]] : $ErrorProtocol
// CHECK:  [[FUNC:%.*]] = function_ref @_TFE19existential_erasurePs13ErrorProtocol17returnOrThrowSelf
// CHECK:  try_apply [[FUNC]]<[[OPEN_TYPE]]>([[ADDR]], [[OPEN]])
//
// CHECK: bb1
// CHECK:  strong_release %0 : $ErrorProtocol
// CHECK:  return [[RESULT]] : $ErrorProtocol
//
// CHECK: bb2([[FAILURE:%.*]] : $ErrorProtocol):
// CHECK:  dealloc_existential_box [[RESULT]]
// CHECK:  strong_release %0 : $ErrorProtocol
// CHECK:  throw [[FAILURE]] : $ErrorProtocol
//
  return try e.returnOrThrowSelf()
}