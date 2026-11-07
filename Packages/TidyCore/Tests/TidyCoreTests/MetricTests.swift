import Foundation
import Testing

@testable import TidyCore

struct MetricTests {
  @Test func searchQueryPrefixesTheSources() {
    #expect(Metric(title: "Mine", filter: "is:pr author:@me").searchQuery == "is:pr author:@me")
    #expect(Metric(title: "Org", sources: ["octo"], filter: "is:issue").searchQuery == "user:octo is:issue")
    #expect(Metric(title: "Me", sources: ["@me"], filter: "").searchQuery == "user:@me")
    #expect(Metric(title: "Typed", sources: ["user:gustaf", "org:tinecli", "repo:octo/app"], filter: "is:issue").searchQuery == "user:gustaf org:tinecli repo:octo/app is:issue")
    #expect(
      Metric(title: "Repos", sources: ["octo/app", "octo/lib"], filter: "is:issue no:label").searchQuery
        == "repo:octo/app repo:octo/lib is:issue no:label")
  }

  @Test func webURLOpensTheSearchOnGitHub() {
    let url = Metric(title: "C", sources: ["octo"], filter: "language:c++").webURL
    #expect(url?.absoluteString == "https://github.com/search?q=user:octo%20language:c%2B%2B&type=issues")
  }

  @Test func glyphFollowsTheFilter() {
    #expect(Metric(title: "", filter: "is:open IS:PR").glyph.octicon == .gitPullRequest)
    #expect(Metric(title: "", filter: "is:issue is:open").glyph.octicon == .issueOpened)
    #expect(Metric(title: "", filter: "assignee:@me").glyph.tone == .grey)
  }

  @Test func searchesMustBeNarrowedAndNamed() {
    #expect(Metric.presets.allSatisfy { $0.isValid })
    #expect(!Metric(title: " ", filter: "author:@me").isValid)
    #expect(!Metric(title: "Open", filter: "is:open").isValid)
    #expect(Metric(title: "Open", filter: "is:open owner:octo").isValid)
    #expect(Metric(title: "Open", filter: "is:open Review-Requested:@me").isValid)
    #expect(!Metric(title: "Open", filter: "is:pr is:open -author:@me").isValid)
    #expect(!Metric(title: "Open", filter: "is:open @media").isValid)
    #expect(!Metric(title: "Open", filter: "is:open -repo:octo/app").isValid)
    #expect(!Metric(title: "Open", filter: "is:open label:\"repo:x\"").isValid)
    #expect(!Metric(title: "Open", filter: "is:open label:\"a repo:x\"").isValid)
    #expect(!Metric(title: "Open", filter: "is:open org:").isValid)
    #expect(!Metric(title: "Open", filter: "is:open label:@me-too").isValid)
    #expect(Metric(title: "Open", sources: ["octo"], filter: "is:open").isValid)
    #expect(Metric(title: "Open", sources: ["octo/app", "@me"], filter: "").isValid)
    #expect(!Metric(title: "Open", sources: ["octo/app/x"], filter: "is:open").isValid)
    #expect(!Metric(title: "Open", sources: ["octo/"], filter: "is:open").isValid)
    #expect(!Metric(title: "Open", sources: ["oc to"], filter: "is:open").isValid)
    #expect(Metric(title: "Open", sources: ["user:gustaf", "org:tinecli"], filter: "is:open").isValid)
    #expect(!Metric(title: "Open", sources: ["label:bug"], filter: "is:open").isValid)
    #expect(!Metric(title: "Open", sources: ["org:"], filter: "is:open").isValid)
    #expect(!Metric(title: "Open", sources: ["octo/"], filter: "author:@me").isValid)
    #expect(!Metric(title: "", sources: ["octo"], filter: "").isValid)
    #expect(Metric(title: "", sources: ["octo"], filter: "").isSearchValid)
  }

  @Test func oldScopesBecomeSources() throws {
    let id = UUID()
    let decode = { (scope: String) in
      try JSONDecoder().decode(Metric.self, from: Data(#"{"id": "\#(id)", "title": "T", "filter": "is:open", "scope": \#(scope)}"#.utf8))
    }
    #expect(try decode(#"{"everywhere": {}}"#).sources == [])
    #expect(try decode(#"{"organization": {"_0": "octo"}}"#).sources == ["octo"])
    let migrated = try decode(#"{"repositories": {"_0": ["octo/app", "octo/lib"]}}"#)
    #expect(migrated == Metric(id: id, title: "T", sources: ["octo/app", "octo/lib"], filter: "is:open"))
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any]
    #expect(saved?["scope"] == nil)
    #expect(try JSONDecoder().decode(Metric.self, from: JSONEncoder().encode(migrated)) == migrated)
  }
}
