// DSSettingsViews.swift — renders DSSettingsSchema; reads and writes DuckStation's settings.ini
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

@MainActor
enum DSLanguage {
    static var isArabic: Bool {
        let lang = SettingsStore.shared.appLanguage
        if lang == .system {
            return (Locale.preferredLanguages.first ?? "en").hasPrefix("ar")
        }
        return lang == .arabic
    }

    static func text(_ t: DSText) -> String { isArabic ? t.ar : t.en }
    static func text(_ en: String, _ ar: String) -> String { isArabic ? ar : en }
}

@MainActor
private enum DSINI {
    static func bool(_ s: DSSetting, _ def: Bool) -> Bool {
        ARMSX2Bridge.getINIBool(s.section, key: s.key, defaultValue: def)
    }
    static func string(_ s: DSSetting, _ def: String) -> String {
        ARMSX2Bridge.getINIString(s.section, key: s.key, defaultValue: def)
    }
    static func int(_ section: String, _ key: String, _ def: Int) -> Int {
        Int(ARMSX2Bridge.getINIInt(section, key: key, defaultValue: Int32(def)))
    }
    static func float(_ s: DSSetting, _ def: Double) -> Double {
        Double(ARMSX2Bridge.getINIFloat(s.section, key: s.key, defaultValue: Float(def)))
    }

    static func apply() {
        ARMSX2Bridge.applyGraphicsSettingsNow()
    }
}

// MARK: - Root rows (inserted into the main settings list)

/// The DuckStation categories, as navigation rows for the main Settings list.
struct DSSettingsCategoryRows: View {
    var body: some View {
        ForEach(DSSettingsSchema.categories) { category in
            NavigationLink {
                DSSettingsCategoryView(category: category)
            } label: {
                Label(DSLanguage.text(category.title), systemImage: category.icon)
            }
        }
    }
}

// MARK: - Category screen

struct DSSettingsCategoryView: View {
    let category: DSSettingsCategory
    @State private var refreshID = UUID()
    @State private var confirmReset = false

    var body: some View {
        List {
            if category.showsBIOSList {
                DSBIOSListSection()
            }
            ForEach(category.groups) { group in
                Section(DSLanguage.text(group.title)) {
                    ForEach(group.settings) { setting in
                        DSSettingRow(setting: setting)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label(DSLanguage.text("Reset to Defaults", "استعادة الإعدادات الافتراضية"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .id(refreshID)
        .environment(\.layoutDirection, DSLanguage.isArabic ? .rightToLeft : .leftToRight)
        .navigationTitle(DSLanguage.text(category.title))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(DSLanguage.text("Reset these settings to their defaults?", "استعادة هذه الإعدادات إلى قيمها الافتراضية؟"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(DSLanguage.text("Reset", "استعادة"), role: .destructive) { resetCategory() }
        }
    }

    private func resetCategory() {
        for group in category.groups {
            for s in group.settings {
                switch s.kind {
                case .toggle(let def):
                    ARMSX2Bridge.setINIBool(s.section, key: s.key, value: def)
                case .choice(let def, _):
                    ARMSX2Bridge.setINIString(s.section, key: s.key, value: def)
                case .int(let def, _, _, _, _):
                    ARMSX2Bridge.setINIInt(s.section, key: s.key, value: Int32(def))
                case .float(let def, _, _, _, _):
                    ARMSX2Bridge.setINIFloat(s.section, key: s.key, value: Float(def))
                case .overclock:
                    ARMSX2Bridge.setINIInt("CPU", key: "OverclockNumerator", value: 1)
                    ARMSX2Bridge.setINIInt("CPU", key: "OverclockDenominator", value: 1)
                }
            }
        }
        DSINI.apply()
        refreshID = UUID()
    }
}

// MARK: - Rows

struct DSSettingRow: View {
    let setting: DSSetting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            if let help = setting.help {
                Text(DSLanguage.text(help))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch setting.kind {
        case .toggle(let def):
            DSToggleRow(setting: setting, defaultValue: def)
        case .choice(let def, let options):
            DSChoiceRow(setting: setting, defaultValue: def, options: options)
        case .int(let def, let min, let max, let step, let unit):
            DSNumberRow(setting: setting, defaultValue: Double(def), range: Double(min)...Double(max),
                        step: Double(step), unit: unit, isInteger: true)
        case .float(let def, let min, let max, let step, let unit):
            DSNumberRow(setting: setting, defaultValue: def, range: min...max, step: step, unit: unit, isInteger: false)
        case .overclock:
            DSOverclockRow(title: DSLanguage.text(setting.title))
        }
    }
}

private struct DSToggleRow: View {
    let setting: DSSetting
    let defaultValue: Bool
    @State private var value = false

    var body: some View {
        Toggle(DSLanguage.text(setting.title), isOn: $value)
            .onAppear { value = DSINI.bool(setting, defaultValue) }
            .onChange(of: value) { _, newValue in
                guard newValue != DSINI.bool(setting, defaultValue) else { return }
                ARMSX2Bridge.setINIBool(setting.section, key: setting.key, value: newValue)
                DSINI.apply()
            }
    }
}

private struct DSChoiceRow: View {
    let setting: DSSetting
    let defaultValue: String
    let options: [DSOption]
    @State private var value = ""

    var body: some View {
        Picker(DSLanguage.text(setting.title), selection: $value) {
            ForEach(options) { option in
                Text(DSLanguage.text(option.label)).tag(option.value)
            }
        }
        .pickerStyle(.navigationLink)
        .onAppear {
            let stored = DSINI.string(setting, defaultValue)
            value = options.contains(where: { $0.value == stored }) ? stored : defaultValue
        }
        .onChange(of: value) { _, newValue in
            guard !newValue.isEmpty, newValue != DSINI.string(setting, defaultValue) else { return }
            ARMSX2Bridge.setINIString(setting.section, key: setting.key, value: newValue)
            DSINI.apply()
        }
    }
}

private struct DSNumberRow: View {
    let setting: DSSetting
    let defaultValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let isInteger: Bool
    @State private var value: Double = 0
    @State private var loaded = false

    private var formatted: String {
        let number = isInteger ? String(Int(value)) : String(format: step < 1 ? "%.1f" : "%.0f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private var usesSlider: Bool { (range.upperBound - range.lowerBound) / step > 24 }

    var body: some View {
        Group {
            if usesSlider {
                VStack(alignment: .leading) {
                    HStack {
                        Text(DSLanguage.text(setting.title))
                        Spacer()
                        Text(formatted).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $value, in: range, step: step) { editing in
                        if !editing { save() }
                    }
                }
            } else {
                Stepper(value: $value, in: range, step: step) {
                    HStack {
                        Text(DSLanguage.text(setting.title))
                        Spacer()
                        Text(formatted).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .onChange(of: value) { _, _ in
                    if loaded { save() }
                }
            }
        }
        .onAppear {
            if isInteger {
                value = Double(DSINI.int(setting.section, setting.key, Int(defaultValue)))
            } else {
                value = DSINI.float(setting, defaultValue)
            }
            DispatchQueue.main.async { loaded = true }
        }
    }

    private func save() {
        if isInteger {
            ARMSX2Bridge.setINIInt(setting.section, key: setting.key, value: Int32(value.rounded()))
        } else {
            ARMSX2Bridge.setINIFloat(setting.section, key: setting.key, value: Float(value))
        }
        DSINI.apply()
    }
}

private struct DSOverclockRow: View {
    let title: String
    @State private var percent = 100
    private static let choices = [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 500, 600]

    var body: some View {
        Picker(title, selection: $percent) {
            ForEach(Self.choices, id: \.self) { p in
                Text("\(p)%").tag(p)
            }
        }
        .pickerStyle(.navigationLink)
        .onAppear {
            let num = DSINI.int("CPU", "OverclockNumerator", 1)
            let den = max(DSINI.int("CPU", "OverclockDenominator", 1), 1)
            let current = Int((Double(num) / Double(den) * 100).rounded())
            percent = Self.choices.min(by: { abs($0 - current) < abs($1 - current) }) ?? 100
        }
        .onChange(of: percent) { _, newValue in
            let g = gcd(newValue, 100)
            ARMSX2Bridge.setINIInt("CPU", key: "OverclockNumerator", value: Int32(newValue / g))
            ARMSX2Bridge.setINIInt("CPU", key: "OverclockDenominator", value: Int32(100 / g))
            DSINI.apply()
        }
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

// MARK: - BIOS list

private struct DSBIOSListSection: View {
    @State private var bioses: [ARMSX2BIOSInfo] = []

    var body: some View {
        Section {
            if bioses.isEmpty {
                Label(DSLanguage.text("No BIOS found. Import a PS1 BIOS (e.g. SCPH-1001.BIN) into the BIOS folder.",
                                      "لم يتم العثور على بايوس. استورد بايوس PS1 (مثل SCPH-1001.BIN) إلى مجلد BIOS."),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                ForEach(bioses, id: \.filePath) { bios in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bios.fileName).font(.body.weight(.semibold))
                        Text(bios.descriptionText).font(.footnote).foregroundStyle(.secondary)
                        if !bios.regionName.isEmpty {
                            Text(bios.regionName).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        } header: {
            Text(DSLanguage.text("Installed BIOS Images", "ملفات البايوس الموجودة"))
        } footer: {
            Text(DSLanguage.text("DuckStation picks the BIOS that matches each game's region automatically.",
                                 "يختار DuckStation البايوس المناسب لمنطقة كل لعبة تلقائياً."))
        }
        .onAppear { bioses = ARMSX2Bridge.availableBIOSInfos() }
    }
}
