import Testing
@testable import MailStrea

@Test
func inMemoryRepositoryReturnsSeedMessages() {
    let repository = InMemoryMailRepository(seedMessages: SeedMailboxData.messages)

    #expect(repository.loadMessages().count == SeedMailboxData.messages.count)
}

@MainActor
@Test
func appStateBootstrapsWithInitialSelection() {
    let repository = InMemoryMailRepository(seedMessages: SeedMailboxData.messages)
    let state = AppState(repository: repository)

    #expect(state.messages.isEmpty == false)
    #expect(state.selectedMessageID == SeedMailboxData.messages.first?.id)
}
