#!/usr/bin/env node
/**
 * Universal AI Quota Engine
 * Aggregates Antigravity (Live & Headless), Google Gemini API, OpenAI, and Anthropic
 * Developed by VH2C • https://vh2c.com.br
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const { AntigravityProvider } = require('./providers/antigravity');
const { GeminiProvider } = require('./providers/gemini');
const { OpenAIProvider } = require('./providers/openai');
const { AnthropicProvider } = require('./providers/anthropic');

const CONFIG_DIR = path.join(os.homedir(), '.config', 'UniversalAIQuota');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

function loadConfig() {
  if (fs.existsSync(CONFIG_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch (_) {}
  }
  return {
    providers: {
      antigravity: { enabled: true },
      gemini: { enabled: Boolean(process.env.GEMINI_API_KEY), api_key: process.env.GEMINI_API_KEY || '' },
      openai: { enabled: Boolean(process.env.OPENAI_API_KEY), api_key: process.env.OPENAI_API_KEY || '' },
      anthropic: { enabled: Boolean(process.env.ANTHROPIC_API_KEY), api_key: process.env.ANTHROPIC_API_KEY || '' }
    }
  };
}

class UniversalQuotaEngine {
  constructor() {
    this.config = loadConfig();
  }

  async fetchAll() {
    const providers = [];
    const pCfg = this.config.providers || {};

    if (pCfg.antigravity?.enabled !== false) {
      providers.push(new AntigravityProvider().fetch());
    }
    if (pCfg.gemini?.enabled && pCfg.gemini?.api_key) {
      providers.push(new GeminiProvider(pCfg.gemini.api_key).fetch());
    }
    if (pCfg.openai?.enabled && pCfg.openai?.api_key) {
      providers.push(new OpenAIProvider(pCfg.openai.api_key).fetch());
    }
    if (pCfg.anthropic?.enabled && pCfg.anthropic?.api_key) {
      providers.push(new AnthropicProvider(pCfg.anthropic.api_key).fetch());
    }

    const results = await Promise.allSettled(providers);
    const valid = results.filter(r => r.status === 'fulfilled' && r.value !== null).map(r => r.value);

    if (valid.length === 0) {
      return {
        needs_setup: true,
        account: 'Nenhum Provedor Configurado',
        plan: 'Configurar',
        providers_count: 0,
        groups: [],
        updated_at: new Date().toLocaleTimeString('pt-BR')
      };
    }

    const allGroups = [];
    let mainAccount = 'Multi-Provider AI';
    let mainPlan = 'Universal Hub';

    for (const item of valid) {
      if (item.provider === 'antigravity') {
        mainAccount = item.account;
        mainPlan = item.plan;
      }
      for (const g of item.groups || []) {
        allGroups.push(g);
      }
    }

    return {
      account: mainAccount,
      plan: mainPlan,
      providers_count: valid.length,
      groups: allGroups,
      updated_at: new Date().toLocaleTimeString('pt-BR')
    };
  }
}

if (require.main === module) {
  const engine = new UniversalQuotaEngine();
  engine.fetchAll().then(res => {
    console.log(JSON.stringify(res, null, 2));
  }).catch(err => {
    console.error(JSON.stringify({ error: err.message }));
    process.exit(1);
  });
}

module.exports = { UniversalQuotaEngine };
