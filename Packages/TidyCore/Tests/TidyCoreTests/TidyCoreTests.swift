import Testing

@testable import TidyCore

struct TidyCoreTests {
  @Test func exposesProductName() {
    #expect(TidyCore.name == "Tidy")
  }
}
