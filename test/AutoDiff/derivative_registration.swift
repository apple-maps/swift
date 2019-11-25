// RUN: %target-run-simple-swift
// REQUIRES: executable_test

import StdlibUnittest
import DifferentiationUnittest

var DerivativeRegistrationTests = TestSuite("DerivativeRegistration")

@_semantics("autodiff.opaque")
func unary(x: Tracked<Float>) -> Tracked<Float> {
  return x
}
@differentiating(unary)
func _vjpUnary(x: Tracked<Float>) -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> Tracked<Float>) {
  return (value: x, pullback: { v in v })
}
DerivativeRegistrationTests.testWithLeakChecking("UnaryFreeFunction") {
  expectEqual(1, gradient(at: 3.0, in: unary))
}

@_semantics("autodiff.opaque")
func multiply(_ x: Tracked<Float>, _ y: Tracked<Float>) -> Tracked<Float> {
  return x * y
}
@differentiating(multiply)
func _vjpMultiply(_ x: Tracked<Float>, _ y: Tracked<Float>)
  -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> (Tracked<Float>, Tracked<Float>)) {
  return (x * y, { v in (v * y, v * x) })
}
DerivativeRegistrationTests.testWithLeakChecking("BinaryFreeFunction") {
  expectEqual((3.0, 2.0), gradient(at: 2.0, 3.0, in: { x, y in multiply(x, y) }))
}

struct Wrapper : Differentiable {
  var float: Tracked<Float>
}

extension Wrapper {
  @_semantics("autodiff.opaque")
  init(_ x: Tracked<Float>, _ y: Tracked<Float>) {
    self.float = x * y
  }

  @differentiating(init(_:_:))
  static func _vjpInit(_ x: Tracked<Float>, _ y: Tracked<Float>)
    -> (value: Self, pullback: (TangentVector) -> (Tracked<Float>, Tracked<Float>)) {
    return (.init(x, y), { v in (v.float * y, v.float * x) })
  }
}
DerivativeRegistrationTests.testWithLeakChecking("Initializer") {
  let v = Wrapper.TangentVector(float: 1)
  let (𝛁x, 𝛁y) = pullback(at: 3, 4, in: { x, y in Wrapper(x, y) })(v)
  expectEqual(4, 𝛁x)
  expectEqual(3, 𝛁y)
}

extension Wrapper {
  @_semantics("autodiff.opaque")
  static func multiply(_ x: Tracked<Float>, _ y: Tracked<Float>) -> Tracked<Float> {
    return x * y
  }

  @differentiating(multiply)
  static func _vjpMultiply(_ x: Tracked<Float>, _ y: Tracked<Float>)
    -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> (Tracked<Float>, Tracked<Float>)) {
    return (x * y, { v in (v * y, v * x) })
  }
}
DerivativeRegistrationTests.testWithLeakChecking("StaticMethod") {
  expectEqual((3.0, 2.0), gradient(at: 2.0, 3.0, in: { x, y in Wrapper.multiply(x, y) }))
}

extension Wrapper {
  @_semantics("autodiff.opaque")
  func multiply(_ x: Tracked<Float>) -> Tracked<Float> {
    return float * x
  }

  @differentiating(multiply)
  func _vjpMultiply(_ x: Tracked<Float>)
    -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> (Wrapper.TangentVector, Tracked<Float>)) {
    return (float * x, { v in
      (TangentVector(float: v * x), v * self.float)
    })
  }
}
DerivativeRegistrationTests.testWithLeakChecking("InstanceMethod") {
  let x: Tracked<Float> = 2
  let wrapper = Wrapper(float: 3)
  let (𝛁wrapper, 𝛁x) = gradient(at: wrapper, x) { wrapper, x in wrapper.multiply(x) }
  expectEqual(Wrapper.TangentVector(float: 2), 𝛁wrapper)
  expectEqual(3, 𝛁x)
}

extension Wrapper {
  subscript(_ x: Tracked<Float>) -> Tracked<Float> {
    @_semantics("autodiff.opaque")
    get { float * x }
    set {}
  }

  @differentiating(subscript(_:))
  func _vjpSubscript(_ x: Tracked<Float>)
    -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> (Wrapper.TangentVector, Tracked<Float>)) {
    return (self[x], { v in
      (TangentVector(float: v * x), v * self.float)
    })
  }
}
DerivativeRegistrationTests.testWithLeakChecking("Subscript") {
  let x: Tracked<Float> = 2
  let wrapper = Wrapper(float: 3)
  let (𝛁wrapper, 𝛁x) = gradient(at: wrapper, x) { wrapper, x in wrapper[x] }
  expectEqual(Wrapper.TangentVector(float: 2), 𝛁wrapper)
  expectEqual(3, 𝛁x)
}

extension Wrapper {
  var computedProperty: Tracked<Float> {
    @_semantics("autodiff.opaque")
    get { float * float }
    set {}
  }

  @differentiating(computedProperty)
  func _vjpComputedProperty()
    -> (value: Tracked<Float>, pullback: (Tracked<Float>) -> Wrapper.TangentVector) {
    return (computedProperty, { [f = self.float] v in
      TangentVector(float: v * (f + f))
    })
  }
}
DerivativeRegistrationTests.testWithLeakChecking("ComputedProperty") {
  let wrapper = Wrapper(float: 3)
  let 𝛁wrapper = gradient(at: wrapper) { wrapper in wrapper.computedProperty }
  expectEqual(Wrapper.TangentVector(float: 6), 𝛁wrapper)
}

runAllTests()
