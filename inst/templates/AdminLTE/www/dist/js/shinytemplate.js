// general

$(function() {
Shiny.addCustomMessageHandler("shinytemplates.click", (params) => {
  if(!params.selector || params.selector === ''){ return; }
  const el = $(params.selector);
  if(!el.length){ return; }
  el.click();
});
});

// Tabset
$(function() {

const tabsetActivate = function(inputId, title){
  let el = document.getElementById(inputId);
  let elbody = document.getElementById(inputId + "Content");
  if(!el){ return("Cannot find tabset with given settings."); }
  if(!elbody){ return("Cannot find tabset with given settings."); }

  el = $(el);
  const existing_items = el.children(".nav-item.nav-tab-header");
  if(!existing_items.length) {
    return("Tab with title '" + title + "' cannot be found.");
  }

  let activated = false;
  existing_items.each((i, item) => {
    const link = $(item).children(".nav-link");
    if(link.text() === title){
      link.click();
      activated = true;
    }
  });

  if(!activated){
    return("Tab with title '" + title + "' cannot be found.");
  }
  return(true);

}

const tabsetRemove = function(inputId, title){
  let el = document.getElementById(inputId);
  let elbody = document.getElementById(inputId + "Content");
  if(!el){ return("Cannot find tabset with given settings."); }
  if(!elbody){ return("Cannot find tabset with given settings."); }

  el = $(el);

  // check if title existed
  const existing_items = el.children(".nav-item.nav-tab-header");
  if(!existing_items.length) {
    return("Tab with title '" + title + "' cannot be found.");
  }
  el = existing_items.children(".nav-link");
  let activate = false;
  let remove_idx = 0;
  const existing_title = el.toArray()
    .map((v, i) => {
      if(v.innerText === title) {
        // remove this tab
        remove_idx = i;
        const rem = $(el[i]);
        const tabid = rem.attr("aria-controls");
        const tab = $("#" + tabid);
        const is_active = rem.attr("aria-selected");
        Shiny.unbindAll(tab);
        rem.parent().remove();
        tab.remove();
        if(is_active === "true"){
          activate = true;
        }
      }
      return(v.innerText);
    });
  if(!existing_title.includes(title)){
    return("A tab with title '" + title + "' cannot be found.");
  }
  if(activate && existing_items.length > 1){
    let active_tab;
    if(remove_idx - 1 >= 0){
      active_tab = existing_items[remove_idx - 1];
    } else {
      active_tab = existing_items[remove_idx + 1];
    }
    console.log(remove_idx);
    $(active_tab).children("a.nav-link").click();
  }
  return(true);

}
const tabsetAdd = function(inputId, title, body, active = true){
  let el = document.getElementById(inputId);
  let elbody = document.getElementById(inputId + "Content");
  if(!el){ return("Cannot find tabset with given settings."); }
  if(!elbody){ return("Cannot find tabset with given settings."); }

  el = $(el);

  // check if title existed
  const existing_items = el.children(".nav-item.nav-tab-header");
  if(existing_items.length){
    const existing_title = existing_items.children(".nav-link")
      .toArray()
      .map((v) => {return(v.innerText);});
    if(existing_title.includes(title)){
      return("A tab with title '" + title + "' already exists.");
    }
  }

  // Shiny.unbindAll(el);

  const tabId = Math.random().toString(16).substr(2, 8);

  // Create header
  const header_item = document.createElement("li");
  header_item.className = "nav-item nav-tab-header";
  const header_a = document.createElement("a");
  header_a.className = "nav-link";
  header_a.setAttribute("href", `#${ inputId }-${tabId}`);
  header_a.setAttribute("id", `${ inputId }-${tabId}-tab`);
  header_a.setAttribute("data-toggle", "pill");
  header_a.setAttribute("role", "tab");
  header_a.setAttribute("aria-controls", `${ inputId }-${tabId}`);
  header_a.setAttribute("aria-selected", "false");
  header_a.innerText = title;

  header_item.appendChild(header_a);

  // add to header

  if(existing_items.length > 0){
    existing_items.last().after(header_item);
  }

  // body
  const body_el = document.createElement("div");
  body_el.className = "tab-pane fade";
  body_el.setAttribute("id", `${ inputId }-${tabId}`);
  body_el.setAttribute("role", "tabpanel");
  body_el.setAttribute("tab-index", tabId);
  body_el.setAttribute("aria-labelledby", `${ inputId }-${tabId}-tab`);
  body_el.innerHTML = body;
  elbody.appendChild(body_el);

  Shiny.bindAll($(elbody));

  if(active){
    header_a.click();
  }

  return(true);

};

Shiny.addCustomMessageHandler("shinytemplates.card_tabset_insert", (params) => {
  const added = tabsetAdd(
    params.inputId,
    params.title,
    params.body,
    params.active
  );
  if(params.notify_on_failure === true && added !== true){
    $(document).Toasts('create', {
      "autohide": true,
      "delay" : 2000,
      "title" : "Cannot create new tab",
      "body"  : added,
      "class" : "bg-warning"
    });
  }
});

Shiny.addCustomMessageHandler("shinytemplates.card_tabset_remove", (params) => {
  const removed = tabsetRemove(
    params.inputId,
    params.title
  );
  if(params.notify_on_failure === true && removed !== true){
    $(document).Toasts('create', {
      "autohide": true,
      "delay" : 2000,
      "title" : "Cannot remove tab " + params.title,
      "body"  : removed,
      "class" : "bg-warning"
    });
  }
});

Shiny.addCustomMessageHandler("shinytemplates.card_tabset_activate", (params) => {
  const activated = tabsetActivate(
    params.inputId,
    params.title
  );
  if(params.notify_on_failure === true && activated !== true){
    $(document).Toasts('create', {
      "autohide": true,
      "delay" : 2000,
      "title" : "Cannot activate tab " + params.title,
      "body"  : activated,
      "class" : "bg-warning"
    });
  }
});

Shiny.addCustomMessageHandler("shinytemplates.cardwidget", (params) => {
  $("#" + params.inputId).CardWidget(params.method);
});

Shiny.addCustomMessageHandler("shinytemplates.card2widget", (params) => {
  $(params.selector).DirectChat("toggle");
});

});

// progress output
$(function() {

const progressOutputBinding = new Shiny.OutputBinding();
progressOutputBinding.name = "shinytemplates.progressOutputBinding";
$.extend(progressOutputBinding, {
  find: function(scope) {
    return $(scope).find(".shinytemplates-progress-output");
  },
  renderValue: function(el, value) {
    const v = parseInt(value.value);
    if(isNaN(v)){ return; }
    if(v < 0){ v = 0; }
    if(v > 100){ v = 100; }
    $(el).find(".progress-bar").css("width", `${v}%`);
    if(typeof(value.description) === "string"){
      $(el)
        .find(".progress-description.progress-message")
        .text(value.description);
    }
  },
  renderError: function(el, err) {
    $(el).addClass("shinytemplates-progress-error");
    $(el)
      .find(".progress-description.progress-error")
      .text(err.message);
  },
  clearError: function(el) {
    $(el).removeClass("shinytemplates-progress-error");
  }
});

Shiny.outputBindings.register(
  progressOutputBinding,
  "shinytemplates.progressOutputBinding");
});

// clipboard output
$(function() {

const clipboardOutputBinding = new Shiny.OutputBinding();
clipboardOutputBinding.name = "shinytemplates.clipboardOutputBinding";
let clipboard;

$.extend(clipboardOutputBinding, {
  find: function(scope) {
    return $(scope).find(".shinytemplates-clipboard-output");
  },
  renderValue: function(el, value) {
    let el_ = $(el);
    if(!el_.hasClass("clipboard-btn")){
      el_ = $(el).find(".clipboard-btn");
    }
    $(el_).attr("data-clipboard-text", value)
  },
  renderError: function(el, err) {
  },
  clearError: function(el) {
  }
});

Shiny.outputBindings.register(
  clipboardOutputBinding,
  "shinytemplates.clipboardOutputBinding");

var cp = new ClipboardJS(".clipboard-btn");

cp.on('success', function(e) {
  $(document).Toasts('create', {
    title : "Copied to clipboard",
    delay: 1000,
    autohide: true,
    icon: "fa fas fa-copy",
    "class" : "bg-success"
  });
  e.clearSelection();
});

});

// Notification
$(function() {

Shiny.addCustomMessageHandler(
  "shinytemplates.show_notification",
  (params) => {
    $(document).Toasts('create', params);
  });

Shiny.addCustomMessageHandler("shinytemplates.clear_notification", (params) => {
  $(params.selector).toast("hide");
});

});


// Theme configuration
$(function() {



$('.content-wrapper').IFrame({
  onTabClick(item) {
    return item
  },
  onTabChanged(item) {
    return item
  },
  onTabCreated(item) {
    return item
  },
  autoIframeMode: false,
  autoItemActive: true,
  autoShowNewTab: true,
  allowDuplicates: false,
  loadingScreen: false,
  useNavbarItems: true
})

const triggerResize = () => {
  setTimeout(function() {
    $(window).trigger("resize");
  }, 50);
};

$(document).on('expanded.lte.cardwidget', (evt) => {

  if(evt.target){
    const card = $(evt.target).parents(".card.start-collapsed");

    if(card.length > 0){

      setTimeout(() => {
        Shiny.unbindAll(card);
        card.removeClass("start-collapsed");
        Shiny.bindAll(card);
      }, 200);

    }
  }
  triggerResize();
});
$(document).on('maximized.lte.cardwidget', triggerResize);
$(document).on('minimized.lte.cardwidget', triggerResize);
$(document).on("loaded.lte.cardrefresh", triggerResize);
$('.card-tools .btn-tool[data-card-widget="refresh"]').on('click', (evt) => {
  evt.preventDefault();
  triggerResize();
});

$(".resize").on("resize", triggerResize);

$(document).ready(() => {
  triggerResize()
});


});

// session storage
$(function() {
  const localStorage = window.localStorage;
  const sessionStorage = window.sessionStorage;

  const session_data = {};

  // Clean the localStorage
  for(let key in localStorage){
    if(key.startsWith("shinytemplates-session-")){
      try {
        const item = JSON.parse(localStorage.getItem(key));
        const now = new Date();
        // one day
        if((now - new Date(item.last_saved)) > 1000 * 60 * 60 * 24) {
          console.debug("Removing expired key: " + key);
          localStorage.removeItem(key);
        }
      } catch (e) {
        console.debug("Removing corrupted key: " + key);
        localStorage.removeItem(key);
      }
    }
  }


  Shiny.addCustomMessageHandler("shinytemplates.cache_session_input", (params) => {
    if(typeof(params.shared_id) !== "string"){ return; }

    const storage_key = "shinytemplates-session-" + params.shared_id;
    sessionStorage.setItem("shinytemplates-storage_key", storage_key);
    sessionStorage.setItem("shinytemplates-private_id", params.private_id);

    if(!session_data.hasOwnProperty(storage_key)) {
      session_data[storage_key] = {};
    }
    const bucket = session_data[storage_key];

    if(!bucket.hasOwnProperty("inputs")){
      bucket.inputs = {};
    }

    inputs = bucket.inputs;

    // load up from localStorage
    const stored = localStorage.getItem(storage_key);
    const now = new Date();
    if(typeof(stored) === "string") {
      try {
        const tmp = JSON.parse(stored);
        const last_saved = new Date(tmp.last_saved);
        const last_inputs = tmp.inputs;
        for(let k in last_inputs){
          inputs[k] = last_inputs[k];
        }
      } catch (e) {}
    }

    // bucket.last_changed = params.private_id;
    for(let k in params.inputs){
      inputs[k] = params.inputs[k];
    }
    bucket.last_edit = params.private_id;
    bucket.last_saved = now;

    localStorage.setItem(storage_key, JSON.stringify(bucket));
    localStorage.setItem("shinytemplates-session", JSON.stringify({
      "storage_key" : storage_key,
      "private_id": params.private_id,
      "last_saved": now
    }));

  });

  // register listener
  window.addEventListener('storage', (evt) => {
    if(evt.key !== "shinytemplates-session"){ return; }

    const storage_key = sessionStorage.getItem("shinytemplates-storage_key");
    const private_id = sessionStorage.getItem("shinytemplates-private_id");

    if(!storage_key || !private_id){ return; }

    // When local storage changes
    try {
      const item = JSON.parse(localStorage.getItem("shinytemplates-session"));

      const last_saved = new Date(item.last_saved);
      if(new Date() - last_saved < 1000 * 3600 * 24){
        if(item.storage_key === storage_key) {

          if(private_id !== item.private_id){
            Shiny.onInputChange("@shinytemplates@", localStorage.getItem(storage_key));
          }

        }
      }
    } catch (e) {}
  });
});

// fancy scrolls
$(function() {

  const dark_mode = $("body").hasClass("dark-mode");

  const scroll_theme = dark_mode ? "os-theme-round-light" : "os-theme-round-dark";
  const scroll_style = {
      visibility       : "auto",
      autoHide         : "move",
      autoHideDelay    : 800,
      dragScrolling    : true,
      clickScrolling   : true,
      touchSupport     : true
  };
  const scroll_callbacks = {
      onInitialized               : null,
      onInitializationWithdrawn   : null,
      onDestroyed                 : null,
      onScrollStart               : null,
      onScroll                    : null,
      onScrollStop                : null,
      onOverflowChanged           : null,
      onOverflowAmountChanged     : null,
      onDirectionChanged          : null,
      onContentSizeChanged        : null,
      onHostSizeChanged           : null,
      onUpdated                   : null
  };
  const scroll_textarea = {
      dynWidth       : false,
      dynHeight      : true,
      inheritedAttrs : ["style", "class"]
  };

  $(".fancy-scroll-y, .overflow-y-auto").overlayScrollbars({
      className  : scroll_theme,
      overflowBehavior : {
          x : "hidden",
          y : "scroll"
      },
      scrollbars : scroll_style,
      textarea : scroll_textarea,
      callbacks : scroll_callbacks
  });

  $(".overflow-x-auto").overlayScrollbars({
      className  : scroll_theme,
      overflowBehavior : {
          x : "scroll",
          y : "hidden"
      },
      scrollbars : scroll_style,
      textarea : scroll_textarea,
      callbacks : scroll_callbacks
  });

  $(".overflow-auto").overlayScrollbars({
      className  : scroll_theme,
      overflowBehavior : {
          x : "scroll",
          y : "scroll"
      },
      scrollbars : scroll_style,
      textarea : scroll_textarea,
      callbacks : scroll_callbacks
  });


});
