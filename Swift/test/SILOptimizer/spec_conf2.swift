// RUN: %target-swift-frontend -O -Xllvm -sil-disable-pass="Function Signature Optimization" -disable-arc-opts -emit-sil -Xllvm -enable-destroyhoisting=false %s | FileCheck %s

// We can't deserialize apply_inst with subst lists. When radar://14443304
// is fixed then we should convert this test to a SIL test.

protocol P { func p() }
protocol Q { func q() }

class Foo: P, Q {
  @inline(never)
  func p() {}
  @inline(never)
  func q() {}
}

@inline(never)
func inner_function<T : protocol<P, Q> >(In In : T) { }
@inline(never)
func outer_function<T : protocol<P, Q> >(In In : T) { inner_function(In: In) }

//CHECK: sil shared [noinline] @_TTSg5C10spec_conf23FooS0_S_1PS_S0_S_1QS____TF10spec_conf214outer_function
//CHECK: function_ref @_TTSg5C10spec_conf23FooS0_S_1PS_S0_S_1QS____TF10spec_conf214inner_function
//CHECK-NEXT: apply
//CHECK: return

outer_function(In: Foo())
