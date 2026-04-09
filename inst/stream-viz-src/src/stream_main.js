/**
 * stream_main.js — StreamViz: multi-channel signal viewer (Three.js renderer)
 *
 * Bundled by esbuild into inst/htmlwidgets/lib/stream-viz/stream_main.js.
 * Exported global: window.StreamVizLib = { StreamViz }
 *
 * The htmlwidgets binding (stream_viz.js) calls:
 *   const viz = new window.StreamVizLib.StreamViz(el, width, height);
 *   await viz.fetchAndRender(streamId);
 *
 * Controls (shown on hover via shidashi-output-widget-* CSS):
 *   Play/Pause  — toggle active polling vs passive (Shiny-triggered) updates
 *   Zoom out    — widen visible time range (×2)
 *   Zoom in     — narrow visible time range (×0.5)
 *   Reset       — return to full view
 *   Export PNG  — download the Three.js visualisation as a PNG file
 *
 * Interaction:
 *   Mouse wheel — zoom in/out centred on cursor
 *   Click-drag  — pan horizontally when zoomed in
 */

import {
  WebGLRenderer,
  Scene,
  OrthographicCamera,
  BufferGeometry,
  Float32BufferAttribute,
  LineBasicMaterial,
  Line,
  Mesh,
  PlaneGeometry,
  MeshBasicMaterial
} from 'three';

const MARGIN = { left: 48, right: 8, top: 4, bottom: 20 };

// Tableau 10 colour palette (matches former D3 schemeTableau10)
const TABLEAU10 = [
  '#4e79a7', '#f28e2b', '#e15759', '#76b7b2', '#59a14f',
  '#edc948', '#b07aa1', '#ff9da7', '#9c755f', '#bab0ac'
];
const TABLEAU10_HEX = [
  0x4e79a7, 0xf28e2b, 0xe15759, 0x76b7b2, 0x59a14f,
  0xedc948, 0xb07aa1, 0xff9da7, 0x9c755f, 0xbab0ac
];

// ---------------------------------------------------------------------------
// Min/max decimation — collapses `arr` to at most `targetPts` points by
// alternating min and max values within each stride window.
// ---------------------------------------------------------------------------
function minMaxDecimate(arr, targetPts) {
  const n = arr.length;
  if (n <= targetPts) return arr;

  const pairs = Math.floor(targetPts / 2);
  const step = n / pairs;
  const out = new Float32Array(pairs * 2);

  for (let i = 0; i < pairs; i++) {
    const start = Math.floor(i * step);
    const end = Math.min(Math.floor((i + 1) * step), n);
    let mn = Infinity;
    let mx = -Infinity;
    for (let j = start; j < end; j++) {
      if (arr[j] < mn) mn = arr[j];
      if (arr[j] > mx) mx = arr[j];
    }
    out[2 * i] = mn;
    out[2 * i + 1] = mx;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Inline binary envelope parser — mirrors fetchStreamData() in index.js but
// works independently so the widget can run in plain Shiny / RStudio Viewer.
// ---------------------------------------------------------------------------
async function fetchBinary(streamId) {
  // Prefer shidashi's built-in helper if available (avoids duplicate parsing)
  if (window.shidashi && typeof window.shidashi.fetchStreamData === 'function') {
    return window.shidashi.fetchStreamData(streamId);
  }

  const url = `stream/${streamId}.bin?_t=${Date.now()}`;
  const resp = await fetch(url, { cache: 'no-store' });
  if (!resp.ok) {
    throw new Error(`StreamViz: fetch failed for "${streamId}" — HTTP ${resp.status}`);
  }
  const buf = await resp.arrayBuffer();
  const view = new DataView(buf);

  // Wire format: [endianFlag:1][headerLen:uint32LE][headerJSON][body]
  const littleEndian = view.getUint8(0) === 0x01;
  const headerLen = view.getUint32(1, littleEndian);
  const headerBytes = new Uint8Array(buf, 5, headerLen);
  const header = JSON.parse(new TextDecoder().decode(headerBytes));

  const bodyBuf = buf.slice(5 + headerLen);
  let data;
  switch (header.data_type) {
    case 'float32': data = new Float32Array(bodyBuf); break;
    case 'float64': data = new Float64Array(bodyBuf); break;
    case 'int32':   data = new Int32Array(bodyBuf);   break;
    case 'json':    data = JSON.parse(new TextDecoder().decode(new Uint8Array(bodyBuf))); break;
    default:        data = bodyBuf;
  }
  return { type: header.data_type, header, data };
}

// ---------------------------------------------------------------------------
// Nice tick generation for axes (replaces D3 axisBottom auto-ticks)
// ---------------------------------------------------------------------------
function niceStep(range, maxTicks) {
  const rough = range / maxTicks;
  const pow = Math.pow(10, Math.floor(Math.log10(rough)));
  const frac = rough / pow;
  let nice;
  if (frac <= 1.5) nice = 1;
  else if (frac <= 3) nice = 2;
  else if (frac <= 7) nice = 5;
  else nice = 10;
  return nice * pow;
}

function generateTicks(tStart, tEnd, maxTicks) {
  const range = tEnd - tStart;
  if (range <= 0 || !isFinite(range)) return [];
  const step = niceStep(range, maxTicks);
  const first = Math.ceil(tStart / step) * step;
  const ticks = [];
  for (let t = first; t <= tEnd + step * 1e-9; t += step) {
    ticks.push(t);
  }
  return ticks;
}

function formatTick(value, step) {
  if (step >= 1) return value.toFixed(0);
  const decimals = Math.max(0, -Math.floor(Math.log10(step)) + 1);
  return value.toFixed(decimals);
}

// ---------------------------------------------------------------------------
// StreamViz — Three.js stacked small-multiples channel display
// ---------------------------------------------------------------------------
export class StreamViz {
  constructor(el, width, height) {
    this.el = el;
    this.width = width;
    this.height = height;

    // Three.js components
    this._renderer = null;
    this._scene = null;
    this._camera = null;
    this._overlayCanvas = null;
    this._overlayCtx = null;
    this._container = null;

    // Cached scene objects for disposal tracking
    this._sceneObjects = [];

    this._lastPayload = null;

    // Zoom state: [startFrac, endFrac] in [0,1], null = full view
    this._xRange = null;

    // Streaming state
    this._streaming = false;
    this._streamId = null;
    this._refreshRate = 33;  // ~30 Hz
    this._lastSignature = null;
    this._dirty = false;
    this._lastFetchTime = 0;
    this._rafId = null;
    this._fetching = false;

    // Controls
    this._controlsEl = null;
    this._playBtn = null;
    this._showControls = true;

    this._init();
  }

  // -------------------------------------------------------------------------
  _init() {
    this.el.innerHTML = '';

    // Container for layered canvases
    const container = document.createElement('div');
    container.style.position = 'relative';
    container.style.width = this.width + 'px';
    container.style.height = this.height + 'px';
    container.style.overflow = 'hidden';
    this.el.appendChild(container);
    this._container = container;

    // Three.js WebGL canvas (bottom layer — backgrounds + signal lines)
    const dpr = window.devicePixelRatio || 1;
    this._renderer = new WebGLRenderer({
      antialias: true,
      alpha: true,
      preserveDrawingBuffer: true  // needed for PNG export
    });
    this._renderer.setSize(this.width, this.height);
    this._renderer.setPixelRatio(dpr);
    this._renderer.setClearColor(0x000000, 0);
    const glCanvas = this._renderer.domElement;
    glCanvas.style.position = 'absolute';
    glCanvas.style.top = '0';
    glCanvas.style.left = '0';
    container.appendChild(glCanvas);

    // 2D overlay canvas (top layer — text labels, axis ticks)
    this._overlayCanvas = document.createElement('canvas');
    this._overlayCanvas.width = Math.round(this.width * dpr);
    this._overlayCanvas.height = Math.round(this.height * dpr);
    this._overlayCanvas.style.width = this.width + 'px';
    this._overlayCanvas.style.height = this.height + 'px';
    this._overlayCanvas.style.position = 'absolute';
    this._overlayCanvas.style.top = '0';
    this._overlayCanvas.style.left = '0';
    this._overlayCanvas.style.pointerEvents = 'none';
    container.appendChild(this._overlayCanvas);
    this._overlayCtx = this._overlayCanvas.getContext('2d');

    // Scene + orthographic camera in pixel coordinates
    // Camera: left=0, right=width, top=height, bottom=0
    // This puts (0, height) at top-left and (width, 0) at bottom-right.
    // We use height - screenY for y-coordinates.
    this._scene = new Scene();
    this._camera = new OrthographicCamera(0, this.width, this.height, 0, -1, 1);
    this._camera.position.z = 0;

    // Empty state
    this._renderEmptyState();
    this._createControls();
    this._setupInteraction();
  }

  // -------------------------------------------------------------------------
  _renderEmptyState() {
    const ctx = this._overlayCtx;
    const dpr = window.devicePixelRatio || 1;
    ctx.clearRect(0, 0, this._overlayCanvas.width, this._overlayCanvas.height);
    ctx.save();
    ctx.scale(dpr, dpr);
    ctx.fillStyle = '#888';
    ctx.font = '14px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('No data — click Simulate', this.width / 2, this.height / 2);
    ctx.restore();
    this._renderer.render(this._scene, this._camera);
  }

  // -------------------------------------------------------------------------
  // Creates the control icons inside a shidashi-output-widget-container,
  // matching the DOM layout used by register_output_widgets in index.js.
  // When register_output_widgets is later called for this output, it will
  // detect shidashi-output-widget-wrapper on the parent and append its own
  // icons (download, popout) to the existing container.
  _createControls() {
    const parent = this.el.parentElement;
    if (!parent) return;

    // Set up the wrapper/container structure identical to register_output_widgets
    parent.classList.add('shidashi-output-widget-wrapper');

    // Reuse existing container if register_output_widgets already created one
    let container = parent.querySelector('.shidashi-output-widget-container');
    if (!container) {
      container = document.createElement('div');
      container.className = 'shidashi-output-widget-container';
      parent.insertBefore(container, this.el);
    }

    const makeIcon = (title, svgHTML, handler) => {
      const a = document.createElement('a');
      a.className = 'shidashi-output-widget-icon';
      a.title = title;
      a.href = '#';
      a.innerHTML = svgHTML;
      a.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        handler();
      });
      return a;
    };

    // Bootstrap Icons SVGs (14×14, fill=currentColor)
    const SVG_PLAY = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path d="m11.596 8.697-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393"/></svg>';
    const SVG_PAUSE = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path d="M5.5 3.5A1.5 1.5 0 0 1 7 5v6a1.5 1.5 0 0 1-3 0V5a1.5 1.5 0 0 1 1.5-1.5m5 0A1.5 1.5 0 0 1 12 5v6a1.5 1.5 0 0 1-3 0V5a1.5 1.5 0 0 1 1.5-1.5"/></svg>';
    const SVG_ZOOM_OUT = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M6.5 12a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11M13 6.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0"/><path d="M10.344 11.742q.044-.04.085-.082l3.943 3.943a.5.5 0 0 0 .708-.708L11.14 10.96a6.5 6.5 0 0 1-.796.782M3 6.5a.5.5 0 0 1 .5-.5h6a.5.5 0 0 1 0 1h-6a.5.5 0 0 1-.5-.5"/></svg>';
    const SVG_ZOOM_IN = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M6.5 12a5.5 5.5 0 1 0 0-11 5.5 5.5 0 0 0 0 11M13 6.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0"/><path d="M10.344 11.742q.044-.04.085-.082l3.943 3.943a.5.5 0 0 0 .708-.708L11.14 10.96a6.5 6.5 0 0 1-.796.782M6.5 3a.5.5 0 0 1 .5.5V6h2.5a.5.5 0 0 1 0 1H7v2.5a.5.5 0 0 1-1 0V7H3.5a.5.5 0 0 1 0-1H6V3.5a.5.5 0 0 1 .5-.5"/></svg>';
    const SVG_RESET = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path fill-rule="evenodd" d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2z"/><path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466"/></svg>';
    const SVG_IMAGE = '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" fill="currentColor" viewBox="0 0 16 16"><path d="M6.002 5.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0"/><path d="M2.002 1a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3a2 2 0 0 0-2-2zm12 1a1 1 0 0 1 1 1v6.5l-3.777-1.947a.5.5 0 0 0-.577.093l-3.71 3.71-2.66-1.772a.5.5 0 0 0-.63.062L1.002 12V3a1 1 0 0 1 1-1z"/></svg>';

    this._svgPlay = SVG_PLAY;
    this._svgPause = SVG_PAUSE;

    if (this._showControls) {
      this._playBtn = makeIcon('Play / Pause streaming', SVG_PLAY, () => this.toggleStreaming());
      container.appendChild(this._playBtn);
      container.appendChild(makeIcon('Zoom out', SVG_ZOOM_OUT, () => this.zoomOut()));
      container.appendChild(makeIcon('Zoom in', SVG_ZOOM_IN, () => this.zoomIn()));
      container.appendChild(makeIcon('Reset zoom', SVG_RESET, () => this.resetZoom()));
      container.appendChild(makeIcon('Export PNG', SVG_IMAGE, () => this.exportPNG()));
    }

    this._controlsEl = container;
  }

  // -------------------------------------------------------------------------
  _setupInteraction() {
    const glCanvas = this._renderer.domElement;

    // Mouse-wheel zoom (centred on cursor)
    glCanvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (!this._lastPayload) return;

      const [start, end] = this._xRange || [0, 1];
      const range = end - start;
      if (e.deltaY < 0 && range <= 0.001) return;
      if (e.deltaY > 0 && range >= 1) return;

      const factor = e.deltaY > 0 ? 1.5 : 1 / 1.5;
      const newRange = Math.min(1, range * factor);

      const rect = glCanvas.getBoundingClientRect();
      const innerW = this.width - MARGIN.left - MARGIN.right;
      const mouseXFrac = Math.max(0, Math.min(1,
        (e.clientX - rect.left - MARGIN.left) / innerW));
      const mouseData = start + mouseXFrac * range;

      let s = mouseData - mouseXFrac * newRange;
      let t = s + newRange;
      if (s < 0) { t -= s; s = 0; }
      if (t > 1) { s -= (t - 1); t = 1; }
      s = Math.max(0, s);

      this._xRange = newRange >= 1 ? null : [s, t];
      this._rerender();
    }, { passive: false });

    // Click-drag to pan when zoomed in
    glCanvas.addEventListener('mousedown', (e) => {
      if (!this._xRange || !this._lastPayload) return;
      const startX = e.clientX;
      const startRange = [...this._xRange];
      glCanvas.style.cursor = 'grabbing';
      e.preventDefault();

      const onMove = (e2) => {
        const dx = e2.clientX - startX;
        const innerW = this.width - MARGIN.left - MARGIN.right;
        const range = startRange[1] - startRange[0];
        const shift = -dx / innerW * range;
        let s = startRange[0] + shift;
        let t = startRange[1] + shift;
        if (s < 0) { t -= s; s = 0; }
        if (t > 1) { s -= (t - 1); t = 1; }
        this._xRange = [Math.max(0, s), Math.min(1, t)];
        this._rerender();
      };

      const onUp = () => {
        glCanvas.style.cursor = '';
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
      };

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });
  }

  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------
  setRefreshRate(rate) {
    this._refreshRate = Math.max(16, rate);  // cap at ~60 Hz
    if (this._streaming) {
      this.stopStreaming();
      this.startStreaming();
    }
  }

  setShowControls(show) {
    this._showControls = show;
  }

  // -------------------------------------------------------------------------
  // Zoom
  // -------------------------------------------------------------------------
  zoomIn() {
    const [start, end] = this._xRange || [0, 1];
    const range = end - start;
    if (range <= 0.001) return;
    const center = (start + end) / 2;
    const nr = range / 2;
    let s = center - nr / 2;
    let t = center + nr / 2;
    if (s < 0) { t -= s; s = 0; }
    if (t > 1) { s -= (t - 1); t = 1; }
    this._xRange = [Math.max(0, s), Math.min(1, t)];
    this._rerender();
  }

  zoomOut() {
    const [start, end] = this._xRange || [0, 1];
    const range = end - start;
    if (range >= 1) return;
    const center = (start + end) / 2;
    const nr = Math.min(1, range * 2);
    let s = center - nr / 2;
    let t = center + nr / 2;
    if (s < 0) { t -= s; s = 0; }
    if (t > 1) { s -= (t - 1); t = 1; }
    this._xRange = nr >= 1 ? null : [Math.max(0, s), Math.min(1, t)];
    this._rerender();
  }

  resetZoom() {
    this._xRange = null;
    this._rerender();
  }

  // -------------------------------------------------------------------------
  // Active streaming (requestAnimationFrame-based)
  // -------------------------------------------------------------------------
  toggleStreaming() {
    if (this._streaming) {
      this.stopStreaming();
    } else {
      this.startStreaming();
    }
  }

  startStreaming() {
    if (!this._streamId) return;
    this._streaming = true;
    if (this._playBtn) this._playBtn.innerHTML = this._svgPause;
    this._scheduleFrame();
  }

  stopStreaming() {
    this._streaming = false;
    if (this._playBtn) this._playBtn.innerHTML = this._svgPlay;
    if (this._rafId) {
      cancelAnimationFrame(this._rafId);
      this._rafId = null;
    }
  }

  _scheduleFrame() {
    if (!this._streaming) return;
    const rAF = window.requestAnimationFrame ||
      window.mozRequestAnimationFrame ||
      window.webkitRequestAnimationFrame ||
      window.msRequestAnimationFrame ||
      window.oRequestAnimationFrame ||
      function (callback) {
        setTimeout(function() { callback(Date.now()); }, 1000 / 60);
      };
    this._rafId = rAF((ts) => this._onFrame(ts));
  }

  _onFrame(ts) {
    if (!this._streaming) return;

    const elapsed = ts - this._lastFetchTime;
    if (elapsed >= this._refreshRate && !this._fetching) {
      this._lastFetchTime = ts;
      this.update();
    }

    if (this._dirty) {
      this._dirty = false;
      if (this._lastPayload) {
        this._renderChannels_from_payload();
      }
    }

    this._scheduleFrame();
  }

  /** Fetch data and set _dirty flag if the signature changed. */
  update() {
    if (!this._streamId) return;
    this._fetching = true;
    fetchBinary(this._streamId)
      .then((payload) => {
        const sig = payload.header.signature || null;
        if (sig !== this._lastSignature) {
          this._lastSignature = sig;
          this._lastPayload = { header: payload.header, data: payload.data };
          this._dirty = true;
        }
      })
      .catch((err) => {
        console.error('[StreamViz] streaming fetch error:', err);
      })
      .finally(() => {
        this._fetching = false;
      });
  }

  // -------------------------------------------------------------------------
  // PNG export — composites WebGL + overlay canvases into a downloadable PNG
  // -------------------------------------------------------------------------
  exportPNG() {
    if (!this._renderer) return;

    // Force a render so the WebGL canvas has current content
    this._renderer.render(this._scene, this._camera);

    const dpr = window.devicePixelRatio || 1;
    const w = Math.round(this.width * dpr);
    const h = Math.round(this.height * dpr);

    const offscreen = document.createElement('canvas');
    offscreen.width = w;
    offscreen.height = h;
    const ctx = offscreen.getContext('2d');

    // White background
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, w, h);

    // Layer 1: WebGL canvas
    ctx.drawImage(this._renderer.domElement, 0, 0, w, h);
    // Layer 2: overlay canvas (text)
    ctx.drawImage(this._overlayCanvas, 0, 0, w, h);

    offscreen.toBlob((blob) => {
      if (!blob) return;
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'stream-viz.png';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 100);
    }, 'image/png');
  }

  // -------------------------------------------------------------------------
  resize(width, height) {
    this.width = width;
    this.height = height;

    if (this._container) {
      this._container.style.width = width + 'px';
      this._container.style.height = height + 'px';
    }
    if (this._renderer) {
      this._renderer.setSize(width, height);
    }
    if (this._overlayCanvas) {
      const dpr = window.devicePixelRatio || 1;
      this._overlayCanvas.width = Math.round(width * dpr);
      this._overlayCanvas.height = Math.round(height * dpr);
      this._overlayCanvas.style.width = width + 'px';
      this._overlayCanvas.style.height = height + 'px';
    }
    if (this._camera) {
      this._camera.right = width;
      this._camera.top = height;
      this._camera.updateProjectionMatrix();
    }
    this._rerender();
  }

  // -------------------------------------------------------------------------
  _rerender() {
    if (this._lastPayload) {
      this._renderChannels_from_payload();
    }
  }

  // -------------------------------------------------------------------------
  /** Render channel-contiguous typed array data.
   *  header must contain: n_channels (int), n_timepoints (int), and optionally
   *  channel_names (string[]), sample_rate (num).
   */
  render(header, typedData) {
    this._lastPayload = { header, data: typedData };
    this._renderChannels_from_payload();
  }

  /** Internal: render from the current _lastPayload. */
  _renderChannels_from_payload() {
    const { header, data: typedData } = this._lastPayload;
    const nCh = header.n_channels || 1;
    const nT  = header.n_timepoints || Math.floor(typedData.length / nCh);

    // Apply zoom: extract visible index range
    const [startFrac, endFrac] = this._xRange || [0, 1];
    const iStart = Math.floor(startFrac * nT);
    const iEnd   = Math.min(nT, Math.ceil(endFrac * nT));

    const channels = [];
    for (let c = 0; c < nCh; c++) {
      const off = c * nT;
      channels.push(typedData.subarray
        ? typedData.subarray(off + iStart, off + iEnd)
        : typedData.slice(off + iStart, off + iEnd));
    }

    this._renderChannels(channels, header, iStart, iEnd);
  }

  // -------------------------------------------------------------------------
  async fetchAndRender(streamId) {
    this._streamId = streamId;
    const payload = await fetchBinary(streamId);
    this._lastSignature = payload.header.signature || null;
    this.render(payload.header, payload.data);
  }

  // -------------------------------------------------------------------------
  // Clear all Three.js objects from the scene and free GPU resources
  // -------------------------------------------------------------------------
  _clearScene() {
    for (let i = 0; i < this._sceneObjects.length; i++) {
      const obj = this._sceneObjects[i];
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) obj.material.dispose();
    }
    this._sceneObjects.length = 0;

    while (this._scene.children.length > 0) {
      this._scene.remove(this._scene.children[0]);
    }
  }

  // Helper: create a Line, track it, and add to scene
  _addLine(positions, color, opacity, z) {
    const geo = new BufferGeometry();
    geo.setAttribute('position', new Float32BufferAttribute(positions, 3));
    const mat = new LineBasicMaterial({
      color: color,
      transparent: opacity < 1,
      opacity: opacity
    });
    const line = new Line(geo, mat);
    this._scene.add(line);
    this._sceneObjects.push(line);
    return line;
  }

  // Helper: create a background rectangle mesh
  _addRect(x, y, w, h, color, opacity, z) {
    const geo = new PlaneGeometry(w, h);
    const mat = new MeshBasicMaterial({
      color: color,
      transparent: true,
      opacity: opacity
    });
    const mesh = new Mesh(geo, mat);
    mesh.position.set(x + w / 2, y + h / 2, z);
    this._scene.add(mesh);
    this._sceneObjects.push(mesh);
    return mesh;
  }

  // -------------------------------------------------------------------------
  _renderChannels(channels, header, iStart, iEnd) {
    const nCh = channels.length;
    const chHeightFull = nCh > 0 ? this.height / nCh : this.height;
    const innerW = Math.max(1, this.width - MARGIN.left - MARGIN.right);

    const chNames = header.channel_names ||
      channels.map((_, i) => `Ch ${i + 1}`);

    // Target ≤ 2×pixel columns so rendering stays fast regardless of nT
    const targetPts = Math.max(4, Math.floor(innerW) * 2);

    // --- Clear previous frame ---
    this._clearScene();

    // --- Clear 2D overlay ---
    const ctx = this._overlayCtx;
    const dpr = window.devicePixelRatio || 1;
    ctx.clearRect(0, 0, this._overlayCanvas.width, this._overlayCanvas.height);
    ctx.save();
    ctx.scale(dpr, dpr);

    // --- Render each channel ---
    channels.forEach((ch, ci) => {
      const isLast = ci === nCh - 1;
      const innerH = Math.max(1, chHeightFull - MARGIN.top - (isLast ? MARGIN.bottom : 4));
      // Screen-space Y of this channel's top edge
      const screenTop = ci * chHeightFull + MARGIN.top;
      // In camera coords: Y is flipped — screenTop maps to (height - screenTop)
      const camTop = this.height - screenTop;
      const camBottom = camTop - innerH;

      // -- per-channel autoscale: mean ± 3σ --
      let sum = 0;
      for (let i = 0; i < ch.length; i++) sum += ch[i];
      const mean = ch.length > 0 ? sum / ch.length : 0;
      let sq = 0;
      for (let i = 0; i < ch.length; i++) sq += (ch[i] - mean) ** 2;
      const std = Math.sqrt(ch.length > 0 ? sq / ch.length : 0) || 1e-9;
      const yMin = mean - 3 * std;
      const yMax = mean + 3 * std;
      const yRange = yMax - yMin;

      // -- Background stripe (alternating channels) --
      if (ci % 2 === 1) {
        this._addRect(MARGIN.left, camBottom, innerW, innerH, 0x808080, 0.06, -0.5);
      }

      // -- Zero line --
      if (yMin < 0 && yMax > 0) {
        const normZero = (0 - yMin) / yRange;
        const zeroY = camBottom + normZero * innerH;
        this._addLine([
          MARGIN.left, zeroY, -0.3,
          MARGIN.left + innerW, zeroY, -0.3
        ], 0x808080, 0.4);
      }

      // -- Signal line (Three.js) --
      const decimated = minMaxDecimate(ch, targetPts);
      const nPts = decimated.length;

      if (nPts > 1) {
        const positions = new Float32Array(nPts * 3);
        const xStep = innerW / (nPts - 1);

        for (let i = 0; i < nPts; i++) {
          const val = decimated[i];
          const clamped = Math.max(yMin, Math.min(yMax, isFinite(val) ? val : mean));
          const normY = (clamped - yMin) / yRange; // 0 = yMin, 1 = yMax
          positions[i * 3]     = MARGIN.left + i * xStep;
          positions[i * 3 + 1] = camBottom + normY * innerH;
          positions[i * 3 + 2] = 0;
        }

        this._addLine(positions, TABLEAU10_HEX[ci % 10], 1.0, 0);
      }

      // -- Channel label (2D overlay) --
      const fontSize = Math.min(11, Math.max(8, innerH / 2));
      ctx.font = `${fontSize}px sans-serif`;
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = TABLEAU10[ci % 10];
      ctx.fillText(
        chNames[ci] || `Ch ${ci + 1}`,
        MARGIN.left - 4,
        screenTop + innerH / 2
      );

      // -- Time axis on the last channel (2D overlay + Three.js tick lines) --
      if (isLast) {
        let tStart, tEnd;
        if (header.timepoints && header.timepoints.length > 0) {
          const tp = header.timepoints;
          tStart = tp[iStart] != null ? tp[iStart] : iStart;
          tEnd   = tp[Math.min(iEnd, tp.length) - 1] != null
                   ? tp[Math.min(iEnd, tp.length) - 1] : iEnd;
        } else if (header.time_start != null && header.time_end != null) {
          const nT = header.n_timepoints || ch.length;
          const fullStart = header.time_start;
          const fullEnd   = header.time_end;
          tStart = fullStart + (iStart / nT) * (fullEnd - fullStart);
          tEnd   = fullStart + (iEnd / nT) * (fullEnd - fullStart);
        } else {
          const sampleRate = header.sample_rate || 1;
          tStart = (iStart || 0) / sampleRate;
          tEnd   = (iEnd || ch.length) / sampleRate;
        }

        // Screen Y of the axis baseline
        const axisScreenY = screenTop + innerH;
        // Camera Y for the axis
        const axisCamY = this.height - axisScreenY;

        // Axis baseline (Three.js)
        this._addLine([
          MARGIN.left, axisCamY, -0.1,
          MARGIN.left + innerW, axisCamY, -0.1
        ], 0xaaaaaa, 1.0);

        // Tick marks and labels
        const nTicks = Math.max(2, Math.min(10, Math.floor(innerW / 60)));
        const ticks = generateTicks(tStart, tEnd, nTicks);
        const tRange = tEnd - tStart;
        const step = ticks.length > 1 ? ticks[1] - ticks[0] : tRange;

        ctx.font = '9px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        ctx.fillStyle = '#666';
        ctx.strokeStyle = '#aaa';
        ctx.lineWidth = 1;

        ticks.forEach((t) => {
          if (t < tStart || t > tEnd) return;
          const xFrac = tRange > 0 ? (t - tStart) / tRange : 0;
          const xPx = MARGIN.left + xFrac * innerW;

          // Tick mark (2D canvas)
          ctx.beginPath();
          ctx.moveTo(xPx, axisScreenY);
          ctx.lineTo(xPx, axisScreenY + 4);
          ctx.stroke();

          // Tick label
          let label;
          if (header.x_decimal_points != null && header.x_decimal_points >= 0) {
            label = t.toFixed(header.x_decimal_points);
          } else {
            label = formatTick(t, step);
          }
          ctx.fillText(label, xPx, axisScreenY + 4);
        });

        // Unit label
        if (header.x_unit) {
          ctx.font = '8px sans-serif';
          ctx.textAlign = 'end';
          ctx.fillStyle = '#999';
          ctx.fillText(header.x_unit, MARGIN.left + innerW, axisScreenY + 14);
        }
      }
    });

    ctx.restore();

    // --- Render Three.js scene ---
    this._renderer.render(this._scene, this._camera);
  }
}

window.StreamVizLib = { StreamViz };
