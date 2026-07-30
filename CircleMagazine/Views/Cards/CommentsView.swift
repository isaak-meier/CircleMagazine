//
//  CommentsView.swift
//  CircleMagazine
//
//  The comments sheet for a feed card (page): loads the page's comments, shows
//  them oldest-first, and posts new ones. Presented from CardView's CommentBar.
//

import SwiftUI

struct CommentsView: View {
    @State private var model: CommentsModel
    @Environment(\.dismiss) private var dismiss

    init(model: CommentsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            header
            Divider().overlay(Style.rule)
            content
            inputBar
        }
        .background(Style.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .task { await model.load() }
    }

    private var grabber: some View {
        Capsule().fill(Style.rule).frame(width: 36, height: 4).padding(.top, 10)
    }

    private var header: some View {
        Text("Comments")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Style.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(alignment: .trailing) {
                Button("Done") { dismiss() }
                    .font(.system(size: 14)).foregroundStyle(Style.meta)
                    .padding(.trailing, Style.Space.lg)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            Spacer(); ProgressView(); Spacer()
        case .loaded(let comments) where comments.isEmpty:
            emptyState
        case .loaded(let comments):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(comments) { row($0) }
                }
                .padding(.horizontal, Style.Space.lg)
                .padding(.vertical, 16)
            }
        case .failed(let message):
            Spacer()
            Text(message).font(Style.body).foregroundStyle(Style.meta)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Style.Space.sm) {
                Image(systemName: "bubble.left").font(.system(size: 30)).foregroundStyle(Style.meta)
                Text("No comments yet.").font(Style.cardTitle).foregroundStyle(Style.ink)
                Text("Start the conversation.").font(Style.body).foregroundStyle(Style.meta)
            }
            Spacer()
        }
    }

    private func row(_ item: CommentWithAuthor) -> some View {
        HStack(alignment: .top, spacing: 11) {
            avatar(item.author)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.author?.username ?? "Someone")
                        .font(Style.byline).foregroundStyle(Style.ink)
                    if let at = item.comment.createdAt {
                        Text(at.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10.5)).foregroundStyle(Style.meta)
                    }
                }
                Text(item.comment.body)
                    .font(.system(size: 14)).foregroundStyle(Color(hex: 0x2A2826))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func avatar(_ user: User?) -> some View {
        if let user {
            Avatar(user: user)
        } else {
            // A comment whose author didn't come back — someone who left.
            SwiftUI.Circle().fill(Style.rule)
                .frame(width: 30, height: 30)
                .overlay(Text("?").font(Style.byline).foregroundStyle(Style.meta))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 11) {
            avatar(model.me)
            TextField("Add a comment…", text: $model.draft, axis: .vertical)
                .font(.system(size: 14)).foregroundStyle(Color(hex: 0x2A2826))
                .onSubmit { Task { await model.send() } }
            Button { Task { await model.send() } } label: {
                if model.posting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(model.canSend ? Style.ink : Style.rule)
                }
            }
            .disabled(!model.canSend)
        }
        .padding(.horizontal, Style.Space.lg)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(Style.rule).frame(height: 1) }
    }
}
