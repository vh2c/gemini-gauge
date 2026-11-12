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
            if let decoded = try? JSONDecoder().decode(QuotaData.self, from: data) {
                var saved = decoded
                saved.timestamp = Date().timeIntervalSince1970
                saved.from_cache = false
                saved.cache_age_seconds = 0
                if let encoded = try? JSONEncoder().encode(saved) {
                    try? encoded.write(to: URL(fileURLWithPath: cachePath))
                }
                return saved
            }
        } catch {
            print("Fetch error: \(error)")
        }
        return nil
    }
}

// MARK: - Radial Gauge View (HUD Widget)
class RadialGaugeView: NSView {
    let item: GaugeItem
    
    init(frame: NSRect, item: GaugeItem) {
        self.item = item
        super.init(frame: frame)
        let rt = item.resetIn != nil && !item.resetIn!.isEmpty ? item.resetIn! : "Totalmente disponível"
        let prov = item.provider != nil ? "Provedor: \(item.provider!)\n" : ""
        self.toolTip = "\(prov)\(item.modelName) • \(item.title)\nCota restante: \(item.percentage)%\nStatus / Reset: \(rt)"
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    var statusColor: NSColor {
        if item.percentage > 50 {
            return NSColor(srgbRed: 0x22/255.0, green: 0x92/255.0, blue: 0x1E/255.0, alpha: 1.0)
        } else if item.percentage > 20 {
            return NSColor(srgbRed: 0xC8/255.0, green: 0x64/255.0, blue: 0x02/255.0, alpha: 1.0)
        } else {
            return NSColor(srgbRed: 0xC6/255.0, green: 0x28/255.0, blue: 0x28/255.0, alpha: 1.0)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (NSApp.delegate as? AppDelegate)?.switchToFullMode()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let cx = bounds.midX
        let cy = bounds.midY + 5
        
        let rOuter: CGFloat = 27.0
        let rInner: CGFloat = 20.5
        let rCenter: CGFloat = 18.0
        let totalTicks = 36
        
        let activeTicks = Int(round(Double(totalTicks) * Double(max(0, min(100, item.percentage))) / 100.0))
        let activeCol = statusColor.cgColor
        let inactiveCol = NSColor(white: 0.32, alpha: 0.7).cgColor
        
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        
        for i in 0..<totalTicks {
            let frac = Double(i) / Double(totalTicks)
            let angle = -Double.pi / 2.0 + frac * 2.0 * Double.pi
            
            let p1 = CGPoint(x: cx + CGFloat(cos(angle)) * rInner, y: cy + CGFloat(sin(angle)) * rInner)
            let p2 = CGPoint(x: cx + CGFloat(cos(angle)) * rOuter, y: cy + CGFloat(sin(angle)) * rOuter)
            
            ctx.setStrokeColor(i < activeTicks ? activeCol : inactiveCol)
            ctx.beginPath()
            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.strokePath()
        }
        
        ctx.setFillColor(activeCol)
        ctx.fillEllipse(in: CGRect(x: cx - rCenter, y: cy - rCenter, width: rCenter * 2, height: rCenter * 2))
        
        let pctStr = "\(item.percentage)%"
        let fontSize: CGFloat = item.percentage >= 100 ? 9.0 : 10.0
        let pctFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: pctFont,
            .foregroundColor: NSColor.white
        ]
        let pctSize = (pctStr as NSString).size(withAttributes: pctAttrs)
        let pctRect = CGRect(x: cx - pctSize.width / 2.0, y: cy - pctSize.height / 2.0 + 0.5, width: pctSize.width, height: pctSize.height)
        (pctStr as NSString).draw(in: pctRect, withAttributes: pctAttrs)
        
        drawCurvedText(text: item.title, center: CGPoint(x: cx, y: cy), radius: rOuter + 8.5, context: ctx)
        
        let subY = cy - rOuter - 13
        let modelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let modelSize = (item.modelName as NSString).size(withAttributes: modelAttrs)
        (item.modelName as NSString).draw(in: CGRect(x: cx - modelSize.width / 2.0, y: subY, width: modelSize.width, height: 12), withAttributes: modelAttrs)
        
        if let rt = item.resetIn, !rt.isEmpty {
            let rtAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .regular),
                .foregroundColor: NSColor(white: 0.65, alpha: 1.0)
            ]
            let rtSize = (rt as NSString).size(withAttributes: rtAttrs)
            (rt as NSString).draw(in: CGRect(x: cx - rtSize.width / 2.0, y: subY - 11, width: rtSize.width, height: 10), withAttributes: rtAttrs)
        }
    }
    
    private func drawCurvedText(text: String, center: CGPoint, radius: CGFloat, context: CGContext) {
        let font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let chars = Array(text)
        var charWidths: [CGFloat] = []
        var totalWidth: CGFloat = 0
        for ch in chars {
            let s = String(ch) as NSString
            let w = s.size(withAttributes: attrs).width
            charWidths.append(w)
            totalWidth += w
        }
        
        let charHeight = ("A" as NSString).size(withAttributes: attrs).height
        let angularSpan = totalWidth / radius
        var currentAngle = Double.pi / 2.0 + Double(angularSpan) / 2.0
        
        for (i, ch) in chars.enumerated() {
            let w = charWidths[i]
            let charAngle = Double(w / radius)
            let midAngle = currentAngle - charAngle / 2.0
            
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
    
    var currentMode: DisplayMode = .full
    var hudOrientation: HudOrientation = .vertical
    var isAlwaysOnTop: Bool = true
    
    var autoRefreshTimer: Timer?
    var refreshBtn: NSButton?
    var isRefreshing: Bool = false
    var isFirstLaunch: Bool = true
    var latestQuota: QuotaData?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        } else {
            NSApp.terminate(nil)
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
    
    func setupHudUI(with quota: QuotaData) {
        let items = quota.gaugeItems
        let isVertical = (hudOrientation == .vertical)
        
        let hudW: CGFloat = isVertical ? 104 : (28 + CGFloat(items.count) * 96 + 10)
        let hudH: CGFloat = isVertical ? (28 + CGFloat(items.count) * 96 + 16) : 108
        
        if hudWindow == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let initX = isVertical ? (screen.maxX - hudW - 16) : (screen.midX - hudW / 2.0)
            let initY = isVertical ? (screen.midY - hudH / 2.0) : (screen.minY + 24)
            let rect = NSRect(x: initX, y: initY, width: hudW, height: hudH)
            
            let panel = NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = isAlwaysOnTop ? .floating : .normal
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            hudWindow = panel
        } else {
            let curFrame = hudWindow!.frame
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let newX = max(screen.minX + 8, min(curFrame.origin.x, screen.maxX - hudW - 8))
            let newY = max(screen.minY + 8, min(curFrame.origin.y + (curFrame.height - hudH), screen.maxY - hudH - 8))
            hudWindow!.setFrame(NSRect(x: newX, y: newY, width: hudW, height: hudH), display: true, animate: true)
        }
        
        guard let panel = hudWindow else { return }
        
        let container = HudContainerView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        container.delegate = self
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.95).cgColor
        container.layer?.cornerRadius = 14
        container.layer?.borderWidth = 1.0
        container.layer?.borderColor = NSColor(white: 0.22, alpha: 1.0).cgColor
        container.menu = buildHudContextMenu()
        
        let toolColor = NSColor(white: 0.70, alpha: 1.0)
        func createMiniBtn(symbolName: String, tooltip: String, action: Selector) -> NSButton {
            let btn = NSButton(frame: .zero)
            btn.isBordered = false
            btn.target = self
            btn.action = action
            btn.toolTip = tooltip
            if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
                btn.image = sym.withSymbolConfiguration(cfg)
                btn.contentTintColor = toolColor
            }
            return btn
        }
        
        let btnClose = createMiniBtn(symbolName: "xmark", tooltip: "Fechar App", action: #selector(closeClicked))
        let btnOrient = createMiniBtn(symbolName: isVertical ? "rectangle.portrait.and.arrow.forward" : "rectangle.and.arrow.up.right.and.arrow.down.left", tooltip: "Alternar Orientação (Vertical / Horizontal)", action: #selector(toggleHudOrientation))
        let btnFull = createMiniBtn(symbolName: "arrow.up.left.and.arrow.down.right", tooltip: "Abrir Janela Completa (Cmd+M)", action: #selector(switchToFullMode))
        let btnRefresh = createMiniBtn(symbolName: "arrow.clockwise", tooltip: "Atualizar Cotas (Cmd+R)", action: #selector(refreshClicked))
        
        if isVertical {
            btnClose.frame = NSRect(x: 10, y: hudH - 22, width: 16, height: 16)
            btnOrient.frame = NSRect(x: 32, y: hudH - 22, width: 16, height: 16)
            btnFull.frame = NSRect(x: 54, y: hudH - 22, width: 16, height: 16)
            btnRefresh.frame = NSRect(x: 76, y: hudH - 22, width: 16, height: 16)
        } else {
            btnClose.frame = NSRect(x: 6, y: hudH - 22, width: 16, height: 16)
            btnOrient.frame = NSRect(x: 6, y: hudH - 44, width: 16, height: 16)
            btnFull.frame = NSRect(x: 6, y: hudH - 66, width: 16, height: 16)
            btnRefresh.frame = NSRect(x: 6, y: hudH - 88, width: 16, height: 16)
        }
        
        container.addSubview(btnClose)
        container.addSubview(btnOrient)
        container.addSubview(btnFull)
        container.addSubview(btnRefresh)
        
        if isVertical {
            var curY = hudH - 28
            for item in items {
                let gView = RadialGaugeView(frame: NSRect(x: 2, y: curY - 96, width: 100, height: 96), item: item)
                container.addSubview(gView)
                curY -= 96
            }
            let brand = NSTextField(labelWithString: "vh2c.com.br")
            brand.font = NSFont.systemFont(ofSize: 8, weight: .regular)
            brand.textColor = NSColor(white: 0.35, alpha: 1.0)
            brand.alignment = .center
            brand.frame = NSRect(x: 2, y: 4, width: 100, height: 12)
            container.addSubview(brand)
        } else {
            var curX: CGFloat = 28
            for item in items {
                let gView = RadialGaugeView(frame: NSRect(x: curX, y: 6, width: 96, height: 96), item: item)
                container.addSubview(gView)
                curX += 96
            }
        }
        
        panel.contentView = container
        panel.orderFront(nil)
    }
    
    func buildHudContextMenu() -> NSMenu {
        let menu = NSMenu()
        let orientTitle = hudOrientation == .vertical ? "Mudar para Horizontal (Topo/Rodapé)" : "Mudar para Vertical (Lateral)"
        let orientItem = NSMenuItem(title: orientTitle, action: #selector(toggleHudOrientation), keyEquivalent: "o")
        orientItem.target = self
        menu.addItem(orientItem)
        
        let fullItem = NSMenuItem(title: "Abrir Janela Completa (Detalhada)", action: #selector(switchToFullMode), keyEquivalent: "m")
        fullItem.target = self
        menu.addItem(fullItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Atualizar Cotas Agora", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let pinItem = NSMenuItem(title: "Sempre no Topo (Flutuante)", action: #selector(toggleAlwaysOnTop), keyEquivalent: "p")
        pinItem.target = self
        pinItem.state = isAlwaysOnTop ? .on : .off
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let closeItem = NSMenuItem(title: "Fechar Quota Hub", action: #selector(closeClicked), keyEquivalent: "q")
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
        let contentHeight: CGFloat = 65 + totalCardsHeight + 10
        let windowHeight = min(contentHeight + 52, 700)
        
        if fullWindow == nil {
            let windowRect = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            let win = NSWindow(
                contentRect: windowRect,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Universal AI Quota Hub"
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
        
        let scrollViewHeight = windowHeight - 50
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: windowWidth, height: scrollViewHeight))
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
            
            let provStr = g.provider != nil ? " [\(g.provider!)]" : ""
            let groupLabel = NSTextField(labelWithString: (g.name + provStr).uppercased())
            groupLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            groupLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
            groupLabel.frame = NSRect(x: 22, y: currentY - 14, width: 416, height: 14)
            contentView.addSubview(groupLabel)
            currentY -= 18
            
            let cardView = NSView(frame: NSRect(x: 20, y: currentY - cardHeight, width: windowWidth - 40, height: cardHeight))
            cardView.wantsLayer = true
            cardView.layer?.backgroundColor = colorField1F.cgColor
            cardView.layer?.cornerRadius = 8
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = colorBorder.cgColor
            contentView.addSubview(cardView)
            
            var cardY = cardHeight - 12
            for (idx, b) in g.buckets.enumerated() {
                if idx > 0 {
                    let sep = NSBox(frame: NSRect(x: 14, y: cardY + 6, width: cardView.frame.width - 28, height: 1))
                    sep.boxType = .separator
                    sep.borderColor = colorSep
                    cardView.addSubview(sep)
                }
                
                let bName = NSTextField(labelWithString: b.name)
                bName.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                bName.textColor = .white
                bName.frame = NSRect(x: 14, y: cardY - 18, width: 230, height: 18)
                cardView.addSubview(bName)
                
                let resetStr = (b.reset_in != nil && !b.reset_in!.isEmpty) ? " • \(b.reset_in!)" : ""
                let valText = "\(b.remaining_pct)%\(resetStr)"
                let bVal = NSTextField(labelWithString: valText)
                bVal.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
                bVal.alignment = .right
                
                if b.remaining_pct > 50 {
                    bVal.textColor = NSColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1.0)
                } else if b.remaining_pct > 20 {
                    bVal.textColor = NSColor(red: 1.00, green: 0.65, blue: 0.15, alpha: 1.0)
                } else {
                    bVal.textColor = NSColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1.0)
                }
                bVal.frame = NSRect(x: cardView.frame.width - 180, y: cardY - 18, width: 166, height: 18)
                cardView.addSubview(bVal)
                cardY -= 20
                
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
        
        let refreshBtn = NSButton(title: "", target: self, action: #selector(refreshClicked))
        refreshBtn.isBordered = false
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.backgroundColor = btnBg.cgColor
        refreshBtn.layer?.cornerRadius = 6
        refreshBtn.frame = NSRect(x: 16, y: 12, width: 94, height: 30)
        refreshBtn.keyEquivalent = "r"
        refreshBtn.keyEquivalentModifierMask = .command
        refreshBtn.imagePosition = .imageLeading
        refreshBtn.imageHugsTitle = true
        refreshBtn.attributedTitle = NSAttributedString(
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
                refreshBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                refreshBtn.image = symbol.withSymbolConfiguration(config)
                refreshBtn.contentTintColor = btnText
            }
        }
        self.refreshBtn = refreshBtn
        mainView.addSubview(refreshBtn)
        
        let hudBtn = NSButton(title: "", target: self, action: #selector(switchToHudMode))
        hudBtn.isBordered = false
        hudBtn.wantsLayer = true
        hudBtn.layer?.backgroundColor = btnBg.cgColor
        hudBtn.layer?.cornerRadius = 6
        hudBtn.frame = NSRect(x: 118, y: 12, width: 102, height: 30)
        hudBtn.keyEquivalent = "m"
        hudBtn.keyEquivalentModifierMask = .command
        hudBtn.imagePosition = .imageLeading
        hudBtn.imageHugsTitle = true
        hudBtn.attributedTitle = NSAttributedString(
            string: "Barra HUD",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        if let symbol = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Modo HUD") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            if #available(macOS 12.0, *) {
                let tinted = config.applying(.init(paletteColors: [btnText]))
                hudBtn.image = symbol.withSymbolConfiguration(tinted)
            } else {
                hudBtn.image = symbol.withSymbolConfiguration(config)
                hudBtn.contentTintColor = btnText
            }
        }
        mainView.addSubview(hudBtn)
        
        let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: 228, y: 17, width: 128, height: 20)
        let brandAttr = NSAttributedString(
            string: "vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10, weight: .regular)
            ]
        )
        brandBtn.attributedTitle = brandAttr
        mainView.addSubview(brandBtn)
        
        let closeBtn = NSButton(title: "", target: self, action: #selector(closeClicked))
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.backgroundColor = btnBg.cgColor
        closeBtn.layer?.cornerRadius = 6
        closeBtn.frame = NSRect(x: windowWidth - 92, y: 12, width: 76, height: 30)
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.attributedTitle = NSAttributedString(
            string: "Fechar",
            attributes: [
                .foregroundColor: btnText,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        mainView.addSubview(closeBtn)
        
        if isFirstLaunch {
            isFirstLaunch = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFront(nil)
        }
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
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
