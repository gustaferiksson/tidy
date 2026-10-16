import Testing

@testable import TidyCore

struct SelectionStepTests {
  let order = ["a", "b", "c", "d"]

  @Test func emptyOrderHasNothingToSelect() {
    #expect(steppedSelection(from: [], in: [], by: 1) == nil)
    #expect(steppedSelection(from: ["a"], in: [], by: -1) == nil)
  }

  @Test func noSelectionStartsAtTheNearEnd() {
    #expect(steppedSelection(from: [], in: order, by: 1) == "a")
    #expect(steppedSelection(from: [], in: order, by: -1) == "d")
  }

  @Test func selectionOutsideTheOrderCountsAsNone() {
    #expect(steppedSelection(from: ["gone"], in: order, by: 1) == "a")
    #expect(steppedSelection(from: ["gone"], in: order, by: -1) == "d")
  }

  @Test func movesOneStep() {
    #expect(steppedSelection(from: ["b"], in: order, by: 1) == "c")
    #expect(steppedSelection(from: ["b"], in: order, by: -1) == "a")
  }

  @Test func clampsAtTheEnds() {
    #expect(steppedSelection(from: ["d"], in: order, by: 1) == "d")
    #expect(steppedSelection(from: ["a"], in: order, by: -1) == "a")
  }

  @Test func multipleSelectionMovesFromTheEdgeInTheDirectionOfTravel() {
    #expect(steppedSelection(from: ["a", "c"], in: order, by: 1) == "d")
    #expect(steppedSelection(from: ["b", "d"], in: order, by: -1) == "a")
  }
}
