/**
 * OpenAI API Provider
 */

const https = require('https');

class OpenAIProvider {
  constructor(apiKey) {
    this.apiKey = apiKey || process.env.OPENAI_API_KEY;
  }

  async fetch() {
    if (!this.apiKey) return null;

    return new Promise((resolve) => {
      const options = {
        hostname: 'api.openai.com',
        path: '/v1/models',
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'User-Agent': 'Universal-AI-Quota-Monitor'
        },
        timeout: 4000
      };

      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          const remReq = res.headers['x-ratelimit-remaining-requests'];
          const limitReq = res.headers['x-ratelimit-limit-requests'];
          const remTokens = res.headers['x-ratelimit-remaining-tokens'];
          const limitTokens = res.headers['x-ratelimit-limit-tokens'];
          const resetReq = res.headers['x-ratelimit-reset-requests'];

          if (res.statusCode === 200) {
            let reqPct = 100;
            if (remReq && limitReq && parseInt(limitReq, 10) > 0) {
              reqPct = Math.round((parseInt(remReq, 10) / parseInt(limitReq, 10)) * 100);
            }

            let tokPct = 100;
            if (remTokens && limitTokens && parseInt(limitTokens, 10) > 0) {
              tokPct = Math.round((parseInt(remTokens, 10) / parseInt(limitTokens, 10)) * 100);
            }

            resolve({
              provider: 'openai',
              account: 'OpenAI API Key',
              plan: 'Tier User',
              mode: 'api',
              groups: [
                {
                  name: 'OpenAI API Rate Limits',
                  description: 'Limites de requisições e tokens por minuto',
                  provider: 'OpenAI',
                  buckets: [
                    {
                      id: 'openai-requests',
                      name: 'RPM Limit Remaining',
                      remaining_pct: reqPct,
                      reset_in: resetReq ? `${resetReq}` : '1m',
                      detail: remReq ? `${remReq}/${limitReq} reqs` : 'Ativo'
                    },
                    {
                      id: 'openai-tokens',
                      name: 'TPM Limit Remaining',
                      remaining_pct: tokPct,
                      reset_in: '1m',
                      detail: remTokens ? `${remTokens}/${limitTokens} tokens` : 'Ativo'
                    }
                  ]
                }
              ]
            });
          } else {
            resolve(null);
          }
        });
      });

      req.on('error', () => resolve(null));
      req.on('timeout', () => { req.destroy(); resolve(null); });
      req.end();
    });
  }
}

module.exports = { OpenAIProvider };
