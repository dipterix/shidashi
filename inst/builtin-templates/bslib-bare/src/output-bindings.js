/**
 * Shiny output bindings for shidashi
 *
 * Registers progress and clipboard output bindings once Shiny is available.
 */

import $ from 'jquery';
import ClipboardJS from 'clipboard';

export function registerOutputBindings() {
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
