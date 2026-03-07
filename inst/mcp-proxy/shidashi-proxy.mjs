#!/usr/bin/env node
/**
 * shidashi-proxy.mjs — stdio ↔ HTTP MCP proxy
 *
 * Reads newline-delimited JSON-RPC from stdin, forwards each message as an
 * HTTP POST to the shidashi /mcp endpoint, and writes JSON-RPC responses
 * (one per line) to stdout.
 *
 * Port resolution order:
 *   1. CLI argument: `node shidashi-proxy.mjs <port>`
 *   2. Latest record in ./ports/ (lexicographic = chronological, ms-timestamp filenames)
 *   3. Fallback: 6564
 *
 * Zero npm dependencies — only Node.js built-ins.
 */

import http from 'http';
import fs from 'fs';
import path from 'path';
import readline from 'readline';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORTS_DIR = path.join(__dirname, 'ports');
const FALLBACK_PORT = 6564;

// ---------------------------------------------------------------------------
// Port resolution
// ---------------------------------------------------------------------------

function resolvePort() {
  const arg = process.argv[2];
  if (arg && /^\d+$/.test(arg)) {
    const p = parseInt(arg, 10);
    process.stderr.write(`[shidashi-proxy] Using port ${p} (from argument)\n`);
    return p;
  }

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
      return data.port;
    }
  } catch (e) {
    process.stderr.write(`[shidashi-proxy] Could not read ports directory: ${e.message}\n`);
  }

  process.stderr.write(`[shidashi-proxy] Using fallback port ${FALLBACK_PORT}\n`);
  return FALLBACK_PORT;
}

const TARGET_PORT = resolvePort();
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

    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: TARGET_PORT,
        path: '/mcp',
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
    for (const msg of messages) {
      process.stdout.write(JSON.stringify(msg) + '\n');
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
