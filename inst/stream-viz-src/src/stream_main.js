/**
 * stream_main.js — StreamViz: multi-channel signal viewer
 *
 * Bundled by esbuild into inst/htmlwidgets/lib/stream-viz/stream_main.js.
 * Exported global: window.StreamVizLib = { StreamViz }
 *
 * The htmlwidgets binding (stream_viz.js) calls:
 *   const viz = new window.StreamVizLib.StreamViz(el, width, height);
 *   await viz.fetchAndRender(streamId);
 */

import {
  select,
} from 'd3-selection';
import { line } from 'd3-shape';
import { scaleLinear } from 'd3-scale';
import { schemeTableau10 } from 'd3-scale-chromatic';

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
      .style('overflow', 'hidden');

    // Empty state placeholder
    this._svg.append('text')
      .attr('x', '50%')
      .attr('y', '50%')
      .attr('text-anchor', 'middle')
      .attr('dominant-baseline', 'middle')
      .attr('fill', '#888')
      .attr('font-size', '14px')
      .text('No data — click Simulate');
  }

  // -------------------------------------------------------------------------
  resize(width, height) {
    this.width = width;
    this.height = height;
    if (this._svg) {
      this._svg.attr('width', width).attr('height', height);
      if (this._lastPayload) {
        this.render(this._lastPayload.header, this._lastPayload.data);
      }
    }
  }

  // -------------------------------------------------------------------------
  /** Render channel-contiguous typed array data.
   *  header must contain: n_channels (int), n_timepoints (int), and optionally
   *  channel_names (string[]), sample_rate (num).
   */
  render(header, typedData) {
    this._lastPayload = { header, data: typedData };

    const nCh = header.n_channels || 1;
    const nT  = header.n_timepoints || Math.floor(typedData.length / nCh);

    // Slice channel-contiguous Float32Array into per-channel views
    const channels = [];
    for (let c = 0; c < nCh; c++) {
      channels.push(typedData.subarray
        ? typedData.subarray(c * nT, (c + 1) * nT)
        : typedData.slice(c * nT, (c + 1) * nT));
    }

    this._renderChannels(channels, header);
  }

  // -------------------------------------------------------------------------
  async fetchAndRender(streamId) {
    const payload = await fetchBinary(streamId);
    this.render(payload.header, payload.data);
  }

  // -------------------------------------------------------------------------
  _renderChannels(channels, header) {
    const marginL = 48;
    const marginR = 8;
    const marginT = 4;
    const marginB = 4;

    const nCh = channels.length;
    const chHeight = nCh > 0 ? this.height / nCh : this.height;
    const innerW = Math.max(1, this.width - marginL - marginR);
    const innerH = Math.max(1, chHeight - marginT - marginB);

    const chNames = header.channel_names ||
      channels.map((_, i) => `Ch ${i + 1}`);

    // Target ≤ 2×pixel columns so rendering stays fast regardless of nT
    const targetPts = Math.max(4, Math.floor(innerW) * 2);

    this._svg.selectAll('*').remove();

    channels.forEach((ch, ci) => {
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
          `translate(${marginL},${ci * chHeight + marginT})`);

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
    });
  }
}

window.StreamVizLib = { StreamViz };
