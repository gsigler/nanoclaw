/**
 * Credential proxy for container isolation.
 * Containers connect here instead of directly to the Anthropic API.
 * The proxy injects real credentials so containers never see them.
 *
 * Two auth modes:
 *   API key:  Proxy injects x-api-key on every request.
 *   OAuth:    Container CLI exchanges its placeholder token for a temp
 *             API key via /api/oauth/claude_cli/create_api_key.
 *             Proxy injects real OAuth token on that exchange request;
 *             subsequent requests carry the temp key which is valid as-is.
 *
 * Credential endpoints (/_cred/*):
 *   Container wrapper scripts call these to fetch third-party tokens
 *   (GitHub, Notion, etc.) on-demand. Tokens never appear in container
 *   env vars or files — only in proxy memory on the host.
 */
import { createServer, Server, ServerResponse } from 'http';
import { request as httpsRequest } from 'https';
import { request as httpRequest, RequestOptions } from 'http';

import { readEnvFile } from './env.js';
import { logger } from './logger.js';

export type AuthMode = 'api-key' | 'oauth';

export interface ProxyConfig {
  authMode: AuthMode;
}

/**
 * Handle /_cred/* endpoints that vend third-party tokens to container
 * wrapper scripts. Same security boundary as the Anthropic proxy —
 * only reachable from containers (proxy binds to docker bridge, not LAN).
 */
function handleCredentialEndpoint(
  url: string,
  secrets: Record<string, string>,
  res: ServerResponse,
): void {
  logger.debug({ endpoint: url }, 'Credential endpoint accessed');

  switch (url) {
    case '/_cred/github-token':
      res.writeHead(secrets.GH_TOKEN ? 200 : 404, {
        'content-type': 'text/plain',
      });
      res.end(secrets.GH_TOKEN || '');
      break;
    case '/_cred/notion-headers':
      if (secrets.NOTION_API_KEY) {
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(
          JSON.stringify({
            Authorization: `Bearer ${secrets.NOTION_API_KEY}`,
            'Notion-Version': '2022-06-28',
          }),
        );
      } else {
        res.writeHead(404, { 'content-type': 'text/plain' });
        res.end('');
      }
      break;
    case '/_cred/tendy-header':
      res.writeHead(secrets.TENDY_API_KEY ? 200 : 404, {
        'content-type': 'text/plain',
      });
      res.end(
        secrets.TENDY_API_KEY ? `Bearer ${secrets.TENDY_API_KEY}` : '',
      );
      break;
    case '/_cred/ynab-token':
      res.writeHead(secrets.YNAB_API_TOKEN ? 200 : 404, {
        'content-type': 'text/plain',
      });
      res.end(secrets.YNAB_API_TOKEN || '');
      break;
    default:
      res.writeHead(404, { 'content-type': 'text/plain' });
      res.end('Not found');
  }
}

export function startCredentialProxy(
  port: number,
  host = '127.0.0.1',
): Promise<Server> {
  const secrets = readEnvFile([
    'ANTHROPIC_API_KEY',
    'CLAUDE_CODE_OAUTH_TOKEN',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_BASE_URL',
    'GH_TOKEN',
    'NOTION_API_KEY',
    'TENDY_API_KEY',
    'YNAB_API_TOKEN',
  ]);

  const authMode: AuthMode = secrets.ANTHROPIC_API_KEY ? 'api-key' : 'oauth';
  const oauthToken =
    secrets.CLAUDE_CODE_OAUTH_TOKEN || secrets.ANTHROPIC_AUTH_TOKEN;

  const upstreamUrl = new URL(
    secrets.ANTHROPIC_BASE_URL || 'https://api.anthropic.com',
  );
  const isHttps = upstreamUrl.protocol === 'https:';
  const makeRequest = isHttps ? httpsRequest : httpRequest;

  return new Promise((resolve, reject) => {
    const server = createServer((req, res) => {
      const url = req.url || '/';

      // Credential endpoints — return tokens on-demand for wrapper scripts.
      // No request body needed; respond immediately.
      if (url.startsWith('/_cred/')) {
        handleCredentialEndpoint(url, secrets, res);
        return;
      }

      // Anthropic API proxy — collect body and forward with injected credentials
      const chunks: Buffer[] = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks);
        const headers: Record<string, string | number | string[] | undefined> =
          {
            ...(req.headers as Record<string, string>),
            host: upstreamUrl.host,
            'content-length': body.length,
          };

        // Strip hop-by-hop headers that must not be forwarded by proxies
        delete headers['connection'];
        delete headers['keep-alive'];
        delete headers['transfer-encoding'];

        if (authMode === 'api-key') {
          // API key mode: inject x-api-key on every request
          delete headers['x-api-key'];
          headers['x-api-key'] = secrets.ANTHROPIC_API_KEY;
        } else {
          // OAuth mode: replace placeholder Bearer token with the real one
          // only when the container actually sends an Authorization header
          // (exchange request + auth probes). Post-exchange requests use
          // x-api-key only, so they pass through without token injection.
          if (headers['authorization']) {
            delete headers['authorization'];
            if (oauthToken) {
              headers['authorization'] = `Bearer ${oauthToken}`;
            }
          }
        }

        const upstream = makeRequest(
          {
            hostname: upstreamUrl.hostname,
            port: upstreamUrl.port || (isHttps ? 443 : 80),
            path: req.url,
            method: req.method,
            headers,
          } as RequestOptions,
          (upRes) => {
            res.writeHead(upRes.statusCode!, upRes.headers);
            upRes.pipe(res);
          },
        );

        upstream.on('error', (err) => {
          logger.error(
            { err, url: req.url },
            'Credential proxy upstream error',
          );
          if (!res.headersSent) {
            res.writeHead(502);
            res.end('Bad Gateway');
          }
        });

        upstream.write(body);
        upstream.end();
      });
    });

    server.listen(port, host, () => {
      logger.info({ port, host, authMode }, 'Credential proxy started');
      resolve(server);
    });

    server.on('error', reject);
  });
}

/** Detect which auth mode the host is configured for. */
export function detectAuthMode(): AuthMode {
  const secrets = readEnvFile(['ANTHROPIC_API_KEY']);
  return secrets.ANTHROPIC_API_KEY ? 'api-key' : 'oauth';
}
