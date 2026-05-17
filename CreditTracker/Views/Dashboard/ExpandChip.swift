import SwiftUI

struct ExpandChip: View {
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: expanded)

                Text(expanded ? "Collapse" : "Expand all")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(expanded ? CT.accent : CT.surface)
            )
            .foregroundStyle(expanded ? Color.white : CT.accentDeep)
            .overlay(
                Capsule().stroke(CT.hairline, lineWidth: expanded ? 0 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: expanded)
    }
}

#Preview {
    HStack(spacing: 16) {
        ExpandChip(expanded: .constant(false))
        ExpandChip(expanded: .constant(true))
    }
    .padding()
    .background(CT.background)
}
