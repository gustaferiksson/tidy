public func steppedSelection(from selection: Set<String>, in order: [String], by offset: Int) -> String? {
  guard !order.isEmpty else { return nil }
  let selected = order.indices.filter { selection.contains(order[$0]) }
  guard let first = selected.first, let last = selected.last else {
    return offset > 0 ? order.first : order.last
  }
  let target = offset > 0 ? last + offset : first + offset
  return order[min(max(target, 0), order.count - 1)]
}
