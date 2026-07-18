/// Fixed, row-major assignment for the policy catalog. The controller-provided
/// collection remains the sole ordering source; visual columns are projections
/// of each item's visible index and never depend on measured card heights.
struct PolicyGroupColumnAssignment<Element> {
    let semanticOrder: [Element]
    let leadingColumn: [Element]
    let trailingColumn: [Element]

    init(_ visibleOrderedElements: [Element]) {
        semanticOrder = visibleOrderedElements
        leadingColumn = visibleOrderedElements.enumerated().compactMap { index, element in
            index.isMultiple(of: 2) ? element : nil
        }
        trailingColumn = visibleOrderedElements.enumerated().compactMap { index, element in
            index.isMultiple(of: 2) ? nil : element
        }
    }

    /// Reconstructs the semantic row-major order from the two fixed columns.
    /// This is useful for tests and accessibility assertions, not rendering.
    var rowMajorOrder: [Element] {
        var result: [Element] = []
        result.reserveCapacity(semanticOrder.count)

        for index in semanticOrder.indices {
            let columnIndex = index / 2
            if index.isMultiple(of: 2) {
                result.append(leadingColumn[columnIndex])
            } else {
                result.append(trailingColumn[columnIndex])
            }
        }

        return result
    }

    /// Gives every visual card a priority derived from its row-major source
    /// index. The two visual columns therefore remain one semantic sequence for
    /// assistive technologies instead of being exposed column by column.
    func accessibilitySortPriority(forSemanticIndex index: Int) -> Double {
        guard semanticOrder.indices.contains(index) else { return 0 }
        return Double(semanticOrder.count - index)
    }
}
