import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var tokenRevealed = false
    @State private var showingRegenerateConfirm = false

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
        switch coordinator.status {
        case .starting:
            statusBadge(color: .yellow, text: "Server starting…")
        case .running(let port):
            statusBadge(color: .green, text: "Server running on port \(port)")
        case .stopped:
            statusBadge(color: .red, text: "Server stopped")
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                statusBadge(color: .orange, text: "Error: \(message)")
                Button("Restart server") {
                    Task { await coordinator.restart() }
                }
                .controlSize(.small)
            }
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
                Text(tokenRevealed ? coordinator.token : String(repeating: "•", count: 16))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button(tokenRevealed ? "Hide" : "Show") {
                    tokenRevealed.toggle()
                }
                .controlSize(.small)
                Button("Copy") {
                    coordinator.copyTokenToPasteboard()
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
                    coordinator.regenerateToken()
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
                Image(systemName: coordinator.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(coordinator.accessibilityGranted ? .green : .red)
                Text("Accessibility")
                Spacer()
                if !coordinator.accessibilityGranted {
                    Button("Open Settings") {
                        coordinator.openAccessibilitySettings()
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
            Task { await coordinator.quit() }
        } label: {
            Label("Quit MacRemote", systemImage: "power")
        }
        .controlSize(.regular)
    }
}

#Preview {
    StatusPanelView(coordinator: AppCoordinator())
        .frame(width: 320)
}
