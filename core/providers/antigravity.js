/**
 * Antigravity Provider for Universal AI Quota Monitor
 * Supports live process discovery + headless language_server fallback
 */

const { exec, spawn } = require('child_process');
const http = require('http');
const https = require('https');
const util = require('util');
const fs = require('fs');
const path = require('path');
const os = require('os');

const execAsync = util.promisify(exec);

const RPC_SUMMARY_PATH = '/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary';
const RPC_USER_STATUS_PATH = '/exa.language_server_pb.LanguageServerService/GetUserStatus';

const DEFAULT_METADATA_BODY = {
  metadata: {
    ideName: 'antigravity',
    extensionName: 'universal-ai-quota-monitor',
    locale: 'en'
  }
};

function formatTimeRemaining(resetTimeString, remainingFraction = 1.0) {
  if (!resetTimeString) return '';
  const resetDate = new Date(resetTimeString);
  if (Number.isNaN(resetDate.getTime()) || resetDate.getFullYear() < 2020) return '';
  const now = new Date();
  const diffMs = resetDate - now;
  if (diffMs <= 0) {
    return (remainingFraction !== undefined && remainingFraction >= 0.99) ? '' : 'Renovando...';
  }
  const totalMinutes = Math.floor(diffMs / (1000 * 60));
  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;
  if (hours > 24) {
    const days = Math.floor(hours / 24);
    const remHours = hours % 24;
    return `${days}d ${remHours}h`;
  }
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}

function extractCsrfToken(commandLine) {
  if (!commandLine || typeof commandLine !== 'string') return null;
  const match = commandLine.match(/--csrf_token(?:=|\s+)["']?([a-z0-9_-]{8,})["']?/i);
  return match ? match[1] : null;
}

function extractCliPorts(commandLine) {
  if (!commandLine || typeof commandLine !== 'string') return [];
  const ports = [];
  const patterns = [
    /--hub[_-]port(?:=|\s+)["']?(\d{2,5})["']?/gi,
    /--extension[_-]server[_-]port(?:=|\s+)["']?(\d{2,5})["']?/gi,
    /--port(?:=|\s+)["']?(\d{2,5})["']?/gi
  ];
  for (const regex of patterns) {
    for (const match of commandLine.matchAll(regex)) {
      const p = parseInt(match[1], 10);
      if (p > 0 && p <= 65535 && !ports.includes(p)) {
        ports.push(p);
      }
    }
  }
  return ports;
}

class AntigravityProvider {
  constructor() {
    this.platform = process.platform;
  }

  async findRunningProcess() {
    try {
      if (this.platform === 'win32') {
        const cmd = 'powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match \'language_server|agy\' } | Select-Object ProcessId, CommandLine | ConvertTo-Json"';
        const { stdout } = await execAsync(cmd, { timeout: 4000 });
        let items = JSON.parse(stdout || '[]');
        if (!Array.isArray(items)) items = [items];
        for (const item of items) {
          const token = extractCsrfToken(item.CommandLine || '');
          if (item.ProcessId && token) {
            return { pid: item.ProcessId, commandLine: item.CommandLine, csrfToken: token };
          }
        }
      } else {
        const cmd = 'ps -eo pid,command | grep -E "language_server|agy" | grep -v grep';
        const { stdout } = await execAsync(cmd, { timeout: 3000 });
        for (const line of stdout.split('\n')) {
          const match = line.trim().match(/^(\d+)\s+(.+)$/);
          if (match) {
            const token = extractCsrfToken(match[2]);
            if (token) return { pid: parseInt(match[1], 10), commandLine: match[2], csrfToken: token };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  async getPorts(pid, commandLine) {
    const ports = extractCliPorts(commandLine);
    try {
      if (this.platform === 'win32') {
        const { stdout } = await execAsync(`netstat -ano | findstr "${pid}"`, { timeout: 3000 });
        for (const line of stdout.split('\n')) {
          const parts = line.trim().split(/\s+/);
          if (parts[1] && parts[parts.length - 1] === String(pid)) {
            const m = parts[1].match(/:(\d+)$/);
            if (m) {
              const p = parseInt(m[1], 10);
              if (p > 1024 && !ports.includes(p)) ports.push(p);
            }
          }
        }
      } else {
        const { stdout } = await execAsync(`lsof -nP -p ${pid} -a -iTCP -sTCP:LISTEN 2>/dev/null`, { timeout: 3000 });
        for (const line of stdout.split('\n')) {
          const m = line.match(/:(\d+)\s+\(LISTEN\)/);
          if (m) {
            const p = parseInt(m[1], 10);
            if (!ports.includes(p)) ports.push(p);
          }
        }
      }
    } catch (_) {}

    const defaults = [58014, 58013, 53530, 53527, 53529, 53533, 53534];
    for (const d of defaults) {
      if (!ports.includes(d)) ports.push(d);
    }
    return ports;
  }

  requestRpc(port, token, path, body, useHttps = false) {
    return new Promise((resolve) => {
      const data = JSON.stringify(body || DEFAULT_METADATA_BODY);
      const options = {
        hostname: '127.0.0.1',
        port: port,
        path: path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          'x-codeium-csrf-token': token
        },
        timeout: 2500,
        rejectUnauthorized: false
      };

      const lib = useHttps ? https : http;
      const req = lib.request(options, (res) => {
        let respData = '';
        res.on('data', chunk => respData += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              resolve({ ok: true, data: JSON.parse(respData) });
            } catch (_) {
              resolve({ ok: false });
            }
          } else {
            resolve({ ok: false, status: res.statusCode });
          }
        });
      });

      req.on('error', () => resolve({ ok: false }));
      req.on('timeout', () => { req.destroy(); resolve({ ok: false }); });
      req.write(data);
      req.end();
    });
  }

  findLanguageServerBinary() {
    const candidates = [
      '/Applications/Antigravity.app/Contents/Resources/bin/language_server',
      path.join(os.homedir(), '.local/share/antigravity/bin/language_server'),
      path.join(os.homedir(), 'AppData/Local/Programs/Antigravity/resources/bin/language_server.exe'),
      path.join(os.homedir(), '.gemini/antigravity/bin/language_server')
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
    return null;
  }

  async fetchHeadless() {
    const binPath = this.findLanguageServerBinary();
    if (!binPath) return null;

    const token = 'uaqm-' + Math.random().toString(36).substring(2, 12);
    const proc = spawn(binPath, [
      '--headless=true',
      '--standalone',
      '--http_server_port=0',
      `--csrf_token=${token}`,
      '--app_data_dir=antigravity'
    ], { stdio: ['ignore', 'pipe', 'pipe'] });

    return new Promise((resolve) => {
      let output = '';
      let timer = setTimeout(() => {
        try { proc.kill(); } catch (_) {}
        resolve(null);
      }, 4000);

      proc.stdout.on('data', async (chunk) => {
        output += chunk.toString();
        const m = output.match(/http(?:s)?:\/\/127\.0\.0\.1:(\d+)/i) || output.match(/port\s*[:=]\s*(\d+)/i);
        if (m) {
          clearTimeout(timer);
          const port = parseInt(m[1], 10);
          const userRes = await this.requestRpc(port, token, RPC_USER_STATUS_PATH, {}, false);
          const sumRes = await this.requestRpc(port, token, RPC_SUMMARY_PATH, {}, false);
          try { proc.kill(); } catch (_) {}
          if (userRes.ok && sumRes.ok) {
            resolve({ summary: sumRes.data, user: userRes.data, mode: 'headless' });
          } else {
            resolve(null);
          }
        }
      });

      proc.on('error', () => {
        clearTimeout(timer);
        resolve(null);
      });
    });
  }

  async fetch() {
    // 1. Tenta processo em execução (0 overhead)
    const proc = await this.findRunningProcess();
    if (proc) {
      const ports = await this.getPorts(proc.pid, proc.commandLine);
      for (const port of ports) {
        for (const isHttps of [false, true]) {
          const userRes = await this.requestRpc(port, proc.csrfToken, RPC_USER_STATUS_PATH, {}, isHttps);
          if (userRes.ok) {
            const sumRes = await this.requestRpc(port, proc.csrfToken, RPC_SUMMARY_PATH, {}, isHttps);
            return this.normalize(sumRes.data || {}, userRes.data || {}, 'online');
          }
        }
      }
    }

    // 2. Se não estiver rodando, tenta boot headless independente
    const headlessRes = await this.fetchHeadless();
    if (headlessRes) {
      return this.normalize(headlessRes.summary || {}, headlessRes.user || {}, 'headless');
    }

    return null;
  }

  normalize(quotaData, userData, mode = 'online') {
    const userStatus = userData.userStatus || {};
    const planInfo = userStatus.planStatus?.planInfo || {};

    const groups = [];
    const qPayload = quotaData.response || quotaData;
    const rawGroups = qPayload.groups || [];
    for (const g of rawGroups) {
      const gItem = {
        name: g.displayName || 'Modelos Antigravity',
        description: g.description || '',
        provider: 'Antigravity (' + (mode === 'headless' ? 'Headless' : 'Live') + ')',
        buckets: []
      };
      for (const b of (g.buckets || [])) {
        const pct = Math.round((b.remainingFraction ?? 1) * 100);
        const timeStr = formatTimeRemaining(b.resetTime, b.remainingFraction);
        gItem.buckets.push({
          id: b.bucketId || '',
          name: b.displayName || 'Limite',
          remaining_pct: pct,
          reset_in: timeStr,
          reset_time: b.resetTime || null,
          detail: timeStr ? `Reseta em ${timeStr}` : ''
        });
      }
      if (gItem.buckets.length > 0) groups.push(gItem);
    }

    return {
      provider: 'antigravity',
      account: userStatus.email || 'Conta Antigravity',
      plan: planInfo.planName || 'Pro',
      mode: mode,
      groups: groups
    };
  }
}

module.exports = { AntigravityProvider };
