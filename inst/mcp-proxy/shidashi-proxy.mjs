#!/usr/bin/env node
/**
 * shidashi-proxy.mjs — stdio ↔ HTTP MCP proxy
 *
 * Reads newline-delimited JSON-RPC from stdin, forwards each message as an
 * HTTP POST to the shidashi /mcp endpoint, and writes JSON-RPC responses
 * (one per line) to stdout.
 *
 * Target resolution order:
 *   1. CLI argument as full URL: `node shidashi-proxy.mjs http://host:port/path`
 *   2. CLI argument as port only: `node shidashi-proxy.mjs <port>`
 *   3. Latest record in ./ports/ (lexicographic = chronological, ms-timestamp filenames)
 *   4. Fallback: http://127.0.0.1:6564/mcp
 *
 * Zero npm dependencies — only Node.js built-ins.
 */

import http from 'http';
import https from 'https';
import fs from 'fs';
import path from 'path';
import readline from 'readline';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORTS_DIR = path.join(__dirname, 'ports');
const FALLBACK_PORT = 6564;

// ---------------------------------------------------------------------------
// Target resolution
// ---------------------------------------------------------------------------

/**
 * Resolves the target endpoint configuration.
 * @returns {{ hostname: string, port: number, path: string, protocol: 'http:' | 'https:' }}
 */
function resolveTarget() {
  const arg = process.argv[2];

  // Check if argument is a full URL
  if (arg && /^https?:\/\//i.test(arg)) {
    try {
      const url = new URL(arg);
      const target = {
        hostname: url.hostname,
        port: parseInt(url.port, 10) || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        protocol: url.protocol,
      };
      process.stderr.write(
        `[shidashi-proxy] Using URL ${url.protocol}//${target.hostname}:${target.port}${target.path} (from argument)\n`
      );
      return target;
    } catch (e) {
      process.stderr.write(`[shidashi-proxy] Invalid URL: ${arg}, falling back\n`);
    }
  }

  // Check if argument is just a port number
  if (arg && /^\d+$/.test(arg)) {
    const p = parseInt(arg, 10);
    process.stderr.write(`[shidashi-proxy] Using port ${p} (from argument)\n`);
    return { hostname: '127.0.0.1', port: p, path: '/mcp', protocol: 'http:' };
  }

  // Try reading from ports directory
  try {
    const files = fs.readdirSync(PORTS_DIR)
      .filter(f => f.endsWith('.json'))
      .sort(); // lexicographic sort == chronological (ms-timestamp filenames)

    if (files.length > 0) {
      const latestFile = files[files.length - 1];
      const data = JSON.parse(
        fs.readFileSync(path.join(PORTS_DIR, latestFile), 'utf8')
      );
      process.stderr.write(
        `[shidashi-proxy] Using port ${data.port} (from ${latestFile}, created ${data.created})\n`
      );
      return { hostname: '127.0.0.1', port: data.port, path: '/mcp', protocol: 'http:' };
    }
  } catch (e) {
    process.stderr.write(`[shidashi-proxy] Could not read ports directory: ${e.message}\n`);
  }

  process.stderr.write(`[shidashi-proxy] Using fallback port ${FALLBACK_PORT}\n`);
  return { hostname: '127.0.0.1', port: FALLBACK_PORT, path: '/mcp', protocol: 'http:' };
}

const TARGET = resolveTarget();
let sessionId = null;

// ---------------------------------------------------------------------------
// HTTP POST to /mcp
// ---------------------------------------------------------------------------

/**
 * Posts a JSON-RPC message to the shidashi MCP endpoint.
 * Returns an array of parsed JSON-RPC objects (may be >1 for SSE responses).
 */
function postToMcp(rawLine) {
  return new Promise((resolve, reject) => {
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'Content-Length': Buffer.byteLength(rawLine),
    };
    if (sessionId) {
      headers['Mcp-Session-Id'] = sessionId;
    }

    const transport = TARGET.protocol === 'https:' ? https : http;

    const req = transport.request(
      {
        hostname: TARGET.hostname,
        port: TARGET.port,
        path: TARGET.path,
        method: 'POST',
        headers,
      },
      (res) => {
        // Persist session ID as soon as we receive it
        const newSid = res.headers['mcp-session-id'];
        if (newSid) {
          sessionId = newSid;
          process.stderr.write(`[shidashi-proxy] Session ID set: ${sessionId}\n`);
        }

        const ct = res.headers['content-type'] || '';
        const chunks = [];
        res.on('data', chunk => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');

          if (ct.includes('text/event-stream')) {
            // Parse SSE: extract every "data: {...}" line
            const messages = [];
            for (const line of raw.split('\n')) {
              const trimmed = line.trim();
              if (trimmed.startsWith('data: ')) {
                try {
                  messages.push(JSON.parse(trimmed.slice(6)));
                } catch (parseErr) {
                  process.stderr.write(
                    `[shidashi-proxy] SSE parse error on line: ${trimmed}\n`
                  );
                }
              }
            }
            resolve(messages);
          } else {
            // application/json — single response object
            try {
              resolve([JSON.parse(raw)]);
            } catch {
              resolve([]);
            }
          }
        });
      }
    );

    req.on('error', reject);
    req.write(rawLine);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// stdin → process → stdout
// ---------------------------------------------------------------------------

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on('line', async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;

  try {
    const messages = await postToMcp(trimmed);
    // Separate responses (have `id`) from server-initiated notifications.
    // Send responses immediately; defer notifications so VS Code's MCP
    // client reads them as distinct messages and acts on them (e.g.
    // refreshing the tool catalog after notifications/tools/list_changed).
    const responses = [];
    const notifications = [];
    for (const msg of messages) {
      if (msg.id !== undefined) {
        responses.push(msg);
      } else {
        notifications.push(msg);
      }
    }
    for (const msg of responses) {
      process.stdout.write(JSON.stringify(msg) + '\n');
    }
    if (notifications.length) {
      setTimeout(() => {
        for (const msg of notifications) {
          process.stderr.write(
            `[shidashi-proxy] Forwarding notification: ${msg.method}\n`
          );
          process.stdout.write(JSON.stringify(msg) + '\n');
        }
      }, 50);
    }
  } catch (err) {
    process.stderr.write(`[shidashi-proxy] Request error: ${err.message}\n`);
    // Emit a JSON-RPC error so VS Code doesn't hang waiting for a response
    try {
      const req = JSON.parse(trimmed);
      if (req.id !== undefined) {
        process.stdout.write(
          JSON.stringify({
            jsonrpc: '2.0',
            id: req.id,
            error: { code: -32603, message: err.message },
          }) + '\n'
        );
      }
    } catch {
      // Not parseable — nothing to respond to
    }
  }
});

rl.on('close', () => process.exit(0));
