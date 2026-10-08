#!/usr/bin/env node
/**
 * shidashi-proxy.mjs — stdio MCP server for shidashi apps
 *
 * Reads newline-delimited JSON-RPC from stdin and writes responses (one per
 * line) to stdout. Tool calls are forwarded over HTTP to a running shidashi
 * app. The proxy works without any running app: it answers `initialize`
 * itself, lists the tools it can, and tells the agent to ask the user what
 * to do instead of failing.
 *
 * Usage:
 *   node mcp-proxy.mjs [--app <app_id | app directory>] [--module <module>]
 *   node mcp-proxy.mjs <url | port>
 *
 * Files written by R, in the shidashi cache folder `<cache>`: the
 * environment variable SHIDASHI_CACHE_DIR; else the folder above this
 * script when it is the copy in `<cache>/mcp_server/` made by
 * setup_mcp_proxy(); else tools::R_user_dir("shidashi", "cache") (the
 * case when this script runs from a Claude plugin):
 *   <cache>/launchers.json            apps saved with shidashi::save_launcher()
 *   <cache>/mcp_server/apps/<id>.json one per running app:
 *                                     {app_id, appdir, host, port, pid, started,
 *                                      log_dir}
 *   <cache>/mcp_server/proxy-meta.json  instructions and meta tools
 *   <cache>/mcp_server/logs/<id>.log  output of apps this proxy started
 *   <cache>/MCP-logs/<folder>/mcp-calls.log  the MCP call log: each app writes
 *                                     the calls it answers to its `log_dir`;
 *                                     this proxy adds the calls that never
 *                                     reach an app, marked `(proxy)`
 *
 * Choosing the app:
 *   --app      the newest live record whose app_id, app directory, or
 *              directory name matches
 *   otherwise  the newest live record
 * Until an app has answered, a record whose port refuses connections is
 * skipped for the next one: its R session may outlive the app it ran.
 * The proxy then sticks to the directory of the app that answered. When the
 * app restarts (new port, new app_id), the next request finds the new record
 * for the same directory. It moves to another directory only when its own
 * has no live app and --app was not given, or when the agent launches a
 * saved app.
 *
 * --module limits every tool call to one module (e.g. `--module demo`).
 * A URL or port argument connects to that endpoint directly instead.
 *
 * Remote apps: `shidashi_connect(url)` attaches the proxy to a shidashi app
 * at any address for this session (localhost always over http; other
 * hosts try https, then http). `shidashi_disconnect` goes back to local
 * apps. Nothing about remote apps is written to disk.
 *
 * The tool list follows the attached app: its tools, plus the meta tools
 * from R and this proxy's own tools. Whenever the attached app changes
 * (none, local, remote), the proxy sends notifications/tools/list_changed.
 *
 * The proxy never starts an app on its own. `shidashi_launch` starts a
 * saved app only when the agent calls it, after asking the user. It opens
 * the module page with $BROWSER when set, otherwise the system browser.
 *
 * Zero npm dependencies — only Node.js built-ins.
 */

import http from 'http';
import https from 'https';
import fs from 'fs';
import os from 'os';
import path from 'path';
import readline from 'readline';
import { spawn } from 'child_process';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// The shidashi cache folder: saved launchers, app copies, and `mcp_server/`.
// An empty variable counts as unset, as in R.
function resolveCacheDir() {
  const env = (name) => process.env[name] || '';
  if (env('SHIDASHI_CACHE_DIR')) return env('SHIDASHI_CACHE_DIR');
  // A copy installed by setup_mcp_proxy() sits in `<cache>/mcp_server/`
  if (path.basename(__dirname) === 'mcp_server') return path.dirname(__dirname);
  // Otherwise (e.g. a Claude plugin): tools::R_user_dir("shidashi", "cache")
  let base = env('R_USER_CACHE_DIR') || env('XDG_CACHE_HOME');
  if (!base) {
    if (process.platform === 'win32') {
      base = path.join(env('LOCALAPPDATA'), 'R', 'cache');
    } else if (process.platform === 'darwin') {
      base = path.join(os.homedir(), 'Library', 'Caches', 'org.R-project.R');
    } else {
      base = path.join(os.homedir(), '.cache');
    }
  }
  return path.join(base, 'R', 'shidashi');
}

const CACHE_DIR = resolveCacheDir();
const SERVER_DIR = path.join(CACHE_DIR, 'mcp_server');
const APPS_DIR = path.join(SERVER_DIR, 'apps');
const LAUNCHERS_PATH = path.join(CACHE_DIR, 'launchers.json');
const LOGS_DIR = path.join(SERVER_DIR, 'logs');
const META_PATH = path.join(SERVER_DIR, 'proxy-meta.json');
const CALL_LOG_ROOT = path.join(CACHE_DIR, 'MCP-logs');
const PROTOCOL_VERSION = '2025-03-26';
const LAUNCH_TIMEOUT_MS = 40000;
const PROXY_STARTED = new Date();

function log(message) {
  process.stderr.write(`[shidashi-proxy] ${message}\n`);
}

// ---------------------------------------------------------------------------
// MCP call log
//
// The app writes every call that reaches it to its log folder (the record's
// `log_dir`). The proxy adds, marked `(proxy)`, the calls that never reach
// an app: its own tools, replies when no app answers, replies the app gave
// without a JSON-RPC answer, and calls the client cancelled. Lines go to the
// folder of the app the proxy used or tried last, else to a folder of its
// own. SHIDASHI_MCP_LOG=false (or 0) turns the log off.
// ---------------------------------------------------------------------------

const CALL_LOG_MAX_CHARS = 300;

// The local app record the proxy used or tried last, or null
let lastRecord = null;

function callLogEnabled() {
  const value = (process.env.SHIDASHI_MCP_LOG || '').trim().toLowerCase();
  return !(value === 'false' || value === '0');
}

function pad(number, width = 2) {
  return String(number).padStart(width, '0');
}

function callLogDir() {
  if (lastRecord && typeof lastRecord.log_dir === 'string' && lastRecord.log_dir) {
    return lastRecord.log_dir;
  }
  const d = PROXY_STARTED;
  const stamp = `${pad(d.getFullYear() % 100)}${pad(d.getMonth() + 1)}` +
    `${pad(d.getDate())}T${pad(d.getHours())}${pad(d.getMinutes())}` +
    `${pad(d.getSeconds())}`;
  return path.join(CALL_LOG_ROOT, `date-${stamp}_app-none`);
}

function callLogTime(d = new Date()) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.` +
    pad(d.getMilliseconds(), 3);
}

function callLogJson(value) {
  if (value === undefined || value === null) return '{}';
  try {
    return JSON.stringify(value);
  } catch {
    return '{?}';
  }
}

function callLogReason(message) {
  return `{reason: ${JSON.stringify(String(message))}}`;
}

// The name a call is logged under: the tool for tools/call, else the method
function callLogName(request) {
  if (request?.method === 'tools/call') {
    const name = request.params?.name;
    return typeof name === 'string' && name ? name : '?';
  }
  return typeof request?.method === 'string' ? request.method : '?';
}

// Write one line: `<time> [type] [name] id=<id> <secs>s (proxy) <payload>`
function appendCallLog(type, name, id, elapsedMs, payload) {
  if (!callLogEnabled()) return;
  const parts = [callLogTime(), `[${type}]`, `[${name}]`];
  if (id !== undefined && id !== null) parts.push(`id=${id}`);
  if (elapsedMs !== undefined && elapsedMs !== null) {
    parts.push(`${(elapsedMs / 1000).toFixed(2)}s`);
  }
  parts.push('(proxy)');
  if (payload) parts.push(payload);
  let line = parts.join(' ').replace(/\r\n|\n|\r/g, '\\n').replace(/\t/g, ' ');
  if (line.length > CALL_LOG_MAX_CHARS) {
    line = line.slice(0, CALL_LOG_MAX_CHARS - 3) + '...';
  }
  try {
    const dir = callLogDir();
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(path.join(dir, 'mcp-calls.log'), line + '\n');
  } catch {
    // the log never breaks a call
  }
}

// Log a call the proxy answered itself: its request, then its reply
function logAnsweredCall(request, started, result) {
  const name = callLogName(request);
  const args = request.method === 'tools/call'
    ? request.params?.arguments
    : request.params;
  appendCallLog('request', name, request.id, null, callLogJson(args));
  const text = (result?.content ?? [])
    .map((item) => (typeof item?.text === 'string' ? item.text : ''))
    .filter(Boolean).join('\n');
  if (result?.isError) {
    appendCallLog('failed', name, request.id, Date.now() - started,
                  callLogReason(text));
  } else {
    appendCallLog('response', name, request.id, Date.now() - started,
                  JSON.stringify(text));
  }
}

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = { app: null, module: null, direct: null };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--app' || arg === '--module') {
      args[arg.slice(2)] = argv[++i] ?? null;
    } else if (arg.startsWith('--app=')) {
      args.app = arg.slice('--app='.length);
    } else if (arg.startsWith('--module=')) {
      args.module = arg.slice('--module='.length);
    } else {
      args.direct = arg;
    }
  }
  return args;
}

const ARGS = parseArgs(process.argv.slice(2));

// A URL or port argument: connect there directly, no app records
function directEndpoint(arg) {
  if (!arg) return null;
  if (/^https?:\/\//i.test(arg)) {
    const url = new URL(arg);
    return {
      protocol: url.protocol,
      hostname: url.hostname,
      port: parseInt(url.port, 10) || (url.protocol === 'https:' ? 443 : 80),
      path: url.pathname + url.search,
      label: url.href,
    };
  }
  if (/^\d+$/.test(arg)) {
    const port = parseInt(arg, 10);
    return {
      protocol: 'http:', hostname: '127.0.0.1', port, path: '/mcp',
      label: `port ${port}`,
    };
  }
  log(`Ignoring unrecognized argument: ${arg}`);
  return null;
}

const DIRECT = directEndpoint(ARGS.direct);
if (DIRECT) log(`Connecting directly to ${DIRECT.label}`);

// ---------------------------------------------------------------------------
// What the proxy knows without an app: meta tools (from R) and its own tools
// ---------------------------------------------------------------------------

// Read on every use: R rewrites the file whenever an app starts, which may
// be after this proxy started
let metaMissingLogged = false;

function loadMeta() {
  try {
    const meta = JSON.parse(fs.readFileSync(META_PATH, 'utf8'));
    return {
      instructions: typeof meta.instructions === 'string' ? meta.instructions : '',
      tools: Array.isArray(meta.tools) ? meta.tools : [],
    };
  } catch {
    if (!metaMissingLogged) {
      metaMissingLogged = true;
      log(`${META_PATH} not found; start a shidashi app once ` +
          '(shidashi::render()) to create it');
    }
    return { instructions: '', tools: [] };
  }
}

const PROXY_INSTRUCTIONS =
  'If a tool says that no shidashi app is running, stop and ask the user ' +
  'whether they will start an app themselves or want you to launch one of ' +
  'their saved apps (see `shidashi_launchers`). Do not decide for them. ' +
  'If the user gives you the address of a shidashi app, call ' +
  '`shidashi_connect` with it. Your tool list follows the app you are ' +
  'attached to; if it did not refresh after connecting or launching, use ' +
  '`shidashi_tools` and `shidashi_call`.';

const PROXY_TOOLS = [
  {
    name: 'shidashi_launchers',
    description:
      'List the shidashi apps the user saved with shidashi::save_launcher(): ' +
      'their ids, descriptions, the modules each can open, and whether each ' +
      'is running. Use it to show the user which apps you can launch.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'shidashi_launch',
    description:
      'Start a saved shidashi app and open one of its modules in the ' +
      'browser. Only call this after the user has chosen the app (and ' +
      'module); never pick one yourself. If the app is already running, ' +
      'this only opens the module.',
    inputSchema: {
      type: 'object',
      properties: {
        id: {
          type: 'string',
          description: 'The saved app id, from `shidashi_launchers`.',
        },
        module: {
          type: 'string',
          description:
            'Optional module id to open, from the app\'s `modules`. Omit to ' +
            'open the dashboard home page.',
        },
      },
      required: ['id'],
    },
  },
  {
    name: 'shidashi_connect',
    description:
      'Attach to a shidashi app at a web address the user gave you, for ' +
      'example one running on another computer or an RStudio Server. ' +
      'Checks the address (https first, then http; always http for ' +
      'localhost), then sends tool calls there for the rest of this ' +
      'session. Your tool list changes to that app\'s tools.',
    inputSchema: {
      type: 'object',
      properties: {
        url: {
          type: 'string',
          description:
            'The app\'s address, e.g. `https://server:8787/p/abc123/` or ' +
            '`127.0.0.1:6564`.',
        },
      },
      required: ['url'],
    },
  },
  {
    name: 'shidashi_disconnect',
    description:
      'Stop using the app attached with `shidashi_connect` and go back to ' +
      'shidashi apps on this computer.',
    inputSchema: { type: 'object', properties: {} },
  },
];

// ---------------------------------------------------------------------------
// Paths and hosts
// ---------------------------------------------------------------------------

function normalizeDir(dir) {
  if (!dir) return '';
  let resolved = path.resolve(dir);
  try {
    resolved = fs.realpathSync(resolved);
  } catch {
    // keep the resolved path when it does not exist
  }
  return resolved.replace(/\\/g, '/').replace(/\/+$/, '');
}

// Host to connect to: a wildcard listen address means this machine
function connectHost(host) {
  if (!host || host === '0.0.0.0' || host === '::') return '127.0.0.1';
  return host;
}

function urlHost(host) {
  const h = connectHost(host);
  return h.includes(':') ? `[${h}]` : h;
}

// ---------------------------------------------------------------------------
// App records
// ---------------------------------------------------------------------------

function isAlive(pid) {
  if (!Number.isInteger(pid)) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

// Live app records, newest first. Records of exited apps are removed.
function liveRecords() {
  let files = [];
  try {
    files = fs.readdirSync(APPS_DIR).filter((f) => f.endsWith('.json'));
  } catch {
    return [];
  }
  const records = [];
  for (const file of files) {
    const recordPath = path.join(APPS_DIR, file);
    let record;
    try {
      record = JSON.parse(fs.readFileSync(recordPath, 'utf8'));
    } catch {
      continue;
    }
    if (!record || !record.app_id || !record.port) continue;
    if (!isAlive(record.pid)) {
      try { fs.unlinkSync(recordPath); } catch { /* already gone */ }
      continue;
    }
    record.appdir = normalizeDir(record.appdir);
    records.push(record);
  }
  records.sort((a, b) => String(b.started).localeCompare(String(a.started)));
  return records;
}

function matchesApp(record, spec) {
  return record.app_id === spec ||
    record.appdir === normalizeDir(spec) ||
    path.basename(record.appdir) === spec;
}

let stickyAppdir = null;
let currentApp = null;

// Whether a local app has answered this proxy (or the agent launched one).
// Until then, a record whose port refuses connections is skipped for the
// next newest one: its process may be an R session that is still running
// after the app in it stopped.
let attached = false;
const unreachable = new Set();

function recordKey(record) {
  return `${record.app_id}:${record.port}:${record.started}`;
}

function selectApp() {
  let records = liveRecords();
  if (!attached) {
    records = records.filter((r) => !unreachable.has(recordKey(r)));
  }
  let record = null;
  if (stickyAppdir) {
    record = records.find((r) => r.appdir === stickyAppdir) ?? null;
  }
  if (!record && ARGS.app) {
    record = records.find((r) => matchesApp(r, ARGS.app)) ?? null;
  }
  if (!record && !ARGS.app) {
    record = records[0] ?? null;
  }
  currentApp = record;
  return record;
}

// The app answered (or the agent launched it): stick to its directory
function useApp(record) {
  if (!attached || stickyAppdir !== record.appdir) {
    log(`Using app ${record.app_id} (${record.appdir}) on port ${record.port}`);
  }
  currentApp = record;
  stickyAppdir = record.appdir;
  attached = true;
}

function appEndpoint(record) {
  let urlPath = '/mcp';
  if (ARGS.module) urlPath += `/${encodeURIComponent(ARGS.module)}`;
  return {
    protocol: 'http:', hostname: connectHost(record.host), port: record.port,
    path: urlPath,
  };
}

// ---------------------------------------------------------------------------
// Saved launchers
// ---------------------------------------------------------------------------

// Saved launchers from launchers.json (an object keyed by id), as a list
function readLaunchers() {
  let saved;
  try {
    saved = JSON.parse(fs.readFileSync(LAUNCHERS_PATH, 'utf8'));
  } catch {
    return [];
  }
  if (!saved || typeof saved !== 'object' || Array.isArray(saved)) return [];
  const launchers = [];
  for (const [id, entry] of Object.entries(saved)) {
    if (!entry || !entry.root_path) continue;
    launchers.push({
      ...entry,
      id,
      root_path: normalizeDir(entry.root_path),
      modules: [].concat(entry.modules ?? []).map(String),
      metadata: entry.metadata && typeof entry.metadata === 'object'
        ? entry.metadata
        : {},
    });
  }
  launchers.sort((a, b) => a.id.localeCompare(b.id));
  return launchers;
}

function code(x) {
  return '`' + x + '`';
}

function describeLauncher(launcher) {
  const modules = launcher.modules.length
    ? launcher.modules.map(code).join(', ')
    : 'none listed';
  const description = launcher.description ? ` — ${launcher.description}` : '';
  const metadata = Object.entries(launcher.metadata)
    .map(([key, value]) => `${key}: ${[].concat(value).join(', ')}`);
  const extra = metadata.length ? `; ${metadata.join('; ')}` : '';
  return `${code(launcher.id)}${description} (modules: ${modules}${extra})`;
}

function saveLauncherHint() {
  return 'The user can save one in R, for example: ' +
    '`shidashi::save_launcher("my-app", "/path/to/app")`.';
}

function moduleUrl(record, module) {
  const base = `http://${urlHost(record.host)}:${record.port}/`;
  return module ? `${base}?module=${encodeURIComponent(module)}` : base;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

// Resolves to { status, messages } where messages are parsed JSON-RPC objects
function post(endpoint, body) {
  return new Promise((resolve, reject) => {
    const transport = endpoint.protocol === 'https:' ? https : http;
    const req = transport.request(
      {
        hostname: endpoint.hostname,
        port: endpoint.port,
        path: endpoint.path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks).toString('utf8');
          const contentType = res.headers['content-type'] || '';
          const messages = [];
          if (contentType.includes('text/event-stream')) {
            for (const line of raw.split('\n')) {
              const trimmed = line.trim();
              if (!trimmed.startsWith('data: ')) continue;
              try {
                messages.push(JSON.parse(trimmed.slice(6)));
              } catch {
                log(`SSE parse error on line: ${trimmed}`);
              }
            }
          } else if (raw.trim()) {
            try {
              messages.push(JSON.parse(raw));
            } catch {
              log(`Non-JSON response (HTTP ${res.statusCode}): ${raw.slice(0, 200)}`);
            }
          }
          resolve({ status: res.statusCode, messages });
        });
      }
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// Whether the app answers on its MCP URL yet
function isServing(record) {
  return new Promise((resolve) => {
    const endpoint = appEndpoint(record);
    const req = http.get(
      { hostname: endpoint.hostname, port: endpoint.port, path: endpoint.path,
        timeout: 2000 },
      (res) => {
        res.resume();
        resolve(res.statusCode === 200);
      }
    );
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.on('error', () => resolve(false));
  });
}

function isConnectionError(err) {
  return ['ECONNREFUSED', 'ECONNRESET', 'EHOSTUNREACH', 'ETIMEDOUT']
    .includes(err && err.code);
}

// ---------------------------------------------------------------------------
// Tool list changes: tell the client when the list it has is out of date
// ---------------------------------------------------------------------------

// Where the last `tools/list` answer came from: null (none yet), 'offline',
// 'direct', or 'app:<appdir>'
let listedFrom = null;

function noteSource(source) {
  if (listedFrom && listedFrom !== source) {
    listedFrom = source;
    write({ jsonrpc: '2.0', method: 'notifications/tools/list_changed' });
  }
}

// Forward one message to the attached app: a remote app, the startup URL,
// or a local app. Returns the response and where it came from, or null when
// no app is reachable. For local apps, a stopped process (the app closed or
// restarted, even on the same port) or a failed connection means: look for
// the app's new record and retry once. Before any local app has answered, a
// record whose port refuses the connection is skipped for the next one.
async function tryForward(body) {
  const fixed = remoteApp ? remoteApp.endpoint : DIRECT;
  if (fixed) {
    try {
      const response = await post(fixed, body);
      response.source = remoteApp ? `remote:${remoteApp.key}` : 'direct';
      noteSource(response.source);
      return response;
    } catch (err) {
      log(`Cannot reach ${fixed.label}: ${err.message}`);
      return null;
    }
  }

  const attempts = attached ? 2 : 10;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (currentApp && !isAlive(currentApp.pid)) currentApp = null;
    const record = currentApp ?? selectApp();
    if (!record) return null;
    lastRecord = record;
    try {
      const response = await post(appEndpoint(record), body);
      useApp(record);
      response.source = `app:${record.appdir}`;
      noteSource(response.source);
      return response;
    } catch (err) {
      if (!isConnectionError(err)) throw err;
      if (!attached) {
        unreachable.add(recordKey(record));
        log(`App ${record.app_id} on port ${record.port} does not answer; ` +
            'trying the next app');
      }
      currentApp = null;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Answers that do not need an app
// ---------------------------------------------------------------------------

function textResult(text, isError = false) {
  return { content: [{ type: 'text', text }], isError };
}

function offlineText() {
  if (remoteApp) {
    return [
      `The remote shidashi app at ${remoteApp.origin} is not reachable, so ` +
        'nothing ran.',
      'Pause here and ask the user what to do; do not choose for them:',
      '1. They check that the app is still running, then you try again ' +
        '(or call `shidashi_connect` with its address again).',
      '2. You go back to shidashi apps on this computer with ' +
        '`shidashi_disconnect`.',
    ].join('\n');
  }
  let what = 'No shidashi app is running';
  if (DIRECT) {
    what = `The shidashi app at ${DIRECT.label} is not running`;
  } else if (stickyAppdir) {
    // name the app by its saved id; never show its directory to the agent
    const saved = readLaunchers().find((l) => l.root_path === stickyAppdir);
    what = saved
      ? `The saved app ${code(saved.id)} is not running`
      : 'The shidashi app you were using is not running';
  } else if (ARGS.app) {
    // `--app` may be a directory; show only its last part
    what = `The shidashi app "${path.basename(ARGS.app)}" is not running`;
  }
  const launchers = readLaunchers();
  const lines = [
    `${what}, so nothing ran.`,
    'Pause here and ask the user which they prefer; do not choose for them:',
    '1. They start a shidashi app themselves (for example with ' +
      '`shidashi::render()` in R) and tell you when it is open.',
  ];
  if (launchers.length) {
    lines.push(
      '2. You launch one of their saved apps with `shidashi_launch` ' +
        '(the `id`, and optionally a `module` to open):'
    );
    for (const launcher of launchers) {
      lines.push(`   - ${describeLauncher(launcher)}`);
    }
  } else {
    lines.push(
      '2. You launch one of their saved apps with `shidashi_launch`, but ' +
        `none are saved yet. ${saveLauncherHint()}`
    );
  }
  lines.push(
    '3. If the app runs on another computer, they give you its address and ' +
      'you call `shidashi_connect`.'
  );
  return lines.join('\n');
}

function initializeResult() {
  return {
    protocolVersion: PROTOCOL_VERSION,
    capabilities: { tools: { listChanged: true } },
    serverInfo: { name: 'shidashi', version: '1.0.0' },
    instructions: [loadMeta().instructions, PROXY_INSTRUCTIONS]
      .filter(Boolean).join('\n\n'),
  };
}

function launchersResult() {
  const running = liveRecords();
  const launchers = readLaunchers().map((launcher) => {
    const record = running.find((r) => r.appdir === launcher.root_path);
    return {
      id: launcher.id,
      description: launcher.description || '',
      modules: launcher.modules,
      metadata: launcher.metadata,
      running: !!record,
      url: record ? moduleUrl(record) : null,
    };
  });
  const text = launchers.length
    ? JSON.stringify({ saved_apps: launchers }, null, 2)
    : `No saved apps. ${saveLauncherHint()}`;
  return textResult(text);
}

// ---------------------------------------------------------------------------
// shidashi_launch
// ---------------------------------------------------------------------------

function openBrowser(url) {
  let command;
  let args;
  if (process.env.BROWSER) {
    command = process.env.BROWSER;
    args = [url];
  } else if (process.platform === 'darwin') {
    command = 'open';
    args = [url];
  } else if (process.platform === 'win32') {
    command = 'cmd';
    args = ['/c', 'start', '""', url];
  } else {
    command = 'xdg-open';
    args = [url];
  }
  try {
    const child = spawn(command, args,
                        { detached: true, stdio: 'ignore', windowsHide: true });
    child.on('error', (err) => log(`Cannot open ${url}: ${err.message}`));
    child.unref();
    return true;
  } catch (err) {
    log(`Cannot open ${url}: ${err.message}`);
    return false;
  }
}

// Start a saved app in the background with `shidashi::run_launcher(id)`.
// The app's output goes to a log file, never to an unread pipe. The app
// uses this proxy's cache folder, so its record lands where we look.
function startLauncher(launcher) {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
  const logPath = path.join(LOGS_DIR, `${launcher.id}.log`);
  const logFd = fs.openSync(logPath, 'w');
  const rscript = launcher.rscript && fs.existsSync(launcher.rscript)
    ? launcher.rscript
    : 'Rscript';
  const expr = `shidashi::run_launcher(${JSON.stringify(launcher.id)})`;
  const state = { exited: false, logPath };
  const child = spawn(rscript, ['-e', expr], {
    detached: true,
    stdio: ['ignore', logFd, logFd],
    windowsHide: true,
    env: { ...process.env, SHIDASHI_CACHE_DIR: CACHE_DIR },
  });
  child.on('error', (err) => {
    state.exited = true;
    fs.appendFileSync(logPath, `\nCannot start ${rscript}: ${err.message}\n`);
  });
  child.on('exit', () => { state.exited = true; });
  child.unref();
  fs.closeSync(logFd);
  log(`Starting saved app ${launcher.id} (log: ${logPath})`);
  return state;
}

function tail(file, lines = 15) {
  try {
    return fs.readFileSync(file, 'utf8').trimEnd().split('\n')
      .slice(-lines).join('\n');
  } catch {
    return '(no log)';
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function launch(args) {
  const id = args?.id;
  const module = args?.module || null;
  const launchers = readLaunchers();
  const launcher = launchers.find((l) => l.id === id);
  if (!launcher) {
    const saved = launchers.length
      ? `Saved apps: ${launchers.map((l) => code(l.id)).join(', ')}.`
      : `No apps are saved. ${saveLauncherHint()}`;
    return textResult(`There is no saved app named ${code(id)}. ${saved}`, true);
  }
  if (module && !launcher.modules.includes(module)) {
    const modules = launcher.modules.length
      ? launcher.modules.map(code).join(', ')
      : 'none';
    return textResult(
      `Module ${code(module)} is not listed for ${code(launcher.id)}. ` +
        `Its modules: ${modules}.`,
      true
    );
  }

  const findRecord = () =>
    liveRecords().find((r) => r.appdir === launcher.root_path) ?? null;
  let record = findRecord();
  const alreadyRunning = !!record;

  if (!record) {
    const started = startLauncher(launcher);
    const deadline = Date.now() + LAUNCH_TIMEOUT_MS;
    while (Date.now() < deadline) {
      await sleep(500);
      const candidate = findRecord();
      if (candidate && await isServing(candidate)) {
        record = candidate;
        break;
      }
      if (started.exited && !candidate) break;
    }
    if (!record) {
      const why = started.exited ? 'stopped before it was ready' :
        `did not start within ${LAUNCH_TIMEOUT_MS / 1000} seconds`;
      return textResult(
        `Saved app ${code(launcher.id)} ${why}. Last lines of ` +
          `${started.logPath}:\n${tail(started.logPath)}`,
        true
      );
    }
  }

  remoteApp = null;
  useApp(record);
  noteSource(`app:${record.appdir}`);

  const url = moduleUrl(record, module);
  const opened = openBrowser(url);
  const lines = [
    alreadyRunning
      ? `Saved app ${code(launcher.id)} was already running on port ${record.port}.`
      : `Started saved app ${code(launcher.id)} on port ${record.port}.`,
    opened
      ? `Opened ${url} in the browser.`
      : `Could not open a browser; ask the user to open ${url}.`,
    module
      ? `Tools run in module ${code(module)} once the page has loaded; call ` +
        '`shidashi_sessions` to confirm it is open.'
      : 'This is the dashboard home page. Ask the user to open a module, or ' +
        'launch again with a `module`.',
  ];
  return textResult(lines.join('\n'));
}

// ---------------------------------------------------------------------------
// shidashi_connect / shidashi_disconnect (this session only)
// ---------------------------------------------------------------------------

// The remote app attached with `shidashi_connect`:
// { endpoint, origin, app_id, key }, or null
let remoteApp = null;

function isLocalHost(hostname) {
  const host = String(hostname).replace(/^\[|\]$/g, '').toLowerCase();
  return host === 'localhost' || host === '::1' || host === '0.0.0.0' ||
    /^127\./.test(host);
}

// Addresses to try for what the user gave: localhost always over http;
// other hosts with no scheme over https, then http. The path ends in `/mcp`
// (or `/mcp/<module>`).
function connectCandidates(input) {
  const raw = String(input ?? '').trim();
  const hasScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
  let base;
  try {
    base = new URL(hasScheme ? raw : `http://${raw}`);
  } catch {
    return [];
  }
  if (!raw || !/^https?:$/.test(base.protocol)) return [];
  let schemes;
  if (isLocalHost(base.hostname)) {
    schemes = ['http:'];
  } else if (hasScheme) {
    schemes = [base.protocol];
  } else {
    schemes = ['https:', 'http:'];
  }
  return schemes.map((scheme) => {
    const url = new URL(base.href);
    url.protocol = scheme;
    let urlPath = url.pathname.replace(/\/+$/, '');
    if (!/\/mcp(\/[^/]+)?$/.test(urlPath)) urlPath += '/mcp';
    url.pathname = urlPath;
    url.search = '';
    url.hash = '';
    return url;
  });
}

function endpointFromUrl(url) {
  let urlPath = url.pathname;
  if (ARGS.module && /\/mcp$/.test(urlPath)) {
    urlPath += `/${encodeURIComponent(ARGS.module)}`;
  }
  return {
    protocol: url.protocol,
    hostname: url.hostname.replace(/^\[|\]$/g, ''),
    port: parseInt(url.port, 10) || (url.protocol === 'https:' ? 443 : 80),
    path: urlPath,
    label: url.origin,
  };
}

// GET the address without following redirects
function probe(url) {
  return new Promise((resolve) => {
    const transport = url.protocol === 'https:' ? https : http;
    const req = transport.get(
      url, { headers: { Accept: 'application/json' }, timeout: 8000 },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => resolve({
          status: res.statusCode,
          headers: res.headers,
          body: Buffer.concat(chunks).toString('utf8'),
        }));
      }
    );
    req.on('timeout', () => req.destroy(new Error('timed out')));
    req.on('error', (err) => resolve({ error: err }));
  });
}

function classifyProbe(result) {
  if (result.error) {
    return { kind: 'unreachable', detail: result.error.code || result.error.message };
  }
  const status = result.status;
  if ((status >= 300 && status < 400) || status === 401 || status === 403) {
    return { kind: 'login', detail: `HTTP ${status}` };
  }
  if (status === 200) {
    let info = null;
    try {
      info = JSON.parse(result.body);
    } catch {
      // not JSON
    }
    if (info && (info.server === 'shidashi' || (info.status === 'ok' && info.app_id))) {
      return { kind: 'shidashi', info };
    }
    if (/sign[\s-]?in|log[\s-]?in/i.test(result.body)) {
      return { kind: 'login', detail: 'a sign-in page' };
    }
  }
  return { kind: 'other', detail: `HTTP ${status}` };
}

function loginText(url) {
  return `${url.origin} asks for a sign-in (for example RStudio Server or ` +
    'Posit Workbench), which this connector cannot do. Ask the user to make ' +
    'the app reachable without it, for example with an SSH tunnel: ' +
    '`ssh -L 6564:localhost:<app port> <server>` (the app port is the one ' +
    'shidashi printed when it started). Then connect to ' +
    '`http://127.0.0.1:6564`.';
}

async function connect(args) {
  const input = args?.url;
  const candidates = connectCandidates(input);
  if (!candidates.length) {
    return textResult(
      `${code(input)} is not a web address. Ask the user for the address of ` +
        'the shidashi app, for example `https://server:8787/p/abc123/`.',
      true
    );
  }

  const unreachable = [];
  for (const url of candidates) {
    log(`Checking ${url.href}`);
    const probed = classifyProbe(await probe(url));
    if (probed.kind === 'unreachable') {
      unreachable.push(`${url.origin} (${probed.detail})`);
      continue;
    }
    if (probed.kind === 'login') return textResult(loginText(url), true);
    if (probed.kind === 'other') {
      return textResult(
        `${url.origin} answered (${probed.detail}), but ${url.pathname} is not ` +
          'a shidashi MCP endpoint. Check the address with the user; the app ' +
          'must be started with `shidashi::render()`.',
        true
      );
    }

    // A shidashi app: confirm it speaks MCP, then attach
    const endpoint = endpointFromUrl(url);
    let serverName = null;
    try {
      const init = await post(endpoint, JSON.stringify({
        jsonrpc: '2.0', id: 'connect', method: 'initialize', params: {},
      }));
      serverName = init.messages.find((m) => m.id === 'connect')
        ?.result?.serverInfo?.name;
    } catch (err) {
      unreachable.push(`${url.origin} (${err.code || err.message})`);
      continue;
    }
    if (serverName !== 'shidashi') {
      return textResult(
        `${url.origin} is not a shidashi MCP endpoint (initialize failed). ` +
          'Check the address with the user.',
        true
      );
    }

    remoteApp = {
      endpoint, origin: url.origin, app_id: probed.info.app_id, key: url.href,
    };
    log(`Connected to remote app ${remoteApp.app_id} at ${url.href}`);
    noteSource(`remote:${remoteApp.key}`);
    return textResult(
      `Connected to shidashi app ${code(remoteApp.app_id)} at ${url.origin}. ` +
        'Its tools may differ from before: if your tool list did not ' +
        'refresh, use `shidashi_tools` and `shidashi_call`. Call ' +
        '`shidashi_sessions` next.'
    );
  }

  return textResult(
    `Could not reach ${unreachable.join(', then ')}. Check the address with ` +
      'the user, and that the app is running.',
    true
  );
}

function disconnect() {
  if (!remoteApp) {
    return textResult(
      'Not attached to a remote app; tool calls already go to shidashi apps ' +
        'on this computer.'
    );
  }
  const origin = remoteApp.origin;
  remoteApp = null;
  currentApp = null;
  // The next request attaches a local app (or none): the tool list changes
  noteSource('disconnected');
  return textResult(
    `Disconnected from ${origin}. Tool calls now go to shidashi apps on this ` +
      'computer; call `shidashi_sessions` to see what is open.'
  );
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

function write(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

function reply(id, result) {
  write({ jsonrpc: '2.0', id, result });
}

function replyError(id, message, code = -32603) {
  write({ jsonrpc: '2.0', id, error: { code, message } });
}

// Write the app's messages; make sure the request gets a reply. The app
// logs the calls it answers; a reply without an answer is logged here.
function relay(request, response, transform = (message) => message,
               started = Date.now()) {
  let answered = false;
  for (const message of response.messages) {
    if (message.id === request.id) {
      answered = true;
      write(transform(message));
    } else {
      write(message);
    }
  }
  if (!answered) {
    const message = `The shidashi app returned HTTP ${response.status} ` +
      'without a JSON-RPC response.';
    appendCallLog('failed', callLogName(request), request.id,
                  Date.now() - started, callLogReason(message));
    replyError(request.id, message);
  }
}

async function handle(request, body) {
  const { id, method, params } = request;
  const started = Date.now();

  if (method === 'initialize') return reply(id, initializeResult());
  if (method === 'ping') return reply(id, {});

  if (method === 'tools/list') {
    // This answer is the new list; no change notification is needed for it
    listedFrom = null;
    const response = await tryForward(body);
    if (response) {
      listedFrom = response.source;
      return relay(request, response, (message) => {
        if (Array.isArray(message.result?.tools)) {
          message.result.tools = [...message.result.tools, ...PROXY_TOOLS];
        }
        return message;
      }, started);
    }
    listedFrom = 'offline';
    const tools = [...loadMeta().tools, ...PROXY_TOOLS];
    appendCallLog('request', 'tools/list', id, null, callLogJson(params));
    appendCallLog('response', 'tools/list', id, Date.now() - started,
                  `{"tools":${tools.length},"offline":true}`);
    return reply(id, { tools });
  }

  if (method === 'tools/call') {
    const name = params?.name;
    const proxyTools = {
      shidashi_launchers: () => launchersResult(),
      shidashi_launch: () => launch(params?.arguments ?? {}),
      shidashi_connect: () => connect(params?.arguments ?? {}),
      shidashi_disconnect: () => disconnect(),
    };
    if (typeof name === 'string' && Object.hasOwn(proxyTools, name)) {
      const result = await proxyTools[name]();
      logAnsweredCall(request, started, result);
      return reply(id, result);
    }
    const response = await tryForward(body);
    if (response) return relay(request, response, undefined, started);
    const text = offlineText();
    // nothing ran: a failure in the log, even for `shidashi_sessions`
    logAnsweredCall(request, started, textResult(text, true));
    return reply(id, textResult(text, name !== 'shidashi_sessions'));
  }

  const response = await tryForward(body);
  if (response) return relay(request, response, undefined, started);
  const message = `Method not found: ${method}`;
  appendCallLog('request', callLogName(request), id, null, callLogJson(params));
  appendCallLog('failed', callLogName(request), id, Date.now() - started,
                callLogReason(message));
  return replyError(id, message, -32601);
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let pending = 0;
let inputClosed = false;

function exitWhenIdle() {
  if (inputClosed && pending === 0) {
    // Exit once the replies are flushed: writes to a pipe are asynchronous
    // on macOS, so exiting right away can cut off the last reply
    process.stdout.write('', () => process.exit(0));
  }
}

rl.on('line', async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;

  let request = null;
  try {
    request = JSON.parse(trimmed);
  } catch {
    log(`Ignoring a line that is not JSON: ${trimmed.slice(0, 200)}`);
    return;
  }
  // Notifications from the client need no reply and no app. A cancelled
  // call (the client gave up waiting) is worth a line in the call log.
  if (!request || typeof request !== 'object' ||
      request.id === undefined || request.id === null) {
    if (request?.method === 'notifications/cancelled') {
      appendCallLog('request', request.method, null, null,
                    callLogJson(request.params));
    }
    return;
  }

  pending++;
  try {
    await handle(request, trimmed);
  } catch (err) {
    log(`Request error: ${err.message}`);
    appendCallLog('failed', callLogName(request), request.id, null,
                  callLogReason(err.message));
    replyError(request.id, err.message);
  } finally {
    pending--;
    exitWhenIdle();
  }
});

// Finish replies that are still in flight before exiting
rl.on('close', () => {
  inputClosed = true;
  exitWhenIdle();
});
