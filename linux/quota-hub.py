#!/usr/bin/env python3
"""
Universal AI Quota Monitor - Linux Edition
Developed by VH2C • https://vh2c.com.br
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
CACHE_FILE = CONFIG_DIR / "quota_cache.json"
PREFS_FILE = CONFIG_DIR / "prefs.json"

def find_node():
    for p in ["/usr/bin/node", "/usr/local/bin/node", "/opt/homebrew/bin/node", "/bin/node"]:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    nvm_nodes = sorted(glob.glob(os.path.expanduser("~/.nvm/versions/node/*/bin/node")), reverse=True)
    if nvm_nodes:
        return nvm_nodes[0]
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
        res = subprocess.run([node_bin, str(ENGINE_SCRIPT)], capture_output=True, text=True, env=env, timeout=6)
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
    if not quota:
        print("❌ Não foi possível carregar dados dos provedores de IA.")
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
        self.root.title("Universal AI Quota Hub")
        self.root.configure(bg="#181818")

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

        w = 460
        total_cards_h = sum(36 + len(g.get("buckets", [])) * 48 for g in groups)
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
                bar_w = 460 - 40 - 28
                fill_w = max(4, int(bar_w * (pct / 100.0)))
                bar_canvas.create_rectangle(0, 0, fill_w, 6, fill=val_col, outline="")

        footer = tk.Frame(self.root, bg="#181818", padx=20, pady=12)
        footer.pack(fill="x", side="bottom")

        self.refresh_btn = tk.Button(footer, text="↻ Atualizar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                                     activebackground="#FFFFFF", relief="flat", padx=12, pady=4, cursor="hand2",
                                     command=lambda: self.refresh(True))
        self.refresh_btn.pack(side="left")

        hud_btn = tk.Button(footer, text="⚏ Barra HUD", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                            activebackground="#FFFFFF", relief="flat", padx=12, pady=4, cursor="hand2",
                            command=self.toggle_mode)
        hud_btn.pack(side="left", padx=10)

        brand_lbl = tk.Label(footer, text="vh2c.com.br", font=("Sans", 8), fg="#666666", bg="#181818", cursor="hand2")
        brand_lbl.pack(side="left", padx=14)
        brand_lbl.bind("<Button-1>", lambda e: webbrowser.open("https://vh2c.com.br"))

        close_btn = tk.Button(footer, text="Fechar", font=("Sans", 9, "bold"), fg="#181818", bg="#EEEEF0",
                              activebackground="#FFFFFF", relief="flat", padx=12, pady=4, cursor="hand2",
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
            h = 28 + len(items) * 96 + 18
        else:
            w = 28 + len(items) * 96 + 10
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
            make_icon(18, 14, "✕", "Fechar", self.root.destroy)
            make_icon(42, 14, "⇄", "Alternar Orientação", self.toggle_orientation)
            make_icon(64, 14, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(86, 14, "↻", "Atualizar", lambda: self.refresh(True))
        else:
            make_icon(14, 16, "✕", "Fechar", self.root.destroy)
            make_icon(14, 40, "⇄", "Alternar Orientação", self.toggle_orientation)
            make_icon(14, 64, "⊞", "Modo Completo", self.toggle_mode)
            make_icon(14, 88, "↻", "Atualizar", lambda: self.refresh(True))

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
