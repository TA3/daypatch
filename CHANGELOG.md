# Changelog

Each release's notes come from its section here (the release workflow requires one).

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
