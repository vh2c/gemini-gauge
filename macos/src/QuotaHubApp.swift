import Cocoa

// MARK: - Data Models
struct Bucket: Codable {
    let id: String?
    let name: String
    let remaining_pct: Int
    let reset_in: String?
    let detail: String?
}

struct Group: Codable {
    let name: String
    let description: String?
    let provider: String?
    let buckets: [Bucket]
}

struct QuotaData: Codable {
    let account: String
    let plan: String?
    let providers_count: Int?
    let groups: [Group]
    let updated_at: String?
    var from_cache: Bool?
    var cache_age_seconds: Int?
    var timestamp: Double?
    var needs_setup: Bool?
}

struct GaugeItem {
    let id: String
    let title: String
    let modelName: String
    let percentage: Int
    let resetIn: String?
    let detail: String?
    let provider: String?
}

struct ProviderConfig: Codable {
    var enabled: Bool?
    var api_key: String?
}

struct AppConfig: Codable {
    var providers: [String: ProviderConfig]?
    var refresh_interval_seconds: Int?
}

extension QuotaData {
    var gaugeItems: [GaugeItem] {
        var items: [GaugeItem] = []
        for g in groups {
            let modelLabel: String
            let lowerG = g.name.lowercased()
            if lowerG.contains("gemini 4") || lowerG.contains("argon") {
                modelLabel = "Argon"
            } else if lowerG.contains("claude") || lowerG.contains("gpt") {
                modelLabel = "Claude/GPT"
            } else if lowerG.contains("openai") {
                modelLabel = "OpenAI"
            } else if lowerG.contains("anthropic") {
                modelLabel = "Claude API"
            } else {
                modelLabel = "Gemini"
            }
            
            for b in g.buckets {
                let limitTitle: String
                let lowerB = b.name.lowercased()
                if lowerB.contains("five") || lowerB.contains("5") {
                    limitTitle = "5 hours Limit"
                } else if lowerB.contains("rpm") || lowerB.contains("req") {
                    limitTitle = "RPM Limit"
                } else if lowerB.contains("tpm") || lowerB.contains("token") {
                    limitTitle = "TPM Limit"
                } else {
                    limitTitle = "Weekly Limit"
                }
                items.append(GaugeItem(
                    id: b.id ?? "",
                    title: limitTitle,
                    modelName: modelLabel,
                    percentage: b.remaining_pct,
                    resetIn: b.reset_in,
                    detail: b.detail,
                    provider: g.provider
                ))
            }
        }
        return items
    }
}

// MARK: - Quota Manager
class QuotaManager {
    static let appSupportDir: String = {
        let path = NSString(string: "~/Library/Application Support/UniversalAIQuota").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()
    
    static var cachePath: String {
        return (appSupportDir as NSString).appendingPathComponent("quota_cache.json")
    }
    
    static var configDir: String {
        let path = NSString(string: "~/.config/UniversalAIQuota").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }
    
    static var configPath: String {
        return (configDir as NSString).appendingPathComponent("config.json")
    }
    
    static func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig(
                providers: [
                    "antigravity": ProviderConfig(enabled: true, api_key: nil),
                    "gemini": ProviderConfig(enabled: false, api_key: ""),
                    "openai": ProviderConfig(enabled: false, api_key: ""),
                    "anthropic": ProviderConfig(enabled: false, api_key: "")
                ],
                refresh_interval_seconds: 30
            )
        }
        return cfg
    }
    
    static func saveConfig(_ cfg: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(cfg) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }
    
    static var engineScript: String {
        let bundlePath = Bundle.main.bundlePath
        let candidate1 = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core/engine.js")
        if FileManager.default.fileExists(atPath: candidate1) { return candidate1 }
        
        let candidate2 = NSString(string: "~/.gemini/antigravity/scratch/universal-ai-quota-monitor/core/engine.js").expandingTildeInPath
        if FileManager.default.fileExists(atPath: candidate2) { return candidate2 }
        
        return NSString(string: "~/universal-ai-quota-monitor/core/engine.js").expandingTildeInPath
    }
    
    static func findNodeBinary() -> String {
        let fileManager = FileManager.default
        let wellKnownPaths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "/bin/node"
        ]
        for path in wellKnownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let nvmBase = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                let candidate = (nvmBase as NSString).appendingPathComponent("\(v)/bin/node")
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return "node"
    }
    
    static func loadQuota(force: Bool = false, maxRetries: Int = 3) -> QuotaData? {
        if !force {
            if let cached = readCache(), let ts = cached.timestamp, (Date().timeIntervalSince1970 - ts) < 30 {
                var c = cached
                c.from_cache = true
                c.cache_age_seconds = Int(Date().timeIntervalSince1970 - ts)
                return c
            }
        }
        
        for attempt in 1...maxRetries {
            if let live = fetchLive() {
                return live
            }
            if attempt < maxRetries {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        
        if let cached = readCache() {
            return cached
        }
        return nil
    }
    
    static func readCache() -> QuotaData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)) else { return nil }
        return try? JSONDecoder().decode(QuotaData.self, from: data)
    }
    
    static func fetchLive() -> QuotaData? {
        let nodeBin = findNodeBinary()
        let task = Process()
        if nodeBin.hasPrefix("/") {
            task.executableURL = URL(fileURLWithPath: nodeBin)
            task.arguments = [engineScript]
        } else {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["node", engineScript]
        }
        
        var env = ProcessInfo.processInfo.environment
        var searchPaths: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let nvmBase = NSString(string: "~/.nvm/versions/node").expandingTildeInPath
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for v in versions.sorted().reversed() {
                searchPaths.append((nvmBase as NSString).appendingPathComponent("\(v)/bin"))
            }
        }
        if let currentPath = env["PATH"] {
            searchPaths.append(currentPath)
        }
        env["PATH"] = searchPaths.joined(separator: ":")
        env["HOME"] = NSHomeDirectory()
        env["USER"] = NSUserName()
        task.environment = env
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if task.terminationStatus == 0, let quota = try? JSONDecoder().decode(QuotaData.self, from: data) {
                var qWithTs = quota
                qWithTs.timestamp = Date().timeIntervalSince1970
                if let encoded = try? JSONEncoder().encode(qWithTs) {
                    try? encoded.write(to: URL(fileURLWithPath: cachePath))
                }
                return qWithTs
            }
        } catch {
            print("Fetch error: \(error)")
        }
        return nil
    }
}

// MARK: - Tachometer Gauge View
class TachometerGaugeView: NSView {
    var item: GaugeItem
    
    init(item: GaugeItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 88, height: 96))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let cx = bounds.midX
        let cy: CGFloat = 52.0
        let radius: CGFloat = 34.0
        let center = CGPoint(x: cx, y: cy)
        
        let startAngleDeg: Double = 220.0
        let endAngleDeg: Double = -40.0
        let totalSweepDeg: Double = 260.0
        
        let toRad = { (deg: Double) -> Double in deg * Double.pi / 180.0 }
        
        // 1. Fundo do dial circular
        let dialBgRect = CGRect(x: cx - radius - 5, y: cy - radius - 5, width: (radius + 5) * 2, height: (radius + 5) * 2)
        context.setFillColor(NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x15/255.0, alpha: 0.95).cgColor)
        context.fillEllipse(in: dialBgRect)
        
        // 2. Trilho do Tacômetro
        let trackPath = CGMutablePath()
        trackPath.addArc(
            center: center,
            radius: radius,
            startAngle: CGFloat(toRad(startAngleDeg)),
            endAngle: CGFloat(toRad(endAngleDeg)),
            clockwise: true
        )
        context.setStrokeColor(NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2D/255.0, alpha: 1.0).cgColor)
        context.setLineWidth(5.5)
        context.setLineCap(.round)
        context.addPath(trackPath)
        context.strokePath()
        
        // 3. Ticks e Graduações
        let numTicks = 24
        for i in 0...numTicks {
            let frac = Double(i) / Double(numTicks)
            let angleDeg = startAngleDeg - frac * totalSweepDeg
            let rad = toRad(angleDeg)
            let isMajor = (i % 6 == 0)
            let tickLen: CGFloat = isMajor ? 5.0 : 3.0
            let rInner = radius - 3.5
            let rOuter = rInner - tickLen
            
            let p1 = CGPoint(x: cx + CGFloat(cos(rad)) * rInner, y: cy + CGFloat(sin(rad)) * rInner)
            let p2 = CGPoint(x: cx + CGFloat(cos(rad)) * rOuter, y: cy + CGFloat(sin(rad)) * rOuter)
            
            let tickColor = isMajor
                ? NSColor(white: 0.55, alpha: 0.85).cgColor
                : NSColor(white: 0.32, alpha: 0.50).cgColor
            context.setStrokeColor(tickColor)
            context.setLineWidth(isMajor ? 1.2 : 0.8)
            context.strokeLineSegments(between: [p1, p2])
        }
        
        // 4. Arco Preenchido Dinâmico
        let pct = Double(min(max(item.percentage, 0), 100))
        let sweepPctDeg = (pct / 100.0) * totalSweepDeg
        let currentAngleDeg = startAngleDeg - sweepPctDeg
        
        let colorGreen = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
        let colorYellow = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
        let colorRed = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
        
        let activeColor: NSColor
        if pct >= 50.0 {
            activeColor = colorGreen
        } else if pct >= 20.0 {
            activeColor = colorYellow
        } else {
            activeColor = colorRed
        }
        
        if sweepPctDeg > 1.0 {
            let activePath = CGMutablePath()
            activePath.addArc(
                center: center,
                radius: radius,
                startAngle: CGFloat(toRad(startAngleDeg)),
                endAngle: CGFloat(toRad(currentAngleDeg)),
                clockwise: true
            )
            context.setStrokeColor(activeColor.cgColor)
            context.setLineWidth(5.5)
            context.setLineCap(.round)
            context.addPath(activePath)
            context.strokePath()
        }
        
        // 5. Ponteiro / Agulha Estilo Tacômetro
        let needleAngleRad = toRad(currentAngleDeg)
        let needleLen = radius - 8.0
        let tipPoint = CGPoint(
            x: cx + CGFloat(cos(needleAngleRad)) * needleLen,
            y: cy + CGFloat(sin(needleAngleRad)) * needleLen
        )
        let baseAngle1 = needleAngleRad + Double.pi / 2.0
        let baseAngle2 = needleAngleRad - Double.pi / 2.0
        let baseR: CGFloat = 2.5
        let baseP1 = CGPoint(x: cx + CGFloat(cos(baseAngle1)) * baseR, y: cy + CGFloat(sin(baseAngle1)) * baseR)
        let baseP2 = CGPoint(x: cx + CGFloat(cos(baseAngle2)) * baseR, y: cy + CGFloat(sin(baseAngle2)) * baseR)
        
        let needlePath = CGMutablePath()
        needlePath.move(to: baseP1)
        needlePath.addLine(to: tipPoint)
        needlePath.addLine(to: baseP2)
        needlePath.closeSubpath()
        
        context.setFillColor(NSColor(white: 0.95, alpha: 0.95).cgColor)
        context.addPath(needlePath)
        context.fillPath()
        
        // Hub central
        let hubRect = CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8)
        context.setFillColor(NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor)
        context.fillEllipse(in: hubRect)
        context.setStrokeColor(activeColor.cgColor)
        context.setLineWidth(1.2)
        context.strokeEllipse(in: hubRect)
        
        // 6. Texto Curvado Superior
        drawCurvedText(
            text: item.title.uppercased(),
            center: center,
            radius: radius + 7.0,
            startAngleRad: toRad(170.0),
            totalSweepRad: toRad(160.0),
            context: context
        )
        
        // 7. Porcentagem no Centro Inferior
        let pctStr = "\(item.percentage)%" as NSString
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let pctSize = pctStr.size(withAttributes: pctAttrs)
        pctStr.draw(at: CGPoint(x: cx - pctSize.width / 2.0, y: cy - 23.0), withAttributes: pctAttrs)
        
        // 8. Nome do Modelo e Reset Inferior
        let modelStr = item.modelName as NSString
        let modelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor(white: 0.70, alpha: 1.0)
        ]
        let mSize = modelStr.size(withAttributes: modelAttrs)
        modelStr.draw(at: CGPoint(x: cx - mSize.width / 2.0, y: 12.0), withAttributes: modelAttrs)
        
        if let reset = item.resetIn, !reset.isEmpty {
            let rStr = reset as NSString
            let rAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.50, alpha: 1.0)
            ]
            let rSize = rStr.size(withAttributes: rAttrs)
            rStr.draw(at: CGPoint(x: cx - rSize.width / 2.0, y: 1.0), withAttributes: rAttrs)
        }
    }
    
    private func drawCurvedText(text: String, center: CGPoint, radius: CGFloat, startAngleRad: Double, totalSweepRad: Double, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.0, weight: .semibold),
            .foregroundColor: NSColor(white: 0.45, alpha: 0.9)
        ]
        let chars = Array(text)
        guard !chars.isEmpty else { return }
        
        var totalWidth: CGFloat = 0
        var charWidths: [CGFloat] = []
        for ch in chars {
            let sz = String(ch).size(withAttributes: attrs)
            charWidths.append(sz.width)
            totalWidth += sz.width
        }
        
        let perimeterSpan = radius * CGFloat(totalSweepRad)
        let spacing = (perimeterSpan - totalWidth) / CGFloat(max(chars.count - 1, 1))
        
        var currentAngle = startAngleRad
        let charHeight: CGFloat = 7.0
        
        for (i, ch) in chars.enumerated() {
            let w = charWidths[i]
            let charAngle = Double(w + spacing) / Double(radius)
            let midAngle = currentAngle - (charAngle / 2.0)
            
            context.saveGState()
            let x = center.x + CGFloat(cos(midAngle)) * radius
            let y = center.y + CGFloat(sin(midAngle)) * radius
            
            context.translateBy(x: x, y: y)
            context.rotate(by: CGFloat(midAngle - Double.pi / 2.0))
            
            let chStr = String(ch) as NSString
            chStr.draw(at: CGPoint(x: -w / 2.0, y: -charHeight / 2.0), withAttributes: attrs)
            context.restoreGState()
            
            currentAngle -= charAngle
        }
    }
}

// MARK: - HUD Container View
class HudContainerView: NSView {
    weak var delegate: AppDelegate?
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "m" {
                delegate?.switchToFullMode()
                return
            } else if event.charactersIgnoringModifiers == "o" {
                delegate?.toggleHudOrientation()
                return
            } else if event.charactersIgnoringModifiers == "r" {
                delegate?.refreshClicked()
                return
            } else if event.charactersIgnoringModifiers == "," {
                delegate?.openSettings()
                return
            }
        }
        if event.keyCode == 53 {
            delegate?.closeClicked()
            return
        }
        super.keyDown(with: event)
    }
}

enum DisplayMode: String {
    case full
    case hud
}

enum HudOrientation: String {
    case vertical
    case horizontal
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var fullWindow: NSWindow?
    var hudWindow: NSPanel?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    
    var currentMode: DisplayMode = .full
    var hudOrientation: HudOrientation = .vertical
    var isAlwaysOnTop: Bool = true
    
    var autoRefreshTimer: Timer?
    var refreshBtn: NSButton?
    var isRefreshing: Bool = false
    var isFirstLaunch: Bool = true
    var latestQuota: QuotaData?
    
    // Settings fields
    var geminiCheck: NSButton?
    var geminiKeyField: NSTextField?
    var antigravityCheck: NSButton?
    var openaiCheck: NSButton?
    var openaiKeyField: NSTextField?
    var anthropicCheck: NSButton?
    var anthropicKeyField: NSTextField?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        
        if let savedMode = UserDefaults.standard.string(forKey: "uaqm_display_mode"),
           let mode = DisplayMode(rawValue: savedMode) {
            currentMode = mode
        }
        if let savedOrient = UserDefaults.standard.string(forKey: "uaqm_hud_orientation"),
           let orient = HudOrientation(rawValue: savedOrient) {
            hudOrientation = orient
        }
        
        let force = CommandLine.arguments.contains("--force")
        if let initialQuota = QuotaManager.loadQuota(force: force, maxRetries: 3) {
            self.latestQuota = initialQuota
            renderCurrentMode()
            startAutoRefreshTimer()
            if initialQuota.needs_setup == true || initialQuota.groups.isEmpty {
                openSettings()
            }
        } else {
            openSettings()
        }
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let img = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Gemini Gauge") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                button.image = img.withSymbolConfiguration(cfg)
            } else {
                button.title = "⚡"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            toggleWindowVisibility()
            return
        }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let titleItem = NSMenuItem(title: "⚡ Gemini Gauge", action: nil, keyEquivalent: "")
            titleItem.attributedTitle = NSAttributedString(
                string: "⚡ Gemini Gauge",
                attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold)]
            )
            menu.addItem(titleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Abrir Janela Principal", action: #selector(switchToFullMode), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Modo Barra HUD", action: #selector(switchToHudMode), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Configurações... (⚙️)", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Atualizar Agora", action: #selector(refreshClicked), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Encerrar Gemini Gauge", action: #selector(closeClicked), keyEquivalent: "q"))
            for item in menu.items { item.target = self }
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleWindowVisibility()
        }
    }
    
    func toggleWindowVisibility() {
        if currentMode == .full {
            if let win = fullWindow, win.isVisible {
                win.orderOut(nil)
            } else {
                renderCurrentMode()
                fullWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            if let win = hudWindow, win.isVisible {
                win.orderOut(nil)
            } else {
                renderCurrentMode()
                hudWindow?.orderFront(nil)
            }
        }
    }
    
    func updateStatusItemTitle() {
        guard let quota = latestQuota else { return }
        var minPct = 100
        for g in quota.groups {
            for b in g.buckets {
                if b.remaining_pct < minPct { minPct = b.remaining_pct }
            }
        }
        if minPct < 100 {
            statusItem?.button?.title = " \(minPct)%"
        } else {
            statusItem?.button?.title = ""
        }
    }
    
    func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performRefresh(animated: false)
        }
    }
    
    @objc func refreshClicked() {
        performRefresh(animated: true)
    }
    
    func performRefresh(animated: Bool) {
        if isRefreshing { return }
        isRefreshing = true
        
        if animated {
            refreshBtn?.isEnabled = false
            refreshBtn?.attributedTitle = NSAttributedString(
                string: "Atualizando...",
                attributes: [
                    .foregroundColor: NSColor(white: 0.50, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
                ]
            )
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let quota = QuotaManager.loadQuota(force: true, maxRetries: 2)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                if let quota = quota {
                    self.latestQuota = quota
                    self.renderCurrentMode()
                    self.updateStatusItemTitle()
                }
                self.resetRefreshBtn()
            }
        }
    }
    
    func resetRefreshBtn() {
        let btnText = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        refreshBtn?.isEnabled = true
        refreshBtn?.attributedTitle = NSAttributedString(
            string: "Atualizar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Atualizar") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                refreshBtn?.image = symbol.withSymbolConfiguration(tinted)
            } else {
                refreshBtn?.image = symbol.withSymbolConfiguration(config)
                refreshBtn?.contentTintColor = btnText
            }
        }
    }
    
    func renderCurrentMode() {
        guard let quota = latestQuota else { return }
        updateStatusItemTitle()
        switch currentMode {
        case .full:
            hudWindow?.orderOut(nil)
            setupFullUI(with: quota)
        case .hud:
            fullWindow?.orderOut(nil)
            setupHudUI(with: quota)
        }
    }
    
    @objc func switchToHudMode() {
        currentMode = .hud
        UserDefaults.standard.set(currentMode.rawValue, forKey: "uaqm_display_mode")
        renderCurrentMode()
    }
    
    @objc func switchToFullMode() {
        currentMode = .full
        UserDefaults.standard.set(currentMode.rawValue, forKey: "uaqm_display_mode")
        renderCurrentMode()
    }
    
    @objc func toggleHudOrientation() {
        hudOrientation = (hudOrientation == .vertical) ? .horizontal : .vertical
        UserDefaults.standard.set(hudOrientation.rawValue, forKey: "uaqm_hud_orientation")
        renderCurrentMode()
    }
    
    @objc func toggleAlwaysOnTop() {
        isAlwaysOnTop = !isAlwaysOnTop
        hudWindow?.level = isAlwaysOnTop ? .floating : .normal
    }
    
    @objc func closeWindowClicked() {
        fullWindow?.orderOut(nil)
        hudWindow?.orderOut(nil)
    }
    
    @objc func toggleModeClicked() {
        if currentMode == .full {
            switchToHudMode()
        } else {
            switchToFullMode()
        }
    }
    
    func setupHudUI(with quota: QuotaData) {
        let items = quota.gaugeItems
        let isVertical = (hudOrientation == .vertical)
        
        let hudW: CGFloat = isVertical ? 108 : (24 + CGFloat(items.count) * 96 + 36)
        let hudH: CGFloat = isVertical ? (32 + CGFloat(items.count) * 96 + 26) : 116
        
        if hudWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 100, y: 100, width: hudW, height: hudH),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = isAlwaysOnTop ? .floating : .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.delegate = self
            hudWindow = panel
        }
        
        guard let panel = hudWindow else { return }
        
        let currentFrame = panel.frame
        let newX: CGFloat
        let newY: CGFloat
        if isFirstLaunch {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                newX = screenFrame.maxX - hudW - 20
                newY = screenFrame.maxY - hudH - 20
            } else {
                newX = 100
                newY = 100
            }
        } else {
            newX = currentFrame.origin.x
            newY = currentFrame.origin.y + (currentFrame.height - hudH)
        }
        
        panel.setFrame(NSRect(x: newX, y: newY, width: hudW, height: hudH), display: true, animate: false)
        
        let container = HudContainerView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        container.delegate = self
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.borderColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor
        container.layer?.borderWidth = 1.0
        
        if isVertical {
            // Barra superior de controle vertical: [⤢ Alternar] [⋯ Opções] [✕ Fechar]
            let topBarY = hudH - 26
            
            let toggleBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
            toggleBtn.isBordered = false
            toggleBtn.frame = NSRect(x: 8, y: topBarY, width: 22, height: 20)
            toggleBtn.toolTip = "Alternar para Janela Completa (Cmd+M)"
            if let sym = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Alternar Modo") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                toggleBtn.image = sym.withSymbolConfiguration(cfg)
                toggleBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(toggleBtn)
            
            let menuBtn = NSButton(title: "", target: self, action: #selector(showHudContextMenu(_:)))
            menuBtn.isBordered = false
            menuBtn.frame = NSRect(x: (hudW - 22) / 2.0, y: topBarY, width: 22, height: 20)
            menuBtn.toolTip = "Menu de Opções"
            if let sym = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Opções") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                menuBtn.image = sym.withSymbolConfiguration(cfg)
                menuBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(menuBtn)
            
            let closeBtn = NSButton(title: "", target: self, action: #selector(closeWindowClicked))
            closeBtn.isBordered = false
            closeBtn.frame = NSRect(x: hudW - 30, y: topBarY, width: 22, height: 20)
            closeBtn.toolTip = "Fechar Janela (✕)"
            if let sym = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                closeBtn.image = sym.withSymbolConfiguration(cfg)
                closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(closeBtn)
            
            for (idx, item) in items.enumerated() {
                let gauge = TachometerGaugeView(item: item)
                let y = hudH - 28 - CGFloat(idx + 1) * 96
                gauge.frame = NSRect(x: 10, y: y, width: 88, height: 96)
                container.addSubview(gauge)
            }
            
            let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
            brandBtn.isBordered = false
            brandBtn.frame = NSRect(x: 4, y: 4, width: hudW - 8, height: 16)
            brandBtn.attributedTitle = NSAttributedString(
                string: "vh2c.com.br",
                attributes: [
                    .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 8.5, weight: .medium)
                ]
            )
            container.addSubview(brandBtn)
        } else {
            // Horizontal HUD
            for (idx, item) in items.enumerated() {
                let gauge = TachometerGaugeView(item: item)
                let x = 12 + CGFloat(idx) * 96
                gauge.frame = NSRect(x: x, y: 14, width: 88, height: 96)
                container.addSubview(gauge)
            }
            
            let colX = hudW - 30
            let closeBtn = NSButton(title: "", target: self, action: #selector(closeWindowClicked))
            closeBtn.isBordered = false
            closeBtn.frame = NSRect(x: colX, y: hudH - 28, width: 22, height: 20)
            closeBtn.toolTip = "Fechar Janela (✕)"
            if let sym = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                closeBtn.image = sym.withSymbolConfiguration(cfg)
                closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(closeBtn)
            
            let toggleBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
            toggleBtn.isBordered = false
            toggleBtn.frame = NSRect(x: colX, y: (hudH - 20) / 2.0, width: 22, height: 20)
            toggleBtn.toolTip = "Alternar para Janela Completa (Cmd+M)"
            if let sym = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Alternar Modo") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                toggleBtn.image = sym.withSymbolConfiguration(cfg)
                toggleBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(toggleBtn)
            
            let menuBtn = NSButton(title: "", target: self, action: #selector(showHudContextMenu(_:)))
            menuBtn.isBordered = false
            menuBtn.frame = NSRect(x: colX, y: 10, width: 22, height: 20)
            menuBtn.toolTip = "Menu de Opções"
            if let sym = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Opções") {
                let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                menuBtn.image = sym.withSymbolConfiguration(cfg)
                menuBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
            }
            container.addSubview(menuBtn)
            
            let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
            brandBtn.isBordered = false
            brandBtn.frame = NSRect(x: 12, y: 2, width: 90, height: 12)
            brandBtn.attributedTitle = NSAttributedString(
                string: "vh2c.com.br",
                attributes: [
                    .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 8.0, weight: .medium)
                ]
            )
            container.addSubview(brandBtn)
        }
        
        panel.contentView = container
        panel.orderFront(nil)
    }
    
    @objc func showHudContextMenu(_ sender: NSButton) {
        let menu = buildContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.midX, y: sender.bounds.midY), in: sender)
    }
    
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Opções Gemini Gauge")
        
        let titleItem = NSMenuItem(title: "⚡ Gemini Gauge", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "⚡ Gemini Gauge",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold)]
        )
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let fullItem = NSMenuItem(title: "Alternar Modo de Tela (Janela / HUD)", action: #selector(toggleModeClicked), keyEquivalent: "m")
        fullItem.target = self
        menu.addItem(fullItem)
        
        let orientTitle = (hudOrientation == .vertical) ? "Mudar para Régua Horizontal" : "Mudar para Régua Vertical"
        let orientItem = NSMenuItem(title: orientTitle, action: #selector(toggleHudOrientation), keyEquivalent: "o")
        orientItem.target = self
        menu.addItem(orientItem)
        
        let refreshItem = NSMenuItem(title: "Atualizar Dados Agora", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let settingsItem = NSMenuItem(title: "Configurações... (⚙️)", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let pinItem = NSMenuItem(title: "Sempre no Topo (Flutuante)", action: #selector(toggleAlwaysOnTop), keyEquivalent: "p")
        pinItem.target = self
        pinItem.state = isAlwaysOnTop ? .on : .off
        menu.addItem(pinItem)
        
        let brandItem = NSMenuItem(title: "Visite vh2c.com.br", action: #selector(brandClicked), keyEquivalent: "")
        brandItem.target = self
        menu.addItem(brandItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closeWinItem = NSMenuItem(title: "Fechar Janela (✕)", action: #selector(closeWindowClicked), keyEquivalent: "w")
        closeWinItem.target = self
        menu.addItem(closeWinItem)
        
        let closeItem = NSMenuItem(title: "Encerrar Gemini Gauge", action: #selector(closeClicked), keyEquivalent: "q")
        closeItem.target = self
        menu.addItem(closeItem)
        
        return menu
    }
    
    func setupFullUI(with quota: QuotaData) {
        let colorBg18 = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        let colorField1F = NSColor(srgbRed: 0x1F/255.0, green: 0x1F/255.0, blue: 0x1F/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2C/255.0, green: 0x2C/255.0, blue: 0x2C/255.0, alpha: 1.0)
        let colorSep = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x28/255.0, alpha: 1.0)
        let colorTrack = NSColor(srgbRed: 0x2D/255.0, green: 0x2D/255.0, blue: 0x2D/255.0, alpha: 1.0)
        
        let windowWidth: CGFloat = 460
        var totalCardsHeight: CGFloat = 0
        for g in quota.groups {
            totalCardsHeight += 32 + CGFloat(g.buckets.count * 48 + 14)
        }
        let footerHeight: CGFloat = 66
        let contentHeight: CGFloat = 65 + totalCardsHeight + 10
        let windowHeight = min(contentHeight + footerHeight + 10, 720)
        
        if fullWindow == nil {
            let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            let win = NSWindow(
                contentRect: windowRect,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Gemini Gauge - AI Quota Monitor"
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.level = .normal
            win.center()
            fullWindow = win
        }
        
        guard let window = fullWindow else { return }
        window.backgroundColor = colorBg18
        window.isOpaque = true
        
        let mainView = NSView(frame: window.contentView!.bounds)
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = colorBg18.cgColor
        mainView.autoresizingMask = [.width, .height]
        window.contentView = mainView
        
        let scrollViewHeight = windowHeight - footerHeight
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: windowWidth, height: scrollViewHeight))
        scrollView.hasVerticalScroller = contentHeight > scrollViewHeight
        scrollView.drawsBackground = true
        scrollView.backgroundColor = colorBg18
        scrollView.autoresizingMask = [.width, .height]
        
        let actualContentHeight = max(contentHeight, scrollViewHeight)
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: actualContentHeight))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = colorBg18.cgColor
        
        var currentY = actualContentHeight - 16
        
        // Conta & Plano
        let accountText = "\(quota.account) • Plano \(quota.plan ?? "Universal")"
        let accountLabel = NSTextField(labelWithString: accountText)
        accountLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        accountLabel.textColor = .white
        accountLabel.frame = NSRect(x: 22, y: currentY - 18, width: 416, height: 18)
        contentView.addSubview(accountLabel)
        currentY -= 22
        
        let cacheInfo = (quota.from_cache ?? false) ? " (Cache \(quota.cache_age_seconds ?? 0)s atrás)" : " (Tempo real)"
        let timeText = "Atualizado às \(quota.updated_at ?? "agora")\(cacheInfo)"
        let timeLabel = NSTextField(labelWithString: timeText)
        timeLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        timeLabel.frame = NSRect(x: 22, y: currentY - 15, width: 416, height: 15)
        contentView.addSubview(timeLabel)
        currentY -= 24
        
        // Cards por Provedor / Grupo
        for g in quota.groups {
            let cardHeight = CGFloat(g.buckets.count * 48 + 14)
            
            let cardView = NSBox(frame: NSRect(x: 16, y: currentY - cardHeight, width: windowWidth - 32, height: cardHeight))
            cardView.boxType = .custom
            cardView.fillColor = colorField1F
            cardView.borderColor = colorBorder
            cardView.borderWidth = 1
            cardView.cornerRadius = 8
            contentView.addSubview(cardView)
            
            var cardY = cardHeight - 14
            for (idx, b) in g.buckets.enumerated() {
                if idx > 0 {
                    let sep = NSBox(frame: NSRect(x: 14, y: cardY + 6, width: cardView.frame.width - 28, height: 1))
                    sep.boxType = .custom
                    sep.fillColor = colorSep
                    sep.borderColor = .clear
                    cardView.addSubview(sep)
                }
                
                let bTitle = NSTextField(labelWithString: b.name)
                bTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                bTitle.textColor = .white
                bTitle.frame = NSRect(x: 14, y: cardY - 16, width: 260, height: 16)
                cardView.addSubview(bTitle)
                
                let valStr = "\(b.remaining_pct)%"
                let bVal = NSTextField(labelWithString: valStr)
                bVal.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
                
                if b.remaining_pct >= 50 {
                    bVal.textColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
                } else if b.remaining_pct >= 20 {
                    bVal.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
                } else {
                    bVal.textColor = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
                }
                bVal.alignment = .right
                bVal.frame = NSRect(x: cardView.frame.width - 150, y: cardY - 16, width: 136, height: 16)
                cardView.addSubview(bVal)
                
                cardY -= 20
                
                if let reset = b.reset_in, !reset.isEmpty {
                    let resetLabel = NSTextField(labelWithString: "Renova em \(reset)")
                    resetLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                    resetLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
                    resetLabel.alignment = .right
                    resetLabel.frame = NSRect(x: cardView.frame.width - 160, y: cardY - 12, width: 146, height: 12)
                    cardView.addSubview(resetLabel)
                }
                
                let barBg = NSBox(frame: NSRect(x: 14, y: cardY - 6, width: cardView.frame.width - 28, height: 6))
                barBg.boxType = .custom
                barBg.fillColor = colorTrack
                barBg.borderColor = .clear
                barBg.cornerRadius = 3
                cardView.addSubview(barBg)
                
                let fillWidth = max(CGFloat(barBg.frame.width) * CGFloat(b.remaining_pct) / 100.0, 4)
                let barFill = NSBox(frame: NSRect(x: 14, y: cardY - 6, width: fillWidth, height: 6))
                barFill.boxType = .custom
                barFill.fillColor = bVal.textColor ?? NSColor.systemGreen
                barFill.borderColor = .clear
                barFill.cornerRadius = 3
                cardView.addSubview(barFill)
                
                cardY -= 14
            }
            
            currentY -= (cardHeight + 12)
        }
        
        scrollView.documentView = contentView
        mainView.addSubview(scrollView)
        
        let btnBg = NSColor(srgbRed: 0xEE/255.0, green: 0xEE/255.0, blue: 0xF0/255.0, alpha: 1.0)
        let btnText = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        
        // ----------------- RODAPÉ (Linha 1: Botões) -----------------
        let footerY: CGFloat = 28
        
        // 1. Atualizar
        let refreshBtn = NSButton(title: "", target: self, action: #selector(refreshClicked))
        refreshBtn.isBordered = false
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.backgroundColor = btnBg.cgColor
        refreshBtn.layer?.cornerRadius = 6
        refreshBtn.frame = NSRect(x: 14, y: footerY, width: 88, height: 28)
        refreshBtn.keyEquivalent = "r"
        refreshBtn.keyEquivalentModifierMask = .command
        refreshBtn.imagePosition = .imageLeading
        refreshBtn.imageHugsTitle = true
        refreshBtn.attributedTitle = NSAttributedString(
            string: "Atualizar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Atualizar") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                refreshBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                refreshBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        self.refreshBtn = refreshBtn
        mainView.addSubview(refreshBtn)
        
        // 2. Alternar Modo de Tela (Barra HUD)
        let hudBtn = NSButton(title: "", target: self, action: #selector(toggleModeClicked))
        hudBtn.isBordered = false
        hudBtn.wantsLayer = true
        hudBtn.layer?.backgroundColor = btnBg.cgColor
        hudBtn.layer?.cornerRadius = 6
        hudBtn.frame = NSRect(x: 108, y: footerY, width: 110, height: 28)
        hudBtn.keyEquivalent = "m"
        hudBtn.keyEquivalentModifierMask = .command
        hudBtn.imagePosition = .imageLeading
        hudBtn.imageHugsTitle = true
        hudBtn.toolTip = "Alternar para Modo Barra HUD (Cmd+M)"
        hudBtn.attributedTitle = NSAttributedString(
            string: "Barra HUD",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Alternar Modo") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                hudBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                hudBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(hudBtn)
        
        // 3. Configurações (⚙️)
        let settingsBtn = NSButton(title: "", target: self, action: #selector(openSettings))
        settingsBtn.isBordered = false
        settingsBtn.wantsLayer = true
        settingsBtn.layer?.backgroundColor = btnBg.cgColor
        settingsBtn.layer?.cornerRadius = 6
        settingsBtn.frame = NSRect(x: 224, y: footerY, width: 94, height: 28)
        settingsBtn.keyEquivalent = ","
        settingsBtn.keyEquivalentModifierMask = .command
        settingsBtn.imagePosition = .imageLeading
        settingsBtn.imageHugsTitle = true
        settingsBtn.toolTip = "Configurar Provedores e Chaves de API (Cmd+,)"
        settingsBtn.attributedTitle = NSAttributedString(
            string: "Configurar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Configurações") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                settingsBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                settingsBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(settingsBtn)
        
        // 4. Botão '✕' Fechar Janela
        let closeBtn = NSButton(title: "", target: self, action: #selector(closeWindowClicked))
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = btnBg.cgColor
        closeBtn.layer?.cornerRadius = 6
        closeBtn.frame = NSRect(x: windowWidth - 76, y: footerY, width: 62, height: 28)
        closeBtn.keyEquivalent = "w"
        closeBtn.keyEquivalentModifierMask = .command
        closeBtn.imagePosition = .imageLeading
        closeBtn.imageHugsTitle = true
        closeBtn.toolTip = "Fechar Janela (✕)"
        closeBtn.attributedTitle = NSAttributedString(
            string: " Fechar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                closeBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                closeBtn.image = symbol.withSymbolConfiguration(config)
            }
        }
        mainView.addSubview(closeBtn)
        
        // ----------------- RODAPÉ (Linha 2: Menção vh2c.com.br) -----------------
        let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: 14, y: 5, width: windowWidth - 28, height: 18)
        brandBtn.toolTip = "Acesse vh2c.com.br"
        brandBtn.attributedTitle = NSAttributedString(
            string: "⚡ Gemini Gauge  •  Desenvolvido por vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 0.90),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
            ]
        )
        mainView.addSubview(brandBtn)
        
        if isFirstLaunch {
            isFirstLaunch = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFront(nil)
        }
    }
    
    // MARK: - Settings Window
    @objc func openSettings() {
        if settingsWindow == nil {
            let w: CGFloat = 460
            let h: CGFloat = 530
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Configurações - Gemini Gauge"
            win.backgroundColor = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        
        guard let win = settingsWindow else { return }
        setupSettingsUI(in: win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupSettingsUI(in win: NSWindow) {
        let cfg = QuotaManager.loadConfig()
        let providers = cfg.providers ?? [:]
        
        let colorBg18 = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        let colorField1F = NSColor(srgbRed: 0x1F/255.0, green: 0x1F/255.0, blue: 0x1F/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x33/255.0, green: 0x33/255.0, blue: 0x33/255.0, alpha: 1.0)
        
        let view = NSView(frame: win.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = colorBg18.cgColor
        win.contentView = view
        
        var y: CGFloat = win.frame.height - 42
        
        // Header
        let titleLabel = NSTextField(labelWithString: "⚙️ Provedores de IA & Modelos")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(titleLabel)
        y -= 20
        
        let subLabel = NSTextField(labelWithString: "Configure as fontes de dados para monitoramento das suas cotas:")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        subLabel.frame = NSRect(x: 20, y: y, width: 420, height: 16)
        view.addSubview(subLabel)
        y -= 30
        
        // 1. Google Gemini API
        let geminiCfg = providers["gemini"]
        let geminiBtn = NSButton(checkboxWithTitle: " Google Gemini API (Google AI Studio)", target: nil, action: nil)
        geminiBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        geminiBtn.state = (geminiCfg?.enabled ?? false) ? .on : .off
        geminiBtn.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(geminiBtn)
        self.geminiCheck = geminiBtn
        y -= 26
        
        let geminiField = NSTextField(frame: NSRect(x: 24, y: y, width: 412, height: 24))
        geminiField.placeholderString = "Chave de API Gemini (AIzaSy...)"
        geminiField.stringValue = geminiCfg?.api_key ?? ""
        geminiField.backgroundColor = colorField1F
        geminiField.textColor = .white
        geminiField.wantsLayer = true
        geminiField.layer?.borderColor = colorBorder.cgColor
        geminiField.layer?.borderWidth = 1
        geminiField.layer?.cornerRadius = 4
        view.addSubview(geminiField)
        self.geminiKeyField = geminiField
        y -= 22
        
        let geminiLink = NSButton(title: "Obter Chave Gratuita no Google AI Studio ↗", target: self, action: #selector(openAiStudioLink))
        geminiLink.isBordered = false
        geminiLink.frame = NSRect(x: 20, y: y, width: 280, height: 18)
        geminiLink.attributedTitle = NSAttributedString(
            string: "Obter Chave Gratuita no Google AI Studio ↗",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular)
            ]
        )
        view.addSubview(geminiLink)
        y -= 34
        
        // 2. Antigravity (Live & Headless)
        let antiCfg = providers["antigravity"]
        let antiBtn = NSButton(checkboxWithTitle: " Antigravity IDE (Live & Headless Standalone)", target: nil, action: nil)
        antiBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        antiBtn.state = (antiCfg?.enabled ?? true) ? .on : .off
        antiBtn.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(antiBtn)
        self.antigravityCheck = antiBtn
        y -= 18
        
        let antiDesc = NSTextField(labelWithString: "Detecta cotas do IDE em execução ou via sonda headless quando fechado.")
        antiDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        antiDesc.textColor = NSColor(white: 0.55, alpha: 1.0)
        antiDesc.frame = NSRect(x: 40, y: y, width: 390, height: 14)
        view.addSubview(antiDesc)
        y -= 32
        
        // 3. OpenAI
        let openCfg = providers["openai"]
        let openBtn = NSButton(checkboxWithTitle: " OpenAI API (GPT-4o, o1, etc.)", target: nil, action: nil)
        openBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        openBtn.state = (openCfg?.enabled ?? false) ? .on : .off
        openBtn.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(openBtn)
        self.openaiCheck = openBtn
        y -= 26
        
        let openField = NSTextField(frame: NSRect(x: 24, y: y, width: 412, height: 24))
        openField.placeholderString = "Chave de API OpenAI (sk-...)"
        openField.stringValue = openCfg?.api_key ?? ""
        openField.backgroundColor = colorField1F
        openField.textColor = .white
        openField.wantsLayer = true
        openField.layer?.borderColor = colorBorder.cgColor
        openField.layer?.borderWidth = 1
        openField.layer?.cornerRadius = 4
        view.addSubview(openField)
        self.openaiKeyField = openField
        y -= 32
        
        // 4. Anthropic Claude
        let antCfg = providers["anthropic"]
        let antBtn = NSButton(checkboxWithTitle: " Anthropic Claude API (Sonnet, Opus)", target: nil, action: nil)
        antBtn.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        antBtn.state = (antCfg?.enabled ?? false) ? .on : .off
        antBtn.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        view.addSubview(antBtn)
        self.anthropicCheck = antBtn
        y -= 26
        
        let antField = NSTextField(frame: NSRect(x: 24, y: y, width: 412, height: 24))
        antField.placeholderString = "Chave de API Anthropic (sk-ant-...)"
        antField.stringValue = antCfg?.api_key ?? ""
        antField.backgroundColor = colorField1F
        antField.textColor = .white
        antField.wantsLayer = true
        antField.layer?.borderColor = colorBorder.cgColor
        antField.layer?.borderWidth = 1
        antField.layer?.cornerRadius = 4
        view.addSubview(antField)
        self.anthropicKeyField = antField
        y -= 45
        
        // Buttons
        let saveBtn = NSButton(title: "Salvar e Atualizar", target: self, action: #selector(saveSettingsClicked))
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor(srgbRed: 0xEE/255.0, green: 0xEE/255.0, blue: 0xF0/255.0, alpha: 1.0).cgColor
        saveBtn.layer?.cornerRadius = 6
        saveBtn.frame = NSRect(x: 20, y: 16, width: 140, height: 32)
        saveBtn.attributedTitle = NSAttributedString(
            string: "Salvar e Atualizar",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        view.addSubview(saveBtn)
        
        let cancelBtn = NSButton(title: "Cancelar", target: self, action: #selector(cancelSettingsClicked))
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.frame = NSRect(x: 170, y: 16, width: 90, height: 32)
        cancelBtn.attributedTitle = NSAttributedString(
            string: "Cancelar",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        view.addSubview(cancelBtn)
    }
    
    @objc func openAiStudioLink() {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func saveSettingsClicked() {
        var cfg = QuotaManager.loadConfig()
        if cfg.providers == nil { cfg.providers = [:] }
        
        cfg.providers?["gemini"] = ProviderConfig(
            enabled: geminiCheck?.state == .on,
            api_key: geminiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        cfg.providers?["antigravity"] = ProviderConfig(
            enabled: antigravityCheck?.state == .on,
            api_key: nil
        )
        cfg.providers?["openai"] = ProviderConfig(
            enabled: openaiCheck?.state == .on,
            api_key: openaiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        cfg.providers?["anthropic"] = ProviderConfig(
            enabled: anthropicCheck?.state == .on,
            api_key: anthropicKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
        
        QuotaManager.saveConfig(cfg)
        settingsWindow?.orderOut(nil)
        performRefresh(animated: true)
    }
    
    @objc func cancelSettingsClicked() {
        settingsWindow?.orderOut(nil)
    }
    
    @objc func brandClicked() {
        if let url = URL(string: "https://vh2c.com.br") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func closeClicked() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        NSApp.terminate(nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Red X closes the window but keeps the app alive in status bar
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
