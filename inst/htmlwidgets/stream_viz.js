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

    return {
      renderValue: function (x) {
        if (x && x.stream_id) {
          viz.fetchAndRender(x.stream_id).catch(function (err) {
            console.error('[stream_viz] fetchAndRender error:', err);
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
    // msg: { id: <outputId>, stream_id: <token_id> }
    const instance = HTMLWidgets.find('#' + msg.id);
    if (!instance) {
      console.warn('[stream_viz] no widget found for #' + msg.id);
      return;
    }
    instance.getViz().fetchAndRender(msg.stream_id).catch(function (err) {
      console.error('[stream_viz] update error:', err);
    });
  });
}
