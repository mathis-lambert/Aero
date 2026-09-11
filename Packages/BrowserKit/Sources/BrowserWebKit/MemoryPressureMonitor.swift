import BrowserCore
import Dispatch

@MainActor
final class MemoryPressureMonitor {
    private let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)

    init(onChange: @escaping @MainActor (MemoryPressure) -> Void) {
        source.setEventHandler { [source] in
            let event = source.data
            let pressure: MemoryPressure = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
            // The source delivers on the main queue.
            MainActor.assumeIsolated { onChange(pressure) }
        }
        source.activate()
    }

    isolated deinit { source.cancel() }
}
