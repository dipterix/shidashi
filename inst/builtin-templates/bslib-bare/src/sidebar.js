/**
 * Shidashi Sidebar
 *
 * Custom sidebar replacing AdminLTE3's sidebar widgets.
 * Supports toggle, treeview groups, search filter, and active state.
 */

export class Sidebar {
  constructor(sidebarEl) {
    this._el = sidebarEl;
    this._navContainer = sidebarEl.querySelector('.shidashi-sidebar-content');
    this._searchInput = sidebarEl.querySelector('[data-shidashi-action="sidebar-search"]');
    this._isOpen = !document.body.classList.contains('sidebar-collapsed');

    this._bindEvents();
  }

  _bindEvents() {
    // Toggle buttons (can be in the header or inside sidebar)
    document.querySelectorAll('[data-shidashi-toggle="sidebar"]').forEach(el => {
      el.addEventListener('click', (e) => {
        e.preventDefault();
        this.toggle();
      });
    });

    // Treeview toggles — click on a nav-group header to expand/collapse
    if (this._navContainer) {
      this._navContainer.addEventListener('click', (e) => {
        const groupLink = e.target.closest('.shidashi-nav-group > .shidashi-nav-link');
        if (groupLink) {
          e.preventDefault();
          const group = groupLink.parentElement;
          this._toggleTreeview(group);
        }
      });
    }

    // Search filter
    if (this._searchInput) {
      this._searchInput.addEventListener('input', () => {
        this._filterItems(this._searchInput.value);
      });
    }

    // Click on a module link to mark it active
    if (this._navContainer) {
      this._navContainer.addEventListener('click', (e) => {
        const link = e.target.closest('.shidashi-nav-item > .shidashi-nav-link');
        if (link && !link.closest('.shidashi-nav-group > .shidashi-nav-link')) {
          this._setActive(link.closest('.shidashi-nav-item'));
        }
      });
    }

    // Overlay dismiss on narrow screens
    const overlay = document.querySelector('.sidebar-overlay');
    if (overlay) {
      overlay.addEventListener('click', () => {
        if (window.innerWidth < 992) {
          this.close();
        }
      });
    }
  }

  toggle() {
    if (this._isOpen) {
      this.close();
    } else {
      this.open();
    }
  }

  open() {
    this._isOpen = true;
    document.body.classList.remove('sidebar-collapsed');
    document.body.classList.add('sidebar-open');
    this._el.classList.add('open');
  }

  close() {
    this._isOpen = false;
    document.body.classList.add('sidebar-collapsed');
    document.body.classList.remove('sidebar-open');
    this._el.classList.remove('open');
  }

  /**
   * Toggle a treeview group open/closed.
   */
  _toggleTreeview(groupEl) {
    const isOpen = groupEl.classList.contains('menu-open');
    const submenu = groupEl.querySelector('.shidashi-nav-treeview');
    if (!submenu) return;

    if (isOpen) {
      groupEl.classList.remove('menu-open');
      submenu.style.maxHeight = '0px';
    } else {
      groupEl.classList.add('menu-open');
      submenu.style.maxHeight = submenu.scrollHeight + 'px';
    }
  }

  /**
   * Set a nav item as active; deactivate others.
   */
  _setActive(itemEl) {
    if (!this._navContainer) return;
    this._navContainer.querySelectorAll('.shidashi-nav-item').forEach(el => {
      el.classList.remove('active');
    });
    itemEl.classList.add('active');

    // Ensure parent group is open
    const parentGroup = itemEl.closest('.shidashi-nav-group');
    if (parentGroup && !parentGroup.classList.contains('menu-open')) {
      this._toggleTreeview(parentGroup);
    }
  }

  /**
   * Activate a menu item by module id attribute.
   */
  setActiveByModule(moduleId) {
    if (!this._navContainer) return;
    const link = this._navContainer.querySelector(`.shidashi-nav-link[shiny-module="${moduleId}"]`);
    if (link) {
      const item = link.closest('.shidashi-nav-item');
      if (item) this._setActive(item);
    }
  }

  /**
   * Filter sidebar items by search query.
   */
  _filterItems(query) {
    if (!this._navContainer) return;
    const q = query.trim().toLowerCase();
    const items = this._navContainer.querySelectorAll('.shidashi-nav-item');

    items.forEach(item => {
      if (!q) {
        item.style.display = '';
        return;
      }
      const text = item.textContent.toLowerCase();
      item.style.display = text.includes(q) ? '' : 'none';
    });

    // Show all groups if filtering, expand them
    const groups = this._navContainer.querySelectorAll('.shidashi-nav-group');
    groups.forEach(group => {
      if (!q) {
        group.style.display = '';
        return;
      }
      const hasVisible = group.querySelector('.shidashi-nav-item:not([style*="display: none"])');
      group.style.display = hasVisible ? '' : 'none';
      if (hasVisible && !group.classList.contains('menu-open')) {
        this._toggleTreeview(group);
      }
    });
  }
}
