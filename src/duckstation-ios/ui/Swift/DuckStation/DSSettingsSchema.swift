// DSSettingsSchema.swift — every user-facing DuckStation setting, grouped like DuckStation's own settings
// SPDX-License-Identifier: GPL-3.0+
//
// Keys, defaults and option values match DuckStation's Settings::Load (src/core/settings.cpp),
// so the core reads exactly what these screens write. Labels are English / Arabic.

import Foundation

struct DSText: Sendable, Hashable {
    let en: String
    let ar: String
    init(_ en: String, _ ar: String) { self.en = en; self.ar = ar }
}

struct DSOption: Sendable, Hashable, Identifiable {
    let value: String
    let label: DSText
    var id: String { value }
    init(_ value: String, _ en: String, _ ar: String) {
        self.value = value
        self.label = DSText(en, ar)
    }
}

enum DSSettingKind: Sendable, Hashable {
    case toggle(default: Bool)
    case choice(default: String, options: [DSOption])
    case int(default: Int, min: Int, max: Int, step: Int, unit: String)
    case float(default: Double, min: Double, max: Double, step: Double, unit: String)
    /// CPU overclock: writes OverclockNumerator/OverclockDenominator as a percentage.
    case overclock
}

struct DSSetting: Sendable, Hashable, Identifiable {
    let section: String
    let key: String
    let title: DSText
    let help: DSText?
    let kind: DSSettingKind
    var id: String { "\(section)/\(key)" }

    init(_ section: String, _ key: String, _ title: DSText, _ kind: DSSettingKind, help: DSText? = nil) {
        self.section = section
        self.key = key
        self.title = title
        self.kind = kind
        self.help = help
    }
}

struct DSSettingsGroup: Sendable, Hashable, Identifiable {
    let title: DSText
    let settings: [DSSetting]
    var id: String { title.en }
}

struct DSSettingsCategory: Sendable, Hashable, Identifiable {
    let id: String
    let title: DSText
    let icon: String
    let groups: [DSSettingsGroup]
    /// Extra content shown above the groups (e.g. the BIOS list).
    let showsBIOSList: Bool

    init(_ id: String, _ title: DSText, icon: String, showsBIOSList: Bool = false, _ groups: [DSSettingsGroup]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.groups = groups
        self.showsBIOSList = showsBIOSList
    }
}

// MARK: - Shared option lists

private let textureFilterOptions: [DSOption] = [
    DSOption("Nearest", "Nearest-Neighbor", "أقرب بكسل (بدون تنعيم)"),
    DSOption("Bilinear", "Bilinear", "ثنائي الخطية"),
    DSOption("BilinearBinAlpha", "Bilinear (No Edge Blending)", "ثنائي الخطية (بدون دمج الحواف)"),
    DSOption("JINC2", "JINC2 (Slow)", "JINC2 (بطيء)"),
    DSOption("JINC2BinAlpha", "JINC2 (Slow, No Edge Blending)", "JINC2 (بطيء، بدون دمج الحواف)"),
    DSOption("xBR", "xBR (Very Slow)", "xBR (بطيء جداً)"),
    DSOption("xBRBinAlpha", "xBR (Very Slow, No Edge Blending)", "xBR (بطيء جداً، بدون دمج الحواف)"),
]

private let memoryCardTypeOptions: [DSOption] = [
    DSOption("None", "No Memory Card", "بدون بطاقة ذاكرة"),
    DSOption("Shared", "Shared Between All Games", "بطاقة مشتركة لكل الألعاب"),
    DSOption("PerGame", "Separate Card Per Game (Serial)", "بطاقة لكل لعبة (حسب الرقم التسلسلي)"),
    DSOption("PerGameTitle", "Separate Card Per Game (Title)", "بطاقة لكل لعبة (حسب الاسم)"),
    DSOption("PerGameFileTitle", "Separate Card Per Game (File Title)", "بطاقة لكل لعبة (حسب اسم الملف)"),
    DSOption("NonPersistent", "Non-Persistent Card (Do Not Save)", "بطاقة مؤقتة (لا تحفظ)"),
]

private func speedOptions(includeUnlimited: Bool, includeDefault: Bool) -> [DSOption] {
    var options: [DSOption] = []
    if includeDefault {
        options.append(DSOption("0", "Same as Normal Speed", "نفس السرعة العادية"))
    }
    for percent in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000] {
        let value = String(format: "%g", Double(percent) / 100.0)
        options.append(DSOption(value, "\(percent)%", "\(percent)٪"))
    }
    if includeUnlimited {
        options.append(DSOption(includeDefault ? "-1" : "0", "Unlimited", "بلا حدود"))
    }
    return options
}

private func multiplierOptions(_ range: ClosedRange<Int>, labelForOne: DSText, zero: DSText? = nil) -> [DSOption] {
    var options: [DSOption] = []
    if let zero { options.append(DSOption("0", zero.en, zero.ar)) }
    for i in range {
        if i == 1 {
            options.append(DSOption("1", labelForOne.en, labelForOne.ar))
        } else {
            options.append(DSOption("\(i)", "\(i)x", "\(i)x"))
        }
    }
    return options
}

// MARK: - Categories

enum DSSettingsSchema {
    static let categories: [DSSettingsCategory] = [console, emulation, bios, memoryCards, graphics, pgxp, display, osd, audio, textures, advanced, debug]

    static let console = DSSettingsCategory("console", DSText("Console", "الجهاز"), icon: "playstation.logo", [
        DSSettingsGroup(title: DSText("Console", "الجهاز"), settings: [
            DSSetting("Console", "Region", DSText("Region", "المنطقة"), .choice(default: "Auto", options: [
                DSOption("Auto", "Auto-Detect", "تلقائي حسب اللعبة"),
                DSOption("NTSC-J", "NTSC-J (Japan)", "NTSC-J (اليابان)"),
                DSOption("NTSC-U", "NTSC-U/C (US, Canada)", "NTSC-U/C (أمريكا، كندا)"),
                DSOption("PAL", "PAL (Europe, Australia)", "PAL (أوروبا، أستراليا)"),
            ])),
            DSSetting("Console", "Enable8MBRAM", DSText("Enable 8MB RAM (Dev Console)", "ذاكرة 8 ميغا (جهاز المطورين)"), .toggle(default: false),
                      help: DSText("Some homebrew and mods need it. Retail games don't.", "تحتاجها بعض التعديلات والبرامج المنزلية فقط.")),
        ]),
        DSSettingsGroup(title: DSText("CPU", "المعالج"), settings: [
            DSSetting("CPU", "ExecutionMode", DSText("Execution Mode", "طريقة التنفيذ"), .choice(default: "CachedInterpreter", options: [
                DSOption("CachedInterpreter", "Cached Interpreter (Faster)", "مفسّر مع ذاكرة مؤقتة (أسرع)"),
                DSOption("Interpreter", "Interpreter (Slowest, Most Accurate)", "مفسّر (الأبطأ، الأدق)"),
            ]), help: DSText("iOS doesn't allow the recompiler without JIT.", "iOS لا يسمح بالمترجم الديناميكي بدون JIT.")),
            DSSetting("CPU", "OverclockEnable", DSText("Enable Clock Speed Control", "تفعيل التحكم بسرعة المعالج"), .toggle(default: false),
                      help: DSText("Overclocking can reduce slowdowns in some games, and break others.", "رفع السرعة قد يقلل البطء في بعض الألعاب وقد يكسر ألعاباً أخرى.")),
            DSSetting("CPU", "Overclock", DSText("Clock Speed", "سرعة المعالج"), .overclock),
        ]),
        DSSettingsGroup(title: DSText("CD-ROM", "قارئ الأقراص"), settings: [
            DSSetting("CDROM", "ReadSpeedup", DSText("Read Speedup", "تسريع القراءة"),
                      .choice(default: "1", options: multiplierOptions(2...10, labelForOne: DSText("None (Double Speed)", "بدون (السرعة الأصلية)"),
                                                                      zero: DSText("Maximum (Unlimited)", "أقصى سرعة")))),
            DSSetting("CDROM", "SeekSpeedup", DSText("Seek Speedup", "تسريع البحث"),
                      .choice(default: "1", options: multiplierOptions(2...10, labelForOne: DSText("None (Normal Speed)", "بدون (السرعة الأصلية)"),
                                                                      zero: DSText("Infinite/Instantaneous", "فوري")))),
            DSSetting("CDROM", "ReadaheadSectors", DSText("Readahead Sectors", "قطاعات القراءة المسبقة"), .int(default: 8, min: 0, max: 32, step: 1, unit: "")),
            DSSetting("CDROM", "RegionCheck", DSText("Enable Region Check", "تفعيل فحص المنطقة"), .toggle(default: false)),
            DSSetting("CDROM", "LoadImageToRAM", DSText("Preload Image to RAM", "تحميل القرص إلى الذاكرة"), .toggle(default: false)),
            DSSetting("CDROM", "LoadImagePatches", DSText("Apply Image Patches (PPF)", "تطبيق باتشات القرص (PPF)"), .toggle(default: false)),
            DSSetting("CDROM", "MuteCDAudio", DSText("Mute CD Audio", "كتم صوت القرص"), .toggle(default: false)),
        ]),
    ])

    static let emulation = DSSettingsCategory("emulation", DSText("Emulation", "المحاكاة"), icon: "gauge.with.dots.needle.67percent", [
        DSSettingsGroup(title: DSText("Speed Control", "التحكم بالسرعة"), settings: [
            DSSetting("Main", "EmulationSpeed", DSText("Emulation Speed", "سرعة المحاكاة"),
                      .choice(default: "1", options: speedOptions(includeUnlimited: true, includeDefault: false))),
            DSSetting("Main", "FastForwardSpeed", DSText("Fast Forward Speed", "سرعة التقديم السريع"),
                      .choice(default: "0", options: speedOptions(includeUnlimited: true, includeDefault: true))),
            DSSetting("Main", "TurboSpeed", DSText("Turbo Speed", "سرعة التيربو"),
                      .choice(default: "0", options: speedOptions(includeUnlimited: true, includeDefault: true))),
            DSSetting("Main", "SyncToHostRefreshRate", DSText("Sync To Host Refresh Rate", "المزامنة مع معدل تحديث الشاشة"), .toggle(default: false)),
        ]),
        DSSettingsGroup(title: DSText("Latency & Rewind", "التأخير والترجيع"), settings: [
            DSSetting("Main", "RunaheadFrameCount", DSText("Runahead Frames", "إطارات السبق (Runahead)"), .int(default: 0, min: 0, max: 10, step: 1, unit: ""),
                      help: DSText("Reduces input lag, costs a lot of CPU.", "يقلل تأخير الأزرار لكنه يستهلك المعالج كثيراً.")),
            DSSetting("Main", "RewindEnable", DSText("Enable Rewind", "تفعيل الترجيع"), .toggle(default: false)),
            DSSetting("Main", "RewindFrequency", DSText("Rewind Save Frequency", "تكرار حفظ الترجيع"), .float(default: 10, min: 0.1, max: 60, step: 0.5, unit: "s")),
            DSSetting("Main", "RewindSaveSlots", DSText("Rewind Save Slots", "خانات الترجيع"), .int(default: 10, min: 1, max: 300, step: 1, unit: "")),
        ]),
        DSSettingsGroup(title: DSText("Save States", "حفظ الحالة"), settings: [
            DSSetting("Main", "SaveStateOnExit", DSText("Save State On Exit", "حفظ الحالة عند الخروج"), .toggle(default: true)),
            DSSetting("Main", "CreateSaveStateBackups", DSText("Create Save State Backups", "نسخ احتياطية لحفظ الحالة"), .toggle(default: false)),
            DSSetting("Main", "LoadDevicesFromSaveStates", DSText("Load Devices From Save States", "تحميل الأجهزة من حفظ الحالة"), .toggle(default: false)),
            DSSetting("Main", "SaveStateCompression", DSText("Save State Compression", "ضغط حفظ الحالة"), .choice(default: "ZstDefault", options: [
                DSOption("Uncompressed", "Uncompressed", "بدون ضغط"),
                DSOption("DeflateLow", "Deflate (Low)", "Deflate (منخفض)"),
                DSOption("DeflateDefault", "Deflate (Default)", "Deflate (افتراضي)"),
                DSOption("DeflateHigh", "Deflate (High)", "Deflate (عالي)"),
                DSOption("ZstLow", "Zstandard (Low)", "Zstandard (منخفض)"),
                DSOption("ZstDefault", "Zstandard (Default)", "Zstandard (افتراضي)"),
                DSOption("ZstHigh", "Zstandard (High)", "Zstandard (عالي)"),
            ])),
        ]),
        DSSettingsGroup(title: DSText("Game Settings", "إعدادات الألعاب"), settings: [
            DSSetting("Main", "ApplyCompatibilitySettings", DSText("Apply Compatibility Settings", "تطبيق إعدادات التوافق"), .toggle(default: true),
                      help: DSText("Automatic fixes from the built-in game database.", "إصلاحات تلقائية من قاعدة بيانات الألعاب.")),
            DSSetting("Main", "ApplyGameSettings", DSText("Apply Per-Game Settings", "تطبيق إعدادات كل لعبة"), .toggle(default: true)),
            DSSetting("Main", "DisableAllEnhancements", DSText("Disable All Enhancements", "تعطيل كل التحسينات"), .toggle(default: false)),
            DSSetting("Console", "EnableCheats", DSText("Enable Cheats", "تفعيل الغش"), .toggle(default: false)),
        ]),
    ])

    static let bios = DSSettingsCategory("bios", DSText("BIOS", "البايوس"), icon: "cpu", showsBIOSList: true, [
        DSSettingsGroup(title: DSText("Options", "الخيارات"), settings: [
            DSSetting("BIOS", "PatchFastBoot", DSText("Fast Boot (Skip BIOS Splash)", "إقلاع سريع (تخطي شعار البايوس)"), .toggle(default: true)),
        ]),
    ])

    static let memoryCards = DSSettingsCategory("memorycards", DSText("Memory Cards", "بطاقات الذاكرة"), icon: "sdcard", [
        DSSettingsGroup(title: DSText("Memory Cards", "بطاقات الذاكرة"), settings: [
            DSSetting("MemoryCards", "Card1Type", DSText("Memory Card 1", "بطاقة الذاكرة 1"), .choice(default: "PerGameTitle", options: memoryCardTypeOptions)),
            DSSetting("MemoryCards", "Card2Type", DSText("Memory Card 2", "بطاقة الذاكرة 2"), .choice(default: "None", options: memoryCardTypeOptions)),
            DSSetting("MemoryCards", "UsePlaylistTitle", DSText("Use Single Card For Multi-Disc Games", "بطاقة واحدة للألعاب متعددة الأقراص"), .toggle(default: true)),
        ]),
        DSSettingsGroup(title: DSText("Controller Ports", "منافذ اليد"), settings: [
            DSSetting("ControllerPorts", "MultitapMode", DSText("Multitap", "موزّع اليد (Multitap)"), .choice(default: "Disabled", options: [
                DSOption("Disabled", "Disabled", "معطّل"),
                DSOption("Port1Only", "Enable on Port 1 Only", "على المنفذ 1 فقط"),
                DSOption("Port2Only", "Enable on Port 2 Only", "على المنفذ 2 فقط"),
                DSOption("BothPorts", "Enable on Ports 1 and 2", "على المنفذين"),
            ])),
        ]),
    ])

    static let graphics = DSSettingsCategory("graphics", DSText("Graphics", "الرسومات"), icon: "paintbrush", [
        DSSettingsGroup(title: DSText("Rendering", "الرسم"), settings: [
            DSSetting("GPU", "Renderer", DSText("Renderer", "محرك الرسم"), .choice(default: "Metal", options: [
                DSOption("Metal", "Hardware (Metal)", "كرت الشاشة (Metal)"),
                DSOption("Software", "Software", "المعالج (Software)"),
            ])),
            DSSetting("GPU", "ResolutionScale", DSText("Internal Resolution", "الدقة الداخلية"), .choice(default: "1", options:
                (1...16).map { DSOption("\($0)", "\($0)x (\($0 * 240)p)", "\($0)x (\($0 * 240)p)") })),
            DSSetting("GPU", "Multisamples", DSText("Multi-Sampling (MSAA)", "منع التسنن (MSAA)"), .choice(default: "1", options: [
                DSOption("1", "Disabled", "معطّل"), DSOption("2", "2x MSAA", "2x MSAA"),
                DSOption("4", "4x MSAA", "4x MSAA"), DSOption("8", "8x MSAA", "8x MSAA"),
            ])),
            DSSetting("GPU", "PerSampleShading", DSText("Per-Sample Shading (SSAA)", "تظليل لكل عينة (SSAA)"), .toggle(default: false)),
            DSSetting("GPU", "TextureFilter", DSText("Texture Filtering", "فلترة الخامات"), .choice(default: "Nearest", options: textureFilterOptions)),
            DSSetting("GPU", "SpriteTextureFilter", DSText("Sprite Texture Filtering", "فلترة خامات الرسوم ثنائية الأبعاد"), .choice(default: "Nearest", options: textureFilterOptions)),
            DSSetting("GPU", "DownsampleMode", DSText("Down-Sampling", "تصغير العينات"), .choice(default: "Disabled", options: [
                DSOption("Disabled", "Disabled", "معطّل"),
                DSOption("Box", "Box (Downsample 3D/Smooth All)", "Box (تنعيم الكل)"),
                DSOption("Adaptive", "Adaptive (Preserve 3D/Smooth 2D)", "تكيّفي (يحافظ على 3D وينعّم 2D)"),
            ])),
        ]),
        DSSettingsGroup(title: DSText("Enhancements", "التحسينات"), settings: [
            DSSetting("GPU", "TrueColor", DSText("True Color Rendering", "ألوان حقيقية (24 بت)"), .toggle(default: true)),
            DSSetting("GPU", "ScaledDithering", DSText("Scaled Dithering", "تدرّج متناسب مع الدقة"), .toggle(default: true)),
            DSSetting("GPU", "Debanding", DSText("True Color Debanding", "إزالة تدرّج الألوان"), .toggle(default: false)),
            DSSetting("GPU", "AccurateBlending", DSText("Accurate Blending", "دمج ألوان دقيق"), .toggle(default: false)),
            DSSetting("GPU", "WidescreenHack", DSText("Widescreen Rendering", "عرض الشاشة العريضة"), .toggle(default: false)),
            DSSetting("GPU", "DisableInterlacing", DSText("Disable Interlacing", "تعطيل التشابك (Interlacing)"), .toggle(default: true)),
            DSSetting("GPU", "ForceNTSCTimings", DSText("Force NTSC Timings (60Hz PAL)", "فرض توقيت NTSC (‏60Hz لألعاب PAL)"), .toggle(default: false)),
            DSSetting("GPU", "ChromaSmoothing24Bit", DSText("FMV Chroma Smoothing", "تنعيم ألوان الفيديوهات"), .toggle(default: false)),
            DSSetting("GPU", "LineDetectMode", DSText("Line Detection", "كشف الخطوط"), .choice(default: "Disabled", options: [
                DSOption("Disabled", "Disabled", "معطّل"),
                DSOption("Quads", "Quads", "رباعيات"),
                DSOption("BasicTriangles", "Triangles (Basic)", "مثلثات (أساسي)"),
                DSOption("AggressiveTriangles", "Triangles (Aggressive)", "مثلثات (قوي)"),
            ])),
            DSSetting("GPU", "ForceRoundTextureCoordinates", DSText("Round Upscaled Texture Coordinates", "تقريب إحداثيات الخامات المكبّرة"), .toggle(default: false)),
        ]),
        DSSettingsGroup(title: DSText("Performance", "الأداء"), settings: [
            DSSetting("GPU", "UseThread", DSText("Threaded Rendering", "الرسم في خيط منفصل"), .toggle(default: true)),
            DSSetting("GPU", "UseSoftwareRendererForReadbacks", DSText("Software Renderer Readbacks", "قراءات الذاكرة بالمعالج"), .toggle(default: false)),
        ]),
    ])

    static let pgxp = DSSettingsCategory("pgxp", DSText("PGXP (Geometry)", "PGXP (تصحيح الأشكال)"), icon: "cube.transparent", [
        DSSettingsGroup(title: DSText("PGXP", "PGXP"), settings: [
            DSSetting("GPU", "PGXPEnable", DSText("Enable PGXP", "تفعيل PGXP"), .toggle(default: false),
                      help: DSText("Fixes the wobbly polygons and warping textures of the PS1.", "يصلح اهتزاز المضلعات وتشوّه الخامات في ألعاب PS1.")),
            DSSetting("GPU", "PGXPCulling", DSText("Culling Correction", "تصحيح الإخفاء"), .toggle(default: true)),
            DSSetting("GPU", "PGXPTextureCorrection", DSText("Perspective Correct Textures", "تصحيح منظور الخامات"), .toggle(default: true)),
            DSSetting("GPU", "PGXPColorCorrection", DSText("Perspective Correct Colors", "تصحيح منظور الألوان"), .toggle(default: false)),
            DSSetting("GPU", "PGXPPreserveProjFP", DSText("Preserve Projection Precision", "الحفاظ على دقة الإسقاط"), .toggle(default: false)),
            DSSetting("GPU", "PGXPDepthBuffer", DSText("Depth Buffer (Low Compatibility)", "مخزن العمق (توافق منخفض)"), .toggle(default: false)),
            DSSetting("GPU", "PGXPDisableOn2DPolygons", DSText("Disable on 2D Polygons", "تعطيل على المضلعات ثنائية الأبعاد"), .toggle(default: false)),
            DSSetting("GPU", "PGXPVertexCache", DSText("Vertex Cache", "ذاكرة الرؤوس المؤقتة"), .toggle(default: false)),
            DSSetting("GPU", "PGXPCPU", DSText("CPU Mode (Very Slow)", "وضع المعالج (بطيء جداً)"), .toggle(default: false)),
            DSSetting("GPU", "PGXPTolerance", DSText("Geometry Tolerance", "سماحية الأشكال"), .float(default: -1, min: -1, max: 10, step: 0.5, unit: "px"),
                      help: DSText("-1 disables the tolerance check.", "القيمة ‎-1 تعطّل فحص السماحية.")),
        ]),
    ])

    static let display = DSSettingsCategory("display", DSText("Display", "العرض"), icon: "tv", [
        DSSettingsGroup(title: DSText("Screen", "الشاشة"), settings: [
            DSSetting("Display", "AspectRatio", DSText("Aspect Ratio", "نسبة العرض"), .choice(default: "Auto (Game Native)", options: [
                DSOption("Auto (Game Native)", "Auto (Game Native)", "تلقائي (حسب اللعبة)"),
                DSOption("Auto (Match Window)", "Stretch To Fill", "تمديد لملء الشاشة"),
                DSOption("4:3", "4:3", "4:3"),
                DSOption("16:9", "16:9", "16:9"),
                DSOption("19:9", "19:9", "19:9"),
                DSOption("20:9", "20:9", "20:9"),
                DSOption("PAR 1:1", "PAR 1:1", "PAR 1:1"),
                DSOption("Custom", "Custom", "مخصص"),
            ])),
            DSSetting("Display", "CustomAspectRatioNumerator", DSText("Custom Aspect Ratio Width", "عرض النسبة المخصصة"), .int(default: 4, min: 1, max: 99, step: 1, unit: "")),
            DSSetting("Display", "CustomAspectRatioDenominator", DSText("Custom Aspect Ratio Height", "ارتفاع النسبة المخصصة"), .int(default: 3, min: 1, max: 99, step: 1, unit: "")),
            DSSetting("Display", "CropMode", DSText("Crop", "القص"), .choice(default: "Overscan", options: [
                DSOption("None", "None", "بدون"),
                DSOption("Overscan", "Only Overscan Area", "منطقة الحواف فقط"),
                DSOption("Borders", "All Borders", "كل الحدود"),
            ])),
            DSSetting("Display", "Scaling", DSText("Scaling", "التكبير"), .choice(default: "BilinearSmooth", options: [
                DSOption("Nearest", "Nearest-Neighbor", "أقرب بكسل"),
                DSOption("NearestInteger", "Nearest-Neighbor (Integer)", "أقرب بكسل (مضاعفات صحيحة)"),
                DSOption("BilinearSmooth", "Bilinear (Smooth)", "ثنائي الخطية (ناعم)"),
                DSOption("BilinearSharp", "Bilinear (Sharp)", "ثنائي الخطية (حاد)"),
                DSOption("BilinearInteger", "Bilinear (Integer)", "ثنائي الخطية (مضاعفات صحيحة)"),
            ])),
            DSSetting("Display", "Alignment", DSText("Position", "الموضع"), .choice(default: "Center", options: [
                DSOption("LeftOrTop", "Left / Top", "يسار / أعلى"),
                DSOption("Center", "Center", "الوسط"),
                DSOption("RightOrBottom", "Right / Bottom", "يمين / أسفل"),
            ])),
            DSSetting("Display", "Rotation", DSText("Rotation", "التدوير"), .choice(default: "Normal", options: [
                DSOption("Normal", "No Rotation", "بدون تدوير"),
                DSOption("Rotate90", "Rotate 90° (Clockwise)", "تدوير 90°"),
                DSOption("Rotate180", "Rotate 180° (Vertical Flip)", "تدوير 180°"),
                DSOption("Rotate270", "Rotate 270° (Clockwise)", "تدوير 270°"),
            ])),
            DSSetting("Display", "StretchVertically", DSText("Stretch Vertically", "تمديد عمودي"), .toggle(default: false)),
            DSSetting("Display", "DeinterlacingMode", DSText("Deinterlacing", "إزالة التشابك"), .choice(default: "Adaptive", options: [
                DSOption("Disabled", "Disabled (Flickering)", "معطّل (وميض)"),
                DSOption("Weave", "Weave (Combing)", "Weave (تمشيط)"),
                DSOption("Blend", "Blend (Blur)", "دمج (ضبابية)"),
                DSOption("Adaptive", "Adaptive (FastMAD)", "تكيّفي (FastMAD)"),
            ])),
        ]),
        DSSettingsGroup(title: DSText("Frame Pacing", "توقيت الإطارات"), settings: [
            DSSetting("Display", "VSync", DSText("Vertical Sync (VSync)", "المزامنة العمودية (VSync)"), .toggle(default: false)),
            DSSetting("Display", "OptimalFramePacing", DSText("Optimal Frame Pacing", "توقيت إطارات مثالي"), .toggle(default: false)),
            DSSetting("Display", "SkipPresentingDuplicateFrames", DSText("Skip Duplicate Frame Display", "تخطي الإطارات المكررة"), .toggle(default: false)),
            DSSetting("Display", "PreFrameSleep", DSText("Reduce Input Latency (Pre-Frame Sleep)", "تقليل تأخير الأزرار"), .toggle(default: false)),
        ]),
    ])

    static let osd = DSSettingsCategory("osd", DSText("On-Screen Display", "معلومات على الشاشة"), icon: "text.below.photo", [
        DSSettingsGroup(title: DSText("On-Screen Display", "معلومات على الشاشة"), settings: [
            DSSetting("Display", "ShowOSDMessages", DSText("Show Messages", "إظهار الرسائل"), .toggle(default: true)),
            DSSetting("Display", "ShowStatusIndicators", DSText("Show Status Indicators", "إظهار مؤشرات الحالة"), .toggle(default: true)),
            DSSetting("Display", "ShowFPS", DSText("Show FPS", "إظهار عدد الإطارات"), .toggle(default: false)),
            DSSetting("Display", "ShowSpeed", DSText("Show Emulation Speed", "إظهار سرعة المحاكاة"), .toggle(default: false)),
            DSSetting("Display", "ShowResolution", DSText("Show Resolution", "إظهار الدقة"), .toggle(default: false)),
            DSSetting("Display", "ShowCPU", DSText("Show CPU Usage", "إظهار استهلاك المعالج"), .toggle(default: false)),
            DSSetting("Display", "ShowGPU", DSText("Show GPU Usage", "إظهار استهلاك كرت الشاشة"), .toggle(default: false)),
            DSSetting("Display", "ShowGPUStatistics", DSText("Show GPU Statistics", "إظهار إحصاءات كرت الشاشة"), .toggle(default: false)),
            DSSetting("Display", "ShowFrameTimes", DSText("Show Frame Times", "إظهار أزمنة الإطارات"), .toggle(default: false)),
            DSSetting("Display", "ShowLatencyStatistics", DSText("Show Latency Statistics", "إظهار إحصاءات التأخير"), .toggle(default: false)),
            DSSetting("Display", "ShowInputs", DSText("Show Controller Input", "إظهار ضغطات اليد"), .toggle(default: false)),
            DSSetting("Display", "ShowEnhancements", DSText("Show Enhancement Settings", "إظهار التحسينات المفعّلة"), .toggle(default: false)),
            DSSetting("Display", "OSDScale", DSText("OSD Scale", "حجم المعلومات"), .float(default: 100, min: 50, max: 300, step: 10, unit: "%")),
        ]),
    ])

    static let audio = DSSettingsCategory("audio", DSText("Audio", "الصوت"), icon: "speaker.wave.2", [
        DSSettingsGroup(title: DSText("Volume", "مستوى الصوت"), settings: [
            DSSetting("Audio", "OutputVolume", DSText("Output Volume", "مستوى الصوت"), .int(default: 100, min: 0, max: 200, step: 5, unit: "%")),
            DSSetting("Audio", "FastForwardVolume", DSText("Fast Forward Volume", "الصوت أثناء التقديم السريع"), .int(default: 100, min: 0, max: 200, step: 5, unit: "%")),
            DSSetting("Audio", "OutputMuted", DSText("Mute All Sound", "كتم كل الأصوات"), .toggle(default: false)),
            DSSetting("CDROM", "MuteCDAudio", DSText("Mute CD Audio", "كتم صوت القرص"), .toggle(default: false)),
        ]),
    ])

    static let advanced = DSSettingsCategory("advanced", DSText("Advanced", "متقدم"), icon: "wrench.and.screwdriver", [
        DSSettingsGroup(title: DSText("Compatibility", "التوافق"), settings: [
            DSSetting("CPU", "RecompilerICache", DSText("Enable CPU Instruction Cache", "تفعيل ذاكرة تعليمات المعالج"), .toggle(default: false)),
            DSSetting("Hacks", "UseOldMDECRoutines", DSText("Use Old MDEC Routines", "استخدام فك الفيديو القديم (MDEC)"), .toggle(default: false)),
            DSSetting("CDROM", "MechaconVersion", DSText("CD-ROM Mechacon Version", "إصدار متحكم القارئ"), .choice(default: "VC1A", options: [
                DSOption("VC0A", "VC0A", "VC0A"), DSOption("VC0B", "VC0B", "VC0B"), DSOption("VC1A", "VC1A", "VC1A"),
                DSOption("VC1B", "VC1B", "VC1B"), DSOption("VD1", "VD1", "VD1"), DSOption("VC2", "VC2", "VC2"),
                DSOption("VC1", "VC1", "VC1"), DSOption("VC2J", "VC2J", "VC2J"), DSOption("VC2A", "VC2A", "VC2A"),
                DSOption("VC2B", "VC2B", "VC2B"), DSOption("VC3A", "VC3A", "VC3A"), DSOption("VC3B", "VC3B", "VC3B"),
                DSOption("VC3C", "VC3C", "VC3C"),
            ])),
        ]),
    ])

    static let textures = DSSettingsCategory("textures", DSText("Texture Replacement", "استبدال الخامات"), icon: "photo.stack", [
        DSSettingsGroup(title: DSText("Replacement", "الاستبدال"), settings: [
            DSSetting("TextureReplacements", "EnableVRAMWriteReplacements", DSText("Enable Background Replacement", "تفعيل استبدال الخلفيات"), .toggle(default: false),
                help: DSText("Put PNG files in Files › Psxp › textures › [Game Serial].", "ضع ملفات PNG في: الملفات › Psxp › textures › [رقم اللعبة].")),
            DSSetting("TextureReplacements", "PreloadTextures", DSText("Preload Replacement Textures", "تحميل الخامات البديلة مسبقاً"), .toggle(default: false)),
        ]),
        DSSettingsGroup(title: DSText("Dumping", "الاستخراج"), settings: [
            DSSetting("TextureReplacements", "DumpVRAMWrites", DSText("Dump Replaceable Backgrounds", "استخراج الخلفيات القابلة للاستبدال"), .toggle(default: false),
                help: DSText("Saved to Files › Psxp › dump › textures.", "تُحفظ في: الملفات › Psxp › dump › textures.")),
            DSSetting("TextureReplacements", "DumpVRAMWriteForceAlphaChannel", DSText("Force Alpha Channel In Dumps", "فرض قناة الشفافية عند الاستخراج"), .toggle(default: true)),
            DSSetting("TextureReplacements", "DumpVRAMWriteWidthThreshold", DSText("Minimum Dump Width", "أقل عرض للاستخراج"), .int(default: 128, min: 1, max: 1024, step: 16, unit: "px")),
            DSSetting("TextureReplacements", "DumpVRAMWriteHeightThreshold", DSText("Minimum Dump Height", "أقل ارتفاع للاستخراج"), .int(default: 128, min: 1, max: 512, step: 16, unit: "px")),
        ]),
    ])

    static let debug = DSSettingsCategory("debug", DSText("Debug", "التصحيح (Debug)"), icon: "ladybug", [
        DSSettingsGroup(title: DSText("Debug Windows", "نوافذ التصحيح"), settings: [
            DSSetting("Debug", "ShowVRAM", DSText("Show VRAM", "عرض ذاكرة الفيديو (VRAM)"), .toggle(default: false)),
            DSSetting("Debug", "ShowGPUState", DSText("Show GPU State", "عرض حالة كرت الشاشة"), .toggle(default: false)),
            DSSetting("Debug", "ShowCDROMState", DSText("Show CD-ROM State", "عرض حالة القارئ"), .toggle(default: false)),
            DSSetting("Debug", "ShowSPUState", DSText("Show SPU State", "عرض حالة الصوت (SPU)"), .toggle(default: false)),
            DSSetting("Debug", "ShowTimersState", DSText("Show Timers State", "عرض حالة المؤقتات"), .toggle(default: false)),
            DSSetting("Debug", "ShowMDECState", DSText("Show MDEC State", "عرض حالة فك الفيديو (MDEC)"), .toggle(default: false)),
            DSSetting("Debug", "ShowDMAState", DSText("Show DMA State", "عرض حالة DMA"), .toggle(default: false)),
        ]),
        DSSettingsGroup(title: DSText("Dumping", "الاستخراج"), settings: [
            DSSetting("Debug", "DumpCPUToVRAMCopies", DSText("Dump CPU to VRAM Copies", "استخراج النسخ من المعالج إلى VRAM"), .toggle(default: false)),
            DSSetting("Debug", "DumpVRAMToCPUCopies", DSText("Dump VRAM to CPU Copies", "استخراج النسخ من VRAM إلى المعالج"), .toggle(default: false)),
        ]),
        DSSettingsGroup(title: DSText("Logging", "السجل (Log)"), settings: [
            DSSetting("Logging", "LogLevel", DSText("Log Level", "مستوى السجل"), .choice(default: "Info", options: [
                DSOption("None", "None", "بدون"), DSOption("Error", "Error", "أخطاء"), DSOption("Warning", "Warning", "تحذيرات"),
                DSOption("Info", "Info", "معلومات"), DSOption("Verbose", "Verbose", "مفصّل"), DSOption("Dev", "Dev", "مطوّر"),
                DSOption("Debug", "Debug", "تصحيح"), DSOption("Trace", "Trace", "تتبّع كامل"),
            ]), help: DSText("Log is saved to Files › Psxp › duckstation.log.", "السجل يُحفظ في: الملفات › Psxp › duckstation.log.")),
            DSSetting("Logging", "LogTimestamps", DSText("Log Timestamps", "توقيت في السجل"), .toggle(default: true)),
        ]),
        DSSettingsGroup(title: DSText("GPU", "كرت الشاشة"), settings: [
            DSSetting("GPU", "UseDebugDevice", DSText("Use Debug GPU Device", "استخدام وضع تصحيح كرت الشاشة"), .toggle(default: false)),
        ]),
    ])
}
