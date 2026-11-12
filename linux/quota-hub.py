#!/usr/bin/env python3
"""
Universal AI Quota Monitor - Linux Edition
Developed by VH2C • https://vh2c.com.br

Supports:
- Full Detailed Window (Antigravity #181818 theme, cards, progress bars)
- Compact Radial HUD (Vertical dock or Horizontal bar with tachometer gauges)
- Multi-Provider Settings Window (Gemini, OpenAI, Claude, Antigravity)
- Terminal CLI Mode (--cli or headless servers)
"""

import sys
import os
import json
import time
import math
import subprocess
import glob
import webbrowser
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
REPO_ROOT = APP_DIR.parent
ENGINE_SCRIPT = REPO_ROOT / "core" / "engine.js"
if not ENGINE_SCRIPT.exists():
    ENGINE_SCRIPT = APP_DIR / "core" / "engine.js"

CONFIG_DIR = Path.home() / ".config" / "UniversalAIQuota"
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_FILE = CONFIG_DIR / "config.json"
CACHE_FILE = CONFIG_DIR / "quota_cache.json"
PREFS_FILE = CONFIG_DIR / "prefs.json"

def load_config():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "providers": {
            "antigravity": {"enabled": True},
            "gemini": {"enabled": False, "api_key": ""},
            "openai": {"enabled": False, "api_key": ""},
            "anthropic": {"enabled": False, "api_key": ""}
        },
        "refresh_interval_seconds": 30
    }

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        print(f"Erro ao salvar configurações: {e}")

def find_node():
    # 1. Check local app embedded/portable node
    local_nodes = [
        APP_DIR / "bin" / "node",
        APP_DIR.parent / "bin" / "node",
        Path.home() / ".local" / "share" / "universal-ai-quota" / "bin" / "node"
    ]
    for ln in local_nodes:
        if ln.exists() and os.access(ln, os.X_OK):
            return str(ln)

    # 2. Check standard system locations
    for p in ["/usr/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/node", "/bin/node"]:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p

    # 3. Check NVM installations
    nvm_nodes = sorted(glob.glob(os.path.expanduser("~/.nvm/versions/node/*/bin/node")), reverse=True)
    if nvm_nodes:
        return nvm_nodes[0]

    # 4. Fallback to PATH
    return "node"

def load_quota(force=False):
    if not force and CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            ts = data.get("timestamp", 0)
            if time.time() - ts < 30:
                data["from_cache"] = True
                data["cache_age_seconds"] = int(time.time() - ts)
                return data
        except Exception:
            pass

    node_bin = find_node()
    env = dict(os.environ)
    extra_paths = ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    env["PATH"] = ":".join(extra_paths) + ":" + env.get("PATH", "")

    try:
        res = subprocess.run([node_bin, str(ENGINE_SCRIPT)], capture_output=True, text=True, env=env, timeout=7)
        if res.returncode == 0 and res.stdout.strip():
            parsed = json.loads(res.stdout.strip())
            parsed["timestamp"] = time.time()
            parsed["from_cache"] = False
            parsed["cache_age_seconds"] = 0
            with open(CACHE_FILE, "w", encoding="utf-8") as f:
                json.dump(parsed, f, indent=2)
            return parsed
    except Exception:
        pass

    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return None

def get_gauge_items(quota):
    items = []
    for g in quota.get("groups", []):
        gname = g.get("name", "").lower()
        if "gemini 4" in gname or "argon" in gname:
            model = "Argon"
        elif "claude" in gname or "gpt" in gname:
            model = "Claude/GPT"
        elif "openai" in gname:
            model = "OpenAI"
        elif "anthropic" in gname:
            model = "Claude API"
        else:
            model = "Gemini"

        for b in g.get("buckets", []):
            bname = b.get("name", "").lower()
            if "5" in bname or "five" in bname:
                limit_title = "5 hours Limit"
            elif "rpm" in bname or "req" in bname:
                limit_title = "RPM Limit"
            elif "tpm" in bname or "token" in bname:
                limit_title = "TPM Limit"
            else:
                limit_title = "Weekly Limit"

            items.append({
                "id": b.get("id", ""),
                "title": limit_title,
                "model": model,
                "pct": b.get("remaining_pct", 100),
                "reset_in": b.get("reset_in", ""),
                "detail": b.get("detail", ""),
                "provider": g.get("provider", "")
            })
    return items

def status_color(pct):
    if pct > 50:
        return "#22921E"
    elif pct > 20:
        return "#C86402"
    else:
        return "#C62828"

def print_cli(quota):
    if not quota or quota.get("needs_setup"):
        print("\n" + "="*58)
        print(" ⚡ Universal AI Quota Monitor - Configuração Necessária")
        print("="*58)
        print(" Nenhum provedor de IA ativo ou configurado.")
        print(f" Configure suas chaves em: {CONFIG_FILE}")
        print(" Exemplo: Adicione GEMINI_API_KEY ou OPENAI_API_KEY.")
        print("="*58 + "\n")
        return

    print("\n" + "="*58)
    print(f" ⚡ Universal AI Quota Monitor - vh2c.com.br")
    print(f" Conta: {quota.get('account', 'Multi-Provider')} • Plano {quota.get('plan', 'Universal')}")
    print(f" Atualizado às {quota.get('updated_at', 'agora')} " + ("(Tempo real)" if not quota.get("from_cache") else "(Cache)"))
    print("="*58)

    for g in quota.get("groups", []):
        prov = f" [{g.get('provider')}]" if g.get('provider') else ""
        print(f"\n📂 {g.get('name', 'Grupo').upper()}{prov}")
        for b in g.get("buckets", []):
            pct = b.get("remaining_pct", 0)
            reset = f" • {b.get('reset_in')}" if b.get("reset_in") else ""
            bar_len = 24
            filled = int(round(bar_len * pct / 100))
            bar = "█" * filled + "░" * (bar_len - filled)
            col = "\033[92m" if pct > 50 else ("\033[93m" if pct > 20 else "\033[91m")
            rst = "\033[0m"
            print(f"  {b.get('name', 'Limite'):<26} {col}{pct:>3}%{rst}{reset}")
            print(f"  [{col}{bar}{rst}]")
    print("\n" + "="*58 + "\n")

try:
    import tkinter as tk
    HAS_TK = True
except ImportError:
    HAS_TK = False

class QuotaHubAppLinux:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Gemini Gauge - AI Quota Monitor")
        self.root.configure(bg="#181818")

        # Load App Icon
        icon_candidates = [
            APP_DIR / "icon.png",
            REPO_ROOT / "assets" / "icon.png",
            Path.home() / ".local" / "share" / "universal-ai-quota" / "icon.png"
        ]
        self._icon_img = None
        for ic in icon_candidates:
            if ic.exists():
                try:
                    self._icon_img = tk.PhotoImage(file=str(ic))
                    self.root.iconphoto(True, self._icon_img)
                    break
                except Exception:
                    pass

        self.prefs = {}
        if PREFS_FILE.exists():
            try:
                with open(PREFS_FILE, "r") as f:
                    self.prefs = json.load(f)
            except Exception:
                pass
        self.mode = self.prefs.get("mode", "full")
        self.orientation = self.prefs.get("orientation", "vertical")

        if "--hud" in sys.argv:
            self.mode = "hud"
        if "--vertical" in sys.argv:
            self.orientation = "vertical"
        if "--horizontal" in sys.argv:
            self.orientation = "horizontal"
        if "--full" in sys.argv:
            self.mode = "full"

        self.quota = load_quota()
        self.is_refreshing = False

        self.root.bind("<Control-m>", lambda e: self.toggle_mode())
        self.root.bind("<Control-M>", lambda e: self.toggle_mode())
        self.root.bind("<Control-o>", lambda e: self.toggle_orientation())
        self.root.bind("<Control-O>", lambda e: self.toggle_orientation())
        self.root.bind("<Control-r>", lambda e: self.refresh(True))
        self.root.bind("<Control-R>", lambda e: self.refresh(True))
        self.root.bind("<F5>", lambda e: self.refresh(True))
        self.root.bind("<Escape>", lambda e: self.root.destroy())

        self.setup_ui()
        self.schedule_auto_refresh()

        # Abre configurações se nenhum provedor estiver configurado
        if not self.quota or self.quota.get("needs_setup") or not self.quota.get("groups"):
            self.root.after(300, self.open_settings)

    def save_prefs(self):
        self.prefs["mode"] = self.mode
        self.prefs["orientation"] = self.orientation
        try:
            with open(PREFS_FILE, "w") as f:
                json.dump(self.prefs, f)
        except Exception:
            pass

    def schedule_auto_refresh(self):
        self.root.after(30000, self.auto_refresh)

    def auto_refresh(self):
        self.refresh(animated=False)
        self.schedule_auto_refresh()

    def refresh(self, animated=True):
        if self.is_refreshing:
            return
        self.is_refreshing = True
        if animated and hasattr(self, "refresh_btn"):
            self.refresh_btn.config(text="Atualizando...")
            self.root.update_idletasks()

        def do_fetch():
            new_data = load_quota(force=True)
            self.root.after(0, lambda: self.on_fetched(new_data))

        import threading
        threading.Thread(target=do_fetch, daemon=True).start()

    def on_fetched(self, data):
        self.is_refreshing = False
        if data:
            self.quota = data
            self.setup_ui()

    def toggle_mode(self):
        self.mode = "hud" if self.mode == "full" else "full"
        self.save_prefs()
        self.setup_ui()

    def toggle_orientation(self):
        self.orientation = "horizontal" if self.orientation == "vertical" else "vertical"
        self.save_prefs()
        self.setup_ui()

    def open_settings(self):
        cfg = load_config()
        pCfg = cfg.get("providers", {})

        dlg = tk.Toplevel(self.root)
        dlg.title("Configurar Provedores de IA - VH2C")
        dlg.geometry("480x420")
        dlg.configure(bg="#181818")
        dlg.transient(self.root)
        dlg.grab_set()

        pad = {"padx": 16, "pady": 6}

        header = tk.Label(dlg, text="⚙️ Configuração de Provedores de IA", font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#181818")
        header.pack(fill="x", pady=(14, 4), padx=16)

        sub = tk.Label(dlg, text="Ative seus provedores ou cole suas chaves de API:", font=("Sans", 8), fg="#999999", bg="#181818")
        sub.pack(fill="x", padx=16, pady=(0, 10))

        # Antigravity
        var_anti = tk.BooleanVar(value=pCfg.get("antigravity", {}).get("enabled", True))
        cb_anti = tk.Checkbutton(dlg, text="Antigravity Pro/Ultra (Detecção Automática / Headless)", variable=var_anti,
                                 font=("Sans", 9, "bold"), fg="#FFFFFF", bg="#181818", selectcolor="#2A2A2A", activebackground="#181818", activeforeground="#FFFFFF")
        cb_anti.pack(anchor="w", **pad)

        # Gemini
        gem_cfg = pCfg.get("gemini", {})
        var_gem = tk.BooleanVar(value=gem_cfg.get("enabled", False))
        f_gem = tk.Frame(dlg, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_gem.pack(fill="x", padx=16, pady=4)
        cb_gem = tk.Checkbutton(f_gem, text="Google Gemini API (AI Studio)", variable=var_gem, font=("Sans", 9, "bold"),
                                fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_gem.pack(anchor="w")
        ent_gem = tk.Entry(f_gem, font=("Sans", 9), bg="#141414", fg="#FFFFFF", insertbackground="white")
        ent_gem.insert(0, gem_cfg.get("api_key", ""))
        ent_gem.pack(fill="x", pady=4)
        link_gem = tk.Label(f_gem, text="🔗 Obter chave grátis no Google AI Studio", font=("Sans", 7), fg="#4DA3FF", bg="#1F1F1F", cursor="hand2")
        link_gem.pack(anchor="w")
        link_gem.bind("<Button-1>", lambda e: webbrowser.open("https://aistudio.google.com/app/apikey"))

        # OpenAI
        oa_cfg = pCfg.get("openai", {})
        var_oa = tk.BooleanVar(value=oa_cfg.get("enabled", False))
        f_oa = tk.Frame(dlg, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_oa.pack(fill="x", padx=16, pady=4)
        cb_oa = tk.Checkbutton(f_oa, text="OpenAI API (sk-proj-...)", variable=var_oa, font=("Sans", 9, "bold"),
                               fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_oa.pack(anchor="w")
        ent_oa = tk.Entry(f_oa, font=("Sans", 9), bg="#141414", fg="#FFFFFF", insertbackground="white")
        ent_oa.insert(0, oa_cfg.get("api_key", ""))
        ent_oa.pack(fill="x", pady=4)

        # Anthropic
        ant_cfg = pCfg.get("anthropic", {})
        var_ant = tk.BooleanVar(value=ant_cfg.get("enabled", False))
        f_ant = tk.Frame(dlg, bg="#1F1F1F", padx=10, pady=8, highlightbackground="#2A2A2A", highlightthickness=1)
        f_ant.pack(fill="x", padx=16, pady=4)
        cb_ant = tk.Checkbutton(f_ant, text="Anthropic Claude API (sk-ant-...)", variable=var_ant, font=("Sans", 9, "bold"),
                                fg="#FFFFFF", bg="#1F1F1F", selectcolor="#2A2A2A", activebackground="#1F1F1F", activeforeground="#FFFFFF")
        cb_ant.pack(anchor="w")
        ent_ant = tk.Entry(f_ant, font=("Sans", 9), bg="#141414", fg="#FFFFFF", insertbackground="white")
        ent_ant.insert(0, ant_cfg.get("api_key", ""))
        ent_ant.pack(fill="x", pady=4)

        # Save Action
        def do_save():
            new_cfg = {
                "providers": {
                    "antigravity": {"enabled": var_anti.get()},
                    "gemini": {"enabled": var_gem.get() or bool(ent_gem.get().strip()), "api_key": ent_gem.get().strip()},
                    "openai": {"enabled": var_oa.get() or bool(ent_oa.get().strip()), "api_key": ent_oa.get().strip()},
                    "anthropic": {"enabled": var_ant.get() or bool(ent_ant.get().strip()), "api_key": ent_ant.get().strip()}
                },
                "refresh_interval_seconds": 30
            }
            save_config(new_cfg)
            dlg.destroy()
            self.refresh(True)

        f_btns = tk.Frame(dlg, bg="#181818", padx=16, pady=10)
        f_btns.pack(fill="x", side="bottom")

        btn_save = tk.Button(f_btns, text="Salvar e Atualizar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                             relief="flat", padx=14, pady=5, cursor="hand2", command=do_save)
        btn_save.pack(side="left")

        btn_cancel = tk.Button(f_btns, text="Cancelar", font=("Sans", 9), fg="#CCCCCC", bg="#2A2A2A",
                               relief="flat", padx=10, pady=5, cursor="hand2", command=dlg.destroy)
        btn_cancel.pack(side="right")

    def setup_ui(self):
        for widget in self.root.winfo_children():
            widget.destroy()

        if self.mode == "full":
            self.setup_full_ui()
        else:
            self.setup_hud_ui()

    def setup_full_ui(self):
        self.root.overrideredirect(False)
        self.root.attributes("-topmost", False)
        self.root.resizable(False, False)
        self.root.configure(bg="#181818")

        quota = self.quota or {}
        groups = quota.get("groups", [])

        w = 480
        total_cards_h = sum(36 + len(g.get("buckets", [])) * 48 for g in groups)
        if total_cards_h == 0:
            total_cards_h = 100
        h = min(80 + total_cards_h + 60, 680)
        self.root.geometry(f"{w}x{h}")

        main_frame = tk.Frame(self.root, bg="#181818", padx=20, pady=16)
        main_frame.pack(fill="both", expand=True)

        acc_text = f"{quota.get('account', 'Multi-Provider')} • Plano {quota.get('plan', 'Universal')}"
        lbl_acc = tk.Label(main_frame, text=acc_text, font=("Sans", 11, "bold"), fg="#FFFFFF", bg="#181818", anchor="w")
        lbl_acc.pack(fill="x")

        time_status = "(Tempo real)" if not quota.get("from_cache") else f"(Cache {quota.get('cache_age_seconds', 0)}s)"
        time_text = f"Atualizado às {quota.get('updated_at', 'agora')} {time_status}"
        lbl_time = tk.Label(main_frame, text=time_text, font=("Sans", 9), fg="#A0A0A0", bg="#181818", anchor="w")
        lbl_time.pack(fill="x", pady=(2, 12))

        if not groups:
            empty_frame = tk.Frame(main_frame, bg="#1F1F1F", padx=20, pady=24, highlightbackground="#2A2A2A", highlightthickness=1)
            empty_frame.pack(fill="both", expand=True, pady=10)
            tk.Label(empty_frame, text="Nenhum provedor ativo ou com cotas detectadas.", font=("Sans", 10, "bold"), fg="#FFFFFF", bg="#1F1F1F").pack()
            tk.Label(empty_frame, text="Clique em 'Configurar' abaixo para adicionar sua chave da Gemini, OpenAI ou Claude.", font=("Sans", 8), fg="#888888", bg="#1F1F1F").pack(pady=4)
            tk.Button(empty_frame, text="⚙️ Configurar Provedores Agora", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                      relief="flat", padx=12, pady=6, cursor="hand2", command=self.open_settings).pack(pady=10)

        for g in groups:
            prov = f" [{g.get('provider')}]" if g.get('provider') else ""
            lbl_g = tk.Label(main_frame, text=(g.get("name", "Modelos") + prov).upper(), font=("Sans", 8, "bold"), fg="#888888", bg="#181818", anchor="w")
            lbl_g.pack(fill="x", pady=(4, 2))

            card = tk.Frame(main_frame, bg="#1F1F1F", bd=1, relief="solid", padx=14, pady=10)
            card.configure(highlightbackground="#2C2C2C", highlightthickness=1)
            card.pack(fill="x", pady=(0, 10))

            for idx, b in enumerate(g.get("buckets", [])):
                if idx > 0:
                    sep = tk.Frame(card, bg="#282828", height=1)
                    sep.pack(fill="x", pady=6)

                row1 = tk.Frame(card, bg="#1F1F1F")
                row1.pack(fill="x")

                bname = tk.Label(row1, text=b.get("name", ""), font=("Sans", 9), fg="#FFFFFF", bg="#1F1F1F")
                bname.pack(side="left")

                pct = b.get("remaining_pct", 100)
                reset_str = f" • {b.get('reset_in')}" if b.get("reset_in") else ""
                val_text = f"{pct}%{reset_str}"
                val_col = status_color(pct)
                bval = tk.Label(row1, text=val_text, font=("Monospace", 9, "bold"), fg=val_col, bg="#1F1F1F")
                bval.pack(side="right")

                bar_canvas = tk.Canvas(card, bg="#2D2D2D", height=6, highlightthickness=0, bd=0)
                bar_canvas.pack(fill="x", pady=(4, 2))
                bar_w = 480 - 40 - 28
                fill_w = max(4, int(bar_w * (pct / 100.0)))
                bar_canvas.create_rectangle(0, 0, fill_w, 6, fill=val_col, outline="")

        footer = tk.Frame(self.root, bg="#181818", padx=20, pady=12)
        footer.pack(fill="x", side="bottom")

        self.refresh_btn = tk.Button(footer, text="↻ Atualizar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                                     activebackground="#FFFFFF", relief="flat", padx=10, pady=4, cursor="hand2",
                                     command=lambda: self.refresh(True))
        self.refresh_btn.pack(side="left")

        hud_btn = tk.Button(footer, text="⚏ Barra HUD", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                            activebackground="#FFFFFF", relief="flat", padx=10, pady=4, cursor="hand2",
                            command=self.toggle_mode)
        hud_btn.pack(side="left", padx=8)

        cfg_btn = tk.Button(footer, text="⚙️ Configurar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                            activebackground="#FFFFFF", relief="flat", padx=10, pady=4, cursor="hand2",
                            command=self.open_settings)
        cfg_btn.pack(side="left", padx=2)

        brand_lbl = tk.Label(footer, text="vh2c.com.br", font=("Sans", 8), fg="#666666", bg="#181818", cursor="hand2")
        brand_lbl.pack(side="left", padx=10)
        brand_lbl.bind("<Button-1>", lambda e: webbrowser.open("https://vh2c.com.br"))

        close_btn = tk.Button(footer, text="Fechar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                              activebackground="#FFFFFF", relief="flat", padx=10, pady=4, cursor="hand2",
                              command=self.root.destroy)
        close_btn.pack(side="right")

    def setup_hud_ui(self):
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg="#141414")

        quota = self.quota or {}
        items = get_gauge_items(quota)
        is_vert = (self.orientation == "vertical")

        if is_vert:
            w = 104
            h = 28 + max(1, len(items)) * 96 + 18
        else:
            w = 28 + max(1, len(items)) * 96 + 10
            h = 108

        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        if is_vert:
            x = sw - w - 24
            y = (sh - h) // 2
        else:
            x = (sw - w) // 2
            y = sh - h - 36
        self.root.geometry(f"{w}x{h}+{x}+{y}")

        self._drag_data = {"x": 0, "y": 0}
        def start_drag(event):
            self._drag_data["x"] = event.x
            self._drag_data["y"] = event.y
        def do_drag(event):
            dx = event.x - self._drag_data["x"]
            dy = event.y - self._drag_data["y"]
            nx = self.root.winfo_x() + dx
            ny = self.root.winfo_y() + dy
            self.root.geometry(f"+{nx}+{ny}")

        canvas = tk.Canvas(self.root, bg="#141414", highlightbackground="#2A2A2A", highlightthickness=1, bd=0)
        canvas.pack(fill="both", expand=True)
        canvas.bind("<Button-1>", start_drag)
        canvas.bind("<B1-Motion>", do_drag)
        canvas.bind("<Double-Button-1>", lambda e: self.toggle_mode())

        def make_icon(x, y, txt, tip, action):
            t = canvas.create_text(x, y, text=txt, font=("Sans", 9, "bold"), fill="#999999", tags="btn")
            canvas.tag_bind(t, "<Button-1>", lambda e: action())
            canvas.tag_bind(t, "<Enter>", lambda e: canvas.itemconfig(t, fill="#FFFFFF"))
            canvas.tag_bind(t, "<Leave>", lambda e: canvas.itemconfig(t, fill="#999999"))

        if is_vert:
            make_icon(14, 14, "✕", "Fechar", self.root.destroy)
            make_icon(34, 14, "⇄", "Alternar Orientação", self.toggle_orientation)
            make_icon(54, 14, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(74, 14, "⚙", "Configurar", self.open_settings)
            make_icon(92, 14, "↻", "Atualizar", lambda: self.refresh(True))
        else:
            make_icon(14, 14, "✕", "Fechar", self.root.destroy)
            make_icon(14, 34, "⇄", "Alternar Orientação", self.toggle_orientation)
            make_icon(14, 54, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(14, 74, "⚙", "Configurar", self.open_settings)
            make_icon(14, 94, "↻", "Atualizar", lambda: self.refresh(True))

        if is_vert:
            cur_y = 30
            for item in items:
                self.draw_gauge(canvas, 52, cur_y + 44, item)
                cur_y += 96
            canvas.create_text(52, h - 8, text="vh2c.com.br", font=("Sans", 7), fill="#555555")
        else:
            cur_x = 28
            for item in items:
                self.draw_gauge(canvas, cur_x + 48, 54, item)
                cur_x += 96

    def draw_gauge(self, canvas, cx, cy, item):
        pct = item.get("pct", 100)
        col = status_color(pct)
        inactive_col = "#333333"

        r_outer = 27
        r_inner = 20.5
        r_center = 18
        total_ticks = 36
        active_ticks = int(round(total_ticks * max(0, min(100, pct)) / 100.0))

        for i in range(total_ticks):
            frac = i / float(total_ticks)
            angle = -math.pi / 2.0 + frac * 2.0 * math.pi
            x1 = cx + math.cos(angle) * r_inner
            y1 = cy + math.sin(angle) * r_inner
            x2 = cx + math.cos(angle) * r_outer
            y2 = cy + math.sin(angle) * r_outer
            c = col if i < active_ticks else inactive_col
            canvas.create_line(x1, y1, x2, y2, fill=c, width=2, capstyle="round")

        canvas.create_oval(cx - r_center, cy - r_center, cx + r_center, cy + r_center, fill=col, outline="")

        font_sz = 9 if pct >= 100 else 10
        canvas.create_text(cx, cy, text=f"{pct}%", font=("Monospace", font_sz, "bold"), fill="#FFFFFF")
        canvas.create_text(cx, cy - r_outer - 7, text=item.get("title", ""), font=("Sans", 8, "bold"), fill="#FFFFFF")
        canvas.create_text(cx, cy + r_outer + 8, text=item.get("model", ""), font=("Sans", 9, "bold"), fill="#FFFFFF")

        rt = item.get("reset_in", "")
        if rt:
            canvas.create_text(cx, cy + r_outer + 19, text=rt, font=("Sans", 8), fill="#999999")

def main():
    if "--cli" in sys.argv or not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        quota = load_quota(force=("--force" in sys.argv))
        print_cli(quota)
        return

    if not HAS_TK:
        print("⚠️  Módulo tkinter não encontrado. Executando em modo CLI.")
        quota = load_quota()
        print_cli(quota)
        return

    app = QuotaHubAppLinux()
    app.root.mainloop()

if __name__ == "__main__":
    main()
