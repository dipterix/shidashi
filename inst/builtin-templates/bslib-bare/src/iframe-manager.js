/**
 * Shidashi IFrame Manager
 *
 * Custom lightweight replacement for AdminLTE3's $.fn.IFrame plugin.
 * Manages a tab bar and iframe container for module isolation.
 */

export class IFrameManager {
  constructor(containerEl) {
    this._container = containerEl;
    this._tabList = containerEl.querySelector('.shidashi-tab-list');
    this._iframeContainer = containerEl.querySelector('.shidashi-iframe-container');
    this._emptyMessage = this._iframeContainer?.querySelector('.shidashi-tab-empty');
    this._tabs = new Map(); // id -> { tab: li, iframe: iframe, url, title }
    this._activeTabId = null;
    this._tabCounter = 0;

    this._bindEvents();
  }

  _bindEvents() {
    // Close all tabs
    this._container.querySelectorAll('[data-shidashi-action="close-all-tabs"]').forEach(el => {
      el.addEventListener('click', (e) => { e.preventDefault(); this.closeAllTabs(); });
    });
    // Close other tabs
    this._container.querySelectorAll('[data-shidashi-action="close-other-tabs"]').forEach(el => {
      el.addEventListener('click', (e) => { e.preventDefault(); this.closeOtherTabs(); });
    });
    // Scroll tabs
    this._container.querySelectorAll('[data-shidashi-action="scroll-tabs-left"]').forEach(el => {
      el.addEventListener('click', (e) => { e.preventDefault(); this.scrollTabBar('left'); });
    });
    this._container.querySelectorAll('[data-shidashi-action="scroll-tabs-right"]').forEach(el => {
      el.addEventListener('click', (e) => { e.preventDefault(); this.scrollTabBar('right'); });
    });
    // Fullscreen
    document.querySelectorAll('[data-shidashi-action="iframe-fullscreen"]').forEach(el => {
      el.addEventListener('click', (e) => { e.preventDefault(); this.toggleFullscreen(); });
    });

    // Tab click delegation
    if (this._tabList) {
      this._tabList.addEventListener('click', (e) => {
        const closeBtn = e.target.closest('.shidashi-tab-close');
        if (closeBtn) {
          e.preventDefault();
          e.stopPropagation();
          const tabId = closeBtn.closest('.shidashi-tab-item')?.dataset.tabId;
          if (tabId) this.closeTab(tabId);
          return;
        }
        const tabItem = e.target.closest('.shidashi-tab-item');
        if (tabItem) {
          e.preventDefault();
          this.activateTab(tabItem.dataset.tabId);
        }
      });
    }
  }

  /**
   * Get a URL identifier for deduplication.
   * Strips shared_id from query to match by module only.
   */
  _normalizeUrl(url) {
    try {
      const u = new URL(url, window.location.origin);
      u.searchParams.delete('shared_id');
      return u.pathname + u.search;
    } catch (e) {
      return url;
    }
  }

  /**
   * Find an existing tab by URL (module).
   */
  _findTabByUrl(url) {
    const normalized = this._normalizeUrl(url);
    for (const [id, entry] of this._tabs) {
      if (this._normalizeUrl(entry.url) === normalized) {
        return id;
      }
    }
    return null;
  }

  /**
   * Open a new tab or activate existing one.
   * @param {string} url - The URL to load in the iframe
   * @param {string} title - Tab title
   * @returns {string} The tab ID
   */
  openTab(url, title) {
    // Check for duplicate
    const existingId = this._findTabByUrl(url);
    if (existingId) {
      this.activateTab(existingId);
      return existingId;
    }

    const tabId = 'tab-' + (++this._tabCounter);

    // Create tab header
    const li = document.createElement('li');
    li.className = 'shidashi-tab-item';
    li.dataset.tabId = tabId;
    li.innerHTML = `
      <a class="shidashi-tab-link" href="#" title="${this._escapeHtml(title)}">
        <span class="shidashi-tab-title">${this._escapeHtml(title)}</span>
        <span class="shidashi-tab-close" title="Close"><i class="fas fa-times"></i></span>
      </a>
    `;

    // Create iframe
    const iframe = document.createElement('iframe');
    iframe.className = 'shidashi-iframe';
    iframe.src = url;
    iframe.dataset.tabId = tabId;
    iframe.style.display = 'none';
    iframe.setAttribute('frameborder', '0');
    iframe.setAttribute('allowfullscreen', 'true');

    // Listen for iframe load to propagate theme and fullscreen state
    iframe.addEventListener('load', () => {
      this._propagateTheme(iframe);
      if (document.body.classList.contains('iframe-mode-fullscreen')) {
        this._propagateFullscreenToIframe(iframe, true);
      }
    });

    this._tabList.appendChild(li);
    this._iframeContainer.appendChild(iframe);
    this._tabs.set(tabId, { tab: li, iframe, url, title });

    this.activateTab(tabId);
    this._updateEmptyState();

    return tabId;
  }

  /**
   * Activate a tab by ID.
   */
  activateTab(tabId) {
    if (!this._tabs.has(tabId)) return;

    // Deactivate all
    this._tabs.forEach((entry, id) => {
      entry.tab.classList.toggle('active', id === tabId);
      entry.iframe.style.display = id === tabId ? 'block' : 'none';
    });

    this._activeTabId = tabId;

    // Scroll the active tab into view
    const entry = this._tabs.get(tabId);
    if (entry?.tab) {
      entry.tab.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'nearest' });
    }

    // Trigger resize for Shiny outputs inside the iframe
    try {
      const iframe = entry.iframe;
      if (iframe.contentWindow) {
        setTimeout(() => {
          try {
            iframe.contentWindow.dispatchEvent(new Event('resize'));
          } catch (e) { /* cross-origin safety */ }
        }, 100);
      }
    } catch (e) { /* cross-origin safety */ }
  }

  /**
   * Close a tab by ID.
   */
  closeTab(tabId) {
    const entry = this._tabs.get(tabId);
    if (!entry) return;

    // If this is the active tab, activate an adjacent one
    if (this._activeTabId === tabId) {
      const ids = Array.from(this._tabs.keys());
      const idx = ids.indexOf(tabId);
      const nextId = ids[idx + 1] || ids[idx - 1];
      if (nextId) {
        this.activateTab(nextId);
      } else {
        this._activeTabId = null;
      }
    }

    // Unbind shiny in iframe before removing
    try {
      if (entry.iframe.contentWindow?.Shiny) {
        entry.iframe.contentWindow.Shiny.unbindAll(entry.iframe.contentDocument.body);
      }
    } catch (e) { /* cross-origin safety */ }

    entry.tab.remove();
    entry.iframe.remove();
    this._tabs.delete(tabId);
    this._updateEmptyState();
  }

  /**
   * Close all tabs.
   */
  closeAllTabs() {
    const ids = Array.from(this._tabs.keys());
    ids.forEach(id => this.closeTab(id));
  }

  /**
   * Close all tabs except the active one.
   */
  closeOtherTabs() {
    const ids = Array.from(this._tabs.keys());
    ids.forEach(id => {
      if (id !== this._activeTabId) this.closeTab(id);
    });
  }

  /**
   * Scroll the tab bar left or right.
   */
  scrollTabBar(direction) {
    if (!this._tabList) return;
    const scrollAmount = 150;
    if (direction === 'left') {
      this._tabList.scrollLeft -= scrollAmount;
    } else {
      this._tabList.scrollLeft += scrollAmount;
    }
  }

  /**
   * Toggle fullscreen mode for the content area.
   */
  toggleFullscreen() {
    document.body.classList.toggle('iframe-mode-fullscreen');
    this._propagateFullscreenToAll();
  }

  /**
   * Propagate iframe-mode-fullscreen class to all child iframe content windows.
   */
  _propagateFullscreenToAll() {
    const isFullscreen = document.body.classList.contains('iframe-mode-fullscreen');
    this._tabs.forEach(entry => {
      this._propagateFullscreenToIframe(entry.iframe, isFullscreen);
    });
  }

  /**
   * Propagate fullscreen state to a single iframe.
   */
  _propagateFullscreenToIframe(iframe, isFullscreen) {
    try {
      const doc = iframe.contentDocument || iframe.contentWindow?.document;
      if (doc && doc.body) {
        if (isFullscreen) {
          doc.body.classList.add('iframe-mode-fullscreen');
        } else {
          doc.body.classList.remove('iframe-mode-fullscreen');
        }
      }
    } catch (e) { /* cross-origin safety */ }
  }

  /**
   * Open a tab by matching sidebar nav link attributes.
   * Used by ravedash's switch_module().
   */
  openTabByModule(moduleId, title) {
    // Find the sidebar link for this module
    const link = document.querySelector(`.shidashi-nav-link[shiny-module="${moduleId}"]`);
    if (link) {
      const url = link.getAttribute('href');
      this.openTab(url, title || link.getAttribute('title') || moduleId);
    }
  }

  /**
   * Propagate current theme to an iframe.
   */
  _propagateTheme(iframe) {
    try {
      const isDark = document.body.classList.contains('dark-mode');
      if (iframe.contentWindow?.shidashi) {
        if (isDark) {
          iframe.contentWindow.shidashi.asDarkMode();
        } else {
          iframe.contentWindow.shidashi.asLightMode();
        }
      }
    } catch (e) { /* cross-origin safety */ }
  }

  /**
   * Propagate theme to all iframes.
   */
  propagateThemeToAll() {
    this._tabs.forEach(entry => {
      this._propagateTheme(entry.iframe);
    });
  }

  /**
   * Broadcast a custom event to all managed iframes.
   * Used for rave-action broadcasting and cross-iframe communication.
   * @param {string} type - Event type name
   * @param {object} message - Event payload
   */
  notifyIframes(type, message = {}) {
    this._tabs.forEach(entry => {
      try {
        const win = entry.iframe.contentWindow;
        if (win) {
          // If the iframe has shidashi loaded, use its broadcastEvent
          if (win.shidashi && typeof win.shidashi.broadcastEvent === 'function') {
            win.shidashi.broadcastEvent(type, message);
          } else {
            // Fallback: dispatch a CustomEvent on the iframe's document
            win.dispatchEvent(new CustomEvent('shidashi-event-' + type, { detail: message }));
          }
        }
      } catch (e) { /* cross-origin safety */ }
    });
  }

  /**
   * Show/hide the empty state message.
   */
  _updateEmptyState() {
    if (this._emptyMessage) {
      this._emptyMessage.style.display = this._tabs.size === 0 ? 'block' : 'none';
    }
  }

  _escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }
}
