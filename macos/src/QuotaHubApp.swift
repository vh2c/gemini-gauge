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

struct GaugeSection {
    let name: String
    let subtitle: String?
    let tag: String // "ANTIGRAVITY", "AI STUDIO", "OPENAI", "CLAUDE"
    let accentColor: NSColor
    let items: [GaugeItem]
}

struct GaugeItem {
    let id: String
    let title: String
    let modelName: String
    let percentage: Int
    let resetIn: String?
    let detail: String?
    let provider: String?
    let sectionTag: String
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
    var gaugeSections: [GaugeSection] {
        var sections: [GaugeSection] = []
        
        var antiGroups: [Group] = []
        var studioGroups: [Group] = []
        var openGroups: [Group] = []
        var antGroups: [Group] = []
        var otherGroups: [Group] = []
        
        for g in groups {
            let p = (g.provider ?? "").lowercased()
            let n = g.name.lowercased()
            if p.contains("antigravity") || n.contains("antigravity") || n.contains("argon") || n.contains("claude and gpt") {
                antiGroups.append(g)
            } else if p.contains("studio") || n.contains("google gemini api") || n.contains("ai studio") {
                studioGroups.append(g)
            } else if p.contains("openai") || n.contains("openai") {
                openGroups.append(g)
            } else if p.contains("anthropic") || n.contains("anthropic") {
                antGroups.append(g)
            } else {
                otherGroups.append(g)
            }
        }
        
        if !antiGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in antiGroups {
                let modelLabel: String
                let lowerG = g.name.lowercased()
                if lowerG.contains("gemini 4") || lowerG.contains("argon") {
                    modelLabel = "Argon"
                } else if lowerG.contains("claude") || lowerG.contains("gpt") {
                    modelLabel = "Claude/GPT"
                } else {
                    modelLabel = "Gemini"
                }
                for b in g.buckets {
                    let limitTitle: String
                    let lowerB = b.name.lowercased()
                    if lowerB.contains("five") || lowerB.contains("5") {
                        limitTitle = "5 hours Limit"
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
                        provider: g.provider,
                        sectionTag: "ANTIGRAVITY"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Antigravity",
                subtitle: "Live & Headless",
                tag: "ANTIGRAVITY",
                accentColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                items: items
            ))
        }
        
        if !studioGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in studioGroups {
                for b in g.buckets {
                    let limitTitle: String
                    let modelLabel: String
                    let lowerB = b.name.lowercased()
                    let bId = (b.id ?? "").lowercased()
                    if lowerB.contains("flash") || bId.contains("flash") {
                        limitTitle = "Flash RPM"
                        modelLabel = "Gemini Flash"
                    } else if lowerB.contains("pro") || bId.contains("pro") {
                        limitTitle = "Pro RPM"
                        modelLabel = "Gemini Pro"
                    } else {
                        limitTitle = "API Key"
                        modelLabel = "AI Studio"
                    }
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: limitTitle,
                        modelName: modelLabel,
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "STUDIO"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Google AI Studio",
                subtitle: "Gemini API",
                tag: "AI STUDIO",
                accentColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0),
                items: items
            ))
        }
        
        if !openGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in openGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: "TPM / RPM",
                        modelName: "OpenAI",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "OPENAI"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "OpenAI API",
                subtitle: "GPT Models",
                tag: "OPENAI",
                accentColor: NSColor(srgbRed: 0x10/255.0, green: 0xA3/255.0, blue: 0x7F/255.0, alpha: 1.0),
                items: items
            ))
        }
        
        if !antGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in antGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: "Rate Limit",
                        modelName: "Claude API",
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "CLAUDE"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Anthropic Claude",
                subtitle: "Claude API",
                tag: "CLAUDE",
                accentColor: NSColor(srgbRed: 0xD9/255.0, green: 0x77/255.0, blue: 0x06/255.0, alpha: 1.0),
                items: items
            ))
        }
        
        if !otherGroups.isEmpty {
            var items: [GaugeItem] = []
            for g in otherGroups {
                for b in g.buckets {
                    items.append(GaugeItem(
                        id: b.id ?? "",
                        title: b.name,
                        modelName: g.name,
                        percentage: b.remaining_pct,
                        resetIn: b.reset_in,
                        detail: b.detail,
                        provider: g.provider,
                        sectionTag: "OTHER"
                    ))
                }
            }
            sections.append(GaugeSection(
                name: "Outros Provedores",
                subtitle: nil,
                tag: "OUTROS",
                accentColor: NSColor(white: 0.7, alpha: 1.0),
                items: items
            ))
        }
        
        return sections
    }
    
    var gaugeItems: [GaugeItem] {
        return gaugeSections.flatMap { $0.items }
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
        
        let colorGreen: NSColor
        if item.sectionTag == "STUDIO" {
            colorGreen = NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0)
        } else if item.sectionTag == "OPENAI" {
            colorGreen = NSColor(srgbRed: 0x10/255.0, green: 0xA3/255.0, blue: 0x7F/255.0, alpha: 1.0)
        } else if item.sectionTag == "CLAUDE" {
            colorGreen = NSColor(srgbRed: 0xD9/255.0, green: 0x77/255.0, blue: 0x06/255.0, alpha: 1.0)
        } else {
            colorGreen = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
        }
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

class FlippedContentView: NSView {
    override var isFlipped: Bool { return true }
}

class FlippedBox: NSBox {
    override var isFlipped: Bool { return true }
}

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds theRect: NSRect) -> NSRect {
        var r = theRect
        let textSize = cellSize(forBounds: theRect)
        let delta = (theRect.size.height - textSize.height) / 2.0
        if delta > 0 {
            r.origin.y += delta.rounded()
            r.size.height = textSize.height
        }
        r.origin.x += 12.0
        r.size.width = max(theRect.size.width - 24.0, 10.0)
        return r
    }
    
    override func titleRect(forBounds theRect: NSRect) -> NSRect {
        return drawingRect(forBounds: theRect)
    }
    
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

func makeCenteredDarkField(frame: NSRect, placeholder: String, value: String) -> NSTextField {
    let field = NSTextField(frame: frame)
    field.cell = VerticallyCenteredTextFieldCell(textCell: value)
    field.isBordered = false
    field.focusRingType = .none
    field.wantsLayer = true
    field.backgroundColor = NSColor(srgbRed: 0x14/255.0, green: 0x14/255.0, blue: 0x16/255.0, alpha: 1.0)
    field.textColor = .white
    field.font = NSFont.systemFont(ofSize: 12.0)
    field.layer?.borderColor = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x33/255.0, alpha: 1.0).cgColor
    field.layer?.borderWidth = 1.0
    field.layer?.cornerRadius = 6.0
    field.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [
            .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 12.0)
        ]
    )
    field.stringValue = value
    return field
}

func makeSectionBadge(title: String, color: NSColor, width: CGFloat) -> NSView {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))
    let bgBox = NSBox(frame: NSRect(x: 8, y: 0, width: width - 16, height: 20))
    bgBox.boxType = .custom
    bgBox.fillColor = color.withAlphaComponent(0.12)
    bgBox.borderColor = color.withAlphaComponent(0.35)
    bgBox.borderWidth = 1.0
    bgBox.cornerRadius = 10.0
    container.addSubview(bgBox)
    
    let dot = NSBox(frame: NSRect(x: 16, y: 7, width: 6, height: 6))
    dot.boxType = .custom
    dot.fillColor = color
    dot.borderColor = .clear
    dot.cornerRadius = 3.0
    container.addSubview(dot)
    
    let label = NSTextField(labelWithString: title.uppercased())
    label.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
    label.textColor = color
    label.alignment = .center
    label.frame = NSRect(x: 24, y: 3, width: width - 40, height: 14)
    container.addSubview(label)
    
    return container
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
    var geminiTestBtn: NSButton?
    var geminiStatusLabel: NSTextField?
    var antigravityCheck: NSButton?
    var openaiCheck: NSButton?
    var openaiKeyField: NSTextField?
    var anthropicCheck: NSButton?
    var anthropicKeyField: NSTextField?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        sendTelemetryHeartbeat()
        
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
    
    func getMachineId() -> String {
        let devFile = NSString(string: "~/.config/UniversalAIQuota/device_id").expandingTildeInPath
        if let existing = try? String(contentsOfFile: devFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }
        let fallback = UUID().uuidString.lowercased()
        try? fallback.write(toFile: devFile, atomically: true, encoding: .utf8)
        return fallback
    }
    
    func sendTelemetryHeartbeat() {
        guard let url = URL(string: "https://api.vh2c.com.br/v1/geminigauje") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GeminiGauge/1.0 (macOS; VH2C)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 2.5
        
        let payload: [String: Any] = [
            "app": "gemini-gauge",
            "version": "1.0.0",
            "os": "macOS",
            "arch": "arm64",
            "machine_id": getMachineId(),
            "timestamp": Int(Date().timeIntervalSince1970)
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
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
        let sections = quota.gaugeSections
        let isVertical = (hudOrientation == .vertical)
        let totalItems = sections.reduce(0) { $0 + $1.items.count }
        
        let hudW: CGFloat
        let hudH: CGFloat
        let maxScreenH = (NSScreen.main?.visibleFrame.height ?? 800) - 60
        
        if totalItems == 0 {
            hudW = isVertical ? 124 : 260
            hudH = isVertical ? 180 : 100
        } else if isVertical {
            hudW = 116
            let calcH = 28 + CGFloat(sections.count) * 28 + CGFloat(totalItems) * 96 + 24
            hudH = min(calcH, maxScreenH)
        } else {
            let sectionsGap = CGFloat(max(sections.count - 1, 0)) * 16
            hudW = max(28 + CGFloat(totalItems) * 96 + sectionsGap + 36, 260)
            hudH = 126
        }
        
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
            
            if totalItems == 0 {
                // Empty state vertical
                let iconLabel = NSTextField(labelWithString: "📡")
                iconLabel.font = NSFont.systemFont(ofSize: 22)
                iconLabel.alignment = .center
                iconLabel.frame = NSRect(x: 10, y: hudH - 58, width: hudW - 20, height: 26)
                container.addSubview(iconLabel)
                
                let emptyTitle = NSTextField(labelWithString: "Sem Cotas")
                emptyTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
                emptyTitle.textColor = .white
                emptyTitle.alignment = .center
                emptyTitle.frame = NSRect(x: 4, y: hudH - 82, width: hudW - 8, height: 16)
                container.addSubview(emptyTitle)
                
                let emptySub = NSTextField(labelWithString: "Abra o IDE ou\ninsira API Key")
                emptySub.font = NSFont.systemFont(ofSize: 9, weight: .regular)
                emptySub.textColor = NSColor(white: 0.60, alpha: 1.0)
                emptySub.alignment = .center
                emptySub.frame = NSRect(x: 4, y: hudH - 118, width: hudW - 8, height: 28)
                container.addSubview(emptySub)
                
                let cfgBtn = NSButton(title: "Configurar", target: self, action: #selector(openSettings))
                cfgBtn.isBordered = false
                cfgBtn.wantsLayer = true
                cfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x28/255.0, alpha: 1.0).cgColor
                cfgBtn.layer?.cornerRadius = 5
                cfgBtn.frame = NSRect(x: 12, y: 26, width: hudW - 24, height: 22)
                cfgBtn.attributedTitle = NSAttributedString(
                    string: "⚙️ Configurar",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
                    ]
                )
                container.addSubview(cfgBtn)
            } else {
                let footerH: CGFloat = 20
                let topBarH: CGFloat = 26
                let scrollH = hudH - topBarH - footerH
                let contentH = CGFloat(sections.count) * 28 + CGFloat(totalItems) * 96
                
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerH, width: hudW, height: scrollH))
                scrollView.hasVerticalScroller = (contentH > scrollH)
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                
                let contentView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: hudW, height: max(contentH, scrollH)))
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
                
                var curY: CGFloat = 2
                for s in sections {
                    let badge = makeSectionBadge(title: s.name, color: s.accentColor, width: hudW)
                    badge.frame = NSRect(x: 0, y: curY, width: hudW, height: 20)
                    contentView.addSubview(badge)
                    curY += 24
                    
                    for item in s.items {
                        let gauge = TachometerGaugeView(item: item)
                        gauge.frame = NSRect(x: (hudW - 88) / 2.0, y: curY, width: 88, height: 96)
                        contentView.addSubview(gauge)
                        curY += 96
                    }
                    curY += 4
                }
                
                scrollView.documentView = contentView
                container.addSubview(scrollView)
            }
            
            let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
            brandBtn.isBordered = false
            brandBtn.frame = NSRect(x: 4, y: 3, width: hudW - 8, height: 16)
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
            if totalItems == 0 {
                let msgLabel = NSTextField(labelWithString: "📡 Sem cotas ativas no momento")
                msgLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                msgLabel.textColor = .white
                msgLabel.frame = NSRect(x: 14, y: hudH - 36, width: hudW - 60, height: 16)
                container.addSubview(msgLabel)
                
                let subLabel = NSTextField(labelWithString: "Abra o Antigravity IDE ou adicione uma chave de API")
                subLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
                subLabel.textColor = NSColor(white: 0.60, alpha: 1.0)
                subLabel.frame = NSRect(x: 14, y: hudH - 56, width: hudW - 60, height: 14)
                container.addSubview(subLabel)
                
                let cfgBtn = NSButton(title: "Configurar Provedores", target: self, action: #selector(openSettings))
                cfgBtn.isBordered = false
                cfgBtn.wantsLayer = true
                cfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x24/255.0, green: 0x24/255.0, blue: 0x28/255.0, alpha: 1.0).cgColor
                cfgBtn.layer?.cornerRadius = 5
                cfgBtn.frame = NSRect(x: 14, y: 16, width: 140, height: 22)
                cfgBtn.attributedTitle = NSAttributedString(
                    string: "⚙️ Configurar Provedores",
                    attributes: [
                        .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                        .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
                    ]
                )
                container.addSubview(cfgBtn)
            } else {
                var curX: CGFloat = 12
                for (sIdx, s) in sections.enumerated() {
                    if sIdx > 0 {
                        let sep = NSBox(frame: NSRect(x: curX + 2, y: 16, width: 1, height: hudH - 32))
                        sep.boxType = .custom
                        sep.fillColor = NSColor(srgbRed: 0x33/255.0, green: 0x33/255.0, blue: 0x38/255.0, alpha: 1.0)
                        sep.borderColor = .clear
                        container.addSubview(sep)
                        curX += 14
                    }
                    
                    let tagLabel = NSTextField(labelWithString: s.name.uppercased())
                    tagLabel.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
                    tagLabel.textColor = s.accentColor
                    tagLabel.frame = NSRect(x: curX + 4, y: hudH - 20, width: CGFloat(s.items.count) * 96, height: 14)
                    container.addSubview(tagLabel)
                    
                    for item in s.items {
                        let gauge = TachometerGaugeView(item: item)
                        gauge.frame = NSRect(x: curX, y: 12, width: 88, height: 96)
                        container.addSubview(gauge)
                        curX += 96
                    }
                }
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
        let colorField1F = NSColor(srgbRed: 0x1E/255.0, green: 0x1E/255.0, blue: 0x22/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2C/255.0, green: 0x2C/255.0, blue: 0x30/255.0, alpha: 1.0)
        let colorSep = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x2E/255.0, alpha: 1.0)
        let colorTrack = NSColor(srgbRed: 0x28/255.0, green: 0x28/255.0, blue: 0x2D/255.0, alpha: 1.0)
        
        let windowWidth: CGFloat = 460
        let footerHeight: CGFloat = 68
        
        // Calcular altura total do conteúdo
        var calcContentH: CGFloat = 18 // padding do topo
        calcContentH += 22 // Título do app e link vh2c
        calcContentH += 18 // Conta e plano
        calcContentH += 16 // Status e timestamp
        calcContentH += 18 // Divisor e espaçamento generoso antes dos cards
        
        if quota.groups.isEmpty {
            calcContentH += 110 + 16
        } else {
            for g in quota.groups {
                calcContentH += 30 + CGFloat(g.buckets.count * 48 + 8) + 14
            }
        }
        calcContentH += 16 // padding inferior
        
        let windowHeight = min(calcContentH + footerHeight, 720)
        
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
        } else if let win = fullWindow {
            let cur = win.frame
            let newY = cur.origin.y + (cur.height - windowHeight)
            win.setFrame(NSRect(x: cur.origin.x, y: newY, width: windowWidth, height: windowHeight), display: true, animate: false)
        }
        
        guard let window = fullWindow else { return }
        window.backgroundColor = colorBg18
        window.isOpaque = true
        
        let mainView = NSView(frame: window.contentView!.bounds)
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = colorBg18.cgColor
        mainView.autoresizingMask = [.width, .height]
        window.contentView = mainView
        
        let scrollViewHeight = window.contentView!.bounds.height - footerHeight
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: windowWidth, height: scrollViewHeight))
        scrollView.hasVerticalScroller = calcContentH > scrollViewHeight
        scrollView.drawsBackground = true
        scrollView.backgroundColor = colorBg18
        scrollView.autoresizingMask = [.width, .height]
        
        let contentView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: max(calcContentH, scrollViewHeight)))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = colorBg18.cgColor
        
        var y: CGFloat = 18
        
        // ----------------- HEADER COM ESPAÇAMENTO -----------------
        let appTitle = NSTextField(labelWithString: "Gemini Gauge")
        appTitle.font = NSFont.systemFont(ofSize: 15.5, weight: .bold)
        appTitle.textColor = .white
        appTitle.frame = NSRect(x: 20, y: y, width: 220, height: 20)
        contentView.addSubview(appTitle)
        y += 24
        
        let accountText = "\(quota.account)  •  Plano \(quota.plan ?? "Universal")"
        let accountLabel = NSTextField(labelWithString: accountText)
        accountLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        accountLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        accountLabel.frame = NSRect(x: 20, y: y, width: windowWidth - 40, height: 16)
        contentView.addSubview(accountLabel)
        y += 18
        
        let cacheInfo = (quota.from_cache ?? false) ? " (Cache \(quota.cache_age_seconds ?? 0)s atrás)" : " (Tempo real)"
        let timeText = "Atualizado às \(quota.updated_at ?? "agora")\(cacheInfo)"
        let timeLabel = NSTextField(labelWithString: timeText)
        timeLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        timeLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        timeLabel.frame = NSRect(x: 20, y: y, width: windowWidth - 40, height: 14)
        contentView.addSubview(timeLabel)
        y += 20
        
        let headerDivider = NSBox(frame: NSRect(x: 18, y: y, width: windowWidth - 36, height: 1))
        headerDivider.boxType = .custom
        headerDivider.fillColor = colorSep
        headerDivider.borderColor = .clear
        contentView.addSubview(headerDivider)
        y += 16 // Espaçamento generoso entre o header e os primeiros indicadores de cota!
        
        // ----------------- CARDS POR PROVEDOR / GRUPO -----------------
        if quota.groups.isEmpty {
            let emptyH: CGFloat = 110
            let cardView = NSBox(frame: NSRect(x: 16, y: y, width: windowWidth - 32, height: emptyH))
            cardView.boxType = .custom
            cardView.fillColor = colorField1F
            cardView.borderColor = colorBorder
            cardView.borderWidth = 1
            cardView.cornerRadius = 8
            contentView.addSubview(cardView)
            
            let eTitle = NSTextField(labelWithString: "Nenhum Provedor Ativo")
            eTitle.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            eTitle.textColor = .white
            eTitle.frame = NSRect(x: 16, y: 14, width: cardView.frame.width - 32, height: 18)
            cardView.addSubview(eTitle)
            
            let eDesc = NSTextField(labelWithString: "O Antigravity IDE está fechado e nenhuma chave de API adicional (Gemini, OpenAI, Claude) foi configurada.")
            eDesc.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            eDesc.textColor = NSColor(white: 0.65, alpha: 1.0)
            eDesc.lineBreakMode = .byWordWrapping
            eDesc.frame = NSRect(x: 16, y: 38, width: cardView.frame.width - 32, height: 32)
            cardView.addSubview(eDesc)
            
            let openCfgBtn = NSButton(title: "Configurar Provedores", target: self, action: #selector(openSettings))
            openCfgBtn.isBordered = false
            openCfgBtn.wantsLayer = true
            openCfgBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x30/255.0, alpha: 1.0).cgColor
            openCfgBtn.layer?.cornerRadius = 5
            openCfgBtn.frame = NSRect(x: 16, y: 76, width: 170, height: 22)
            openCfgBtn.attributedTitle = NSAttributedString(
                string: "⚙️ Configurar Provedores",
                attributes: [
                    .foregroundColor: NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)
                ]
            )
            cardView.addSubview(openCfgBtn)
            y += emptyH + 14
        } else {
            for g in quota.groups {
                let cardHeight = 30 + CGFloat(g.buckets.count * 48 + 8)
                let cardView = NSBox(frame: NSRect(x: 16, y: y, width: windowWidth - 32, height: cardHeight))
                cardView.boxType = .custom
                cardView.fillColor = colorField1F
                cardView.borderColor = colorBorder
                cardView.borderWidth = 1
                cardView.cornerRadius = 8
                contentView.addSubview(cardView)
                
                let isStudio = (g.provider ?? "").lowercased().contains("studio") || g.name.lowercased().contains("gemini api")
                let accentColor = isStudio
                    ? NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0)
                    : NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
                
                // Group Title
                let gTitle = NSTextField(labelWithString: g.name)
                gTitle.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
                gTitle.textColor = NSColor(white: 0.95, alpha: 1.0)
                gTitle.frame = NSRect(x: 14, y: 10, width: cardView.frame.width - 170, height: 16)
                cardView.addSubview(gTitle)
                
                let tagText = isStudio ? "GOOGLE AI STUDIO" : "ANTIGRAVITY"
                let tagLabel = NSTextField(labelWithString: tagText)
                tagLabel.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
                tagLabel.textColor = accentColor
                tagLabel.alignment = .right
                tagLabel.frame = NSRect(x: cardView.frame.width - 150, y: 10, width: 136, height: 16)
                cardView.addSubview(tagLabel)
                
                var cardY: CGFloat = 32
                for (idx, b) in g.buckets.enumerated() {
                    if idx > 0 {
                        let sep = NSBox(frame: NSRect(x: 14, y: cardY - 4, width: cardView.frame.width - 28, height: 1))
                        sep.boxType = .custom
                        sep.fillColor = colorSep
                        sep.borderColor = .clear
                        cardView.addSubview(sep)
                    }
                    
                    let bTitle = NSTextField(labelWithString: b.name)
                    bTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
                    bTitle.textColor = .white
                    bTitle.frame = NSRect(x: 14, y: cardY, width: 260, height: 16)
                    cardView.addSubview(bTitle)
                    
                    let valStr = "\(b.remaining_pct)%"
                    let bVal = NSTextField(labelWithString: valStr)
                    bVal.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
                    
                    if b.remaining_pct >= 50 {
                        bVal.textColor = accentColor
                    } else if b.remaining_pct >= 20 {
                        bVal.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
                    } else {
                        bVal.textColor = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
                    }
                    bVal.alignment = .right
                    bVal.frame = NSRect(x: cardView.frame.width - 150, y: cardY, width: 136, height: 16)
                    cardView.addSubview(bVal)
                    
                    cardY += 18
                    
                    if let reset = b.reset_in, !reset.isEmpty {
                        let resetLabel = NSTextField(labelWithString: "Renova em \(reset)")
                        resetLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
                        resetLabel.textColor = NSColor(white: 0.50, alpha: 1.0)
                        resetLabel.alignment = .right
                        resetLabel.frame = NSRect(x: cardView.frame.width - 160, y: cardY - 4, width: 146, height: 12)
                        cardView.addSubview(resetLabel)
                    }
                    
                    let barBg = NSBox(frame: NSRect(x: 14, y: cardY + 12, width: cardView.frame.width - 28, height: 6))
                    barBg.boxType = .custom
                    barBg.fillColor = colorTrack
                    barBg.borderColor = .clear
                    barBg.cornerRadius = 3
                    cardView.addSubview(barBg)
                    
                    let fillWidth = max(CGFloat(barBg.frame.width) * CGFloat(b.remaining_pct) / 100.0, 4)
                    let barFill = NSBox(frame: NSRect(x: 14, y: cardY + 12, width: fillWidth, height: 6))
                    barFill.boxType = .custom
                    barFill.fillColor = bVal.textColor ?? NSColor.systemGreen
                    barFill.borderColor = .clear
                    barFill.cornerRadius = 3
                    cardView.addSubview(barFill)
                    
                    cardY += 24
                }
                
                y += cardHeight + 14
            }
        }
        
        scrollView.documentView = contentView
        mainView.addSubview(scrollView)
        
        let btnBg = NSColor(srgbRed: 0xEE/255.0, green: 0xEE/255.0, blue: 0xF0/255.0, alpha: 1.0)
        let btnText = NSColor(srgbRed: 0x18/255.0, green: 0x18/255.0, blue: 0x18/255.0, alpha: 1.0)
        
        // ----------------- RODAPÉ (Linha 1: Botões) -----------------
        let footerY: CGFloat = 30
        
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
        
        // ----------------- RODAPÉ (Linha 2: Menção vh2c.com.br SEM ícone colorido, ligeiramente maior) -----------------
        let brandBtn = NSButton(title: "", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: 14, y: 5, width: windowWidth - 28, height: 20)
        brandBtn.toolTip = "Acesse vh2c.com.br"
        brandBtn.attributedTitle = NSAttributedString(
            string: "Desenvolvido por vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 0.95),
                .font: NSFont.systemFont(ofSize: 12.0, weight: .semibold)
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
            let w: CGFloat = 500
            let h: CGFloat = 620
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
        let colorCard = NSColor(srgbRed: 0x1E/255.0, green: 0x1E/255.0, blue: 0x22/255.0, alpha: 1.0)
        let colorBorder = NSColor(srgbRed: 0x2E/255.0, green: 0x2E/255.0, blue: 0x33/255.0, alpha: 1.0)
        
        let view = FlippedContentView(frame: win.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = colorBg18.cgColor
        win.contentView = view
        
        let contentW = win.contentView!.bounds.width
        var y: CGFloat = 22
        
        // Header
        let titleLabel = NSTextField(labelWithString: "⚙️ Provedores de IA & Modelos")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 20, y: y, width: contentW - 40, height: 22)
        view.addSubview(titleLabel)
        y += 26
        
        let subLabel = NSTextField(labelWithString: "Configure as fontes de dados para monitoramento das suas cotas:")
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        subLabel.frame = NSRect(x: 20, y: y, width: contentW - 40, height: 16)
        view.addSubview(subLabel)
        y += 24
        
        // 1. Google Gemini API Card
        let geminiCardH: CGFloat = 152
        let geminiCard = FlippedBox(frame: NSRect(x: 18, y: y, width: contentW - 36, height: geminiCardH))
        geminiCard.boxType = .custom
        geminiCard.fillColor = colorCard
        geminiCard.borderColor = colorBorder
        geminiCard.borderWidth = 1
        geminiCard.cornerRadius = 8
        view.addSubview(geminiCard)
        
        let geminiCfg = providers["gemini"]
        let geminiBtn = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        geminiBtn.state = (geminiCfg?.enabled ?? false) ? .on : .off
        geminiBtn.attributedTitle = NSAttributedString(
            string: "  Google Gemini API (Google AI Studio)",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
        )
        geminiBtn.frame = NSRect(x: 14, y: 12, width: geminiCard.frame.width - 28, height: 20)
        geminiCard.addSubview(geminiBtn)
        self.geminiCheck = geminiBtn
        
        let geminiHint = NSTextField(labelWithString: "💡 Chaves do Google AI Studio começam com AIzaSy...")
        geminiHint.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        geminiHint.textColor = NSColor(white: 0.55, alpha: 1.0)
        geminiHint.frame = NSRect(x: 36, y: 34, width: geminiCard.frame.width - 50, height: 15)
        geminiCard.addSubview(geminiHint)
        
        let fieldW: CGFloat = geminiCard.frame.width - 28 - 92
        let geminiField = makeCenteredDarkField(
            frame: NSRect(x: 14, y: 52, width: fieldW, height: 34),
            placeholder: "Chave de API Gemini (AIzaSy...)",
            value: geminiCfg?.api_key ?? ""
        )
        geminiCard.addSubview(geminiField)
        self.geminiKeyField = geminiField
        
        let testBtn = NSButton(title: "Testar", target: self, action: #selector(testGeminiKeyClicked))
        testBtn.isBordered = false
        testBtn.wantsLayer = true
        testBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x30/255.0, alpha: 1.0).cgColor
        testBtn.layer?.cornerRadius = 6
        testBtn.frame = NSRect(x: 14 + fieldW + 8, y: 52, width: 84, height: 34)
        testBtn.attributedTitle = NSAttributedString(
            string: "Testar",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
        )
        geminiCard.addSubview(testBtn)
        self.geminiTestBtn = testBtn
        
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = NSColor(white: 0.60, alpha: 1.0)
        statusLabel.frame = NSRect(x: 14, y: 92, width: geminiCard.frame.width - 28, height: 16)
        geminiCard.addSubview(statusLabel)
        self.geminiStatusLabel = statusLabel
        
        let geminiLink = NSButton(title: "", target: self, action: #selector(openAiStudioLink))
        geminiLink.isBordered = false
        geminiLink.frame = NSRect(x: 14, y: 114, width: geminiCard.frame.width - 28, height: 20)
        geminiLink.attributedTitle = NSAttributedString(
            string: "Obter Chave Gratuita no Google AI Studio (aistudio.google.com) ↗",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular)
            ]
        )
        geminiCard.addSubview(geminiLink)
        
        y += geminiCardH + 12
        
        // 2. Antigravity Card
        let antiCardH: CGFloat = 68
        let antiCard = FlippedBox(frame: NSRect(x: 18, y: y, width: contentW - 36, height: antiCardH))
        antiCard.boxType = .custom
        antiCard.fillColor = colorCard
        antiCard.borderColor = colorBorder
        antiCard.borderWidth = 1
        antiCard.cornerRadius = 8
        view.addSubview(antiCard)
        
        let antiCfg = providers["antigravity"]
        let antiBtn = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        antiBtn.state = (antiCfg?.enabled ?? true) ? .on : .off
        antiBtn.attributedTitle = NSAttributedString(
            string: "  Antigravity IDE (Live & Headless Standalone)",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
        )
        antiBtn.frame = NSRect(x: 14, y: 12, width: antiCard.frame.width - 28, height: 20)
        antiCard.addSubview(antiBtn)
        self.antigravityCheck = antiBtn
        
        let antiDesc = NSTextField(labelWithString: "Detecta cotas do IDE em execução ou via sonda headless quando fechado.")
        antiDesc.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        antiDesc.textColor = NSColor(white: 0.55, alpha: 1.0)
        antiDesc.frame = NSRect(x: 36, y: 36, width: antiCard.frame.width - 50, height: 16)
        antiCard.addSubview(antiDesc)
        
        y += antiCardH + 12
        
        // 3. OpenAI Card
        let openCardH: CGFloat = 88
        let openCard = FlippedBox(frame: NSRect(x: 18, y: y, width: contentW - 36, height: openCardH))
        openCard.boxType = .custom
        openCard.fillColor = colorCard
        openCard.borderColor = colorBorder
        openCard.borderWidth = 1
        openCard.cornerRadius = 8
        view.addSubview(openCard)
        
        let openCfg = providers["openai"]
        let openBtn = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        openBtn.state = (openCfg?.enabled ?? false) ? .on : .off
        openBtn.attributedTitle = NSAttributedString(
            string: "  OpenAI API (GPT-4o, o1, etc.)",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
        )
        openBtn.frame = NSRect(x: 14, y: 12, width: openCard.frame.width - 28, height: 20)
        openCard.addSubview(openBtn)
        self.openaiCheck = openBtn
        
        let openField = makeCenteredDarkField(
            frame: NSRect(x: 14, y: 38, width: openCard.frame.width - 28, height: 34),
            placeholder: "Chave de API OpenAI (sk-...)",
            value: openCfg?.api_key ?? ""
        )
        openCard.addSubview(openField)
        self.openaiKeyField = openField
        
        y += openCardH + 12
        
        // 4. Anthropic Claude Card
        let antCardH: CGFloat = 88
        let antCard = FlippedBox(frame: NSRect(x: 18, y: y, width: contentW - 36, height: antCardH))
        antCard.boxType = .custom
        antCard.fillColor = colorCard
        antCard.borderColor = colorBorder
        antCard.borderWidth = 1
        antCard.cornerRadius = 8
        view.addSubview(antCard)
        
        let antCfg = providers["anthropic"]
        let antBtn = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        antBtn.state = (antCfg?.enabled ?? false) ? .on : .off
        antBtn.attributedTitle = NSAttributedString(
            string: "  Anthropic Claude API (Sonnet, Opus)",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            ]
        )
        antBtn.frame = NSRect(x: 14, y: 12, width: antCard.frame.width - 28, height: 20)
        antCard.addSubview(antBtn)
        self.anthropicCheck = antBtn
        
        let antField = makeCenteredDarkField(
            frame: NSRect(x: 14, y: 38, width: antCard.frame.width - 28, height: 34),
            placeholder: "Chave de API Anthropic (sk-ant-...)",
            value: antCfg?.api_key ?? ""
        )
        antCard.addSubview(antField)
        self.anthropicKeyField = antField
        
        y += antCardH + 18
        
        // Footer Buttons
        let saveBtn = NSButton(title: "Salvar e Atualizar", target: self, action: #selector(saveSettingsClicked))
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0).cgColor
        saveBtn.layer?.cornerRadius = 6
        saveBtn.frame = NSRect(x: 18, y: y, width: 144, height: 34)
        saveBtn.attributedTitle = NSAttributedString(
            string: "Salvar e Atualizar",
            attributes: [
                .foregroundColor: NSColor(srgbRed: 0x12/255.0, green: 0x12/255.0, blue: 0x12/255.0, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ]
        )
        view.addSubview(saveBtn)
        
        let cancelBtn = NSButton(title: "Cancelar", target: self, action: #selector(cancelSettingsClicked))
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.backgroundColor = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x2E/255.0, alpha: 1.0).cgColor
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.frame = NSRect(x: 172, y: y, width: 90, height: 34)
        cancelBtn.attributedTitle = NSAttributedString(
            string: "Cancelar",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        view.addSubview(cancelBtn)
        
        let brandBtn = NSButton(title: "vh2c.com.br", target: self, action: #selector(brandClicked))
        brandBtn.isBordered = false
        brandBtn.frame = NSRect(x: contentW - 140, y: y + 8, width: 120, height: 18)
        brandBtn.attributedTitle = NSAttributedString(
            string: "vh2c.com.br",
            attributes: [
                .foregroundColor: NSColor(white: 0.40, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]
        )
        view.addSubview(brandBtn)
    }
    
    @objc func testGeminiKeyClicked() {
        let key = geminiKeyField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty {
            geminiStatusLabel?.stringValue = "⚠️ Digite uma chave de API para testar"
            geminiStatusLabel?.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
            return
        }
        
        if key.hasPrefix("AQ.") || key.hasPrefix("ya29.") {
            geminiStatusLabel?.stringValue = "⚠️ Use Chave do Google AI Studio (inicia com AIzaSy...)"
            geminiStatusLabel?.textColor = NSColor(srgbRed: 0xF5/255.0, green: 0xA6/255.0, blue: 0x23/255.0, alpha: 1.0)
            return
        }
        
        geminiTestBtn?.isEnabled = false
        geminiStatusLabel?.stringValue = "Testando conexão com Google AI..."
        geminiStatusLabel?.textColor = NSColor(white: 0.70, alpha: 1.0)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nodeBin = QuotaManager.findNodeBinary()
            let task = Process()
            if nodeBin.hasPrefix("/") {
                task.executableURL = URL(fileURLWithPath: nodeBin)
                task.arguments = [QuotaManager.engineScript, "--test-gemini", key]
            } else {
                task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                task.arguments = ["node", QuotaManager.engineScript, "--test-gemini", key]
            }
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            task.environment = env
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    self?.geminiTestBtn?.isEnabled = true
                    if output.contains("\"ok\":true") {
                        self?.geminiStatusLabel?.stringValue = "✓ Chave válida! Modelos Gemini conectados."
                        self?.geminiStatusLabel?.textColor = NSColor(srgbRed: 0x00/255.0, green: 0xE6/255.0, blue: 0x99/255.0, alpha: 1.0)
                        self?.geminiCheck?.state = .on
                    } else {
                        self?.geminiStatusLabel?.stringValue = "✕ Não autorizado. Obtenha chave em aistudio.google.com"
                        self?.geminiStatusLabel?.textColor = NSColor(srgbRed: 0xFF/255.0, green: 0x4D/255.0, blue: 0x4F/255.0, alpha: 1.0)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.geminiTestBtn?.isEnabled = true
                    self?.geminiStatusLabel?.stringValue = "✕ Erro: \(error.localizedDescription)"
                    self?.geminiStatusLabel?.textColor = NSColor.systemRed
                }
            }
        }
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
