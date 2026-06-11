# AX Smoke

`make smoke-local` is a local/manual validation path for a real macOS GUI session.

Requirements:

- Apple Silicon Mac.
- Current terminal has Accessibility permission.
- No other window manager is active.
- Prefer a dedicated test user account.

Expected checks:

- Fixture app launches.
- parket launches.
- AX can read fixture windows.
- Standard fixture windows are visible onscreen.
- Utility panel is not counted as a standard tileable window.
- Minimized fixture window is not counted as tileable.
- parket exits through signal handling.
- Fixture windows remain onscreen after parket exits.

Manual follow-up scenarios:

- Switch workspaces with Option+1 through Option+9.
- Move focused fixture window with Option+Shift+1 through Option+Shift+9.
- Check native-tab-like fixture windows do not split into separate tiles.
- Toggle pause tiling from the status item.
- Restore all windows from the status item.
