import Foundation
import Testing

@testable import TidyCore

struct FilterTests {
  let pull = InboxItem(thread: Fixture.thread("101"))
  let release = InboxItem(thread: Fixture.thread("103"))

  func loaded(_ item: InboxItem, author: String? = nil, state: SubjectState? = nil) -> InboxItem {
    InboxItem(thread: item.thread, status: .loaded(SubjectDetails(state: state, author: author.map { GitHubUser(login: $0) })))
  }

  @Test func matchesRepositoryOrOrganization() {
    #expect(FilterCondition.repository("octo/app").matches(pull) == true)
    #expect(FilterCondition.repository("OCTO/APP").matches(pull) == true)
    #expect(FilterCondition.repository("octo").matches(pull) == true)
    #expect(FilterCondition.repository("octo/lib").matches(pull) == false)
    #expect(FilterCondition.notRepository("octo/lib").matches(pull) == true)
    #expect(FilterCondition.notRepository("octo").matches(pull) == false)
  }

  @Test func matchesReasonAndCategory() {
    #expect(FilterCondition.reason(.reviewRequested).matches(pull) == true)
    #expect(FilterCondition.reason(.mention).matches(pull) == false)
    #expect(FilterCondition.category(.release).matches(release) == true)
    #expect(FilterCondition.category(.securityAlert).matches(InboxItem(thread: Fixture.thread("105"))) == true)
    #expect(FilterCondition.category(.ci).matches(InboxItem(thread: Fixture.thread("104"))) == true)
  }

  @Test func subjectConditionsAreUndeterminedWhileLoading() {
    #expect(FilterCondition.author("dependabot[bot]").matches(pull) == nil)
    #expect(FilterCondition.state(.merged).matches(pull) == nil)
    #expect(FilterCondition.author("Dependabot[bot]").matches(loaded(pull, author: "dependabot[bot]")) == true)
    #expect(FilterCondition.state(.draft).matches(loaded(pull, state: .draft)) == true)
    #expect(FilterCondition.author("mona").matches(InboxItem(thread: pull.thread, status: .failed)) == false)
    #expect(FilterCondition.state(.failed).matches(InboxItem(thread: Fixture.thread("104"))) == true)
  }

  @Test func allConditionsMustMatch() {
    let rule = FilterRule(conditions: [.repository("octo/app"), .reason(.reviewRequested)])
    #expect(rule.matches(pull) == true)
    #expect(FilterRule(conditions: [.repository("octo/app"), .reason(.mention)]).matches(pull) == false)
    #expect(FilterRule(conditions: [.reason(.mention), .author("x")]).matches(pull) == false)
    #expect(FilterRule(conditions: [.reason(.reviewRequested), .author("x")]).matches(pull) == nil)
    #expect(FilterRule(conditions: []).matches(pull) == false)
  }

  @Test func firstMatchWins() {
    let dontNotify = FilterRule(conditions: [.repository("octo")], action: .dontNotify)
    let hide = FilterRule(conditions: [.repository("octo/app")], action: .hide)
    #expect([dontNotify, hide].outcome(for: pull) == .matched(dontNotify))
    #expect([hide, dontNotify].outcome(for: pull) == .matched(hide))
    #expect([hide, dontNotify].outcome(for: pull).hides)
    #expect([dontNotify].outcome(for: pull).hides == false)
    #expect([dontNotify].outcome(for: pull).silences)
    #expect([FilterRule]().outcome(for: pull) == .none)
  }

  @Test func undeterminedEarlierRuleBlocksLaterMatch() {
    let byAuthor = FilterRule(conditions: [.author("renovate[bot]")])
    let hide = FilterRule(conditions: [.repository("octo/app")])
    #expect([byAuthor, hide].outcome(for: pull) == .undetermined)
    #expect([byAuthor, hide].outcome(for: loaded(pull, author: "mona")) == .matched(hide))
  }

  @Test func rulesRoundTripAsJSON() throws {
    let rules = [
      FilterRule(conditions: [.notRepository("octo/app"), .category(.ci), .state(.notPlanned)], action: .hideAndMarkDone),
      FilterRule(conditions: [.author("dependabot[bot]"), .reason(Reason(rawValue: "new_reason"))], action: .dontNotify),
    ]
    let decoded = try JSONDecoder().decode([FilterRule].self, from: JSONEncoder().encode(rules))
    #expect(decoded == rules)
    #expect(RuleAction.hideAndMarkRead.isOptIn && !RuleAction.hide.isOptIn)
  }
}
