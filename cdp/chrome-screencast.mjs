// Drives a headless Google Chrome via the DevTools Protocol and streams the
// page as a screencast. Each frame is written atomically to <outdir>/frame.png
// followed by an incremented integer in <outdir>/frame.seq. Pharo polls
// frame.seq (tiny) and, on change, reads frame.png (guaranteed complete because
// the seq bump happens only after the atomic rename).
//
// Zero npm dependencies: Node >= 22 provides global fetch + WebSocket.
//
// Usage: node chrome-screencast.mjs <url> <outdir> [width] [height]

import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, renameSync, mkdirSync, openSync, readSync, closeSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const url = process.argv[2] || 'https://example.com';
const outdir = process.argv[3] || '/tmp/wv-cdp';
const width = parseInt(process.argv[4] || '800', 10);
const height = parseInt(process.argv[5] || '600', 10);

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9222;

mkdirSync(outdir, { recursive: true });
const userDataDir = mkdtempSync(join(tmpdir(), 'wv-chrome-'));

const chrome = spawn(CHROME, [
  '--headless=new',
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${userDataDir}`,
  `--window-size=${width},${height}`,
  '--hide-scrollbars',
  '--disable-gpu',
  '--no-first-run',
  '--no-default-browser-check',
  'about:blank',
], { stdio: ['ignore', 'ignore', 'inherit'] });

let seq = 0;
function writeFrame(b64) {
  const buf = Buffer.from(b64, 'base64');
  const tmp = join(outdir, 'frame.png.tmp');
  writeFileSync(tmp, buf);
  renameSync(tmp, join(outdir, 'frame.png')); // atomic on same fs
  seq += 1;
  writeFileSync(join(outdir, 'frame.seq'), String(seq)); // ordering: seq AFTER png
}

async function waitForPageTarget() {
  for (let i = 0; i < 100; i++) {
    try {
      const res = await fetch(`http://localhost:${PORT}/json`);
      const targets = await res.json();
      const page = targets.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page.webSocketDebuggerUrl;
    } catch (_) { /* chrome not up yet */ }
    await new Promise(r => setTimeout(r, 100));
  }
  throw new Error('no page target from Chrome after 10s');
}

let msgId = 0;
function send(ws, method, params) {
  msgId += 1;
  ws.send(JSON.stringify({ id: msgId, method, params: params || {} }));
  return msgId;
}

const wsUrl = await waitForPageTarget();
const ws = new WebSocket(wsUrl);

ws.addEventListener('open', () => {
  send(ws, 'Page.enable');
  send(ws, 'Page.navigate', { url });
  send(ws, 'Page.startScreencast', {
    format: 'png',
    everyNthFrame: 1,
    maxWidth: width,
    maxHeight: height,
  });
  console.error(`[cdp] streaming ${url} -> ${outdir} at ${width}x${height}`);
});

ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.method === 'Page.screencastFrame') {
    writeFrame(m.params.data);
    send(ws, 'Page.screencastFrameAck', { sessionId: m.params.sessionId });
    if (seq % 30 === 0) console.error(`[cdp] frame ${seq}`);
  }
});

// --- input channel: Pharo appends one JSON command per line to input.jsonl;
// we tail it (tracking a byte offset) and dispatch CDP input events. ---
const inputPath = join(outdir, 'input.jsonl');
let inputOffset = 0;
const inbuf = Buffer.alloc(64 * 1024);
let partial = '';

function dispatchCommand(cmd) {
  if (cmd.type === 'move') {
    send(ws, 'Input.dispatchMouseEvent', { type: 'mouseMoved', x: cmd.x, y: cmd.y });
  } else if (cmd.type === 'click') {
    const base = { x: cmd.x, y: cmd.y, button: 'left', buttons: 1, clickCount: 1 };
    send(ws, 'Input.dispatchMouseEvent', { type: 'mousePressed', ...base });
    send(ws, 'Input.dispatchMouseEvent', { type: 'mouseReleased', ...base });
  } else if (cmd.type === 'scroll') {
    send(ws, 'Input.dispatchMouseEvent', {
      type: 'mouseWheel', x: cmd.x, y: cmd.y, deltaX: cmd.dx || 0, deltaY: cmd.dy || 0,
    });
  } else if (cmd.type === 'key') {
    // cmd.text for character input; cmd.key/windowsVirtualKeyCode for specials
    if (cmd.text) {
      send(ws, 'Input.dispatchKeyEvent', { type: 'keyDown', text: cmd.text, key: cmd.key || cmd.text });
      send(ws, 'Input.dispatchKeyEvent', { type: 'char', text: cmd.text, key: cmd.key || cmd.text });
      send(ws, 'Input.dispatchKeyEvent', { type: 'keyUp', text: cmd.text, key: cmd.key || cmd.text });
    }
  }
}

function pollInput() {
  try {
    if (existsSync(inputPath)) {
      // Handle truncation/recreation: if the file shrank, restart from the top.
      const size = statSync(inputPath).size;
      if (size < inputOffset) { inputOffset = 0; partial = ''; }
      const fd = openSync(inputPath, 'r');
      let n;
      while ((n = readSync(fd, inbuf, 0, inbuf.length, inputOffset)) > 0) {
        inputOffset += n;
        partial += inbuf.toString('utf8', 0, n);
        let idx;
        while ((idx = partial.indexOf('\n')) >= 0) {
          const line = partial.slice(0, idx).trim();
          partial = partial.slice(idx + 1);
          if (line) {
            try { dispatchCommand(JSON.parse(line)); }
            catch (e) { console.error('[cdp] bad input line:', line); }
          }
        }
      }
      closeSync(fd);
    }
  } catch (e) { console.error('[cdp] input poll error', e.message); }
}
setInterval(pollInput, 20);

ws.addEventListener('close', () => { console.error('[cdp] ws closed'); shutdown(); });
ws.addEventListener('error', (e) => { console.error('[cdp] ws error', e.message || e); });

function shutdown() {
  try { chrome.kill(); } catch (_) {}
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
