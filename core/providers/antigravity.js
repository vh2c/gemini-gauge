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

  findFromDaemonHubs() {
    try {
      const daemonDir = path.join(os.homedir(), '.gemini/antigravity/daemon');
      if (!fs.existsSync(daemonDir)) return null;
      const files = fs.readdirSync(daemonDir).filter(f => f.startsWith('hub_') && f.endsWith('.json'));
      // Sort newest first
      files.sort((a, b) => {
        try {
          return fs.statSync(path.join(daemonDir, b)).mtimeMs - fs.statSync(path.join(daemonDir, a)).mtimeMs;
        } catch (_) { return 0; }
      });

      for (const file of files) {
        try {
          const content = JSON.parse(fs.readFileSync(path.join(daemonDir, file), 'utf8'));
          if (content.pid && content.csrfToken) {
            try {
              process.kill(content.pid, 0); // Check if alive
              return {
                pid: content.pid,
                csrfToken: content.csrfToken,
                httpPort: content.httpPort,
                httpsPort: content.httpsPort,
                commandLine: ''
              };
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  async findRunningProcess() {
    // 1. Instant check from daemon directory
    const daemonHub = this.findFromDaemonHubs();
    if (daemonHub) return daemonHub;

    // 2. Fallback to process table scan
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

  async getPorts(proc) {
    if (proc.httpsPort || proc.httpPort) {
      const p = [];
      if (proc.httpsPort) p.push(proc.httpsPort);
      if (proc.httpPort) p.push(proc.httpPort);
      return p;
    }
    const pid = proc.pid;
    const commandLine = proc.commandLine || '';
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

    const defaults = [53078, 53079, 58014, 58013, 53530, 53527, 53529, 53533, 53534];
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
    const args = [
      '--standalone',
      '--override_ide_name', 'antigravity',
      '--subclient_type', 'hub',
      '--app_data_dir', 'antigravity',
      '--api_server_url', 'https://generativelanguage.googleapis.com',
      '--cloud_code_endpoint', 'https://daily-cloudcode-pa.googleapis.com',
      '--https_server_port', '0',
      '--csrf_token', token
    ];

    const proc = spawn(binPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    return new Promise((resolve) => {
      let resolved = false;
      let stderrOutput = '';
      let stdoutOutput = '';

      const cleanup = () => {
        try { proc.kill(); } catch (_) {}
      };

      const timer = setTimeout(() => {
        if (!resolved) {
          resolved = true;
          cleanup();
          resolve(null);
        }
      }, 5000);

      const tryConnect = async (port, isHttps) => {
        if (resolved) return;
        // Small delay for server initialization
        await new Promise(r => setTimeout(r, 250));
        const userRes = await this.requestRpc(port, token, RPC_USER_STATUS_PATH, {}, isHttps);
        const sumRes = await this.requestRpc(port, token, RPC_SUMMARY_PATH, {}, isHttps);
        if (!resolved && (sumRes.ok || userRes.ok)) {
          resolved = true;
          clearTimeout(timer);
          cleanup();
          resolve({ summary: sumRes.data || {}, user: userRes.data || {}, mode: 'headless' });
        }
      };

      const handleChunk = (chunk) => {
        const text = chunk.toString();
        // Check for HTTPS port
        const mHttps = text.match(/listening on random port at (\d+) for HTTPS/i);
        if (mHttps) {
          const port = parseInt(mHttps[1], 10);
          tryConnect(port, true);
          return;
        }
        // Check for HTTP port
        const mHttp = text.match(/listening on random port at (\d+) for HTTP/i);
        if (mHttp) {
          const port = parseInt(mHttp[1], 10);
          tryConnect(port, false);
          return;
        }
      };

      proc.stderr.on('data', (d) => {
        stderrOutput += d.toString();
        handleChunk(d);
      });
      proc.stdout.on('data', (d) => {
        stdoutOutput += d.toString();
        handleChunk(d);
      });

      proc.on('error', () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          resolve(null);
        }
      });

      proc.on('exit', () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          resolve(null);
        }
      });
    });
  }

  async fetch() {
    // 1. Tenta processo em execução (0 overhead)
    const proc = await this.findRunningProcess();
    if (proc) {
      const ports = await this.getPorts(proc);
      for (const port of ports) {
        for (const isHttps of [true, false]) {
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
