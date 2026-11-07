import Testing

@testable import TidyCore

struct MetricTests {
  @Test func searchQueryPrefixesTheScope() {
    #expect(Metric(title: "Mine", filter: "is:pr author:@me").searchQuery == "is:pr author:@me")
    #expect(Metric(title: "Org", filter: "is:issue", scope: .organization("octo")).searchQuery == "org:octo is:issue")
    #expect(
      Metric(title: "Repos", filter: "is:issue no:label", scope: .repositories(["octo/app", "octo/lib"])).searchQuery
        == "repo:octo/app repo:octo/lib is:issue no:label")
  }

  @Test func glyphFollowsTheFilter() {
    #expect(Metric(title: "", filter: "is:open IS:PR").glyph.octicon == .gitPullRequest)
    #expect(Metric(title: "", filter: "is:issue is:open").glyph.octicon == .issueOpened)
    #expect(Metric(title: "", filter: "assignee:@me").glyph.tone == .grey)
  }

  @Test func searchesMustBeNarrowedAndNamed() {
    #expect(Metric.defaults.allSatisfy { $0.isValid })
    #expect(Metric.presets.last?.isValid == false)
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
    #expect(Metric(title: "Open", filter: "is:open", scope: .organization("octo")).isValid)
    #expect(!Metric(title: "Open", filter: "is:open", scope: .organization("")).isValid)
    #expect(!Metric(title: "Open", filter: "is:open", scope: .organization("octo/app")).isValid)
    #expect(Metric(title: "Open", filter: "is:open", scope: .repositories(["octo/app"])).isValid)
    #expect(!Metric(title: "Open", filter: "is:open", scope: .repositories([])).isValid)
    #expect(!Metric(title: "Open", filter: "is:open", scope: .repositories(["octo/app", "octo"])).isValid)
    #expect(!Metric(title: "Open", filter: "is:open", scope: .repositories(["octo/"])).isValid)
  }
}
