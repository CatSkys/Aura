import AppKit
import SwiftUI

// The card the assistant asks in: drawn in the conversation, not as a sheet on
// the window.
//
// Dia asks this way. Its own card is `.card` in
// web-chat-resources/dist/app/immutable/assets/4.CtTaD-3d.css — 534pt wide,
// 20pt corners, raised surface, 18pt down the sides, a 12/40 shadow, and it
// enters from a 1rem above while the ground dims. The reasons it is a card in
// the column and not a sheet are both practical: a sheet belongs to the
// browser while these questions belong to the conversation, and a sheet covers
// the very page the question is about.
//
// Two questions share the shape, because they are the same shape:
//
//   · a confirmation before something that can't be taken back (AIToolRisk):
//     what, where, and Dia's answers — allow once, allow for this chat, deny.
//     Money is never remembered, so it is offered two.
//   · `ask_user`: the model stops and hands the page back to you — a sign-in,
//     a code, a password. Nothing is filled in for you.
//
// Both take no clicks in their first half second (CaptureAsk's rule in
// Browser.swift): a page can time a click to land where a button is about to
// be, and this is the one place where that trick would press "Allow".
//
// A test run answers without a card, the way Ask.testing does, so a probe can
// drive the loop without a window that a hidden run can't show.

@MainActor
final class AIToolAsk: ObservableObject {
    /// What is being asked, and the answers it takes.
    struct Card: Identifiable {
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
        /// Whether "always" is one of the answers: a payment never is.
        let remembers: Bool
        /// When it appeared. A click in the first half second is the page's.
        let at = Date()
    }

    enum Kind: Equatable {
        /// A confirmation before an action that can't be taken back.
        case confirm(AIToolRisk.Class)
        /// The model's own question (`ask_user`).
        case ask
    }

    /// What a confirmation may be answered.
    enum Confirm: Equatable {
        case allow
        /// Allowed, and remembered for this site and this class of action.
        case always
        case refuse
    }

    /// What `ask_user` may be answered.
    enum Answer: Equatable {
        /// Done: the person says they are ready to go on.
        case done
        /// They stopped the whole thing.
        case stop
        /// They closed it without answering.
        case cancel
    }

    /// A test run's answer to a confirmation, in place of a card. Never set
    /// otherwise.
    static var confirming: Confirm?
    /// A test run's answer to `ask_user`.
    static var answering: Answer?

    /// The card on screen, if there is one. One at a time: the loop waits on
    /// the answer before the rest of the same message happens.
    @Published private(set) var card: Card?

    private var settle: ((Confirm) -> Void)?

    // MARK: - the two questions

    /// The confirmation card for something that can't be taken back.
    func confirm(kind: AIToolRisk.Class, what: String, site: String) async -> Confirm {
        if Store.testing, let answer = Self.confirming { return answer }
        let answer = await show(Card(
            kind: .confirm(kind),
            title: kind.title,
            detail: kind.detail(what, site.isEmpty ? Localized("this page") : site),
            remembers: kind.remembers))
        // Money is never remembered, whatever came back.
        if answer == .always, !kind.remembers { return .allow }
        return answer
    }

    /// `ask_user`: the model stops and hands the page back to you.
    func ask(title: String, reason: String) async -> Answer {
        if Store.testing, let answer = Self.answering { return answer }
        switch await show(Card(kind: .ask,
                               title: title.isEmpty ? Localized("The assistant needs you") : title,
                               detail: reason,
                               remembers: false)) {
        case .allow: return .done
        case .always: return .done
        case .refuse: return .stop
        }
    }

    /// Puts the card up and waits for it. Nothing but your click answers it,
    /// and the click has to be late enough not to be the page's.
    private func show(_ shown: Card) async -> Confirm {
        card = shown
        let choice = await withCheckedContinuation { (done: CheckedContinuation<Confirm, Never>) in
            settle = { done.resume(returning: $0) }
        }
        card = nil
        settle = nil
        guard Date().timeIntervalSince(shown.at) >= 0.5 else { return .refuse }
        return choice
    }

    /// A button on the card.
    func answer(_ choice: Confirm) {
        let settle = self.settle
        self.settle = nil
        settle?(choice)
    }

    /// Anything that ends the card without an answer: the turn was stopped, or
    /// the window went away.
    func cancel() { answer(.refuse) }
}

// MARK: - the card

/// Dia's question card, drawn in the column: the title, what it would do, and
/// its answers as plain rows down the card's foot — in the order Dia puts
/// them, "Allow once", "Always allow for this chat", "Deny".
///
/// The order is the point. The safe answer is not the one under the pointer
/// and not the one a stray Return presses, and Deny is always drawn.
struct AIToolAskCard: View {
    /// Watched here as well as in the conversation: the card comes and goes
    /// without a line being added, so nothing else would redraw.
    @ObservedObject var asking: AIToolAsk
    let card: AIToolAsk.Card

    /// Dia's own numbers, in points.
    private enum Measure {
        static let width: CGFloat = 534
        static let corner: CGFloat = 20
        static let inset: CGFloat = 18
        static let gap: CGFloat = 14
        static let row: CGFloat = 40
    }

    /// A confirmation's three answers; the model's question takes two.
    private var rows: [(String, AIToolAsk.Confirm)] {
        switch card.kind {
        case .confirm:
            var rows: [(String, AIToolAsk.Confirm)] = [(Localized("Allow Once"), .allow)]
            // A payment is never remembered, so it is offered no such row.
            if card.remembers { rows.append((Localized("Always Allow for This Chat"), .always)) }
            rows.append((Localized("Deny"), .refuse))
            return rows
        case .ask:
            return [(Localized("Done, Go On"), .allow), (Localized("Stop Here"), .refuse)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Measure.gap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: card.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.Chat.ink)
                Text(verbatim: card.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.Chat.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.Chat.edge)
                            .frame(height: 1)
                    }
                    rowButton(row.0, row.1)
                }
            }
        }
        .padding(.horizontal, Measure.inset)
        .padding(.vertical, 16)
        .frame(maxWidth: Measure.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Measure.corner, style: .continuous)
                .fill(Palette.Chat.raised)
                .shadow(color: .black.opacity(0.24), radius: 20, y: 12)
        }
        // Dia enters the card from a little above, and the motion is the sign
        // that this is new rather than part of the answer above it.
        .transition(.opacity.combined(with: .offset(y: -10)))
    }

    private func rowButton(_ title: String, _ choice: AIToolAsk.Confirm) -> some View {
        Button {
            asking.answer(choice)
        } label: {
            HStack {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: choice == .refuse ? .medium : .regular))
                    .foregroundStyle(choice == .refuse ? Palette.Chat.muted : Palette.Chat.ink)
                Spacer(minLength: 0)
            }
            .frame(height: Measure.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
    }
}
