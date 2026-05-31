import AppKit
import ApplicationServices

package final class WindowObserver {
    package static let shared = WindowObserver()

    private static let maxRetries = 10
    private static let retryInterval: TimeInterval = 0.05

    private var observers: [pid_t: AXObserver] = [:]

    private init() {}

    package func start() {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            self?.handleAppLaunched(app)
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

        nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular
            else { return }
            WorkspaceManager.shared.followExternalFocus(pid: app.processIdentifier)
        }

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            observeApp(pid: pid)
            if let windows = WindowManager.windows(pid: pid) {
                observeWindows(windows, pid: pid)
            }
        }
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        observeApp(pid: pid)
        trySyncWindows(pid: pid, attempt: 0)
    }

    private func trySyncWindows(pid: pid_t, attempt: Int) {
        guard let windows = WindowManager.windows(pid: pid), !windows.isEmpty else {
            retrySyncWindows(pid: pid, attempt: attempt)
            return
        }

        WorkspaceManager.shared.syncWindows(pid: pid, windows: windows)
        observeWindows(windows, pid: pid)
    }

    private func retrySyncWindows(pid: pid_t, attempt: Int) {
        guard attempt < Self.maxRetries else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval) {
            self.trySyncWindows(pid: pid, attempt: attempt + 1)
        }
    }

    private func observeApp(pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, WindowObserver.axCallback, &observer)
        guard result == .success, let obs = observer else { return }

        let appRef = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(obs, appRef, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(obs, appRef, kAXFocusedWindowChangedNotification as CFString, nil)
        AXObserverAddNotification(obs, appRef, kAXFocusedUIElementChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

        observers[pid] = obs
    }

    private static let axCallback: AXObserverCallback = { _, element, notification, _ in
        let notif = notification as String

        if notif == kAXWindowCreatedNotification {
            var pidValue: pid_t = 0
            AXUIElementGetPid(element, &pidValue)
            WindowObserver.shared.trySyncWindows(pid: pidValue, attempt: 0)
        } else if notif == kAXUIElementDestroyedNotification {
            var pidValue: pid_t = 0
            AXUIElementGetPid(element, &pidValue)
            if let obs = WindowObserver.shared.observers[pidValue] {
                for name in [
                    kAXUIElementDestroyedNotification,
                    kAXMovedNotification,
                    kAXResizedNotification,
                ] {
                    AXObserverRemoveNotification(obs, element, name as CFString)
                }
            }
            let windows = WindowManager.windows(pid: pidValue) ?? []
            WorkspaceManager.shared.syncWindows(pid: pidValue, windows: windows)
        } else if notif == kAXFocusedWindowChangedNotification || notif == kAXFocusedUIElementChangedNotification {
            var pidValue: pid_t = 0
            AXUIElementGetPid(element, &pidValue)
            WorkspaceManager.shared.followExternalFocus(pid: pidValue)
        } else if notif == kAXMovedNotification || notif == kAXResizedNotification {
            var pidValue: pid_t = 0
            AXUIElementGetPid(element, &pidValue)
            WorkspaceManager.shared.handleWindowGeometryChange(pid: pidValue, element: element)
        }
    }

    private func observeWindow(element: AXUIElement, pid: pid_t) {
        guard let obs = observers[pid] else { return }
        AXObserverAddNotification(obs, element, kAXUIElementDestroyedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXMovedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXResizedNotification as CFString, nil)
    }

    private func observeWindows(_ windows: [TrackedWindow], pid: pid_t) {
        for window in windows {
            for member in window.members {
                observeWindow(element: member, pid: pid)
            }
        }
    }
}
