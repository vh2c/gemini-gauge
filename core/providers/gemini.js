/**
 * Google Gemini API Provider (AI Studio / Vertex AI Key)
 */

const https = require('https');

class GeminiProvider {
  constructor(apiKey) {
    this.apiKey = apiKey || process.env.GEMINI_API_KEY;
  }

  async fetch() {
    if (!this.apiKey) return null;

    return new Promise((resolve) => {
      const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${this.apiKey}`;
      https.get(url, { timeout: 4000 }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          if (res.statusCode === 200) {
            try {
              const json = JSON.parse(data);
              const models = (json.models || []).filter(m => m.name.includes('gemini'));
              resolve({
                provider: 'gemini_api',
                account: 'Google AI Studio Key',
                plan: 'Google Cloud API',
                mode: 'api',
                groups: [
                  {
                    name: 'Google Gemini API',
                    description: `${models.length} modelos Gemini disponíveis na chave`,
                    provider: 'Google AI Studio',
                    buckets: [
                      {
                        id: 'gemini-flash-rpm',
                        name: 'Gemini Flash Rate Limit',
                        remaining_pct: 100,
                        reset_in: '1m',
                        detail: '15 RPM (Free) / 1000 RPM (Paid)'
                      },
                      {
                        id: 'gemini-pro-rpm',
                        name: 'Gemini Pro Rate Limit',
                        remaining_pct: 100,
                        reset_in: '1m',
                        detail: '2 RPM (Free) / 360 RPM (Paid)'
                      },
                      {
                        id: 'gemini-key-status',
                        name: 'API Key Access & Models',
                        remaining_pct: 100,
                        reset_in: 'Ativo',
                        detail: `${models.length} modelos liberados`
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
      }).on('error', () => resolve(null));
    });
  }
}

module.exports = { GeminiProvider };
