import AppKit
import ApplicationServices

private struct AXCallbackElement: @unchecked Sendable {
    let value: AXUIElement
}

private struct AXCallbackNotification: @unchecked Sendable {
    let value: CFString
}

private struct WorkspaceNotification: @unchecked Sendable {
    let value: Notification
}

@MainActor
package final class WindowObserver {
    package static let shared = WindowObserver()

    private static let maxRetries = 10
    private static let retryInterval: TimeInterval = 0.05
    private static let syncCoalesceDelay: TimeInterval = 0.06
    private static let focusCoalesceDelay: TimeInterval = 0.015
    private static let startupReconcileDelays: [TimeInterval] = [0.25, 1.0]
    private static let windowCreatedReconcileDelays: [TimeInterval] = [0.25, 1.0]

    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindowElements: [pid_t: [AXUIElement]] = [:]
    private var syncWorks: [pid_t: DispatchWorkItem] = [:]
    private var delayedSyncWorks: [pid_t: [DispatchWorkItem]] = [:]
    private var pendingSyncAllowsEmpty: [pid_t: Bool] = [:]
    private var focusWorks: [pid_t: DispatchWorkItem] = [:]
    private var isStarted = false

    private init() {}

    package func start() {
        if !isStarted {
            isStarted = true
            let nc = NSWorkspace.shared.notificationCenter

            nc.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main
            ) { note in
                let notification = WorkspaceNotification(value: note)
                MainActor.assumeIsolated {
                    WindowObserver.shared.handleLaunchNotification(notification.value)
                }
            }

            nc.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil, queue: .main
            ) { note in
                let notification = WorkspaceNotification(value: note)
                MainActor.assumeIsolated {
                    WindowObserver.shared.handleTerminateNotification(notification.value)
                }
            }

            nc.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { note in
                let notification = WorkspaceNotification(value: note)
                MainActor.assumeIsolated {
                    WindowObserver.shared.handleActivateNotification(notification.value)
                }
            }

            scheduleStartupReconciles()
        }

        observeRunningApplications()
    }

    private func observeRunningApplications() {
        for app in WindowManager.managedApplications() {
            let pid = app.processIdentifier
            observeApp(pid: pid)
            if let snapshot = PerformanceTelemetry.measure(.axSnapshot, { WindowManager.windowSnapshot(pid: pid) }) {
                observeWindowElements(snapshot.elements, pid: pid)
            }
        }
    }

    private func scheduleStartupReconciles() {
        for delay in Self.startupReconcileDelays {
            let work = DispatchWorkItem { [self] in
                reconcileRunningApplications()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func reconcileRunningApplications() {
        guard ParketRuntime.shared.isRunning else { return }
        for app in WindowManager.managedApplications() {
            let pid = app.processIdentifier
            observeApp(pid: pid)
            guard
                let snapshot = PerformanceTelemetry.measure(
                    .axSnapshot,
                    { WindowManager.windowSnapshot(pid: pid) }
                )
            else {
                continue
            }
            WorkspaceManager.shared.syncWindows(pid: pid, windows: snapshot.windows)
            observeWindowElements(snapshot.elements, pid: pid)
        }
    }

    private func handleLaunchNotification(_ note: Notification) {
        guard ParketRuntime.shared.isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            WindowManager.isManagedApplication(app)
        else { return }
        handleAppLaunched(app)
    }

    private func handleTerminateNotification(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        if ParketRuntime.shared.isRunning {
            WorkspaceManager.shared.removeWindow(pid: pid)
        }
        observers.removeValue(forKey: pid)
        observedWindowElements.removeValue(forKey: pid)
        syncWorks.removeValue(forKey: pid)?.cancel()
        for work in delayedSyncWorks.removeValue(forKey: pid) ?? [] {
            work.cancel()
        }
        pendingSyncAllowsEmpty.removeValue(forKey: pid)
        focusWorks.removeValue(forKey: pid)?.cancel()
    }

    private func handleActivateNotification(_ note: Notification) {
        guard ParketRuntime.shared.isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            WindowManager.isManagedApplication(app)
        else { return }
        WorkspaceManager.shared.followExternalFocus(pid: app.processIdentifier)
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        observeApp(pid: pid)
        trySyncWindows(pid: pid, attempt: 0)
    }

    private func trySyncWindows(pid: pid_t, attempt: Int) {
        trySyncWindows(pid: pid, attempt: attempt, allowEmpty: false)
    }

    private func trySyncWindows(pid: pid_t, attempt: Int, allowEmpty: Bool) {
        let snapshot = PerformanceTelemetry.measure(.axSnapshot) {
            WindowManager.windowSnapshot(pid: pid)
        }
        guard let snapshot, allowEmpty || !snapshot.windows.isEmpty else {
            retrySyncWindows(pid: pid, attempt: attempt, allowEmpty: allowEmpty)
            return
        }

        WorkspaceManager.shared.syncWindows(pid: pid, windows: snapshot.windows)
        observeWindowElements(snapshot.elements, pid: pid)
    }

    private func retrySyncWindows(pid: pid_t, attempt: Int, allowEmpty: Bool) {
        guard attempt < Self.maxRetries else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval) {
            self.trySyncWindows(pid: pid, attempt: attempt + 1, allowEmpty: allowEmpty)
        }
    }

    private func scheduleSyncWindows(pid: pid_t, allowEmpty: Bool) {
        pendingSyncAllowsEmpty[pid] = (pendingSyncAllowsEmpty[pid] ?? true) && allowEmpty
        syncWorks[pid]?.cancel()
        let work = DispatchWorkItem { [self] in
            syncWorks.removeValue(forKey: pid)
            let allowEmpty = pendingSyncAllowsEmpty.removeValue(forKey: pid) ?? allowEmpty
            trySyncWindows(pid: pid, attempt: 0, allowEmpty: allowEmpty)
        }
        syncWorks[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.syncCoalesceDelay, execute: work)
    }

    private func scheduleDelayedSyncWindows(pid: pid_t) {
        for work in delayedSyncWorks.removeValue(forKey: pid) ?? [] {
            work.cancel()
        }
        let works = Self.windowCreatedReconcileDelays.map { delay in
            let work = DispatchWorkItem { [self] in
                trySyncWindows(pid: pid, attempt: 0, allowEmpty: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
        delayedSyncWorks[pid] = works
    }

    private func scheduleFocusFollow(pid: pid_t) {
        focusWorks[pid]?.cancel()
        let work = DispatchWorkItem { [self] in
            focusWorks.removeValue(forKey: pid)
            WorkspaceManager.shared.followExternalFocus(pid: pid)
        }
        focusWorks[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.focusCoalesceDelay, execute: work)
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
        let callbackElement = AXCallbackElement(value: element)
        let callbackNotification = AXCallbackNotification(value: notification)
        MainActor.assumeIsolated {
            WindowObserver.shared.handleAXNotification(
                element: callbackElement.value,
                notification: callbackNotification.value
            )
        }
    }

    private func handleAXNotification(element: AXUIElement, notification: CFString) {
        guard ParketRuntime.shared.isRunning else { return }
        let notif = notification as String

        if notif == kAXWindowCreatedNotification {
            let pidValue = pid(for: element)
            scheduleSyncWindows(pid: pidValue, allowEmpty: false)
            scheduleDelayedSyncWindows(pid: pidValue)
        } else if notif == kAXUIElementDestroyedNotification {
            let pidValue = pid(for: element)
            if let obs = observers[pidValue] {
                for name in [
                    kAXUIElementDestroyedNotification,
                    kAXMovedNotification,
                    kAXResizedNotification,
                    kAXWindowMiniaturizedNotification,
                    kAXWindowDeminiaturizedNotification,
                ] {
                    AXObserverRemoveNotification(obs, element, name as CFString)
                }
            }
            removeObservedWindow(element: element, pid: pidValue)
            WindowManager.invalidateAppliedGeometry(element)
            WorkspaceManager.shared.handleWindowDestroyed(pid: pidValue, element: element)
            scheduleSyncWindows(pid: pidValue, allowEmpty: true)
        } else if notif == kAXWindowMiniaturizedNotification {
            scheduleSyncWindows(pid: pid(for: element), allowEmpty: true)
        } else if notif == kAXWindowDeminiaturizedNotification {
            let pidValue = pid(for: element)
            scheduleSyncWindows(pid: pidValue, allowEmpty: false)
            scheduleDelayedSyncWindows(pid: pidValue)
        } else if notif == kAXFocusedWindowChangedNotification || notif == kAXFocusedUIElementChangedNotification {
            scheduleFocusFollow(pid: pid(for: element))
        } else if notif == kAXMovedNotification || notif == kAXResizedNotification {
            WorkspaceManager.shared.handleWindowGeometryChange(pid: pid(for: element), element: element)
        }
    }

    private func observeWindow(element: AXUIElement, pid: pid_t) {
        guard let obs = observers[pid] else { return }
        guard !isObservedWindow(element: element, pid: pid) else { return }
        AXObserverAddNotification(obs, element, kAXUIElementDestroyedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXMovedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXResizedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXWindowMiniaturizedNotification as CFString, nil)
        AXObserverAddNotification(obs, element, kAXWindowDeminiaturizedNotification as CFString, nil)
        observedWindowElements[pid, default: []].append(element)
    }

    private func observeWindowElements(_ elements: [AXUIElement], pid: pid_t) {
        for element in elements {
            observeWindow(element: element, pid: pid)
        }
    }

    private func pid(for element: AXUIElement) -> pid_t {
        PerformanceTelemetry.recordAXRead()
        var pidValue: pid_t = 0
        AXUIElementGetPid(element, &pidValue)
        return pidValue
    }

    private func isObservedWindow(element: AXUIElement, pid: pid_t) -> Bool {
        observedWindowElements[pid]?.contains { CFEqual($0, element) } ?? false
    }

    private func removeObservedWindow(element: AXUIElement, pid: pid_t) {
        observedWindowElements[pid]?.removeAll { CFEqual($0, element) }
    }
}
