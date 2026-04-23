import Foundation

actor MailSyncService {
    func bootstrap() async {
        MailClientLogger.sync.info("Bootstrapping MailClient services")
    }

    func refreshAll() async {
        MailClientLogger.sync.info("Refreshing all mailboxes")
    }
}
