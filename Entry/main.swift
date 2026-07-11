import AppKit
import ParketCore

@MainActor
final class TerminationCoordinator: NSObject, NSApplicationDelegate {
    private var terminationRequested = false

    func requestTermination() {
        guard !terminationRequested else { return }
        terminationRequested = true
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WorkspaceManager.shared.restoreAllWindows()
        return .terminateNow
    }
}

@MainActor
final class SignalCoordinator {
    private var sources: [DispatchSourceSignal] = []

    init(termination: TerminationCoordinator) {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    termination.requestTermination()
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let termination = TerminationCoordinator()
let signals = SignalCoordinator(termination: termination)
app.delegate = termination
ParketRuntime.shared.start()
withExtendedLifetime((termination, signals)) {
    app.run()
}
