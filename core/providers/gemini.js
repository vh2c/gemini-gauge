/**
 * Google Gemini API Provider (AI Studio / Google Cloud)
 * Supports standard Gemini API keys (AIzaSy...) and OAuth Bearer tokens
 */

const https = require('https');

class GeminiProvider {
  constructor(apiKey) {
    this.apiKey = (apiKey || process.env.GEMINI_API_KEY || '').trim();
  }

  static async testConnection(apiKey) {
    const provider = new GeminiProvider(apiKey);
    return provider.fetch();
  }

  async fetch() {
    if (!this.apiKey) return null;

    const isBearer = this.apiKey.startsWith('ya29.') || this.apiKey.startsWith('AQ.');
    const url = isBearer
      ? 'https://generativelanguage.googleapis.com/v1beta/models'
      : `https://generativelanguage.googleapis.com/v1beta/models?key=${this.apiKey}`;

    const headers = {
      'User-Agent': 'GeminiGauge/1.0 (vh2c.com.br)'
    };
    if (isBearer) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    return new Promise((resolve) => {
      const req = https.get(url, { headers, timeout: 5000 }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              const json = JSON.parse(data);
              const allModels = json.models || [];
              const geminiModels = allModels.filter(m => (m.name || '').includes('gemini'));
              const count = geminiModels.length || allModels.length || 1;

              resolve({
                provider: 'gemini_api',
                account: this.apiKey.substring(0, 10) + '...',
                plan: 'Google AI Studio API',
                mode: 'api',
                groups: [
                  {
                    name: 'Google Gemini API',
                    description: `${count} modelos disponíveis na sua chave`,
                    provider: 'Google AI Studio',
                    buckets: [
                      {
                        id: 'gemini-flash-rpm',
                        name: 'Gemini Flash Rate Limit',
                        remaining_pct: 100,
                        reset_in: '1m',
                        detail: '15 RPM (Gratuito) / 1000 RPM (Pay-as-you-go)'
                      },
                      {
                        id: 'gemini-pro-rpm',
                        name: 'Gemini Pro Rate Limit',
                        remaining_pct: 100,
                        reset_in: '1m',
                        detail: '2 RPM (Gratuito) / 360 RPM (Pay-as-you-go)'
                      },
                      {
                        id: 'gemini-key-status',
                        name: 'Acesso & Modelos da Chave',
                        remaining_pct: 100,
                        reset_in: 'Ativo',
                        detail: `${count} modelos liberados na conta`
                      }
                    ]
                  }
                ]
              });
            } catch (_) {
              resolve(null);
            }
          } else {
            resolve(null);
          }
        });
      });

      req.on('error', () => resolve(null));
      req.on('timeout', () => { req.destroy(); resolve(null); });
    });
  }
}

module.exports = { GeminiProvider };
