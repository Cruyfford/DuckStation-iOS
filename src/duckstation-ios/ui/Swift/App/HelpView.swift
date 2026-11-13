// HelpView.swift — Practical user guide
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI
import UIKit

struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [HelpItem]
}

struct HelpItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

private enum HelpTopic: Hashable, Identifiable {
    case item(section: Int, item: Int)
    case about

    var id: String {
        switch self {
        case .item(let section, let item):
            return "\(section)-\(item)"
        case .about:
            return "about"
        }
    }
}

// Psxp: PS1 guide.
// The guide is built once, from the main thread, the first time Help is shown.
private func h(_ en: String, _ ar: String) -> String {
    Thread.isMainThread ? MainActor.assumeIsolated { DSLanguage.text(en, ar) }
        : ((Locale.preferredLanguages.first ?? "en").hasPrefix("ar") ? ar : en)
}

private let helpData: [HelpSection] = [
    HelpSection(title: h("Getting Started", "البداية"), icon: "play.circle", items: [
        HelpItem(
            question: h("BIOS", "البايوس"),
            answer: h("Import a PS1 BIOS dumped from your own console (for example SCPH-1001 for USA, SCPH-5500 for Japan, SCPH-7502 for Europe). Psxp picks the BIOS that matches each game's region automatically.",
                      "استورد بايوس PS1 مستخرجاً من جهازك (مثل SCPH-1001 الأمريكي أو SCPH-5500 الياباني أو SCPH-7502 الأوروبي). يختار Psxp البايوس المناسب لمنطقة كل لعبة تلقائياً.")
        ),
        HelpItem(
            question: h("Game formats", "صيغ الألعاب"),
            answer: h("CUE/BIN, CHD, PBP, M3U (multi-disc), ISO, IMG, ECM, MDS/MDF and PS-EXE. For BIN games, import the .cue file too.",
                      "CUE/BIN و CHD و PBP و M3U (الألعاب متعددة الأقراص) و ISO و IMG و ECM و MDS/MDF و PS-EXE. لألعاب BIN استورد ملف cue معها.")
        ),
        HelpItem(
            question: h("Multi-disc games", "الألعاب متعددة الأقراص"),
            answer: h("Use an .m3u playlist or open the in-game menu and choose Change Disc.",
                      "استخدم ملف m3u، أو افتح قائمة اللعبة واختر تغيير القرص.")
        ),
        HelpItem(
            question: h("Covers", "الأغلفة"),
            answer: h("Covers download automatically for PS1 games using the game serial (for example SLUS-00594). You can also import your own images from the Covers menu.",
                      "تُحمّل الأغلفة تلقائياً لألعاب PS1 حسب رقم اللعبة (مثل SLUS-00594)، ويمكنك استيراد صورك من قائمة الأغلفة.")
        ),
    ]),
    HelpSection(title: h("Playing", "اللعب"), icon: "gamecontroller", items: [
        HelpItem(
            question: h("Controller", "يد التحكم"),
            answer: h("Port 1 is a DualShock by default. Games without analog support stay in digital mode, and the stick then moves the D-Pad. Old games that need the original pad can use Digital Pad in Settings › PS1 Controller.",
                      "المنفذ 1 يعمل كـ DualShock افتراضياً. الألعاب التي لا تدعم الأنالوج تبقى على الوضع الرقمي وتحرّك العصا الأسهم. الألعاب القديمة التي تحتاج اليد الأصلية اختر لها اليد الرقمية من الإعدادات › يد تحكم PS1.")
        ),
        HelpItem(
            question: h("Save states", "حفظ الحالة"),
            answer: h("Open the in-game menu to save or load any slot. Your progress is also kept automatically when you leave a game.",
                      "افتح قائمة اللعبة للحفظ أو التحميل من أي خانة. ويُحفظ تقدمك تلقائياً عند الخروج من اللعبة.")
        ),
        HelpItem(
            question: h("Memory cards", "بطاقات الذاكرة"),
            answer: h("Each game gets its own memory card by default, so saves never run out of space. You can change this in Settings › Memory Cards.",
                      "كل لعبة لها بطاقة ذاكرة خاصة افتراضياً فلا تمتلئ البطاقة أبداً. يمكنك تغيير ذلك من الإعدادات › بطاقات الذاكرة.")
        ),
        HelpItem(
            question: h("Cheats", "الغشّات"),
            answer: h("In a game, open the menu and choose Cheats. Load codes from the built-in database, type GameShark codes, or import a .cht file. Cheats are saved per game.",
                      "أثناء اللعب افتح القائمة واختر الغشّات. حمّل الأكواد من قاعدة البيانات المدمجة، أو اكتب أكواد GameShark، أو استورد ملف cht. تُحفظ الغشّات لكل لعبة.")
        ),
    ]),
    HelpSection(title: h("Graphics", "الرسوميات"), icon: "sparkles.tv", items: [
        HelpItem(
            question: h("Resolution scale", "دقة العرض"),
            answer: h("1x is the original PS1 resolution. Higher values look sharper and use more power.",
                      "1x هي دقة PS1 الأصلية. القيم الأعلى أوضح لكنها تستهلك طاقة أكثر.")
        ),
        HelpItem(
            question: h("PGXP", "PGXP"),
            answer: h("Fixes the wobbly polygons and warping textures of the original hardware. Turn it off if a game shows glitches.",
                      "يصلح اهتزاز المضلعات وتشوّه الخامات الموجود في الجهاز الأصلي. أطفئه إذا ظهرت مشاكل في لعبة.")
        ),
        HelpItem(
            question: h("Texture replacement", "استبدال الخامات"),
            answer: h("Put PNG replacements in Files › Psxp › textures › [Game Serial] and turn on replacement in Settings › Texture Replacement.",
                      "ضع ملفات PNG في الملفات › Psxp › textures › [رقم اللعبة] وفعّل الاستبدال من الإعدادات › استبدال الخامات.")
        ),
    ]),
    HelpSection(title: h("Troubleshooting", "حل المشاكل"), icon: "wrench.and.screwdriver", items: [
        HelpItem(
            question: h("A game crashes or freezes", "اللعبة تتوقف أو تعلق"),
            answer: h("Check that the BIOS region matches the game, import the .cue for BIN games, and try turning off PGXP or CPU overclock. The log is in Files › Psxp › duckstation.log and crashes are written to crash.txt.",
                      "تأكد أن منطقة البايوس تطابق اللعبة، واستورد ملف cue لألعاب BIN، وجرّب إطفاء PGXP أو تسريع المعالج. السجل موجود في الملفات › Psxp › duckstation.log والأعطال تُكتب في crash.txt.")
        ),
    ]),
]

struct HelpView: View {
    @State private var settings = SettingsStore.shared
    @State private var copyStatusMessage: String?
    @State private var expandedItemIDs: Set<UUID> = []
#if targetEnvironment(macCatalyst)
    @State private var selectedTopic: HelpTopic? = .item(section: 0, item: 0)
#endif

    static var controllerTargetOrder: [String] {
        helpData.flatMap(\.items).map { targetID($0) }
            + ["settings.help.copy-troubleshooting"]
    }

    private static func targetID(_ item: HelpItem) -> String {
        "settings.help.item.\(item.id.uuidString)"
    }

    private var backgroundConfigured: Bool {
        settings.hasCustomBackground && settings.backgroundEnabledInSettings
    }

    private var backgroundActive: Bool {
        backgroundConfigured
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        NavigationSplitView {
            List(selection: $selectedTopic) {
                ForEach(helpData.indices, id: \.self) { sectionIndex in
                    let section = helpData[sectionIndex]
                    Section {
                        ForEach(section.items.indices, id: \.self) { itemIndex in
                            let item = section.items[itemIndex]
                            Text(settings.localized(item.question))
                                .tag(HelpTopic.item(section: sectionIndex, item: itemIndex))
                        }
                    } header: {
                        Label(settings.localized(section.title), systemImage: section.icon)
                    }
                }

                Section {
                    Label(settings.localized("Version"), systemImage: "info.circle")
                        .tag(HelpTopic.about)
                } header: {
                    Text(settings.localized("About"))
                }
            }
            .navigationTitle(settings.localized("Help"))
            .listStyle(.sidebar)
        } detail: {
            helpDetail(for: selectedTopic)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .containerBackground(backgroundActive ? Color.clear : Color(uiColor: .systemGroupedBackground), for: .navigation)
#else
        List {
            ForEach(helpData) { section in
                Section {
                    ForEach(section.items) { item in
                        DisclosureGroup(isExpanded: expandedBinding(for: item)) {
                            Text(settings.localized(item.answer))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } label: {
                            Text(settings.localized(item.question))
                                .font(.body)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                                .controllerAccessibilityActionTarget(
                                    label: settings.localized(item.question)
                                ) {
                                    toggle(item)
                                }
                        }
                        .controllerAccessibilityTargetID(Self.targetID(item))
                    }
                } header: {
                    Label(settings.localized(section.title), systemImage: section.icon)
                }
            }

            Section {
                HStack {
                    Text(settings.localized("Version"))
                    Spacer()
                    Text(ARMSX2Bridge.buildVersion())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Button {
                    copyTroubleshootingInfo()
                } label: {
                    Label(settings.localized("Copy Troubleshooting Info"), systemImage: "doc.on.doc")
                }
                .controllerAccessibilityActionTarget(
                    id: "settings.help.copy-troubleshooting",
                    label: settings.localized("Copy Troubleshooting Info")
                ) {
                    copyTroubleshootingInfo()
                }
                if let copyStatusMessage {
                    Text(settings.localized(copyStatusMessage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label(settings.localized("About"), systemImage: "info.circle")
            }
        }
        .controllerAccessibilityTargetOrder(Self.controllerTargetOrder)
        .navigationTitle(settings.localized("Help"))
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func expandedBinding(for item: HelpItem) -> Binding<Bool> {
        Binding(
            get: { expandedItemIDs.contains(item.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedItemIDs.insert(item.id)
                } else {
                    expandedItemIDs.remove(item.id)
                }
            }
        )
    }

    private func toggle(_ item: HelpItem) {
        if expandedItemIDs.contains(item.id) {
            expandedItemIDs.remove(item.id)
        } else {
            expandedItemIDs.insert(item.id)
        }
    }

    @ViewBuilder
    private func helpDetail(for topic: HelpTopic?) -> some View {
        switch topic {
        case .item(let sectionIndex, let itemIndex):
            let section = helpData[sectionIndex]
            let item = section.items[itemIndex]

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(settings.localized(section.title), systemImage: section.icon)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(settings.localized(item.question))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text(settings.localized(item.answer))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(settings.localized(item.question))

        case .about:
            Form {
                Section(settings.localized("App")) {
                    HStack {
                        Text(settings.localized("Version"))
                        Spacer()
                        Text(ARMSX2Bridge.buildVersion())
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Button {
                        copyTroubleshootingInfo()
                    } label: {
                        Label(settings.localized("Copy Troubleshooting Info"), systemImage: "doc.on.doc")
                    }
                    if let copyStatusMessage {
                        Text(settings.localized(copyStatusMessage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(settings.localized("About"))

        case .none:
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text(settings.localized("Select a help topic"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copyTroubleshootingInfo() {
        UIPasteboard.general.string = troubleshootingInfoText()
        copyStatusMessage = "Troubleshooting info copied."
    }

    private func troubleshootingInfoText() -> String {
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Psxp"
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let device = UIDevice.current

        return [
            "App: \(appName)",
            "Version: \(appVersion)",
            "Build: \(buildNumber)",
            "Platform: iOS",
            "iOS Version: \(device.systemVersion)",
            "Device Type: \(device.model)"
        ].joined(separator: "\n")
    }
}
