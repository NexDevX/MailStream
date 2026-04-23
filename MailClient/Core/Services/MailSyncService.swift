import Foundation

actor MailSyncService {
    func bootstrap() async {
        MailClientLogger.sync.info("Bootstrapping MailStrea services")
    }

    func refreshAll() async {
        MailClientLogger.sync.info("Refreshing all mailboxes")
    }
}
