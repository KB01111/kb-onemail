# Blue Windows chrome and automatic releases

Approved in chat on 2026-11-05: keep native Windows caption controls and Snap Layouts, use a transparent Mica caption with matching solid fallback, and ship the existing blue identity through installer, taskbar and tray. Retain the application identifier and profile.

Use the existing Tauri updater plugin and protected signing identity. Check at startup and daily; installation continues to require approval and a successful draft-save handshake. BetterBox 0.2.1 needs one manual upgrade because it predates the updater.

Build from main locally when hosted minutes are unavailable. A shared release command and main-push workflow must validate, build, sign, verify, upload immutable versioned assets, then advance the preview channel. Derive the patch number from main's first-parent commit count so every main revision has a newer version without committing generated version changes. Never publish a dirty checkout or move the channel to an older version. Preserve unsigned-Windows-publisher disclosure.

The evaluated Decorum plugin replaces native controls with web controls. Use the existing Windows compositor integration for the approved native-control design; do not add a redundant titlebar dependency.
