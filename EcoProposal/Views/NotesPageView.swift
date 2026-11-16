import SwiftUI

/// A full US-Letter page of proposal Notes. Long notes are split across as many
/// of these pages as needed (see `NotesPaginator`); each page receives one
/// pre-measured chunk of rich text.
struct NotesPageView: View {
    let snapshot: ProposalSnapshot
    let company: CompanyInfo
    /// This page's slice of the notes, with bold/italic/underline preserved.
    let content: AttributedString
    let pageIndex: Int
    let pageCount: Int

    static let pageSize = ProposalDocumentView.pageSize

    // Layout constants shared with the paginator: the content area is the page
    // minus margins, header row, title bar, and stack spacing — with a little
    // slack so measurement differences never clip the last line.
    static let margin: CGFloat = 36
    static let headerHeight: CGFloat = 28
    static let titleBarHeight: CGFloat = 20
    static let stackSpacing: CGFloat = 12
    static var contentSize: CGSize {
        CGSize(
            width: pageSize.width - margin * 2 - 8,   // 4pt horizontal text padding each side
            height: pageSize.height - margin * 2 - headerHeight - titleBarHeight
                - stackSpacing * 2 - 18               // ~1 line of slack
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.stackSpacing) {
            HStack {
                BrandLogo(height: Self.headerHeight)
                Spacer()
                Text(headerLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(height: Self.headerHeight)

            Text("NOTES")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: Self.titleBarHeight)
                .background(Color.ecoGreen)

            Text(content)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(Self.margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(.black)
    }

    private var headerLabel: String {
        if pageCount > 1 {
            return "\(snapshot.proposalNumber) • Notes (page \(pageIndex + 1) of \(pageCount))"
        }
        return "\(snapshot.proposalNumber) • Notes"
    }
}
