// DSInGameSettingsView.swift — DuckStation settings as a panel (in-game menu / game context menu)
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI

struct DSInGameSettingsView: View {
    let onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DSSettingsCategoryRows()
                } footer: {
                    Text(DSLanguage.text("Changes apply immediately and are shared by all games.",
                                         "التغييرات تُطبَّق فوراً وتشمل كل الألعاب."))
                }
            }
            .environment(\.layoutDirection, DSLanguage.isArabic ? .rightToLeft : .leftToRight)
            .navigationTitle(DSLanguage.text("Settings", "الإعدادات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DSLanguage.text("Done", "تم")) {
                        if let onDone { onDone() } else { dismiss() }
                    }
                }
            }
        }
    }
}

struct DSUnavailableView: View {
    let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(DSLanguage.text("Not available for PlayStation 1 games yet.", "غير متوفر لألعاب بلايستيشن 1 حالياً."))
                .multilineTextAlignment(.center)
            Button(DSLanguage.text("Close", "إغلاق")) {
                if let onClose { onClose() } else { dismiss() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
