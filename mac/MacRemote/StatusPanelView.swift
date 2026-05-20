import SwiftUI

struct StatusPanelView: View {
    @StateObject private var viewModel: StatusViewModel
    @State private var tokenRevealed = false
    @State private var showingRegenerateConfirm = false

    init(viewModel: StatusViewModel? = nil) {
        // В превью можно прокинуть свою ViewModel; в проде создаём из глобального TokenStore.
        _viewModel = StateObject(wrappedValue: viewModel ?? StatusViewModel(tokenStore: TokenStore()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            tokenSection
            Divider()
            permissionsSection
            Divider()
            quitButton
        }
        .padding(14)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MacRemote").font(.headline)
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.status {
        case .running(let port):
            statusBadge(color: .green, text: "Server running on port \(port)")
        case .stopped:
            statusBadge(color: .red, text: "Server stopped")
        case .error(let message):
            statusBadge(color: .orange, text: "Error: \(message)")
        }
    }

    private func statusBadge(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Token

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(tokenRevealed ? viewModel.token : String(repeating: "•", count: 16))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button(tokenRevealed ? "Hide" : "Show") {
                    tokenRevealed.toggle()
                }
                .controlSize(.small)
                Button("Copy") {
                    viewModel.copyTokenToPasteboard()
                }
                .controlSize(.small)
            }
            Button {
                showingRegenerateConfirm = true
            } label: {
                Label("Regenerate token", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .confirmationDialog(
                "Regenerate token?",
                isPresented: $showingRegenerateConfirm
            ) {
                Button("Regenerate", role: .destructive) {
                    viewModel.regenerateToken()
                    tokenRevealed = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Это разъединит всех клиентов. Новый токен будет скопирован в буфер обмена.")
            }
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: viewModel.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(viewModel.accessibilityGranted ? .green : .red)
                Text("Accessibility")
                Spacer()
                if !viewModel.accessibilityGranted {
                    Button("Open Settings") {
                        viewModel.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
            Text("Automation: macOS запросит разрешение при первой команде, нажмите OK.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Quit

    private var quitButton: some View {
        Button {
            viewModel.quit()
        } label: {
            Label("Quit MacRemote", systemImage: "power")
        }
        .controlSize(.regular)
    }
}

#Preview {
    StatusPanelView()
        .frame(width: 320)
}
