import SwiftUI

struct StatusPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacRemote server")
                .font(.headline)
            Text("Сервер ещё не запущен.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    StatusPanelView()
        .frame(width: 320)
}
