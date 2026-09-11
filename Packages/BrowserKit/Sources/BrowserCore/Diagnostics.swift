/// Shared names for signposts, visible in Instruments under the Points of Interest and os_signpost tracks.
public enum Diagnostics {
    public static let subsystem = "dev.lightbrowser"

    public enum Category {
        public static let launch = "Launch"
        public static let pageLifecycle = "PageLifecycle"
        public static let storage = "Storage"
    }

    public enum Signpost {
        public static let launch: StaticString = "Launch"
        public static let sessionLoad: StaticString = "SessionLoad"
        public static let sessionWrite: StaticString = "SessionWrite"
        public static let pageCreated: StaticString = "PageCreated"
        public static let pageRestored: StaticString = "PageRestored"
        public static let pageHibernated: StaticString = "PageHibernated"
        public static let hibernationCheck: StaticString = "HibernationCheck"
    }
}
