/**
 * stream_viz.js — htmlwidgets binding for stream_viz
 *
 * Thin glue between the htmlwidgets framework and window.StreamVizLib.StreamViz
 * (bundled separately in stream_main.js via inst/stream-viz-src/).
 */

HTMLWidgets.widget({
  name: 'stream_viz',
  type: 'output',

  factory: function (el, width, height) {
    const viz = new window.StreamVizLib.StreamViz(el, width, height);

    // Watch for container resize (e.g. CSS resize: vertical)
    if (typeof ResizeObserver !== 'undefined') {
      const ro = new ResizeObserver(function (entries) {
        for (var i = 0; i < entries.length; i++) {
          var cr = entries[i].contentRect;
          if (cr.width > 0 && cr.height > 0) {
            viz.resize(cr.width, cr.height);
          }
        }
      });
      ro.observe(el);
    }

    return {
      renderValue: function (x) {
        if (x && x.refresh_rate) {
          viz.setRefreshRate(x.refresh_rate);
        }
        if (x && x.show_controls === false) {
          viz.setShowControls(false);
        }
        if (x && x.stream_id) {
          viz.fetchAndRender(x.stream_id).then(function () {
            if (x.streaming === true) {
              viz.startStreaming();
            }
          }).catch(function (err) {
            // File may not exist yet — if streaming requested, start polling
            if (x.streaming === true) {
              viz.startStreaming();
            } else {
              console.error('[stream_viz] fetchAndRender error:', err);
            }
          });
        }
      },

      resize: function (width, height) {
        viz.resize(width, height);
      },

      // Expose viz instance so updateStreamViz custom message can reach it
      getViz: function () { return viz; }
    };
  }
});

// Shiny custom message handler — updates an existing widget in-place.
// Sent by updateStreamViz() on the R side.
if (typeof Shiny !== 'undefined') {
  Shiny.addCustomMessageHandler('stream_viz.render', function (msg) {
    // msg: { id, stream_id, streaming? }
    function applyMessage(retries) {
      var instance = HTMLWidgets.find('#' + msg.id);
      if (!instance) {
        if (retries > 0) {
          setTimeout(function () { applyMessage(retries - 1); }, 250);
        } else {
          console.warn('[stream_viz] no widget found for #' + msg.id);
        }
        return;
      }
      var viz = instance.getViz();
      viz.fetchAndRender(msg.stream_id).catch(function (err) {
        console.error('[stream_viz] update error:', err);
      });
      if (msg.streaming === true) {
        viz.startStreaming();
      } else if (msg.streaming === false) {
        viz.stopStreaming();
      }
    }
    applyMessage(20);
  });
}
