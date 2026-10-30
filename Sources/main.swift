import AppKit
import Carbon
import WebKit

let BAR_W: CGFloat = 460
let HEADER_H: CGFloat = 52
let ROW_H: CGFloat = 34
let FULL_W: CGFloat = 650
let FULL_H: CGFloat = 600
let MARGIN: CGFloat = 16
let STRIP_H: CGFloat = 30
// Courbe douce : démarre vite, ralentit longuement à la fin
let SMOOTH = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
let SAFARI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
// Navigateur pour ⌘↵ : nil = navigateur par défaut, ou un bundle id (ex. "com.google.Chrome")
let BROWSER_ID: String? = nil

func encode(_ s: String) -> String {
  s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
}

func toURL(_ text: String) -> URL {
  let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil, let u = URL(string: t) { return u }
  if t.range(of: #"^localhost(:\d+)?(/.*)?$"#, options: [.regularExpression, .caseInsensitive]) != nil,
     let u = URL(string: "http://" + t) { return u }
  if !t.contains(" "), t.range(of: #"^[^\s/]+\.[a-zA-Z]{2,}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil,
     let u = URL(string: "https://" + t) { return u }
  return URL(string: "https://www.google.com/search?q=" + encode(t))!
}

func roundedMask(radius r: CGFloat) -> NSImage {
  let side = r * 2 + 1
  let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
    return true
  }
  img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
  img.resizingMode = .stretch
  return img
}

final class Panel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

// Une ligne de suggestion
final class Row: NSView {
  var onClick: (() -> Void)?
  var selected = false {
    didSet { layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : nil }
  }

  init(text: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 7
    let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
    icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
    icon.contentTintColor = .secondaryLabelColor
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 14)
    label.lineBreakMode = .byTruncatingTail
    for v in [icon, label] as [NSView] {
      v.translatesAutoresizingMaskIntoConstraints = false
      addSubview(v)
    }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: ROW_H),
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 16),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  override func mouseDown(with event: NSEvent) { onClick?() }
}

final class App: NSObject, NSApplicationDelegate, NSTextFieldDelegate, WKUIDelegate, WKNavigationDelegate {
  static let shared = App()

  let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: BAR_W, height: HEADER_H),
                    styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
  let field = NSTextField()
  let divider = NSBox()
  var header: NSStackView!
  var strip: NSStackView!
  var webTop: NSLayoutConstraint!
  let list = NSStackView()
  var webView: WKWebView!
  var rows: [Row] = []
  var suggestions: [String] = []
  var sel = -1
  var expanded = false
  let pageBg = NSView()
  let progress = NSView()
  var progressW: NSLayoutConstraint!
  var progressObs: NSKeyValueObservation?
  var task: URLSessionDataTask?
  var urlObs: NSKeyValueObservation?
  var hotKeyRef: EventHotKeyRef?

  func applicationDidFinishLaunching(_ n: Notification) {
    buildMenu()
    buildPanel()
    registerHotKey()
    installKeyMonitor()
    if CommandLine.arguments.contains("--show") { show() }
    if let i = CommandLine.arguments.firstIndex(of: "--debug"), i + 1 < CommandLine.arguments.count {
      debugRun(CommandLine.arguments[i + 1])
    }
    if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count {
      screenshots(to: CommandLine.arguments[i + 1])
    }
  }

  // Plus d'icône dans la barre des menus : rouvrir l'app (Spotlight, Finder) affiche la barre
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    show()
    return false
  }

  // MARK: Construction

  func makeButton(_ symbol: String, _ tip: String, _ action: Selector, size: CGFloat = 28) -> NSButton {
    let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
    b.isBordered = false
    b.toolTip = tip
    b.symbolConfiguration = .init(pointSize: size * 0.43, weight: .semibold)
    b.contentTintColor = .secondaryLabelColor
    b.wantsLayer = true
    b.layer?.cornerRadius = 7
    b.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: size).isActive = true
    b.heightAnchor.constraint(equalToConstant: size).isActive = true
    return b
  }

  func buildPanel() {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.minSize = NSSize(width: 380, height: HEADER_H)

    // Conteneur du contenu, arrondi pour que la page web ne déborde pas dans les coins
    let root = NSView()
    root.wantsLayer = true
    root.layer?.cornerRadius = 14
    root.layer?.masksToBounds = true

    if #available(macOS 26.0, *) {
      // Liquid Glass, style « clear » pour un maximum de transparence
      let glass = NSGlassEffectView()
      glass.style = .clear
      glass.cornerRadius = 14
      glass.contentView = root
      panel.contentView = glass
    } else {
      let blur = NSVisualEffectView()
      blur.material = .hudWindow
      blur.blendingMode = .behindWindow
      blur.state = .active
      // En .behindWindow le flou ignore le cornerRadius du layer : seul un maskImage arrondit
      // vraiment la fenêtre (sinon coins carrés clairs), et l'ombre suit alors la forme
      blur.maskImage = roundedMask(radius: 14)
      root.translatesAutoresizingMaskIntoConstraints = false
      blur.addSubview(root)
      NSLayoutConstraint.activate([
        root.topAnchor.constraint(equalTo: blur.topAnchor),
        root.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        root.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
        root.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
      ])
      panel.contentView = blur
    }

    let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
    icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
    icon.contentTintColor = .labelColor

    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 18)
    field.placeholderString = "Rechercher ou saisir une URL…"
    field.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.delegate = self
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let closeButton = makeButton("xmark", "Fermer (Échap)", #selector(close))

    header = NSStackView(views: [icon, field, closeButton])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 10
    header.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 12)

    // Fine bande au-dessus de la page : juste « Ouvrir dans le navigateur » et « Fermer »
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    strip = NSStackView(views: [spacer,
                                makeButton("arrow.up.forward.app", "Ouvrir dans le navigateur (⌘↵)", #selector(openCurrentInBrowser), size: 22),
                                makeButton("xmark", "Fermer (Échap)", #selector(close), size: 22)])
    strip.orientation = .horizontal
    strip.alignment = .centerY
    strip.spacing = 6
    strip.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    strip.isHidden = true

    divider.boxType = .separator
    divider.isHidden = true

    list.orientation = .vertical
    list.spacing = 0
    list.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    list.isHidden = true

    let cfg = WKWebViewConfiguration()
    cfg.websiteDataStore = .default()
    webView = WKWebView(frame: .zero, configuration: cfg)
    webView.customUserAgent = SAFARI_UA
    // Pas de fond blanc avant que la page se dessine (flash blanc en mode sombre)
    webView.setValue(false, forKey: "drawsBackground")
    webView.underPageBackgroundColor = .textBackgroundColor
    webView.uiDelegate = self
    webView.navigationDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    webView.isHidden = true
    urlObs = webView.observe(\.url) { [weak self] w, _ in
      guard let self, self.expanded, let u = w.url, u.scheme != "about", self.field.currentEditor() == nil else { return }
      self.field.stringValue = u.absoluteString
    }

    pageBg.wantsLayer = true
    pageBg.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    pageBg.isHidden = true
    progress.wantsLayer = true
    progress.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    progress.alphaValue = 0
    progressObs = webView.observe(\.estimatedProgress) { [weak self] w, _ in
      guard let self else { return }
      guard self.expanded else { return }
      let p = w.estimatedProgress
      let width = self.webView.bounds.width
      if p >= 1 {
        NSAnimationContext.runAnimationGroup({ c in
          c.duration = 0.2
          self.progressW.animator().constant = width
          self.progress.animator().alphaValue = 0
        })
      } else {
        self.progress.alphaValue = 1
        NSAnimationContext.runAnimationGroup { c in
          c.duration = 0.2
          self.progressW.animator().constant = width * max(p, 0.1)
        }
      }
    }

    for v in [header!, strip!, divider, list, pageBg, webView!, progress] as [NSView] {
      v.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(v)
    }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: root.topAnchor),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: HEADER_H),
      strip.topAnchor.constraint(equalTo: root.topAnchor),
      strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      strip.heightAnchor.constraint(equalToConstant: STRIP_H),
      divider.topAnchor.constraint(equalTo: header.bottomAnchor),
      divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      divider.heightAnchor.constraint(equalToConstant: 1),
      list.topAnchor.constraint(equalTo: divider.bottomAnchor),
      list.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      list.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    webTop = webView.topAnchor.constraint(equalTo: root.topAnchor, constant: HEADER_H + 1)
    webTop.isActive = true
    progressW = progress.widthAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      pageBg.topAnchor.constraint(equalTo: webView.topAnchor),
      pageBg.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
      pageBg.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
      pageBg.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
      progress.topAnchor.constraint(equalTo: webView.topAnchor),
      progress.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
      progress.heightAnchor.constraint(equalToConstant: 2),
      progressW,
    ])
  }

  func buildMenu() {
    // Menus invisibles : ⌘Q pour quitter, et ⌘C / ⌘V / ⌘A dans le champ
    let main = NSMenu()
    let appItem = NSMenuItem()
    appItem.submenu = NSMenu()
    appItem.submenu?.addItem(withTitle: "Quitter Little Browser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    main.addItem(appItem)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "Édition")
    edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
  }

  func registerHotKey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
      DispatchQueue.main.async { App.shared.toggle() }
      return noErr
    }, 1, &spec, nil, nil)
    let id = EventHotKeyID(signature: OSType(0x4C444941), id: 1)
    RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
  }

  func installKeyMonitor() {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      guard let self, e.window === self.panel else { return e }
      let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
      // Lettres lues d'après la disposition du clavier (AZERTY comme QWERTY)
      let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
      if e.keyCode == 53 && mods.isEmpty {                                  // Échap
        if self.expanded && !self.header.isHidden { self.showPage() } else { self.close() }
        return nil
      }
      guard mods == .command else { return e }
      switch ch {
      case "\r", "\u{3}": self.commandEnter(); return nil                  // ⌘↵
      case "w": self.close(); return nil                                     // ⌘W
      case "l": self.focusField(); return nil                                // ⌘L
      case "r": self.webView.reload(); return nil                            // ⌘R
      case "[": self.webView.goBack(); return nil                            // ⌘[
      case "]": self.webView.goForward(); return nil                         // ⌘]
      default: return e
      }
    }
  }

  // MARK: Fenêtre

  // Coin haut droit de l'écran principal, sous la barre de menu
  func place(_ w: CGFloat, _ h: CGFloat) {
    let vf = (NSScreen.screens.first ?? NSScreen.main!).visibleFrame
    panel.setFrame(NSRect(x: vf.maxX - w - MARGIN, y: vf.maxY - MARGIN - h, width: w, height: h), display: true)
    panel.invalidateShadow()
  }

  // Redimensionne en gardant le coin haut droit fixe
  func resize(_ w: CGFloat, _ h: CGFloat, animate: Bool = false, then done: (() -> Void)? = nil) {
    let f = panel.frame
    let r = NSRect(x: f.maxX - w, y: f.maxY - h, width: w, height: h)
    if animate {
      NSAnimationContext.runAnimationGroup({ c in
        c.duration = 0.22
        c.timingFunction = SMOOTH
        c.allowsImplicitAnimation = true
        panel.animator().setFrame(r, display: true)
      }, completionHandler: { self.panel.invalidateShadow(); done?() })
    } else {
      panel.setFrame(r, display: true)
      panel.invalidateShadow()
      done?()
    }
  }

  // Page affichée : la barre de recherche disparaît, il reste la fine bande
  func showPage() {
    header.isHidden = true
    divider.isHidden = true
    strip.isHidden = false
    webTop.constant = STRIP_H
    panel.makeFirstResponder(webView)
  }

  // ⌘L sur une page : la barre de recherche revient pour taper une autre adresse
  func showSearch() {
    header.isHidden = false
    divider.isHidden = false
    strip.isHidden = true
    webTop.constant = HEADER_H + 1
  }

  func show() {
    task?.cancel()
    expanded = false
    webView.isHidden = true
    pageBg.isHidden = true
    progress.alphaValue = 0
    progressW.constant = 0
    showSearch()
    field.stringValue = ""
    setSuggestions([])
    place(BAR_W, HEADER_H)
    prewarm()
    // Apparition : fondu + légère descente
    let target = panel.frame
    panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
    panel.alphaValue = 0
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
    NSAnimationContext.runAnimationGroup { c in
      c.duration = 0.18
      c.timingFunction = SMOOTH
      panel.animator().alphaValue = 1
      panel.animator().setFrame(target, display: true)
    }
  }

  // Charge Google en arrière-plan : moteur web démarré et connexion déjà ouverte
  // au moment où la recherche est lancée
  func prewarm() {
    webView.load(URLRequest(url: URL(string: "https://www.google.com/generate_204")!))
  }

  func dismiss() {
    task?.cancel()
    panel.orderOut(nil)
    webView.load(URLRequest(url: URL(string: "about:blank")!))
  }

  // Disparition : fondu rapide
  @objc func close() {
    task?.cancel()
    NSAnimationContext.runAnimationGroup({ c in
      c.duration = 0.12
      c.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    }, completionHandler: {
      self.dismiss()
      self.panel.alphaValue = 1
      NSApp.hide(nil)
    })
  }

  func toggle() {
    if panel.isVisible && panel.isKeyWindow && NSApp.isActive { close() }
    else if panel.isVisible {
      NSApp.activate(ignoringOtherApps: true)
      panel.makeKeyAndOrderFront(nil)
    } else { show() }
  }

  func focusField() {
    if expanded { showSearch() }
    panel.makeFirstResponder(field)
    field.currentEditor()?.selectAll(nil)
  }

  // MARK: Suggestions

  func setSuggestions(_ s: [String]) {
    suggestions = s
    sel = -1
    rows.forEach { $0.removeFromSuperview() }
    rows = s.map { text in
      let r = Row(text: text)
      r.onClick = { [weak self] in self?.go(text, inBrowser: NSEvent.modifierFlags.contains(.command)) }
      return r
    }
    for r in rows {
      list.addArrangedSubview(r)
      r.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -12).isActive = true
    }
    list.isHidden = s.isEmpty
    divider.isHidden = s.isEmpty && !expanded
    if !expanded {
      resize(BAR_W, s.isEmpty ? HEADER_H : HEADER_H + 1 + 12 + CGFloat(s.count) * ROW_H, animate: panel.isVisible)
    }
  }

  func fetchSuggestions(_ q: String) {
    task?.cancel()
    guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return setSuggestions([]) }
    let url = URL(string: "https://suggestqueries.google.com/complete/search?client=chrome&hl=fr&ie=utf-8&oe=utf-8&q=" + encode(q))!
    task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data,
            let arr = try? JSONSerialization.jsonObject(with: data) as? [Any], arr.count > 1,
            let found = arr[1] as? [String] else { return }
      DispatchQueue.main.async {
        guard let self, !self.expanded, self.field.stringValue == q else { return }
        self.setSuggestions(Array(found.prefix(6)))
      }
    }
    task?.resume()
  }

  func move(_ step: Int) {
    guard !rows.isEmpty else { return }
    let last = rows.count - 1
    if step > 0 { sel = sel >= last ? -1 : sel + 1 } else { sel = sel <= -1 ? last : sel - 1 }
    for (i, r) in rows.enumerated() { r.selected = i == sel }
  }

  // MARK: Navigation

  func submit(inBrowser: Bool) {
    let text = sel >= 0 ? suggestions[sel] : field.stringValue
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    go(text, inBrowser: inBrowser)
  }

  func go(_ text: String, inBrowser: Bool) {
    let url = toURL(text)
    if inBrowser { return openInBrowser(url) }
    task?.cancel()
    if !expanded {
      // La page (fond opaque + barre de chargement) s'affiche tout de suite
      expanded = true
      webView.load(URLRequest(url: url))
      setSuggestions([])
      showPage()
      pageBg.isHidden = false
      webView.isHidden = true
      field.stringValue = url.absoluteString
      resize(FULL_W, FULL_H, animate: true) {
        guard self.expanded else { return }
        self.webView.isHidden = false
        self.panel.makeFirstResponder(self.webView)
      }
      return
    }
    webView.load(URLRequest(url: url))
    showPage()
    field.stringValue = url.absoluteString
  }

  func commandEnter() {
    if field.currentEditor() != nil { submit(inBrowser: true) }
    else if let u = webView.url, u.scheme != "about" { openInBrowser(u) }
  }

  @objc func openCurrentInBrowser() {
    if let u = webView.url, u.scheme != "about" { openInBrowser(u) }
  }

  func openInBrowser(_ url: URL) {
    dismiss()
    let ws = NSWorkspace.shared
    if let id = BROWSER_ID, let browser = ws.urlForApplication(withBundleIdentifier: id) {
      ws.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
    } else {
      ws.open(url)
    }
  }

  // MARK: Délégués

  func controlTextDidChange(_ n: Notification) {
    if !expanded { fetchSuggestions(field.stringValue) }
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    switch sel {
    case #selector(NSResponder.moveDown(_:)): move(1); return true
    case #selector(NSResponder.moveUp(_:)): move(-1); return true
    case #selector(NSResponder.insertNewline(_:)): submit(inBrowser: false); return true
    case #selector(NSResponder.cancelOperation(_:)): close(); return true
    default: return false
    }
  }

  // Les liens « nouvel onglet » s'ouvrent dans la même fenêtre
  func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if action.targetFrame == nil, let u = action.request.url { w.load(URLRequest(url: u)) }
    return nil
  }
}

// Mode test : lance une recherche et enregistre la fenêtre image par image
typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let captureFn: CaptureFn? = {
  guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
        let f = dlsym(h, "CGWindowListCreateImage") else { return nil }
  return unsafeBitCast(f, to: CaptureFn.self)
}()

extension App {
  func debugRun(_ q: String) {
    let dir = "/tmp/ld-frames"
    try? FileManager.default.removeItem(atPath: dir)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    show()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      self.field.stringValue = q
      let t0 = CACurrentMediaTime()
      var n = 0
      Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
        let t = CACurrentMediaTime() - t0
        if let img = captureFn?(.null, 8, UInt32(self.panel.windowNumber), 1)?.takeRetainedValue() {
          let rep = NSBitmapImageRep(cgImage: img)
          let path = String(format: "%@/%03d_%04dms.png", dir, n, Int(t * 1000))
          try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        n += 1
        if t > 1.2 { timer.invalidate(); NSApp.terminate(nil) }
      }
      self.go(q, inBrowser: false)
    }
  }
}

// Captures pour la documentation : la barre avec suggestions, puis la page
extension App {
  func snap(_ path: String) {
    guard let img = captureFn?(.null, 8, UInt32(panel.windowNumber), 1)?.takeRetainedValue() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }

  func screenshots(to dir: String) {
    show()
    let q = "recette crêpes"
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      self.field.stringValue = q
      self.fetchSuggestions(q)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        self.snap(dir + "/bar.png")
        self.go(q, inBrowser: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
          self.snap(dir + "/page.png")
          NSApp.terminate(nil)
        }
      }
    }
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = App.shared
app.run()
