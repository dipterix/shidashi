/**
 * stream_main.js — StreamViz: multi-channel signal viewer
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
 *   Export SVG  — download the D3 visualisation as a vector SVG file
 *
 * Interaction:
 *   Mouse wheel — zoom in/out centred on cursor
 *   Click-drag  — pan horizontally when zoomed in
 */

import { select } from 'd3-selection';
import { line } from 'd3-shape';
import { scaleLinear } from 'd3-scale';
import { schemeTableau10 } from 'd3-scale-chromatic';
import { axisBottom } from 'd3-axis';
import { format as d3format } from 'd3-format';

const MARGIN = { left: 48, right: 8, top: 4, bottom: 20 };

// ---------------------------------------------------------------------------
// Min/max decimation — collapses `arr` to at most `targetPts` points by
// alternating min and max values within each stride window.
// ---------------------------------------------------------------------------
function minMaxDecimate(arr, targetPts) {
  const n = arr.length;
  if (n <= targetPts) return Array.from(arr);

  const pairs = Math.floor(targetPts / 2);
  const step = n / pairs;
  const out = new Array(pairs * 2);

  for (let i = 0; i < pairs; i++) {
    const start = Math.floor(i * step);
    const end = Math.min(Math.floor((i + 1) * step), n);
    let mn = Infinity;
    let mx = -Infinity;
    for (let j = start; j < end; j++) {
      if (arr[j] < mn) mn = arr[j];
      if (arr[j] > mx) mx = arr[j];
    }
    // store min first then max so the path traces a plausible waveform
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
// StreamViz — D3 stacked small-multiples channel display
// ---------------------------------------------------------------------------
export class StreamViz {
  constructor(el, width, height) {
    this.el = el;
    this.width = width;
    this.height = height;

    this._svg = null;
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
    select(this.el).selectAll('*').remove();

    this._svg = select(this.el)
      .append('svg')
      .attr('width', this.width)
      .attr('height', this.height)
      .style('display', 'block')
      .style('overflow', 'hidden')
      .style('font-family', 'sans-serif');

    // Empty state placeholder
    this._svg.append('text')
      .attr('x', '50%')
      .attr('y', '50%')
      .attr('text-anchor', 'middle')
      .attr('dominant-baseline', 'middle')
      .attr('fill', '#888')
      .attr('font-size', '14px')
      .text('No data — click Simulate');

    this._createControls();
    this._setupInteraction();
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
      container.appendChild(makeIcon('Export SVG', SVG_IMAGE, () => this.exportSVG()));
    }

    this._controlsEl = container;
  }

  // -------------------------------------------------------------------------
  _setupInteraction() {
    // const svgNode = this._svg.node();

    // // Mouse-wheel zoom (centred on cursor)
    // svgNode.addEventListener('wheel', (e) => {
    //   e.preventDefault();
    //   const [start, end] = this._xRange || [0, 1];
    //   const range = end - start;
    //   if (e.deltaY < 0 && range <= 0.001) return;
    //   if (e.deltaY > 0 && range >= 1)     return;

    //   const factor = e.deltaY > 0 ? 1.5 : 1 / 1.5;
    //   const newRange = Math.min(1, range * factor);

    //   const rect = svgNode.getBoundingClientRect();
    //   const innerW = this.width - MARGIN.left - MARGIN.right;
    //   const mouseXFrac = Math.max(0, Math.min(1,
    //     (e.clientX - rect.left - MARGIN.left) / innerW));
    //   const mouseData = start + mouseXFrac * range;

    //   let s = mouseData - mouseXFrac * newRange;
    //   let t = s + newRange;
    //   if (s < 0) { t -= s; s = 0; }
    //   if (t > 1) { s -= (t - 1); t = 1; }
    //   s = Math.max(0, s);

    //   this._xRange = newRange >= 1 ? null : [s, t];
    //   this._rerender();
    // }, { passive: false });

    // // Click-drag to pan when zoomed in
    // svgNode.addEventListener('mousedown', (e) => {
    //   if (!this._xRange) return;
    //   const startX = e.clientX;
    //   const startRange = [...this._xRange];
    //   svgNode.style.cursor = 'grabbing';
    //   e.preventDefault();

    //   const onMove = (e2) => {
    //     const dx = e2.clientX - startX;
    //     const innerW = this.width - MARGIN.left - MARGIN.right;
    //     const range = startRange[1] - startRange[0];
    //     const shift = -dx / innerW * range;
    //     let s = startRange[0] + shift;
    //     let t = startRange[1] + shift;
    //     if (s < 0) { t -= s; s = 0; }
    //     if (t > 1) { s -= (t - 1); t = 1; }
    //     this._xRange = [Math.max(0, s), Math.min(1, t)];
    //     this._rerender();
    //   };

    //   const onUp = () => {
    //     svgNode.style.cursor = '';
    //     document.removeEventListener('mousemove', onMove);
    //     document.removeEventListener('mouseup', onUp);
    //   };

    //   document.addEventListener('mousemove', onMove);
    //   document.addEventListener('mouseup', onUp);
    // });
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
  // SVG export — downloads the D3 visualisation as a vector .svg file
  // -------------------------------------------------------------------------
  exportSVG() {
    const svgNode = this._svg.node();
    if (!svgNode) return;

    const clone = svgNode.cloneNode(true);
    clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

    const svgString = new XMLSerializer().serializeToString(clone);
    const blob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = 'stream-viz.svg';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 100);
  }

  // -------------------------------------------------------------------------
  resize(width, height) {
    this.width = width;
    this.height = height;
    if (this._svg) {
      this._svg.attr('width', width).attr('height', height);
      this._rerender();
    }
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
  _renderChannels(channels, header, iStart, iEnd) {
    const nCh = channels.length;
    // Reserve bottom margin only on the last channel for the time axis
    const chHeightFull = nCh > 0 ? this.height / nCh : this.height;
    const innerW = Math.max(1, this.width - MARGIN.left - MARGIN.right);

    const chNames = header.channel_names ||
      channels.map((_, i) => `Ch ${i + 1}`);

    // Target ≤ 2×pixel columns so rendering stays fast regardless of nT
    const targetPts = Math.max(4, Math.floor(innerW) * 2);

    this._svg.selectAll('*').remove();

    channels.forEach((ch, ci) => {
      const isLast = ci === nCh - 1;
      const innerH = Math.max(1, chHeightFull - MARGIN.top - (isLast ? MARGIN.bottom : 4));

      // --- per-channel autoscale: mean ± 3σ ----------------------------------
      let sum = 0;
      for (let i = 0; i < ch.length; i++) sum += ch[i];
      const mean = sum / ch.length;
      let sq = 0;
      for (let i = 0; i < ch.length; i++) sq += (ch[i] - mean) ** 2;
      const std = Math.sqrt(sq / ch.length) || 1e-9;
      const yMin = mean - 3 * std;
      const yMax = mean + 3 * std;

      const decimated = minMaxDecimate(ch, targetPts);

      const xScale = scaleLinear()
        .domain([0, decimated.length - 1])
        .range([0, innerW]);
      const yScale = scaleLinear()
        .domain([yMin, yMax])
        .range([innerH, 0]);

      const g = this._svg.append('g')
        .attr('transform',
          `translate(${MARGIN.left},${ci * chHeightFull + MARGIN.top})`);

      // background stripe (subtle alternation)
      if (ci % 2 === 1) {
        g.append('rect')
          .attr('width', innerW)
          .attr('height', innerH)
          .attr('fill', 'rgba(128,128,128,0.06)');
      }

      // zero line
      if (yMin < 0 && yMax > 0) {
        g.append('line')
          .attr('x1', 0).attr('x2', innerW)
          .attr('y1', yScale(0)).attr('y2', yScale(0))
          .attr('stroke', 'rgba(128,128,128,0.4)')
          .attr('stroke-dasharray', '3,2')
          .attr('stroke-width', 0.5);
      }

      // signal path
      const pathGen = line()
        .x((_, i) => xScale(i))
        .y(d => {
          const clamped = Math.max(yMin, Math.min(yMax, d));
          return yScale(clamped);
        })
        .defined(d => isFinite(d));

      g.append('path')
        .datum(decimated)
        .attr('fill', 'none')
        .attr('stroke', schemeTableau10[ci % 10])
        .attr('stroke-width', 0.9)
        .attr('d', pathGen);

      // channel label
      const fontSize = Math.min(11, Math.max(8, innerH / 2));
      g.append('text')
        .attr('x', -4)
        .attr('y', innerH / 2)
        .attr('text-anchor', 'end')
        .attr('dominant-baseline', 'middle')
        .attr('font-size', fontSize + 'px')
        .attr('fill', schemeTableau10[ci % 10])
        .text(chNames[ci] || `Ch ${ci + 1}`);

      // Time axis on the last channel
      if (isLast) {
        // Determine time domain from header fields
        let tStart, tEnd;
        if (header.timepoints && header.timepoints.length > 0) {
          // Explicit timepoint vector — slice to visible range
          const tp = header.timepoints;
          tStart = tp[iStart] != null ? tp[iStart] : iStart;
          tEnd   = tp[Math.min(iEnd, tp.length) - 1] != null
                   ? tp[Math.min(iEnd, tp.length) - 1] : iEnd;
        } else if (header.time_start != null && header.time_end != null) {
          // Explicit start/end range
          const nT = header.n_timepoints || ch.length;
          const fullStart = header.time_start;
          const fullEnd   = header.time_end;
          tStart = fullStart + (iStart / nT) * (fullEnd - fullStart);
          tEnd   = fullStart + (iEnd / nT) * (fullEnd - fullStart);
        } else {
          // Fallback: index / sample_rate
          const sampleRate = header.sample_rate || 1;
          tStart = (iStart || 0) / sampleRate;
          tEnd   = (iEnd || ch.length) / sampleRate;
        }

        const timeScale = scaleLinear()
          .domain([tStart, tEnd])
          .range([0, innerW]);

        // Tick formatter: honour x_decimal_points if provided
        const nTicks = Math.max(2, Math.min(10, Math.floor(innerW / 60)));
        const axis = axisBottom(timeScale)
          .ticks(nTicks)
          .tickSizeOuter(0);
        if (header.x_decimal_points != null && header.x_decimal_points >= 0) {
          axis.tickFormat(d3format('.' + header.x_decimal_points + 'f'));
        }

        const axisG = g.append('g')
          .attr('transform', `translate(0,${innerH})`)
          .call(axis);
        axisG.selectAll('text')
          .attr('font-size', '9px')
          .attr('fill', '#666');
        axisG.selectAll('.domain, .tick line')
          .attr('stroke', '#aaa');

        // Unit label
        if (header.x_unit) {
          axisG.append('text')
            .attr('x', innerW)
            .attr('y', 14)
            .attr('text-anchor', 'end')
            .attr('font-size', '8px')
            .attr('fill', '#999')
            .text(header.x_unit);
        }
      }
    });
  }
}

window.StreamVizLib = { StreamViz };
