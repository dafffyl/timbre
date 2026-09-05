import SwiftUI
import TimbreCore

struct KeyboardView: View {
    let layout: KeyboardLayout
    var viewModel: DictationViewModel
    let onMicTap: () -> Void
    let onCancelTap: () -> Void
    let onDismissError: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            statusBar

            ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Text(key)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var statusBar: some View {
        switch viewModel.state {
        case .idle:
            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

        case .fullAccessRequired:
            Text("Autorise l'accès complet dans Réglages pour dicter")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

        case .waiting(let label):
            HStack {
                ProgressView()
                Text(label)
                    .font(.caption)
                Spacer()
                Button("Annuler", action: onCancelTap)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .error(let message):
            Button(action: onDismissError) {
                HStack {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Spacer()
                    Text("OK")
                        .font(.caption2.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    KeyboardView(layout: .azerty, viewModel: DictationViewModel(), onMicTap: {}, onCancelTap: {}, onDismissError: {})
}
