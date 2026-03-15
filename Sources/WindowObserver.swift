import AppKit
import ApplicationServices

final class WindowObserver {
    static let shared = WindowObserver()

    private var observers: [pid_t: AXObserver] = [:]

    private init() {}

    func start() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.handleAppLaunched(app)
            }
        }

        nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            WorkspaceManager.shared.removeWindow(pid: pid)
            WindowObserver.shared.observers.removeValue(forKey: pid)
        }

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            observeApp(pid: app.processIdentifier)
        }
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return }

        for win in windows {
            let tw = TrackedWindow(element: win, pid: pid)
            guard tw.isTileable() else { continue }
            WorkspaceManager.shared.addWindow(tw)
        }

        observeApp(pid: pid)
    }

    private func observeApp(pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, WindowObserver.axCallback, &observer)
        guard result == .success, let obs = observer else { return }

        let appRef = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(obs, appRef, kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        observers[pid] = obs
    }

    private static let axCallback: AXObserverCallback = { _, element, notification, _ in
        let notif = notification as String

        if notif == kAXWindowCreatedNotification {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                var pidValue: pid_t = 0
                AXUIElementGetPid(element, &pidValue)
                let tw = TrackedWindow(element: element, pid: pidValue)
                guard tw.isTileable() else { return }
                WorkspaceManager.shared.addWindow(tw)
            }
        }
    }
}
