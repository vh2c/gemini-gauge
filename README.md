# 🌐 Universal AI Quota Monitor

[![Powered by VH2C](https://img.shields.io/badge/Developed%20by-vh2c.com.br-blue.svg?style=flat-square)](https://vh2c.com.br)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg?style=flat-square)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square)](#)
[![Python](https://img.shields.io/badge/Python-3.8+-3776AB.svg?style=flat-square&logo=python&logoColor=white)](#)
[![PowerShell](https://img.shields.io/badge/PowerShell-WPF-5391FE.svg?style=flat-square)](#)

A standalone, multi-provider AI usage quota & rate-limit monitor developed by **VH2C**.

Monitors your AI quotas across multiple providers in a unified desktop interface **without requiring the Antigravity IDE to be open**, while supporting standalone API keys for **Google Gemini**, **OpenAI**, and **Anthropic Claude**.

---

## ⚡ Supported Providers

1. **Antigravity Pro / Ultra**:
   - Rolling 5-Hour Limit & Weekly Limit for Gemini Flash, Gemini Pro, Claude 3.5, GPT-4o, and Argon.
   - **Runs independently**: Automatically detects running IDE or spins up a headless background engine probe when Antigravity is closed.
2. **Google AI Studio / Gemini API**:
   - Real-time model availability, RPM, TPM, and API key access status.
3. **OpenAI API**:
   - Request-per-minute (RPM) and token-per-minute (TPM) rate limit tracking.
4. **Anthropic Claude API**:
   - Claude API request and token quota limits.

---

## 🎛️ Dual Display Modes

- **Full Detailed Window**: Traditional clean card layout (`#181818` background, `#1F1F1F` cards), full model details, progress bars, and countdown timers.
- **Compact Radial HUD**: Sleek floating widget with speedometer/tachometer-style radial gauges:
  - 36 radial tick marks with high-contrast active status colors (Green `#22921E`, Amber `#C86402`, Red `#C62828`).
  - Centered percentage badge.
  - Can be oriented as a **Vertical** sidebar strip (~104px wide) or **Horizontal** dock bar (~108px high).
  - Draggable anywhere, always-on-top floating panel.

### Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd + M` (macOS) / `Ctrl + M` (Linux/Windows) | Toggle between **Full Window** and **Radial HUD** |
| `Cmd + O` (macOS) / `Ctrl + O` (Linux/Windows) | Toggle HUD orientation between **Vertical** and **Horizontal** |
| `Cmd + R` (macOS) / `Ctrl + R` (Linux/Windows) | Refresh all quotas immediately |
| `Esc` | Close application |
| **Double-Click any Gauge** | Expand into the Full Detailed Window |

---

## ⚙️ Configuration (Optional API Keys)

To monitor standalone API keys alongside your Antigravity account, create or edit `~/.config/UniversalAIQuota/config.json`:

```json
{
  "providers": {
    "antigravity": {
      "enabled": true
    },
    "gemini": {
      "enabled": true,
      "api_key": "YOUR_GEMINI_API_KEY"
    },
    "openai": {
      "enabled": true,
      "api_key": "sk-proj-YOUR_OPENAI_KEY"
    },
    "anthropic": {
      "enabled": true,
      "api_key": "sk-ant-YOUR_ANTHROPIC_KEY"
    }
  },
  "refresh_interval_seconds": 30
}
```

*You can also set environment variables: `GEMINI_API_KEY`, `OPENAI_API_KEY`, and `ANTHROPIC_API_KEY`.*

---

## 🖥️ Installation

### 🍏 macOS
```bash
git clone https://github.com/vh2c/universal-ai-quota-monitor.git
cd universal-ai-quota-monitor/macos
./install.sh
```

### 🐧 Linux
```bash
git clone https://github.com/vh2c/universal-ai-quota-monitor.git
cd universal-ai-quota-monitor/linux
./install.sh

# Run via terminal:
quota-hub
# Or CLI headless mode:
quota-hub --cli
```

### 🪟 Windows
```powershell
git clone https://github.com/vh2c/universal-ai-quota-monitor.git
cd universal-ai-quota-monitor\windows
.\install.ps1
```

---

## 🏢 About VH2C

Developed and maintained by [VH2C Soluções Tecnológicas](https://vh2c.com.br).

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright © 2026 [VH2C](https://vh2c.com.br).
