# Changelog

Each release's notes come from its section here (the release workflow requires one).

## 0.12.2

Fixes and hardening from a code review by Filip Kotek ([ejthbit/daypatch](https://github.com/ejthbit/daypatch)) — thank you!

**Dia ✦**
- 🩹 The sidebar URL bar and ← → ↻ buttons appear as soon as Dia ✦ starts, not only after ⌃⌘U.
- 🫥 Dia's top bar stays hidden while the sidebar is collapsed (e.g. in focus mode), like Arc. Prefer it back? Settings › DayPatch › **Top bar while the sidebar is hidden**.
- 🔐 DayPatch no longer overwrites Dia's own settings: page-content extraction and telemetry sampling are only changed while *Hide AI* / *Block telemetry* are on, and Dia's values come back when they're off. Values earlier versions wrote are cleared once.
- ⌨️ Command bar: Backspace removes an autocompletion; Enter never acts on results from an earlier keystroke; plain text searches with your search engine; `view-source:`, `blob:` and `tel:` open as themselves and schemes match in any case; `[::1]` opens over http; new bookmarks and search-engine changes show up without restarting; the active profile's history is used; accented searches match any case; a stray pasted character no longer crashes it.
- ⌨️ ⌘T, ⌘L and ⌃⌘U work with Caps Lock on.
- 🩹 The shortcut recorder no longer swallows keys once you click away from Settings, and accepts F2–F12. Shortcuts need ⌃ or ⌘ (⌥ + a key types characters on many layouts, so the ⌥1…⌥9 profile option is gone).
- 🗂️ Sorting and grouping tabs never moves pinned tabs or tabs from another profile; `example.com.` groups with `example.com`.
- 🩹 Fixed a possible crash when windows close.
- 🛡️ Safer against Dia updates: hooks install all-or-nothing instead of half-way.

**DayPatch**
- 🔐 DayPatch is signed with the hardened runtime, so other programs can't inject code into it and borrow its App Management permission.
- 🛡️ DayPatch only patches or restores a Dia signed by The Browser Company, refuses to patch from a modified DayPatch.app, and re-patches Dia ✦ when its signature no longer verifies (e.g. a swapped `daypatch.dylib`).
- 🩹 Never replaces Dia while it (or the original Dia during a passkey handoff) is running or has just updated itself; an interrupted swap is recovered instead of leaving Dia missing.
- 🩹 A failed self-update puts the old DayPatch back; relaunching passes the app's path safely; the background job and login item follow DayPatch when it's moved.
- 🩹 A failing automatic patch waits for you instead of retrying every 2 minutes; the window no longer freezes while checking signatures; the old profile merge runs only once.

## 0.12.1

- 🏠 **Local addresses work in the command bar.** Completing a site you've visited keeps its `http://` and port (`homeassistant.local:8123`, `localhost:3000`) instead of turning it into `https://homeassistant.local`. Typed addresses use `http://` for `localhost`, `.local`, `.lan`, `.home.arpa`, `.internal`, `.test`, private IPs and plain names like `nas:5000`, which also no longer start a search.
- 🖼️ **Favicons while typing.** The command bar's field shows the icon of the site it will open, and DayPatch keeps its own copy of each site's favicon, since Dia's Chromium forgets them a day or two after a visit.
- 🔢 The sidebar URL bar shows the port (`localhost:3000`).

## 0.12.0

- ⌨️ **Extra shortcuts** (Settings › DayPatch › Shortcuts, off by default, each one changeable): sort tabs by domain (⌃⌥S), group tabs by domain (⌃⌥G), next / previous profile (⌃⌥→ / ⌃⌥←), move the current tab to the next profile (⌃⌥⇧→), and switch to profile 1–9 (⌃1…⌃9).
- 📏 The sidebar URL bar is as wide as the pinned tabs below it.
- 🩹 The command bar's tab actions talk to Dia ✦ itself, never the original Dia while a passkey handoff has it open.
- 🩹 Fixed a possible crash at launch when Dia's scripting support isn't ready yet.

## 0.11.1

- 🔐 **Passkeys from Apple Passwords:** Dia ✦ menu › **Use Passkeys in Original Dia…** reopens your tabs in the original Dia so Touch ID passkeys work, with a **Back to Dia ✦** button to return. (Apple only allows them in Dia's own app.)
- 🗂️ **Dia ✦ uses your regular Dia profile again.** Renaming the app had given it a profile of its own, so tabs, history and logins drifted apart from the original Dia (which Restore and Update Dia… open). DayPatch moves the newer profile back into place once, keeping the older one in `~/Library/Application Support/daypatch/profile-backups`.
- ✦ The star now comes from the display name and the app menu; Dia's internal name stays "Dia".
- 🔗 DayPatch links to its GitHub page (window footer and menu bar menu), and both DayPatch and Dia's Settings pane say it isn't affiliated with The Browser Company.

## 0.11.0

- 🩹 **Dia is patched in place** by default and becomes **Dia ✦**. The original is kept, so **Restore** puts it back in one click.
- 📦 Prefer a separate app? Untick **Patch Dia directly** to get `~/Applications/Dia ✦.app` and leave Dia untouched.
- 🔄 **Dia's own updater stays on** (in place); DayPatch re-patches after an update. **Update Dia…** remains as a fallback.
- 🙈 Hide AI now also hides **Chat with this tab** in tab hover cards.
- 🫥 **Reveal top bar on hover** is now off by default.
- 🔎 Command bar: most-visited sites rank first (`g` → Google), and result text has more contrast in dark mode.
- 🎛️ Settings pane: content no longer scrolls under the title bar.
- 🧹 The old `Patched Dia.app` is moved to the Trash once Dia ✦ is ready.

## 0.10.1

- 🖼️ README screenshots; "DayPatch" spelled consistently in the UI.

## 0.10.0

- 🎉 First release as DayPatch.
