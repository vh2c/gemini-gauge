/**
 * Anthropic Claude API Provider
 */

const https = require('https');

class AnthropicProvider {
  constructor(apiKey) {
    this.apiKey = apiKey || process.env.ANTHROPIC_API_KEY;
  }

  async fetch() {
    if (!this.apiKey) return null;

    return new Promise((resolve) => {
      const data = JSON.stringify({
        model: 'claude-3-haiku-20240307',
        max_tokens: 1,
        messages: [{ role: 'user', content: 'hi' }]
      });

      const options = {
        hostname: 'api.anthropic.com',
        path: '/v1/messages',
        method: 'POST',
        headers: {
          'x-api-key': this.apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(data)
        },
        timeout: 4000
      };

      const req = https.request(options, (res) => {
        let respData = '';
        res.on('data', chunk => respData += chunk);
        res.on('end', () => {
          const remReq = res.headers['anthropic-ratelimit-requests-remaining'];
          const limitReq = res.headers['anthropic-ratelimit-requests-limit'];
          const resetReq = res.headers['anthropic-ratelimit-requests-reset'];
          const remTokens = res.headers['anthropic-ratelimit-tokens-remaining'];
          const limitTokens = res.headers['anthropic-ratelimit-tokens-limit'];

          let reqPct = 100;
          if (remReq && limitReq && parseInt(limitReq, 10) > 0) {
            reqPct = Math.round((parseInt(remReq, 10) / parseInt(limitReq, 10)) * 100);
          }

          let tokPct = 100;
          if (remTokens && limitTokens && parseInt(limitTokens, 10) > 0) {
            tokPct = Math.round((parseInt(remTokens, 10) / parseInt(limitTokens, 10)) * 100);
          }

          if (res.statusCode === 200 || res.statusCode === 429) {
            resolve({
              provider: 'anthropic',
              account: 'Anthropic Claude API',
              plan: 'API Tier',
              mode: 'api',
              groups: [
                {
                  name: 'Anthropic Claude Rate Limits',
                  description: 'Limites de requisições e tokens por minuto',
                  provider: 'Anthropic',
                  buckets: [
                    {
                      id: 'claude-requests',
                      name: 'RPM Limit Remaining',
                      remaining_pct: reqPct,
                      reset_in: resetReq ? `${resetReq}` : '1m',
                      detail: remReq ? `${remReq}/${limitReq} reqs` : 'Ativo'
                    },
                    {
                      id: 'claude-tokens',
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
      req.write(data);
      req.end();
    });
  }
}

module.exports = { AnthropicProvider };
