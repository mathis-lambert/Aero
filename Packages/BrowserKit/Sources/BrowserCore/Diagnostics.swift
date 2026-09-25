/// Shared names for signposts, visible in Instruments under the Points of Interest and os_signpost tracks.
public enum Diagnostics {
    public static let subsystem = "dev.auro"

    public enum Category {
        public static let launch = "Launch"
        package static let pageLifecycle = "PageLifecycle"
        package static let storage = "Storage"
    }

    public enum Signpost {
        public static let launch: StaticString = "Launch"
        package static let sessionLoad: StaticString = "SessionLoad"
        package static let sessionWrite: StaticString = "SessionWrite"
        package static let pageCreated: StaticString = "PageCreated"
        package static let pageRestored: StaticString = "PageRestored"
        package static let pageHibernated: StaticString = "PageHibernated"
        package static let hibernationCheck: StaticString = "HibernationCheck"
    }
}
