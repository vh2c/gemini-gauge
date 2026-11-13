/**
 * Gemini Gauge Telemetry & Heartbeat
 * Developed by VH2C • https://vh2c.com.br
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const ENDPOINT = 'https://api.vh2c.com.br/v1/geminigauje';

function getTelemetryDir() {
  const dir = path.join(os.homedir(), '.config', 'UniversalAIQuota');
  if (!fs.existsSync(dir)) {
    try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  }
  return dir;
}

function getMachineId() {
  const idFile = path.join(getTelemetryDir(), 'device_id');
  if (fs.existsSync(idFile)) {
    try {
      const id = fs.readFileSync(idFile, 'utf8').trim();
      if (id && id.length >= 8) return id;
    } catch (_) {}
  }

  // Generate anonymous persistent machine fingerprint
  const rawSeed = [
    os.hostname(),
    os.platform(),
    os.arch(),
    os.cpus()?.[0]?.model || 'unknown-cpu',
    os.totalmem()
  ].join('|');

  const newId = crypto.createHash('sha256').update(rawSeed).digest('hex').substring(0, 32);
  try {
    fs.writeFileSync(idFile, newId, 'utf8');
  } catch (_) {}
  return newId;
}

function sendHeartbeat(extraData = {}) {
  const payload = JSON.stringify({
    app: 'gemini-gauge',
    version: '1.0.0',
    os: os.platform(),
    os_release: os.release(),
    arch: os.arch(),
    machine_id: getMachineId(),
    locale: Intl.DateTimeFormat().resolvedOptions().locale || 'pt-BR',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Sao_Paulo',
    timestamp: Math.floor(Date.now() / 1000),
    ...extraData
  });

  try {
    const url = new URL(ENDPOINT);
    const options = {
      hostname: url.hostname,
      port: url.port || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'User-Agent': 'GeminiGauge/1.0 (VH2C; Desktop)'
      },
      timeout: 2500
    };

    const client = url.protocol === 'https:' ? https : http;
    const req = client.request(options, (res) => {
      // Drain data silently
      res.on('data', () => {});
    });

    req.on('error', () => {});
    req.on('timeout', () => {
      try { req.destroy(); } catch (_) {}
    });

    req.write(payload);
    req.end();
  } catch (_) {
    // Fail silently
  }
}

module.exports = {
  ENDPOINT,
  getMachineId,
  sendHeartbeat
};
