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
                .buttonStyle(SpringPressButtonStyle())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(book.map { "\($0.asset) \($0.side)" }.joined(separator: ", "))
    }
}

struct BookCell: View {
    let row: BookRow
    let isSelected: Bool

    private var hasActionableSignal: Bool {
        row.side == "HIGH" || row.side == "LOW"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(row.asset)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if hasActionableSignal {
                    Circle()
                        .fill(bookInk(row.side))
                        .frame(width: 4, height: 4)
                        .shadow(color: bookInk(row.side).opacity(0.8), radius: 3)
                }
            }

            Text(row.side)
                .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(bookInk(row.side))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? DeskInk.indigo.opacity(0.32)
                        : Color.white.opacity(0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? DeskInk.electric.opacity(0.55)
                        : (hasActionableSignal ? bookInk(row.side).opacity(0.25) : Color.white.opacity(0.05)),
                    lineWidth: isSelected ? 1.0 : 0.5
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
    }
}
