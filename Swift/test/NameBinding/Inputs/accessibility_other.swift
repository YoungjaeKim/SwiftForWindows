import has_accessibility

public let a = 0
internal let b = 0
private let c = 0

extension Foo {
  public static func a() {}
  internal static func b() {}
  private static func c() {}  // expected-note {{'c' declared here}}
}

struct PrivateInit {
  private init() {}  // expected-note {{'init' declared here}}
}

extension Foo {
  private func method() {}
  private typealias TheType = Float
}

extension OriginallyEmpty {
  func method() {}
  typealias TheType = Float
}

private func privateInBothFiles() {}
func privateInPrimaryFile() {} // expected-note {{previously declared here}}
private func privateInOtherFile() {} // expected-error {{invalid redeclaration}}
