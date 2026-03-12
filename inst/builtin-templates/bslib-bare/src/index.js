/**
 * Shidashi - Bootstrap 5 / bslib dashboard toolkit
 *
 * jQuery is used for Shiny output bindings (find() must return jQuery objects)
 * and for Shiny custom events (shiny:connected is a jQuery event).
 * jQuery is provided by Shiny at runtime and treated as external by esbuild.
 */

import $ from 'jquery';
import { IFrameManager } from './iframe-manager.js';
import { Sidebar } from './sidebar.js';
import ClipboardJS from 'clipboard';

// ============================================================================
// Output Bindings (registered once Shiny is available)
// ============================================================================

function registerOutputBindings() {
  if (!window.Shiny) return;
  const Shiny = window.Shiny;

  // --- Progress Output Binding ---
  const progressOutputBinding = new Shiny.OutputBinding();
  progressOutputBinding.name = 'shidashi.progressOutputBinding';

  $.extend(progressOutputBinding, {
    find: function(scope) {
      return $(scope).find('.shidashi-progress-output');
    },
    renderValue: function(el, value) {
      let v = parseInt(value.value);
      if (isNaN(v)) return;
      if (v < 0) v = 0;
      if (v > 100) v = 100;
      $(el).find('.progress-bar').css('width', v + '%');
      if (typeof value.description === 'string') {
        $(el).find('.progress-description.progress-message').text(value.description);
      }
    },
    renderError: function(el, err) {
      if (err.message === 'argument is of length zero') {
        $(el).removeClass('shidashi-progress-error');
        $(el).find('.progress-bar').css('width', '0%');
      } else {
        $(el).addClass('shidashi-progress-error')
          .find('.progress-description.progress-error')
          .text(err.message);
      }
    },
    clearError: function(el) {
      $(el).removeClass('shidashi-progress-error');
    }
  });

  Shiny.outputBindings.register(progressOutputBinding, 'shidashi.progressOutputBinding');

  // --- Clipboard Output Binding ---
  const clipboardOutputBinding = new Shiny.OutputBinding();
  clipboardOutputBinding.name = 'shidashi.clipboardOutputBinding';

  $.extend(clipboardOutputBinding, {
    find: function(scope) {
      return $(scope).find('.shidashi-clipboard-output');
    },
    renderValue: function(el, value) {
      let el_ = $(el);
      if (!el_.hasClass('clipboard-btn')) {
        el_ = $(el).find('.clipboard-btn');
      }
      el_.attr('data-clipboard-text', value);
    },
    renderError: function(el, err) {
      let el_ = $(el);
      if (!el_.hasClass('clipboard-btn')) {
        el_ = $(el).find('.clipboard-btn');
      }
      el_.attr('data-clipboard-text', 'Error: ' + err.message);
    }
  });

  Shiny.outputBindings.register(clipboardOutputBinding, 'shidashi.clipboardOutputBinding');

  // Clipboard click handler (delegation)
  new ClipboardJS('.clipboard-btn').on('success', (e) => {
    window.shidashi.createNotification({
      title: 'Copied to clipboard',
      delay: 1000,
      autohide: true,
      icon: 'fa fas fa-copy',
      class: 'bg-success'
    });
    e.clearSelection();
  });
}

// ============================================================================
// Shidashi Main Class
// ============================================================================

class ShidashiApp {
  constructor() {
    this._shiny = null;
    this._dummy = document.createElement('div');
    this._dummy2 = document.createElement('div');
    this._localStorage = window.localStorage;
    this._sessionStorage = window.sessionStorage;
    this._keyPrefix = 'shidashi-session-';
    this._keyNotification = 'shidashi-session';
    this._keyTheme = 'shidashi-theme';
    this._listeners = {};
    this._storageDuration = 1000 * 60 * 60 * 24; // 1 day (matches original)
    this.sessionData = {};
    this._initialized = false;
    this._shiny_registered = false;
    this.shiny_connected = false;
    this._shiny_callstacks = [];
    this.sidebar = null;
    this.iframeManager = null;
    this._toastCounter = 0;
  }

  // ---------- Shiny helper ----------

  ensureShiny(then) {
    if (!this._shiny) {
      this._shiny = window.Shiny;
    }
    if (typeof then === 'function') {
      this._shiny_callstacks.push(then);
    }
    if (document.readyState && document.readyState === 'complete' &&
        this._shiny && this.shiny_connected) {
      while (this._shiny_callstacks.length > 0) {
        const f = this._shiny_callstacks.shift();
        try {
          f(this._shiny);
        } catch (e) {
          console.warn(e);
        }
      }
    }
  }

  bindAll(el, ensure = true) {
    const b = (shiny) => {
      shiny.bindAll(el);
      // Also report active tabs in any tabsets within el
      const tabLists = (el instanceof HTMLElement ? el : document).querySelectorAll('.card-tabs [role="tablist"]');
      for (let ii = 0; ii < tabLists.length; ii++) {
        const pa = tabLists[ii];
        if (pa && pa.id) {
          const activeTab = pa.querySelector('li.nav-item > .nav-link.active');
          if (activeTab) {
            shiny.setInputValue(pa.id, activeTab.textContent);
          }
        }
      }
    };
    if (ensure || this._shiny) {
      this.ensureShiny(b);
    }
  }

  unbindAll(el, ensure = true) {
    const ub = (shiny) => {
      shiny.unbindAll(el);
    };
    if (ensure || this._shiny) {
      this.ensureShiny(ub);
    }
  }

  // ---------- localStorage session sync ----------

  fromLocalStorage(key, defaultIfNotFound, ignoreDuration = false) {
    try {
      const item = JSON.parse(this._localStorage.getItem(key));
      item.last_saved = new Date(item.last_saved);
      item._key = key;
      if (!ignoreDuration) {
        const now = new Date();
        if (now - item.last_saved > this._storageDuration) {
          console.debug('Removing expired key: ' + key);
          this._localStorage.removeItem(key);
        } else {
          return item;
        }
      } else {
        return item;
      }
    } catch (e) {
      console.debug('Removing corrupted key: ' + key);
      this._localStorage.removeItem(key);
    }
    if (defaultIfNotFound === true) {
      return {
        inputs: {},
        last_saved: new Date(),
        last_edit: this._private_id,
        inputs_changed: [],
        _key: key
      };
    }
    return defaultIfNotFound;
  }

  async cleanLocalStorage(maxEntries = 1000) {
    const items = [];
    for (let key in this._localStorage) {
      if (key.startsWith(this._keyPrefix)) {
        const item = this.fromLocalStorage(key);
        if (maxEntries && item) {
          items.push(item);
        }
      }
    }
    if (items.length && items.length > maxEntries) {
      items.sort((v1, v2) => v1.last_saved > v2.last_saved ? 1 : -1);
      items.splice(items.length - maxEntries);
      items.forEach((item) => {
        this._localStorage.removeItem(item._key);
      });
    }
  }

  _setSharedId(shared_id) {
    if (typeof this._shared_id !== 'string' && typeof shared_id === 'string') {
      this._shared_id = shared_id;
      this._storage_key = this._keyPrefix + this._shared_id;
    }
    return this._storage_key;
  }

  _setPrivateId(private_id) {
    if (typeof this._private_id !== 'string') {
      if (typeof private_id === 'string') {
        this._private_id = private_id;
      } else {
        this._private_id = Math.random().toString(16).substr(2, 8);
      }
    }
    return this._private_id;
  }

  broadcastSessionData(shared_id, private_id) {
    const storage_key = this._setSharedId(shared_id);
    if (!storage_key) return;
    const private_id_ = this._setPrivateId(private_id);

    const keys_changed = Object.keys(this.sessionData);
    if (!keys_changed.length) return;

    const now = new Date();
    const stored = this.fromLocalStorage(storage_key, true, true);
    stored.last_saved = now;
    stored.last_edit = private_id_;
    stored.inputs_changed = keys_changed;
    for (let k in this.sessionData) {
      stored.inputs[k] = this.sessionData[k];
    }
    this._localStorage.setItem(storage_key, JSON.stringify(stored));
    this._localStorage.setItem(this._keyNotification, JSON.stringify({
      storage_key: storage_key,
      private_id: private_id_,
      last_saved: now
    }));
  }

  // ---------- Active module reporting ----------

  /**
   * Report the currently active module to Shiny via @shidashi_active_module@ input.
   * Called from IFrameManager.activateTab(), set_current_module handler, and
   * standalone module initialization.
   * @param {string} moduleId - The module identifier
   */
  _reportActiveModule(moduleId) {
    if (!moduleId) return;
    this._activeModuleId = moduleId;
    this.ensureShiny(() => {
      if (typeof this._shiny.onInputChange !== 'function') return;
      this._shiny.onInputChange('@shidashi_active_module@', {
        module_id: moduleId,
        token: this._sessionToken || null,
        timestamp: Date.now()
      });
    });
  }

  // ---------- Event system ----------

  broadcastEvent(type, message = {}) {
    const event = new CustomEvent('shidashi-event-' + type, { detail: message });
    this._dummy.dispatchEvent(event);
    this.ensureShiny(() => {
      if (typeof this._shiny.onInputChange !== 'function') return;
      this._shiny.onInputChange('@shidashi_event@', {
        type: type,
        message: message,
        shared_id: this._shared_id,
        private_id: this._private_id
      });
    });
    // Propagate to managed iframes
    if (this.iframeManager) {
      this.iframeManager.notifyIframes(type, message);
    }
  }

  registerListener(type, callback, replace = true) {
    const event_str = 'shidashi-event-' + type;
    if (replace) {
      const old_function = this._listeners[type];
      if (typeof old_function === 'function') {
        this._dummy.removeEventListener(event_str, old_function);
      }
    }
    if (typeof callback === 'function') {
      const cb_ = (evt) => callback(evt.detail);
      this._dummy.addEventListener(event_str, cb_);
      this._listeners[type] = cb_;
    }
  }

  // ---------- Theme ----------

  _col2Hex(color, fallback) {
    let col = color.trim();
    if (col.length < 4) return fallback || '#000000';
    if (col[0] === '#') {
      if (col.length === 7) return col;
      col = '#' + col[1] + col[1] + col[2] + col[2] + col[3] + col[3];
      return col;
    }
    // Handle rgba with alpha=0 (transparent) — return fallback
    const rgbaMatch = col.match(/rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/);
    if (rgbaMatch && parseFloat(rgbaMatch[4]) === 0) {
      return fallback || '#ffffff';
    }
    let parts = col.match(/rgb[a]?\((\d+),\s*(\d+),\s*(\d+)[\),]/);
    if (!parts) return fallback || '#000000';
    delete parts[0];
    for (let i = 1; i <= 3; ++i) {
      parts[i] = parseInt(parts[i]).toString(16);
      if (parts[i].length === 1) parts[i] = '0' + parts[i];
    }
    col = '#' + parts.slice(1, 4).join('');
    return col;
  }

  _reportTheme(mode) {
    if (typeof mode !== 'string') {
      mode = this.isDarkMode() ? 'dark' : 'light';
    }
    const darkFallbackBg = '#343a40';
    const lightFallbackBg = '#ffffff';
    const darkFallbackFg = '#e9ecef';
    const lightFallbackFg = '#343a40';
    const background = mode === 'dark' ? darkFallbackBg : lightFallbackBg;
    const foreground = mode === 'dark' ? darkFallbackFg : lightFallbackFg;

    this.broadcastEvent('theme.changed', {
      theme: mode,
      mode: mode,
      background: background,
      foreground: foreground
    });
  }

  isDarkMode() {
    return document.body.classList.contains('dark-mode');
  }

  _updateThemeIcon(mode) {
    const icon = document.querySelector('[data-shidashi-action="theme-toggle"] i');
    if (!icon) return;
    if (mode === 'dark') {
      icon.classList.remove('fa-moon');
      icon.classList.add('fa-sun');
    } else {
      icon.classList.remove('fa-sun');
      icon.classList.add('fa-moon');
    }
  }

  asLightMode() {
    document.body.classList.remove('dark-mode');
    // Sidebar stays dark by default in light mode (rave-pipelines convention)
    // Only switch to sidebar-light if the sidebar has the explicit opt-in class
    const aside = document.querySelector('.shidashi-sidebar');
    if (aside && aside.classList.contains('shidashi-sidebar--follow-theme')) {
      aside.classList.remove('sidebar-dark');
      aside.classList.add('sidebar-light');
    }
    // Header navbar theme
    const header = document.querySelector('.shidashi-header');
    if (header) {
      header.setAttribute('data-bs-theme', 'light');
    }
    // Update theme toggle icon: show moon (click to go dark)
    this._updateThemeIcon('light');
    this._sessionStorage.setItem(this._keyTheme, 'light');
    // Propagate to iframes
    if (this.iframeManager) {
      this.iframeManager.propagateThemeToAll();
    }
    this._reportTheme('light');
  }

  asDarkMode() {
    document.body.classList.add('dark-mode');
    const aside = document.querySelector('.shidashi-sidebar');
    if (aside) {
      aside.classList.remove('sidebar-light');
      aside.classList.add('sidebar-dark');
    }
    // Header navbar theme
    const header = document.querySelector('.shidashi-header');
    if (header) {
      header.setAttribute('data-bs-theme', 'dark');
    }
    // Update theme toggle icon: show sun (click to go light)
    this._updateThemeIcon('dark');
    this._sessionStorage.setItem(this._keyTheme, 'dark');
    if (this.iframeManager) {
      this.iframeManager.propagateThemeToAll();
    }
    this._reportTheme('dark');
  }

  // ---------- UI actions ----------

  click(selector) {
    if (!selector || selector === '') return;
    const el = document.querySelector(selector);
    if (el) el.click();
  }

  triggerResize(timeout) {
    if (timeout) {
      setTimeout(() => this.triggerResize(), timeout);
    } else {
      window.dispatchEvent(new Event('resize'));
      this.ensureShiny(() => {
        this._shiny.unbindAll(this._dummy2);
      });
    }
  }

  // ---------- Tabset (card-tabset) ----------

  tabsetAdd(inputId, title, body, active = true) {
    const el = document.getElementById(inputId);
    const elbody = document.getElementById(inputId + 'Content');
    if (!el) return 'Cannot find tabset with given settings.';
    if (!elbody) return 'Cannot find tabset with given settings.';

    // Check for duplicate title
    const existingHeaders = el.querySelectorAll(':scope > .nav-item.nav-tab-header');
    for (const item of existingHeaders) {
      const link = item.querySelector('.nav-link');
      if (link && link.textContent === title) {
        return "A tab with title '" + title + "' already exists.";
      }
    }

    const tabId = Math.random().toString(16).substr(2, 8);

    // Create header
    const headerItem = document.createElement('li');
    headerItem.className = 'nav-item nav-tab-header';
    const headerA = document.createElement('a');
    headerA.className = 'nav-link';
    headerA.setAttribute('href', `#${inputId}-${tabId}`);
    headerA.setAttribute('id', `${inputId}-${tabId}-tab`);
    headerA.setAttribute('data-bs-toggle', 'tab');
    headerA.setAttribute('role', 'tab');
    headerA.setAttribute('aria-controls', `${inputId}-${tabId}`);
    headerA.setAttribute('aria-selected', 'false');
    headerA.textContent = title;
    headerItem.appendChild(headerA);

    // Insert after last header
    if (existingHeaders.length > 0) {
      existingHeaders[existingHeaders.length - 1].after(headerItem);
    } else {
      el.appendChild(headerItem);
    }

    // Create body pane
    const bodyEl = document.createElement('div');
    bodyEl.className = 'tab-pane fade';
    bodyEl.setAttribute('id', `${inputId}-${tabId}`);
    bodyEl.setAttribute('role', 'tabpanel');
    bodyEl.setAttribute('tab-index', tabId);
    bodyEl.setAttribute('aria-labelledby', `${inputId}-${tabId}-tab`);
    bodyEl.innerHTML = body;
    elbody.appendChild(bodyEl);

    this.bindAll(elbody);

    if (active) {
      return this.tabsetActivate(inputId, title);
    }
    return true;
  }

  tabsetRemove(inputId, title) {
    const el = document.getElementById(inputId);
    const elbody = document.getElementById(inputId + 'Content');
    if (!el) return 'Cannot find tabset with given settings.';
    if (!elbody) return 'Cannot find tabset with given settings.';

    const existingItems = el.querySelectorAll(':scope > .nav-item.nav-tab-header');
    if (!existingItems.length) {
      return "Tab with title '" + title + "' cannot be found.";
    }

    let found = false;
    let activate = false;
    let removeIdx = -1;

    existingItems.forEach((item, i) => {
      const link = item.querySelector('.nav-link');
      if (link && link.textContent === title) {
        found = true;
        removeIdx = i;
        const tabid = link.getAttribute('aria-controls');
        const tab = document.getElementById(tabid);
        const isActive = link.getAttribute('aria-selected');
        this.unbindAll(tab);
        item.remove();
        if (tab) tab.remove();
        if (isActive === 'true') {
          activate = true;
        }
      }
    });

    if (!found) {
      return "A tab with title '" + title + "' cannot be found.";
    }

    if (activate && existingItems.length > 1) {
      let activeTab;
      if (removeIdx - 1 >= 0) {
        activeTab = existingItems[removeIdx - 1];
      } else {
        activeTab = existingItems[removeIdx + 1];
      }
      if (activeTab) {
        const link = activeTab.querySelector('a.nav-link');
        if (link) link.click();
      }
    }
    return true;
  }

  tabsetActivate(inputId, title) {
    const el = document.getElementById(inputId);
    const elbody = document.getElementById(inputId + 'Content');
    if (!el) return 'Cannot find tabset with given settings.';
    if (!elbody) return 'Cannot find tabset with given settings.';

    const existingItems = el.querySelectorAll(':scope > .nav-item.nav-tab-header');
    if (!existingItems.length) {
      return "Tab with title '" + title + "' cannot be found.";
    }

    let activated = false;
    existingItems.forEach((item) => {
      const link = item.querySelector('.nav-link');
      if (!link) return;
      const paneId = link.getAttribute('aria-controls');
      const pane = paneId ? document.getElementById(paneId) : null;
      if (link.textContent === title) {
        link.click();
        activated = true;
      } else {
        link.classList.remove('active');
        link.setAttribute('aria-selected', 'false');
        if (pane) {
          pane.classList.remove('show', 'active');
        }
      }
    });

    if (!activated) {
      return "Tab with title '" + title + "' cannot be found.";
    }
    return true;
  }

  // ---------- Card / card2 / flip-box ----------

  card(inputId, method) {
    const el = document.getElementById(inputId);
    if (!el) return;
    const card = el.closest('.card') || el;
    this._cardOperate(card, method);
  }

  _cardOperate(card, method) {
    if (!card) return;
    switch (method) {
      case 'collapse':
        // CSS on .card.shidashi-collapsed handles the soft-hide:
        // height:0 + overflow:hidden keeps the element in the DOM so
        // Shiny outputs retain defined width and continue to update.
        card.classList.add('shidashi-collapsed');
        this._updateCardIcon(card, true);
        break;

      case 'minimize':
        // Reverse of maximize: restore the card from fullscreen
        card.classList.remove('shidashi-maximized');
        document.body.classList.remove('shidashi-card-maximized');
        this._updateMaximizeIcon(card);
        this.triggerResize(50);
        break;

      case 'expand':
        card.classList.remove('shidashi-collapsed');
        if (card.classList.contains('start-collapsed')) {
          this.unbindAll(card);
          card.classList.remove('start-collapsed');
          this.bindAll(card);
        }
        this._updateCardIcon(card, false);
        this.triggerResize(50);
        break;

      case 'maximize':
        card.classList.add('shidashi-maximized');
        document.body.classList.add('shidashi-card-maximized');
        this._updateMaximizeIcon(card);
        this.triggerResize(50);
        break;

      case 'toggleMaximize':
        if (method === 'toggleMaximize' && card.classList.contains('shidashi-maximized')) {
          card.classList.remove('shidashi-maximized');
          document.body.classList.remove('shidashi-card-maximized');
        } else {
          card.classList.add('shidashi-maximized');
          document.body.classList.add('shidashi-card-maximized');
        }
        this._updateMaximizeIcon(card);
        this.triggerResize(50);
        break;

      case 'restore':
        card.classList.remove('shidashi-maximized');
        document.body.classList.remove('shidashi-card-maximized');
        this._updateMaximizeIcon(card);
        this.triggerResize(50);
        break;

      case 'toggle':
        if (card.classList.contains('shidashi-collapsed') || card.classList.contains('start-collapsed')) {
          this._cardOperate(card, 'expand');
        } else {
          this._cardOperate(card, 'collapse');
        }
        break;

      case 'remove':
        card.remove();
        break;

      default:
        break;
    }
  }

  _updateCardIcon(card, collapsed) {
    const icon = card.querySelector('[data-card-widget="collapse"] i, [data-card-widget="collapse"] .fas');
    if (icon) {
      if (collapsed) {
        icon.classList.remove('fa-minus');
        icon.classList.add('fa-plus');
      } else {
        icon.classList.remove('fa-plus');
        icon.classList.add('fa-minus');
      }
    }
  }

  _updateMaximizeIcon(card) {
    const btn = card.querySelector('[data-card-widget="maximize"]');
    if (!btn) return;
    const icon = btn.querySelector('i, .fas');
    if (icon) {
      if (card.classList.contains('shidashi-maximized')) {
        icon.classList.remove('fa-expand');
        icon.classList.add('fa-compress');
      } else {
        icon.classList.remove('fa-compress');
        icon.classList.add('fa-expand');
      }
    }
  }

  toggleCard2(selector) {
    const el = document.querySelector(selector);
    if (!el) return;
    // Match original AdminLTE3 behavior: click the button to trigger DirectChat toggle
    el.click();
  }

  flipBox(inputId) {
    const el = document.getElementById(inputId);
    if (el && el.classList.contains('flip-box')) {
      el.classList.toggle('active');
    }
  }

  // ---------- Notification (BS5 Toast) ----------

  createNotification(options) {
    const container = this._getToastContainer();
    const id = 'shidashi-toast-' + (++this._toastCounter);

    const toastEl = document.createElement('div');
    toastEl.id = id;
    toastEl.className = 'toast';
    toastEl.setAttribute('role', 'alert');
    toastEl.setAttribute('aria-live', 'assertive');
    toastEl.setAttribute('aria-atomic', 'true');

    if (options.class) {
      toastEl.classList.add(...options.class.split(/\s+/));
    }
    if (options.autohide === false) {
      toastEl.setAttribute('data-bs-autohide', 'false');
    } else {
      toastEl.setAttribute('data-bs-autohide', 'true');
      toastEl.setAttribute('data-bs-delay', String(options.delay || 5000));
    }

    // Build toast content
    let headerHtml = '';
    if (options.icon) {
      headerHtml += `<i class="${options.icon} me-2"></i>`;
    }
    if (options.image) {
      headerHtml += `<img src="${this._escapeAttr(options.image)}" class="rounded me-2" alt="" style="width:20px;height:20px;">`;
    }
    headerHtml += `<strong class="me-auto">${this._escapeHtml(options.title || '')}</strong>`;
    if (options.subtitle) {
      headerHtml += `<small>${this._escapeHtml(options.subtitle)}</small>`;
    }

    toastEl.innerHTML = `
      <div class="toast-header">
        ${headerHtml}
        <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
      </div>
      ${options.body ? `<div class="toast-body">${options.body}</div>` : ''}
    `;

    container.appendChild(toastEl);

    // Bind Shiny outputs inside toast
    this.ensureShiny(() => {
      this._shiny.bindAll(toastEl);
    });

    // Show via BS5 Toast API
    if (window.bootstrap?.Toast) {
      const toast = new bootstrap.Toast(toastEl);
      toast.show();

      // Remove from DOM after hidden
      toastEl.addEventListener('hidden.bs.toast', () => {
        this.ensureShiny(() => {
          this._shiny.unbindAll(toastEl);
        });
        toastEl.remove();
      });
    }
  }

  clearNotification(selector) {
    const els = document.querySelectorAll(selector || '.toast');
    els.forEach(el => {
      if (window.bootstrap?.Toast) {
        const instance = bootstrap.Toast.getInstance(el);
        if (instance) {
          instance.hide();
          return;
        }
      }
      el.remove();
    });
  }

  _getToastContainer() {
    let container = document.getElementById('shidashi-toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'shidashi-toast-container';
      container.className = 'toast-container position-fixed top-0 end-0 p-3';
      container.style.zIndex = '1100';
      document.body.appendChild(container);
    }
    return container;
  }

  // ---------- Progress ----------

  setProgress(inputId, value, max = 100, description = null) {
    if (typeof value !== 'number' || isNaN(value)) return;
    const el = document.getElementById(inputId);
    if (!el) return;

    let v = parseInt(value / max * 100);
    v = Math.max(0, Math.min(100, v));
    const bar = el.querySelector('.progress-bar');
    if (bar) bar.style.width = v + '%';
    if (typeof description === 'string') {
      const desc = el.querySelector('.progress-description.progress-message');
      if (desc) desc.textContent = description;
    }
  }

  // ---------- Scroll ----------

  scrollTop(duration = 200) {
    window.scrollTo({ top: 0, behavior: duration > 0 ? 'smooth' : 'instant' });
  }

  // ---------- Drawer ----------

  drawerOpen() {
    // Drawer is always local to the current frame (module iframe)
    const drawer = document.querySelector('.shidashi-drawer');
    const overlay = document.querySelector('.shidashi-drawer-overlay');
    if (drawer) drawer.classList.add('open');
    if (overlay) overlay.classList.add('open');
    this.broadcastEvent('drawer.open', {});
  }

  drawerClose() {
    const drawer = document.querySelector('.shidashi-drawer');
    const overlay = document.querySelector('.shidashi-drawer-overlay');
    if (drawer) drawer.classList.remove('open');
    if (overlay) overlay.classList.remove('open');
    this.broadcastEvent('drawer.close', {});
  }

  drawerToggle() {
    const drawer = document.querySelector('.shidashi-drawer');
    if (drawer && drawer.classList.contains('open')) {
      this.drawerClose();
    } else {
      this.drawerOpen();
    }
  }

  // ---------- Open URL ----------

  openUrl(url, target = '_blank') {
    if (url) {
      window.open(url, target);
    }
  }

  // ---------- Utils ----------

  async matchSelector(el, selector, next, strict = false) {
    if (!el) return;
    const els = document.querySelectorAll(selector);
    if (!els.length) return;

    for (const item of els) {
      if (item === el || (!strict && item.contains(el))) {
        if (typeof next === 'function') {
          return next(item);
        }
        return true;
      }
    }
  }

  shinyHandler(action, callback) {
    if (!this._shiny) {
      if (window.Shiny) {
        this._shiny = window.Shiny;
      } else {
        console.error('Cannot find window.Shiny object. Is R-shiny running?');
        return false;
      }
    }
    this._shiny.addCustomMessageHandler('shidashi.' + action, callback);
  }

  _escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str || '';
    return div.innerHTML;
  }

  _escapeAttr(str) {
    return (str || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  /**
   * Capture a <canvas> element as a data URL.
   * Handles WebGL canvases whose drawing buffer may have been cleared
   * after compositing (preserveDrawingBuffer === false) by reading
   * pixels directly via gl.readPixels and compositing onto a 2D canvas.
   * Returns null when capture is not possible (e.g. tainted canvas).
   */
  _captureCanvas(canvas) {
    // Try the fast path first – works for 2D and WebGL with preserveDrawingBuffer
    try {
      const url = canvas.toDataURL('image/png');
      // A blank WebGL canvas still returns a valid data-url but the
      // base64 payload is very short (transparent 1×1 is ~100 chars).
      // If the payload looks substantial, trust it.
      const payload = url.split(',')[1] || '';
      if (payload.length > 200) return url;
    } catch (e) {
      // Tainted – cannot capture at all
      return null;
    }

    // Attempt WebGL readPixels capture
    const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
    if (!gl) {
      // It is a 2D canvas whose toDataURL already succeeded above
      try { return canvas.toDataURL('image/png'); } catch (e) { return null; }
    }

    try {
      const w = canvas.width;
      const h = canvas.height;
      const pixels = new Uint8Array(w * h * 4);
      gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);

      // gl.readPixels returns rows bottom-to-top; flip vertically
      const tmp = new Uint8Array(w * 4);
      for (let row = 0; row < Math.floor(h / 2); row++) {
        const topOffset = row * w * 4;
        const botOffset = (h - row - 1) * w * 4;
        tmp.set(pixels.subarray(topOffset, topOffset + w * 4));
        pixels.copyWithin(topOffset, botOffset, botOffset + w * 4);
        pixels.set(tmp, botOffset);
      }

      // Paint onto an offscreen 2D canvas and export
      const c2d = document.createElement('canvas');
      c2d.width = w;
      c2d.height = h;
      const ctx = c2d.getContext('2d');
      const imageData = ctx.createImageData(w, h);
      imageData.data.set(pixels);
      ctx.putImageData(imageData, 0, 0);
      return c2d.toDataURL('image/png');
    } catch (e) {
      return null;
    }
  }

  // ---------- Card tool click delegation ----------

  _bindCardTools() {
    document.addEventListener('click', (evt) => {
      // Collapse/expand
      const collapseBtn = evt.target.closest('[data-card-widget="collapse"]');
      if (collapseBtn) {
        evt.preventDefault();
        const card = collapseBtn.closest('.card');
        if (card) this._cardOperate(card, 'toggle');
        return;
      }

      // Maximize/restore
      const maxBtn = evt.target.closest('[data-card-widget="maximize"]');
      if (maxBtn) {
        evt.preventDefault();
        const card = maxBtn.closest('.card');
        if (card) this._cardOperate(card, 'toggleMaximize');
        return;
      }

      // Refresh / loading
      const refreshBtn = evt.target.closest('[data-card-widget="refresh"]');
      if (refreshBtn) {
        evt.preventDefault();
        this.triggerResize(50);
        return;
      }

      // Flip
      const flipBtn = evt.target.closest('[data-card-widget="flip"]');
      if (flipBtn) {
        evt.preventDefault();
        const card = flipBtn.closest('.card');
        if (card) {
          const flipBox = card.querySelector('.flip-box');
          if (flipBox) flipBox.classList.toggle('active');
        }
        return;
      }

      // Remove
      const removeBtn = evt.target.closest('[data-card-widget="remove"]');
      if (removeBtn) {
        evt.preventDefault();
        const card = removeBtn.closest('.card');
        if (card) this._cardOperate(card, 'remove');
        return;
      }

      // Chat toggle (card2)
      const chatBtn = evt.target.closest('[data-shidashi-action="chat-toggle"]');
      if (chatBtn) {
        evt.preventDefault();
        const directChat = chatBtn.closest('.direct-chat');
        if (directChat) directChat.classList.toggle('direct-chat-contacts-open');
        return;
      }
    });

    // Double-click flip-box
    document.addEventListener('dblclick', (evt) => {
      this.matchSelector(evt.target, '.flip-box', (item) => {
        const action = item.getAttribute('data-toggle') || item.getAttribute('data-bs-toggle');
        if (action === 'click') {
          item.classList.toggle('active');
        } else if (action === 'click-front') {
          item.classList.add('active');
        }
      });
    });
  }

  // ---------- Initialization ----------

  _finalize_initialization() {
    if (this._initialized) return;
    this._initialized = true;

    // Initialize sidebar
    const sidebarEl = document.querySelector('.shidashi-sidebar');
    if (sidebarEl) {
      this.sidebar = new Sidebar(sidebarEl);
      document.body.classList.add('has-sidebar');
    }

    // Detect iframe context — hide module header when embedded
    if (window.self !== window.top) {
      document.body.classList.add('in-iframe');
    }

    // Initialize iframe manager
    const iframeContainer = document.querySelector('.shidashi-content');
    if (iframeContainer) {
      this.iframeManager = new IFrameManager(iframeContainer);
    }

    // Restore theme
    const theme = this._sessionStorage.getItem(this._keyTheme);
    if (theme === 'light') {
      this.asLightMode();
    } else if (theme === 'dark') {
      this.asDarkMode();
    } else if (document.body.classList.contains('dark-mode')) {
      // Body starts with dark-mode class from R but no stored preference
      const header = document.querySelector('.shidashi-header');
      if (header) { header.setAttribute('data-bs-theme', 'dark'); }
      this._updateThemeIcon('dark');
    }

    // Back-to-top widget
    this._initBackToTop();

    // Card tools delegation
    this._bindCardTools();

    // Start-collapsed cards: after expand, remove start-collapsed class
    document.addEventListener('click', (evt) => {
      const collapseBtn = evt.target.closest('[data-card-widget="collapse"]');
      if (!collapseBtn) return;
      const card = collapseBtn.closest('.card.start-collapsed');
      if (!card) return;

      this.unbindAll(card);
      card.classList.remove('start-collapsed');
      this.bindAll(card);
    });

    // Theme toggle icon (sun/moon)
    const themeToggle = document.querySelector('[data-shidashi-action="theme-toggle"]');
    if (themeToggle) {
      themeToggle.addEventListener('click', (e) => {
        e.preventDefault();
        if (this.isDarkMode()) {
          this.asLightMode();
        } else {
          this.asDarkMode();
        }
      });
    }

    // Storage listener (cross-tab session sync)
    window.addEventListener('storage', (evt) => {
      if (evt.key !== this._keyNotification) return;
      const storage_key = this._storage_key;
      const private_id = this._private_id;
      if (!storage_key || !private_id) return;

      try {
        const item = JSON.parse(this._localStorage.getItem(this._keyNotification));
        const last_saved = new Date(item.last_saved);
        if (new Date() - last_saved < this._storageDuration) {
          if (item.storage_key === storage_key && private_id !== item.private_id) {
            this.ensureShiny(() => {
              this._shiny.onInputChange('@shidashi@', this._localStorage.getItem(storage_key));
            });
          }
        }
      } catch (e) {}
    });

    // Sidebar nav links → open iframe tab
    if (this.iframeManager && sidebarEl) {
      sidebarEl.addEventListener('click', (evt) => {
        const link = evt.target.closest('.shidashi-nav-link[href]');
        if (!link) return;
        // Skip group toggles (they have child treeview)
        if (link.parentElement?.classList.contains('shidashi-nav-group')) return;
        const href = link.getAttribute('href');
        if (!href || href === '#') return;
        evt.preventDefault();
        const title = link.getAttribute('title') || link.textContent.trim();
        this.iframeManager.openTab(href, title);
      });
    }

    // Tab change listener: report active tab name to Shiny input
    // In BS5, tab events are 'shown.bs.tab' on the nav-link element
    document.body.addEventListener('shown.bs.tab', (evt) => {
      const el = evt.target;
      const tablist = el.closest('[role="tablist"]');
      if (!tablist) return;
      const cardTabs = tablist.closest('.card-tabs');
      if (!cardTabs) return;
      if (!tablist.id) return;
      const tabname = el.textContent;
      this.ensureShiny((shiny) => {
        shiny.setInputValue(tablist.id, tabname);
      });
      this.broadcastEvent('tabset.activated', {
        tablistId: tablist.id,
        title: tabname
      });
    });

    // Report initial active tabs when Shiny becomes available
    // (queued via ensureShiny — will drain once shiny_connected is true)
    $(document).ready(() => {
      this.ensureShiny((shiny) => {
        const $tabLists = $('.card-tabs [role="tablist"]');
        for (let ii = 0; ii < $tabLists.length; ii++) {
          const pa = $tabLists[ii];
          if (pa && pa.id) {
            const activeTab = pa.querySelector('li.nav-item > .nav-link.active');
            if (activeTab) {
              shiny.setInputValue(pa.id, $(activeTab).text());
            }
          }
        }
      });
    });

    // Drawer overlay click → close drawer (use delegation for dynamic content)
    document.addEventListener('click', (e) => {
      if (e.target.classList.contains('shidashi-drawer-overlay')) {
        this.drawerClose();
      }
    });

    // Drawer close-tab click → close drawer (no-overlay mode)
    document.addEventListener('click', (e) => {
      const closeTab = e.target.closest('.shidashi-drawer-close-tab');
      if (closeTab) {
        e.stopPropagation();
        this.drawerClose();
      }
    });

    // Drawer toggle button
    document.addEventListener('click', (evt) => {
      const toggleBtn = evt.target.closest('[data-shidashi-action="drawer-toggle"]');
      if (toggleBtn) {
        evt.preventDefault();
        this.drawerToggle();
        return;
      }

      // Generic shidashi-button click → broadcast event to Shiny
      const shidashiBtn = evt.target.closest('[data-shidashi-action="shidashi-button"]');
      if (shidashiBtn) {
        evt.preventDefault();
        const eventData = {};
        // Collect data-shidashi-* attributes as event payload
        for (const attr of shidashiBtn.attributes) {
          if (attr.name.startsWith('data-shidashi-') && attr.name !== 'data-shidashi-action') {
            const key = attr.name.replace('data-shidashi-', '');
            eventData[key] = attr.value;
          }
        }
        eventData.id = shidashiBtn.id || '';
        this.broadcastEvent('button.click', eventData);
        return;
      }
    });

    // Resize handle init
    this._initResizeHandles();

    // Standalone module: when there is no iframe manager and the page
    // is not itself inside an iframe, report the current module from URL
    if (!this.iframeManager && window.self === window.top) {
      const urlParams = new URLSearchParams(window.location.search);
      const moduleId = urlParams.get('module');
      if (moduleId) {
        this._reportActiveModule(moduleId);
      }
    }
  }

  _initResizeHandles() {
    // Vertical resize handles: inject a drag handle into .resize-vertical containers
    const verticals = document.querySelectorAll('.resize-vertical');
    verticals.forEach((container) => {
      // Skip if already initialised
      if (container.querySelector('.shidashi-resize-handle')) return;

      const handle = document.createElement('div');
      handle.className = 'shidashi-resize-handle';
      container.appendChild(handle);

      let startY = 0;
      let startHeight = 0;

      const onMouseMove = (e) => {
        const delta = e.clientY - startY;
        const newHeight = Math.max(60, startHeight + delta);
        container.style.height = newHeight + 'px';
      };

      const onMouseUp = () => {
        handle.classList.remove('active');
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
        this.triggerResize(50);
      };

      handle.addEventListener('mousedown', (e) => {
        e.preventDefault();
        startY = e.clientY;
        startHeight = container.offsetHeight;
        handle.classList.add('active');
        document.body.style.userSelect = 'none';
        document.body.style.cursor = 'ns-resize';
        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      });
    });

    // Horizontal resize handles: inject a drag handle into .resize-horizontal dividers
    document.querySelectorAll('.resize-horizontal').forEach((divider) => {
      // Skip if already initialised
      if (divider.querySelector('.shidashi-resize-handle-h')) return;

      const handle = document.createElement('div');
      handle.className = 'shidashi-resize-handle-h';
      divider.appendChild(handle);

      let startX = 0;
      let startWidthLeft = 0;
      let startWidthRight = 0;
      let leftEl = null;
      let rightEl = null;

      const onMouseMove = (e) => {
        const dx = e.clientX - startX;
        const totalWidth = startWidthLeft + startWidthRight;
        const newLeftWidth = Math.max(50, Math.min(totalWidth - 50, startWidthLeft + dx));
        const newRightWidth = totalWidth - newLeftWidth;
        leftEl.style.width = newLeftWidth + 'px';
        leftEl.style.flex = 'none';
        rightEl.style.width = newRightWidth + 'px';
        rightEl.style.flex = 'none';
      };

      const onMouseUp = () => {
        handle.classList.remove('active');
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
        this.triggerResize(50);
      };

      divider.addEventListener('mousedown', (e) => {
        e.preventDefault();
        leftEl = divider.previousElementSibling;
        rightEl = divider.nextElementSibling;
        if (!leftEl || !rightEl) return;
        startX = e.clientX;
        startWidthLeft = leftEl.getBoundingClientRect().width;
        startWidthRight = rightEl.getBoundingClientRect().width;
        handle.classList.add('active');
        document.body.style.userSelect = 'none';
        document.body.style.cursor = 'col-resize';
        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      });
    });
  }

  _initBackToTop() {
    const gotopEl = document.querySelector('.shidashi-back-to-top');
    if (!gotopEl) return;

    const gotopBtn = gotopEl.querySelector('.btn-go-top');
    const menu = gotopEl.querySelector('.dropdown-menu');
    const anchors = document.querySelectorAll('.shidashi-anchor');

    // Build anchor dropdown items
    if (menu) {
      anchors.forEach((item) => {
        let itemId = item.getAttribute('id');
        if (typeof itemId !== 'string' || !itemId) {
          itemId = item.textContent.replace(/[^a-zA-Z0-9_-]/gi, '-').replace(/(--)/gi, '');
          itemId = 'shidashi-anchor-id-' + itemId;
          item.setAttribute('id', itemId);
        }
        const el = document.createElement('a');
        el.className = 'dropdown-item';
        el.href = '#' + itemId;
        el.textContent = item.textContent;
        menu.appendChild(el);
      });
    }

    if (gotopBtn) {
      gotopBtn.addEventListener('click', () => this.scrollTop());
    }
  }

  // ---------- Register Shiny message handlers ----------

  _register_shiny() {
    if (!this._shiny) {
      if (window.Shiny) {
        this._shiny = window.Shiny;
      } else {
        console.error('Cannot find window.Shiny object. Is R-shiny running?');
        return false;
      }
    }
    if (this._shiny_registered) return;
    this._shiny_registered = true;

    this.shinyHandler('click', (params) => {
      this.click(params.selector);
    });

    this.shinyHandler('box_flip', (params) => {
      this.flipBox(params.inputId);
    });

    this.shinyHandler('card_tabset_insert', (params) => {
      const added = this.tabsetAdd(params.inputId, params.title, params.body, params.active);
      if (params.notify_on_failure === true && added !== true) {
        this.createNotification({
          autohide: true,
          delay: 2000,
          title: 'Cannot create new tab',
          body: added,
          class: 'bg-warning'
        });
      }
    });

    this.shinyHandler('card_tabset_remove', (params) => {
      const removed = this.tabsetRemove(params.inputId, params.title);
      if (params.notify_on_failure === true && removed !== true) {
        this.createNotification({
          autohide: true,
          delay: 2000,
          title: 'Cannot remove tab ' + params.title,
          body: removed,
          class: 'bg-warning'
        });
      }
    });

    this.shinyHandler('card_tabset_activate', (params) => {
      const activated = this.tabsetActivate(params.inputId, params.title);
      if (params.notify_on_failure === true && activated !== true) {
        this.createNotification({
          autohide: true,
          delay: 2000,
          title: 'Cannot activate tab ' + params.title,
          body: activated,
          class: 'bg-warning'
        });
      }
    });

    this.shinyHandler('cardwidget', (params) => {
      if (params.inputId) {
        // Direct id-based lookup
        const el = document.getElementById(params.inputId);
        if (el) {
          const card = el.closest('.card') || el;
          this._cardOperate(card, params.method);
        }
      } else if (params.title) {
        // Title-based lookup via data-title attribute
        const cards = document.querySelectorAll('.card[data-title]');
        for (const c of cards) {
          if (c.getAttribute('data-title') === params.title) {
            this._cardOperate(c, params.method);
            break;
          }
        }
      }
    });

    this.shinyHandler('card2widget', (params) => {
      this.toggleCard2(params.selector);
    });

    this.shinyHandler('show_notification', (params) => {
      this.createNotification(params);
    });

    this.shinyHandler('clear_notification', (params) => {
      this.clearNotification(params.selector);
    });

    this.shinyHandler('set_progress', (params) => {
      this.setProgress(params.outputId, params.value, params.max || 100, params.description);
    });

    this.shinyHandler('make_scroll_fancy', (params) => {
      // No-op: using CSS native scrollbars instead of OverlayScrollbars
      // Keeping handler registered so R calls don't error
    });

    this.shinyHandler('cache_session_input', (params) => {
      this.sessionData = params.inputs;
      this.broadcastSessionData(params.shared_id, params.private_id);
    });

    this.shinyHandler('get_theme', (params) => {
      this._reportTheme();
    });

    this.shinyHandler('reset_output', (params) => {
      const el = document.getElementById(params.outputId);
      if (el && el.parentElement) {
        this.ensureShiny((shiny) => {
          const $parentEl = $(el.parentElement);
          Object.keys(shiny.outputBindings.bindingNames).forEach((key) => {
            const binding = shiny.outputBindings.bindingNames[key].binding;
            if (binding && typeof binding.find === 'function') {
              $(binding.find($parentEl)).each(function() {
                if (this.id === el.id) {
                  binding.renderError(el, {
                    message: params.message || '',
                    type: 'shiny-output-error-shiny.silent.error shiny-output-error-validation'
                  });
                }
              });
            }
          });
        });
      }
    });

    // --- Additional handlers used by ravedash ---

    this.shinyHandler('set_current_module', (params) => {
      if (this.sidebar && params.module_id) {
        this.sidebar.setActiveByModule(params.module_id);
      }
      if (this.iframeManager && params.module_id) {
        this.iframeManager.openTabByModule(params.module_id, params.title);
      }
      // Report active module even when there is no iframe manager
      if (params.module_id) {
        this._reportActiveModule(params.module_id);
      }
    });

    this.shinyHandler('shutdown_session', (params) => {
      // Close the window or navigate away
      if (params.url) {
        window.location.href = params.url;
      } else {
        window.close();
      }
    });

    this.shinyHandler('open_iframe_tab', (params) => {
      if (this.iframeManager) {
        this.iframeManager.openTab(params.url, params.title || 'Module');
      }
    });

    this.shinyHandler('set_html', (params) => {
      if (params.selector) {
        const els = document.querySelectorAll(params.selector);
        els.forEach(el => {
          if (params.content !== undefined) {
            this.unbindAll(el, false);
            if (params.is_text) {
              el.textContent = params.content;
            } else {
              el.innerHTML = params.content;
            }
            this.bindAll(el, false);
          }
        });
      }
    });

    this.shinyHandler('accordion', (params) => {
      if (!params.selector) return;
      const el = document.querySelector(params.selector);
      if (!el) return;
      const method = params.method || 'toggle';
      if (method === 'expand') {
        if (el.classList.contains('collapsed')) { el.click(); }
      } else if (method === 'collapse') {
        if (!el.classList.contains('collapsed')) { el.click(); }
      } else {
        el.click();
      }
    });

    this.shinyHandler('add_class', (params) => {
      if (params.selector && params.class) {
        document.querySelectorAll(params.selector).forEach(el => {
          el.classList.add(...params.class.split(/\s+/).filter(Boolean));
        });
      }
    });

    this.shinyHandler('remove_class', (params) => {
      if (params.selector && params.class) {
        document.querySelectorAll(params.selector).forEach(el => {
          el.classList.remove(...params.class.split(/\s+/).filter(Boolean));
        });
      }
    });

    this.shinyHandler('add_attribute', (params) => {
      // params: { selector, attribute, value }
      if (params.selector && params.attribute) {
        document.querySelectorAll(params.selector).forEach(el => {
          el.setAttribute(params.attribute, params.value ?? '');
        });
      }
    });

    this.shinyHandler('remove_attribute', (params) => {
      // params: { selector, attribute }
      if (params.selector && params.attribute) {
        document.querySelectorAll(params.selector).forEach(el => {
          el.removeAttribute(params.attribute);
        });
      }
    });

    // --- Drawer handlers ---

    this.shinyHandler('drawer_open', (params) => {
      this.drawerOpen();
    });

    this.shinyHandler('drawer_close', (params) => {
      this.drawerClose();
    });

    this.shinyHandler('drawer_toggle', (params) => {
      this.drawerToggle();
    });

    // --- Activate a specific drawer tab (for chatbot) ---

    this.shinyHandler('activate_drawer_tab', (params) => {
      if (params.target) {
        const tabBtn = document.querySelector(
          `.shidashi-drawer-tabs [data-bs-target="${params.target}"]`
        );
        if (tabBtn && window.bootstrap && window.bootstrap.Tab) {
          const tab = new window.bootstrap.Tab(tabBtn);
          tab.show();
        }
      }
    });

    // --- Module token registration (for chatbot) ---

    this.shinyHandler('register_module_token', (params) => {
      if (params.token) {
        this._sessionToken = params.token;
        // Re-report active module so R gets the updated token
        if (this._activeModuleId) {
          this._reportActiveModule(this._activeModuleId);
        }
      }
    });

    // --- Chatbot status bar handler ---

    this.shinyHandler('update_chat_status', (params) => {
      // params: { id, text, title?, status: "ready"|"recalculating"|"unknown" }
      const el = document.getElementById(params.id);
      if (!el) return;
      if (params.text !== undefined) {
        el.textContent = params.text;
      }
      if (params.title !== undefined) {
        el.setAttribute('title', params.title);
      }
      // Toggle recalculating blink
      el.classList.toggle(
        'shidashi-chatbot-status-recalculating',
        params.status === 'recalculating'
      );
      // Mark unknown cost with strikethrough
      el.classList.toggle(
        'shidashi-chatbot-status-unknown',
        params.status === 'unknown'
      );
    });

    // --- Chatbot stop button initialization ---

    this.shinyHandler('init_chat_stop_button', (params) => {
      // params: { chat_id, stop_id }
      const chatContainer = document.getElementById(params.chat_id);
      if (!chatContainer) return;

      const chatInput = chatContainer.querySelector('shiny-chat-input');
      if (!chatInput) return;

      // Don't create if already exists
      if (document.getElementById(params.stop_id)) return;

      // Create stop button - styles defined in shidashi.scss
      const stopBtn = document.createElement('button');
      stopBtn.type = 'button';
      stopBtn.id = params.stop_id;
      stopBtn.className = 'shidashi-chatbot-stop';
      stopBtn.title = 'Stop generation';
      stopBtn.setAttribute('aria-label', 'Stop generation');
      stopBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="currentColor" viewBox="0 0 16 16">
        <path d="M16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0M6.5 5A1.5 1.5 0 0 0 5 6.5v3A1.5 1.5 0 0 0 6.5 11h3A1.5 1.5 0 0 0 11 9.5v-3A1.5 1.5 0 0 0 9.5 5z"/>
      </svg>`;

      // Insert into the chat input container
      chatInput.style.position = 'relative';
      chatInput.appendChild(stopBtn);

      // Bind Shiny input - increment counter on click
      stopBtn.addEventListener('click', () => {
        if (window.Shiny) {
          const currentVal = Shiny.shinyapp.$inputValues[params.stop_id] || 0;
          Shiny.setInputValue(params.stop_id, currentVal + 1, { priority: 'event' });
        }
      });
    });

    // --- Chatbot stop button toggle ---

    this.shinyHandler('toggle_stop_button', (params) => {
      // params: { id, visible }
      const el = document.getElementById(params.id);
      if (!el) return;
      // Toggle visibility via CSS class
      el.classList.toggle('shidashi-chatbot-stop-visible', params.visible);
    });

    // --- Open URL handler ---

    this.shinyHandler('open_url', (params) => {
      this.openUrl(params.url, params.target || '_blank');
    });

    // --- Query UI handler (MCP) ---

    this.shinyHandler('query_ui', (params) => {
      // params: { selector, request_id, input_id }
      const selector = params.selector;
      const requestId = params.request_id;
      const inputId = params.input_id;
      if (!selector || !requestId || !inputId) return;

      const el = document.querySelector(selector);
      if (!el) {
        Shiny.setInputValue(inputId, {
          request_id: requestId,
          html: '',
          image_data: '',
          image_type: ''
        }, { priority: 'event' });
        return;
      }

      // Check if element is a <canvas>
      if (el.tagName === 'CANVAS') {
        const dataUrl = this._captureCanvas(el);
        if (dataUrl) {
          const parts = dataUrl.split(',');
          const mime = (parts[0] || '').replace(/^data:/, '').replace(/;base64$/, '') || 'image/png';
          Shiny.setInputValue(inputId, {
            request_id: requestId,
            html: '',
            image_data: parts[1] || '',
            image_type: mime
          }, { priority: 'event' });
          return;
        }
        // Tainted or empty canvas — fall through to innerHTML
      }

      // Check if element contains a single <img> with a data URI or a <canvas> child
      const canvas = el.querySelector('canvas');
      if (canvas) {
        const dataUrl = this._captureCanvas(canvas);
        if (dataUrl) {
          const parts = dataUrl.split(',');
          const mime = (parts[0] || '').replace(/^data:/, '').replace(/;base64$/, '') || 'image/png';
          Shiny.setInputValue(inputId, {
            request_id: requestId,
            html: '',
            image_data: parts[1] || '',
            image_type: mime
          }, { priority: 'event' });
          return;
        }
        // fall through
      }

      const img = el.querySelector('img[src^="data:"]');
      if (img && el.querySelectorAll('img').length === 1) {
        const src = img.getAttribute('src') || '';
        // src is "data:image/png;base64,..."
        const parts = src.split(',');
        const mime = (parts[0] || '').replace(/^data:/, '').replace(/;base64$/, '') || 'image/png';
        Shiny.setInputValue(inputId, {
          request_id: requestId,
          html: '',
          image_data: parts[1] || '',
          image_type: mime
        }, { priority: 'event' });
        return;
      }

      // Default: return innerHTML
      Shiny.setInputValue(inputId, {
        request_id: requestId,
        html: el.innerHTML,
        image_data: '',
        image_type: ''
      }, { priority: 'event' });
    });

    // --- Ask-user handler (MCP built-in tool) ---

    this.shinyHandler('ask_user', (params) => {
      // params: { request_id, input_id, message, choices, allow_freeform }
      const requestId = params.request_id;
      const inputId = params.input_id;
      if (!requestId || !inputId) return;

      const message = params.message || 'The agent needs your input:';
      const choices = params.choices || [];
      const allowFreeform = params.allow_freeform !== false;

      // Build a Bootstrap 5 modal
      const modalId = 'shidashi-ask-user-modal-' + requestId;
      const existing = document.getElementById(modalId);
      if (existing) existing.remove();

      let bodyHTML = `<p class="mb-3">${this._escapeHtml(message)}</p>`;

      // Choice buttons
      if (choices.length > 0) {
        bodyHTML += '<div class="d-flex flex-wrap gap-2 mb-3">';
        choices.forEach((choice, i) => {
          bodyHTML += `<button type="button" class="btn btn-outline-primary shidashi-ask-user-choice" data-choice-index="${i}">${this._escapeHtml(choice)}</button>`;
        });
        bodyHTML += '</div>';
      }

      // Free-form input
      if (allowFreeform) {
        bodyHTML += `<div class="mb-2"><textarea class="form-control shidashi-ask-user-freeform" rows="3" placeholder="Type your response..."></textarea></div>`;
      }

      const modalHTML = `
        <div class="modal fade" id="${modalId}" tabindex="-1" data-bs-backdrop="static" data-bs-keyboard="false">
          <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
              <div class="modal-header">
                <h5 class="modal-title">Agent Request</h5>
              </div>
              <div class="modal-body">${bodyHTML}</div>
              <div class="modal-footer">
                ${allowFreeform ? '<button type="button" class="btn btn-primary shidashi-ask-user-submit" disabled>Submit</button>' : ''}
                <button type="button" class="btn btn-secondary shidashi-ask-user-cancel">Cancel</button>
              </div>
            </div>
          </div>
        </div>`;

      document.body.insertAdjacentHTML('beforeend', modalHTML);
      const modalEl = document.getElementById(modalId);
      const bsModal = new bootstrap.Modal(modalEl);

      const respond = (value, cancelled) => {
        Shiny.setInputValue(inputId, {
          request_id: requestId,
          value: value,
          cancelled: !!cancelled
        }, { priority: 'event' });
        bsModal.hide();
        modalEl.addEventListener('hidden.bs.modal', () => modalEl.remove(), { once: true });
      };

      // Choice button clicks
      modalEl.querySelectorAll('.shidashi-ask-user-choice').forEach(btn => {
        btn.addEventListener('click', () => {
          const idx = parseInt(btn.dataset.choiceIndex, 10);
          respond(choices[idx], false);
        });
      });

      // Free-form submit
      const submitBtn = modalEl.querySelector('.shidashi-ask-user-submit');
      const textarea = modalEl.querySelector('.shidashi-ask-user-freeform');
      if (submitBtn && textarea) {
        textarea.addEventListener('input', () => {
          submitBtn.disabled = !textarea.value.trim();
        });
        submitBtn.addEventListener('click', () => {
          respond(textarea.value.trim(), false);
        });
      }

      // Cancel
      modalEl.querySelector('.shidashi-ask-user-cancel').addEventListener('click', () => {
        respond(null, true);
      });

      bsModal.show();

      // Focus textarea if present
      if (textarea) {
        modalEl.addEventListener('shown.bs.modal', () => textarea.focus(), { once: true });
      }
    });
  }
}

// ============================================================================
// Bootstrap
// ============================================================================

// Create global instance immediately
window.shidashi = new ShidashiApp();

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', _init);
} else {
  _init();
}

function _init() {
  registerOutputBindings();
  window.shidashi._finalize_initialization();

  // Register shiny handlers when shiny connects
  // NOTE: 'shiny:connected' is a jQuery custom event, must use $(document).on()
  $(document).on('shiny:connected', () => {
    // 1. Register all message handlers first
    window.shidashi._register_shiny();
    // 2. NOW mark as connected and drain the queue
    window.shidashi.shiny_connected = true;
    window.shidashi.ensureShiny();
  });
}

// Highlight.js initialization (if loaded)
if (window.hljs) {
  window.hljs.configure({ languages: [] });
  if (typeof window.hljs.highlightAll === 'function') {
    window.hljs.highlightAll();
  } else if (typeof window.hljs.initHighlightingOnLoad === 'function') {
    window.hljs.initHighlightingOnLoad();
  }
}
