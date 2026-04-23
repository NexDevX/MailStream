import Foundation

enum SeedMailboxData {
    static let messages: [MailMessage] = [
        MailMessage(
            sidebarItem: .allMail,
            inboxFilter: .inbox,
            senderName: "Elena Rostova",
            senderRole: "Design Team, Product Leads",
            recipientLine: "to Design Team, Product Leads",
            tag: "DESIGN",
            subject: "Q3 Brand Strategy & Visual Language Update",
            preview: "Following our review session yesterday, I've consolidated the typography shifts and tonal layering adjustments.",
            timestampLabel: "10:42 AM",
            relativeTimestamp: "10:42 AM (2 hours ago)",
            isPriority: true,
            bodyParagraphs: [
                "Hi everyone,",
                "Following our review session yesterday, I've consolidated the typography shifts and tonal layering adjustments. The hairline borders are working beautifully in the prototype, reducing visual noise while maintaining clear structural boundaries."
            ],
            highlights: [
                "Adopt a serif display style for primary headings to establish the editorial feel.",
                "Use a clean sans-serif for controls and body copy to preserve readability at smaller sizes.",
                "Reserve shadows for active and floating states so the resting layout stays calm."
            ],
            closing: "Best,\nElena"
        ),
        MailMessage(
            sidebarItem: .allMail,
            inboxFilter: .focused,
            senderName: "Marcus Chen",
            senderRole: "Platform Engineering",
            recipientLine: "to Platform Team",
            tag: "DEV",
            subject: "API Documentation for v2.4",
            preview: "The endpoints have been stabilized. Please review the updated swagger docs before implementation begins.",
            timestampLabel: "Yesterday",
            relativeTimestamp: "Yesterday at 6:18 PM",
            isPriority: true,
            bodyParagraphs: [
                "Team,",
                "The API surface for v2.4 is now stable. The remaining work is mostly naming cleanup and examples. If nobody objects, I will publish the developer-facing docs tomorrow morning."
            ],
            highlights: [
                "Freeze endpoint names this week.",
                "Ship response examples with pagination notes.",
                "Align auth header examples across all endpoints."
            ],
            closing: "Thanks,\nMarcus"
        ),
        MailMessage(
            sidebarItem: .allMail,
            inboxFilter: .archive,
            senderName: "Operations Team",
            senderRole: "Weekly Reporting",
            recipientLine: "to Workspace Leads",
            tag: "ADMIN",
            subject: "Weekly Performance Report",
            preview: "Automated metrics digest for the week ending October 12th. Overall system uptime remained at 99.99%.",
            timestampLabel: "Oct 12",
            relativeTimestamp: "Oct 12 at 8:00 AM",
            isPriority: false,
            bodyParagraphs: [
                "Hello all,",
                "Attached is the weekly performance digest. Uptime remained within target and the incident count was lower than the trailing four-week average."
            ],
            highlights: [
                "Uptime held at 99.99%.",
                "Support backlog decreased by 12%.",
                "Average response time improved on both web and desktop."
            ],
            closing: "Regards,\nOperations"
        ),
        MailMessage(
            sidebarItem: .drafts,
            inboxFilter: .inbox,
            senderName: "You",
            senderRole: "Draft",
            recipientLine: "to Leadership",
            tag: "DRAFT",
            subject: "Launch Notes for MailStrea Preview",
            preview: "Current draft covers the initial UI milestone, DMG distribution, and internal test goals.",
            timestampLabel: "Draft",
            relativeTimestamp: "Saved 18 minutes ago",
            isPriority: false,
            bodyParagraphs: [
                "Preview build summary:",
                "The first pass is focused on a stable desktop shell, seeded mailbox content, and a distribution flow that works without login or sync dependencies."
            ],
            highlights: [
                "Ship a polished static UI first.",
                "Package a local DMG for stakeholder review.",
                "Leave mailbox integration for the next milestone."
            ],
            closing: "Joey"
        ),
        MailMessage(
            sidebarItem: .sent,
            inboxFilter: .inbox,
            senderName: "You",
            senderRole: "Founder",
            recipientLine: "to Design Review",
            tag: "SENT",
            subject: "MailStrea desktop direction",
            preview: "Sharing the current layout direction for sidebar hierarchy, message cards, and the reading surface.",
            timestampLabel: "Apr 21",
            relativeTimestamp: "Apr 21 at 2:14 PM",
            isPriority: false,
            bodyParagraphs: [
                "Hi all,",
                "The current direction is intentionally restrained: warm neutrals, strong type hierarchy, and minimal chrome. This should make the client feel editorial instead of dashboard-like."
            ],
            highlights: [
                "Keep the sidebar quiet and structured.",
                "Use large serif headlines in detail view.",
                "Avoid decorative color until we add real account state."
            ],
            closing: "Joey"
        ),
        MailMessage(
            sidebarItem: .trash,
            inboxFilter: .archive,
            senderName: "System",
            senderRole: "Cleanup",
            recipientLine: "to You",
            tag: "SYSTEM",
            subject: "Deleted test message",
            preview: "Temporary seed content removed from the local prototype mailbox.",
            timestampLabel: "Apr 20",
            relativeTimestamp: "Apr 20 at 11:03 AM",
            isPriority: false,
            bodyParagraphs: [
                "This item exists only to populate the Trash destination during the prototype phase."
            ],
            highlights: [
                "No action required."
            ],
            closing: "System"
        )
    ]
}
