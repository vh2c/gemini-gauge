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
                plan: 'Pay-as-you-go / Free Tier',
                mode: 'api',
                groups: [
                  {
                    name: 'Gemini API (Google AI Studio)',
                    description: `${models.length} modelos disponíveis via API Key`,
                    provider: 'Google Cloud / AI Studio',
                    buckets: [
                      {
                        id: 'gemini-api-status',
                        name: 'API Key Status & Access',
                        remaining_pct: 100,
                        reset_in: 'Ativo',
                        detail: `${models.length} modelos ativos`
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
