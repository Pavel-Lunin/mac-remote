import Foundation
import os

/// Объявляет сервер в локальной сети через Bonjour (`_macremote._tcp.`).
///
/// Используем `NetService` — он помечен deprecated в macOS 14+, но всё ещё
/// единственный способ объявить сервис без открытия дополнительного сокета.
/// `Network.framework` (`NWListener.service`) пришлось бы биндить на отдельный
/// порт, что нам не нужно — TCP-сокет уже держит Vapor.
final class BonjourPublisher: NSObject {
    private let log = Logger(subsystem: "com.macremote.app", category: "discovery")
    private var service: NetService?

    /// Публикует сервис. `name` — отображаемое имя (имя Mac).
    func publish(port: UInt16, name: String) {
        let resolvedName = name.isEmpty ? "MacRemote" : name
        let service = NetService(
            domain: "",                   // "" — let Bonjour pick local.
            type: "_macremote._tcp.",
            name: resolvedName,
            port: Int32(port)
        )
        service.delegate = self
        service.publish()
        self.service = service
        log.notice("publishing \(resolvedName, privacy: .public) on port \(port, privacy: .public)")
    }

    /// Снимает публикацию (если была).
    func unpublish() {
        guard let service else { return }
        service.stop()
        service.delegate = nil
        self.service = nil
        log.notice("unpublished")
    }
}

extension BonjourPublisher: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        log.notice("did publish on port \(sender.port, privacy: .public)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        log.error("did not publish: \(errorDict, privacy: .public)")
    }

    func netServiceDidStop(_ sender: NetService) {
        log.notice("did stop")
    }
}
