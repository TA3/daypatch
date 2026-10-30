// The DayPatch window: status, feature health and settings in one place. Opens when
// you launch DayPatch from Applications (and from the menu bar item).
import SwiftUI

struct DayPatchWindowView: View {
    @ObservedObject var c: Controller

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Group {
                section("Patched Dia") { patchedRows }
                section("Updates") { updateRows }
                if let h = c.health { section("Features") { healthRows(h) } }
                section("Settings") { settingsRows }
            }
            footer
        }
        .padding(22)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: DayPatchIcon.appIcon(size: 128)).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("DayPatch").font(.system(size: 20, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    Text(c.busy ?? c.attention ?? (c.status.isUpToDate ? "Everything's up to date" : c.statusLine))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var dotColor: Color {
        if c.busy != nil { return .blue }
        if c.attention != nil { return .orange }
        if case .upToDate = c.status.state { return .green }
        return .orange
    }

    // MARK: Sections

    @ViewBuilder private var patchedRows: some View {
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.statusLine)
                Text("daypatch \(c.engine.patchVersion)" + (c.status.patchedFrom.map { " · built from Dia \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } trailing: {
            Button("Open") { c.openPatchedDia() }
        }
        Divider().padding(.leading, 14)
        row {
            Text(c.status.isUpToDate ? "Rebuild from the installed Dia" : "Patch now")
        } trailing: {
            Button(c.status.isUpToDate ? "Rebuild" : "Patch") { c.repatch() }.disabled(c.busy != nil)
        }
    }

    @ViewBuilder private var updateRows: some View {
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.selfUpdate.map { "DayPatch \($0.version) is available" } ?? "DayPatch \(SelfUpdater.currentVersion)")
                Text(c.selfUpdateChecking ? "Checking GitHub…" : (c.selfUpdateResult ?? "Updates come from GitHub Releases and are signature-checked."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if let r = c.selfUpdate {
                Button("Install") { c.installSelfUpdate(r) }.disabled(c.busy != nil)
            } else {
                Button("Check") { c.checkSelfUpdate(manual: true) }.disabled(c.selfUpdateChecking)
            }
        }
        Divider().padding(.leading, 14)
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dia updates itself")
                Text(c.updateHint ?? "Open the regular Dia and use its own updater. DayPatch re-patches when Dia changes.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Button("Update Dia…") { c.updateDia() }.disabled(c.busy != nil)
        }
        if let e = c.lastError {
            Divider().padding(.leading, 14)
            row {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(3)
            } trailing: {
                Button("Dismiss") { c.clearError() }
            }
        }
    }

    @ViewBuilder private func healthRows(_ h: Health) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 7) {
                ForEach(h.checks, id: \.name) { check in
                    Label {
                        Text(check.name).foregroundStyle(check.ok ? .primary : .secondary)
                    } icon: {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.ok ? .green : .red)
                    }
                    .font(.callout)
                }
            }
            HStack {
                Text("Checked when Patched Dia last opened (Dia \(h.diaVersion))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if h.failures > 0, h.date != Prefs.dismissedHealthDate {
                    Button("Dismiss") { c.dismissHealth() }.controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder private var settingsRows: some View {
        row { Text("Patch automatically") } trailing: { Toggle("", isOn: $c.autoRepatch).labelsHidden().toggleStyle(.switch).controlSize(.small) }
        Divider().padding(.leading, 14)
        row { Text("Update DayPatch automatically") } trailing: { Toggle("", isOn: $c.autoUpdateSelf).labelsHidden().toggleStyle(.switch).controlSize(.small) }
        Divider().padding(.leading, 14)
        row {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show in menu bar")
                Text(modeDetail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Picker("", selection: $c.menuBarMode) {
                ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
        }
        if c.menuBarMode == .always {
            Divider().padding(.leading, 14)
            row { Text("Open at login") } trailing: { Toggle("", isOn: $c.openAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.small) }
        }
    }

    private var modeDetail: String {
        switch c.menuBarMode {
        case .always: return "DayPatch stays in the menu bar."
        case .whenNeeded: return "Works in the background; the icon appears only when something needs you."
        case .never: return "Works in the background and sends notifications. Open DayPatch to see this window."
        }
    }

    private var footer: some View {
        HStack {
            Text("daypatch \(c.engine.patchVersion)").foregroundStyle(.secondary)
            Spacer()
            Button("Quit DayPatch") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        }
    }

    private func row<L: View, T: View>(@ViewBuilder _ leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 16) {
            leading().frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }
}
