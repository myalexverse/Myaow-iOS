import SwiftUI

struct MyaowScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1.3)
                    .foregroundStyle(MyaowColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(MyaowColor.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct MyaowIconAction: View {
    let symbol: String
    let label: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(prominent ? Color.black : MyaowColor.textPrimary)
                .frame(width: 48, height: 48)
                .background(prominent ? MyaowColor.orange : MyaowColor.surface, in: RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MyaowSearchField: View {
    @Binding var text: String
    var placeholder = "Buscar"
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(MyaowColor.textSecondary)
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(MyaowColor.textPrimary)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MyaowColor.textSecondary)
                        .frame(width: 32, height: 36)
                }
                .accessibilityLabel("Borrar búsqueda")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MyaowColor.borderSubtle, lineWidth: 0.5))
    }
}

struct MyaowFilterTabs: View {
    let labels: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Button { selection = label } label: {
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selection == label ? MyaowColor.charcoal : MyaowColor.textSecondary)
                            .padding(.horizontal, 17)
                            .frame(minHeight: 38)
                            .background(selection == label ? MyaowColor.textPrimary : MyaowColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == label ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

struct MyaowSectionLabel: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .tracking(1.8)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail { Text(detail) }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MyaowColor.textSecondary)
    }
}

struct MyaowEmptyState: View {
    let title: String
    let message: String
    var symbol = "bubble.left.and.bubble.right"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(MyaowColor.surface)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(-8))
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(MyaowColor.orange)
            }
            .padding(.bottom, 7)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(MyaowColor.textPrimary)
            Text(message)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(MyaowColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 285)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 9) {
                        Text(actionTitle)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MyaowColor.charcoal)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(MyaowColor.textPrimary, in: Capsule())
                }
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
    }
}

struct MyaowSettingsRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(MyaowColor.textPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(MyaowColor.textPrimary)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary) }
            }
            Spacer(minLength: 5)
            if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary) }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(MyaowColor.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 19)
        .contentShape(Rectangle())
    }
}
