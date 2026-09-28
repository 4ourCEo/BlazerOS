import BlazerCore
import SwiftUI

struct BookStripView: View, Equatable {
    let book: [BookRow]
    let selectedPair: String
    let onSelect: (String) -> Void

    static nonisolated func == (lhs: BookStripView, rhs: BookStripView) -> Bool {
        lhs.book == rhs.book && lhs.selectedPair == rhs.selectedPair
    }

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(book) { row in
                Button {
                    onSelect(row.asset)
                } label: {
                    BookCell(row: row, isSelected: row.asset == selectedPair)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(book.map { "\($0.asset) \($0.side)" }.joined(separator: ", "))
    }
}

struct BookCell: View {
    let row: BookRow
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.asset)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(row.side)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bookInk(row.side))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.white.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
