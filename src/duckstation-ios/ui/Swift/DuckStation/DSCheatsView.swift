// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// PS1 cheat manager for the running game: GameShark codes, the built-in cheat database,
// and imported .cht files (PCSXR / libretro / ePSXe formats).

import SwiftUI
import UniformTypeIdentifiers

struct DSCheatItem: Identifiable, Sendable, Equatable {
    let index: Int
    let name: String
    let group: String
    let code: String
    var enabled: Bool
    let manual: Bool
    var id: Int { index }
}

private enum DSCheatsBackend {
    static func items(_ entries: [DSCheatEntry]) -> [DSCheatItem] {
        entries.map {
            DSCheatItem(index: $0.index, name: $0.name, group: $0.group, code: $0.code,
                        enabled: $0.enabled, manual: $0.manual)
        }
    }

    static func load() async -> [DSCheatItem] {
        await Task.detached(priority: .userInitiated) { items(DSCheats.loadCheats()) }.value
    }

    static func running() async -> Bool {
        await Task.detached(priority: .userInitiated) { DSCheats.isGameRunning() }.value
    }
}

struct DSCheatsView: View {
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var cheats: [DSCheatItem] = []
    @State private var gameRunning = true
    @State private var loading = true
    @State private var showingAdd = false
    @State private var showingImporter = false
    @State private var confirmRemoveAll = false
    @State private var message: String?

    private func t(_ en: String, _ ar: String) -> String { DSLanguage.text(en, ar) }

    private struct CheatGroup: Identifiable {
        let name: String
        let items: [DSCheatItem]
        var id: String { name }
    }

    private var groups: [CheatGroup] {
        var order: [String] = []
        var map: [String: [DSCheatItem]] = [:]
        for cheat in cheats {
            if map[cheat.group] == nil { order.append(cheat.group) }
            map[cheat.group, default: []].append(cheat)
        }
        return order.map { CheatGroup(name: $0, items: map[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !gameRunning {
                    Section {
                        Label(t("Start a game to manage its cheats.", "شغّل لعبة لإدارة الغشّات الخاصة بها."),
                              systemImage: "gamecontroller")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    actionsSection
                    if cheats.isEmpty && !loading {
                        Section {
                            Text(t("No cheats yet. Load them from the database, add a GameShark code, or import a .cht file.",
                                   "لا توجد غشّات بعد. حمّلها من قاعدة البيانات، أو أضف كود GameShark، أو استورد ملف cht."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(groups) { group in
                        let items = group.items
                        Section(group.name.isEmpty ? t("Cheats", "الغشّات") : group.name) {
                            ForEach(items) { cheat in
                                row(cheat)
                            }
                            .onDelete { offsets in
                                let indices = offsets.map { items[$0].index }.sorted(by: >)
                                Task { await remove(indices) }
                            }
                        }
                    }
                    if !cheats.isEmpty {
                        Section {
                            Button(t("Remove All Cheats", "حذف كل الغشّات"), role: .destructive) {
                                confirmRemoveAll = true
                            }
                        }
                    }
                }
            }
            .navigationTitle(t("Cheats", "الغشّات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "تم")) {
                        if let onClose { onClose() } else { dismiss() }
                    }
                }
            }
            .overlay {
                if loading { ProgressView() }
            }
            .task { await reload() }
            .sheet(isPresented: $showingAdd) {
                DSAddCheatView { name, group, code in
                    await add(name: name, group: group, code: code)
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.plainText, .text, .data],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await importFile(url) }
                }
            }
            .confirmationDialog(t("Remove all cheats for this game?", "حذف كل غشّات هذه اللعبة؟"),
                                isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button(t("Remove All", "حذف الكل"), role: .destructive) {
                    Task { await removeAll() }
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(t("OK", "حسناً"), role: .cancel) {}
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await loadDatabase() }
            } label: {
                Label(t("Load From Cheat Database", "تحميل من قاعدة بيانات الغشّات"), systemImage: "tray.and.arrow.down")
            }
            Button {
                showingAdd = true
            } label: {
                Label(t("Add GameShark Code", "إضافة كود GameShark"), systemImage: "plus.circle")
            }
            Button {
                showingImporter = true
            } label: {
                Label(t("Import Cheat File (.cht)", "استيراد ملف غشّات (.cht)"), systemImage: "doc.badge.plus")
            }
        } footer: {
            Text(t("Cheats are saved per game and stay on until you turn them off.",
                   "تُحفظ الغشّات لكل لعبة وتبقى مفعّلة حتى تطفئها."))
        }
    }

    @ViewBuilder
    private func row(_ cheat: DSCheatItem) -> some View {
        if cheat.manual {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheat.name)
                    Text(cheat.code).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(t("Apply", "تطبيق")) {
                    let index = cheat.index
                    Task.detached { DSCheats.applyCheat(at: index) }
                }
                .buttonStyle(.bordered)
            }
        } else {
            Toggle(isOn: Binding(
                get: { cheat.enabled },
                set: { newValue in Task { await setEnabled(cheat.index, newValue) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cheat.name)
                    Text(cheat.code).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    // MARK: Actions

    private func reload() async {
        loading = true
        gameRunning = await DSCheatsBackend.running()
        cheats = gameRunning ? await DSCheatsBackend.load() : []
        loading = false
    }

    private func setEnabled(_ index: Int, _ enabled: Bool) async {
        if let i = cheats.firstIndex(where: { $0.index == index }) { cheats[i].enabled = enabled }
        await Task.detached { DSCheats.setCheatAt(index, enabled: enabled) }.value
    }

    private func loadDatabase() async {
        loading = true
        let count = await Task.detached { DSCheats.loadFromDatabase() }.value
        await reload()
        message = count > 0
            ? t("Loaded \(count) cheats from the database.", "تم تحميل \(count) غشّ من قاعدة البيانات.")
            : t("No cheats for this game in the database.", "لا توجد غشّات لهذه اللعبة في قاعدة البيانات.")
    }

    private func add(name: String, group: String, code: String) async -> Bool {
        let ok = await Task.detached { DSCheats.addCheatNamed(name, group: group, code: code) }.value
        if ok { await reload() }
        return ok
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: temp)
        do {
            try FileManager.default.copyItem(at: url, to: temp)
        } catch {
            message = t("Couldn't read the file.", "تعذّرت قراءة الملف.")
            return
        }
        let path = temp.path
        let added = await Task.detached { DSCheats.importCheatFile(path) }.value
        try? FileManager.default.removeItem(at: temp)
        await reload()
        message = added >= 0
            ? t("Imported \(added) cheats.", "تم استيراد \(added) غشّ.")
            : t("This file isn't a supported cheat file.", "هذا الملف ليس ملف غشّات مدعوماً.")
    }

    private func remove(_ indices: [Int]) async {
        await Task.detached {
            for index in indices { DSCheats.removeCheat(at: index) }
        }.value
        await reload()
    }

    private func removeAll() async {
        await Task.detached { DSCheats.removeAllCheats() }.value
        await reload()
    }
}

private struct DSAddCheatView: View {
    let onAdd: (String, String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = ""
    @State private var code = ""
    @State private var failed = false
    @State private var saving = false

    private func t(_ en: String, _ ar: String) -> String { DSLanguage.text(en, ar) }

    var body: some View {
        NavigationStack {
            Form {
                Section(t("Name", "الاسم")) {
                    TextField(t("Infinite Health", "صحة لا نهائية"), text: $name)
                }
                Section(t("Group (optional)", "المجموعة (اختياري)")) {
                    TextField(t("Player", "اللاعب"), text: $group)
                }
                Section {
                    TextEditor(text: $code)
                        .font(.body.monospaced())
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text(t("GameShark Code", "كود GameShark"))
                } footer: {
                    Text(t("One code per line, for example: 8009C6E4 0FFF",
                           "كود في كل سطر، مثال: 8009C6E4 0FFF"))
                }
                if failed {
                    Text(t("That code couldn't be read. Check the format.", "تعذّرت قراءة الكود. تأكد من الصيغة."))
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(t("Add Code", "إضافة كود"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "إلغاء")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Add", "إضافة")) {
                        saving = true
                        Task {
                            let ok = await onAdd(name, group, code)
                            saving = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(saving || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
