import OSLog

enum MailClientLogger {
    static let app = Logger(subsystem: "com.mailclient.app", category: "app")
    static let sync = Logger(subsystem: "com.mailclient.app", category: "sync")
}
