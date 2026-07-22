//
//  CoralRow.swift
//  StrategyForge
//
//  THE canonical list row (premium verdict B1). Every list — chats, repos, providers,
//  catalog — uses this one row instead of four hand-rolled anatomies, so the app reads as
//  one product, not four screens by different people. Fixed height, a consistent 30pt
//  leading slot, a title + optional subtitle in one type pairing, and a trailing zone.
//  Group rows in an inset container (`coralRowGroup`) with hairline dividers.
//

import SwiftUI

struct CoralRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// Selected rows wear a coral spine + soft wash (coral = the active thing).
    var selected: Bool = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Space.s) {
            leading()
                .frame(width: 30, height: 30)
                .foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sfBodyM.weight(.medium)).foregroundStyle(Theme.ink)
                    .lineLimit(1).truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Space.s)
            trailing()
        }
        .padding(.horizontal, Space.s)
        .frame(minHeight: subtitle == nil ? 40 : 50)
        .background(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(Theme.selectionFill)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent)
                            .frame(width: 2.5).padding(.vertical, 7)
                    }
            }
        }
        .contentShape(Rectangle())
        .hoverTint(cornerRadius: Theme.rowCorner)
    }
}

// Convenience initialisers so call sites stay terse.
extension CoralRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, selected: Bool = false,
         @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, subtitle: subtitle, selected: selected,
                  leading: leading, trailing: { EmptyView() })
    }
}

extension CoralRow where Leading == AnyView {
    /// The common case: an SF Symbol leading icon.
    init(_ title: String, subtitle: String? = nil, systemImage: String, selected: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: subtitle, selected: selected,
                  leading: { AnyView(Image(systemName: systemImage).font(.system(size: 15))) },
                  trailing: trailing)
    }
}

extension CoralRow where Leading == AnyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String, selected: Bool = false) {
        self.init(title: title, subtitle: subtitle, selected: selected,
                  leading: { AnyView(Image(systemName: systemImage).font(.system(size: 15))) },
                  trailing: { EmptyView() })
    }
}

extension View {
    /// Wraps a stack of `CoralRow`s in one inset group with a hairline border — the premium
    /// "grouped list" surface (crisp depth on white without relying on shadow).
    func coralRowGroup() -> some View {
        self
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// A hairline row divider inset to align under a CoralRow's text (past the 30pt leading).
    func coralRowDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline.opacity(0.7)).frame(height: 1)
                .padding(.leading, 30 + Space.s + Space.s)
        }
    }
}
