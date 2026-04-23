import OSLog

enum MailClientLogger {
    static let app = Logger(subsystem: "com.mailclient.app", category: "app")
    static let sync = Logger(subsystem: "com.mailclient.app", category: "sync")
    static let network = Logger(subsystem: "com.mailclient.app", category: "network")
    static let storage = Logger(subsystem: "com.mailclient.app", category: "storage")
}
