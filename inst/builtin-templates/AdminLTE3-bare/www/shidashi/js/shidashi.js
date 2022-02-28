
// progress output
$(function() {

  const progressOutputBinding = new Shiny.OutputBinding();
  progressOutputBinding.name = "shidashi.progressOutputBinding";
  $.extend(progressOutputBinding, {
    find: function(scope) {
      return $(scope).find(".shidashi-progress-output");
    },
    renderValue: function(el, value) {
      let v = parseInt(value.value);
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
      if(err.message === "argument is of length zero"){
        $(el).removeClass("shidashi-progress-error");
        $(el).find(".progress-bar").css("width", "0%");
      } else {
        $(el)
          .addClass("shidashi-progress-error")
          .find(".progress-description.progress-error")
          .text(err.message);
      }
    },
    clearError: function(el) {
      $(el).removeClass("shidashi-progress-error");
    }
  });

  Shiny.outputBindings.register(
    progressOutputBinding,
    "shidashi.progressOutputBinding");
});

// clipboard output
$(function() {

  const clipboardOutputBinding = new Shiny.OutputBinding();
  clipboardOutputBinding.name = "shidashi.clipboardOutputBinding";

  $.extend(clipboardOutputBinding, {
    find: function(scope) {
      return $(scope).find(".shidashi-clipboard-output");
    },
    renderValue: function(el, value) {
      let el_ = $(el);
      if(!el_.hasClass("clipboard-btn")){
        el_ = $(el).find(".clipboard-btn");
      }
      $(el_).attr("data-clipboard-text", value);
    },
    renderError: function(el, err) {
      let el_ = $(el);
      if(!el_.hasClass("clipboard-btn")){
        el_ = $(el).find(".clipboard-btn");
      }
      $(el_).attr("data-clipboard-text", "Error: " + err.message);
    }
  });

  Shiny.outputBindings.register(clipboardOutputBinding, "shidashi.clipboardOutputBinding");

  // No need to re-register because they use delegation
  new ClipboardJS(".clipboard-btn").on('success', function(e) {
    window.shidashi.createNotification({
      title : "Copied to clipboard",
      delay: 1000,
      autohide: true,
      icon: "fa fas fa-copy",
      "class" : "bg-success"
    });
    e.clearSelection();
  });

});


// shidashi toolbox
(function(){

const default_scroll_opt = {
  autoUpdate           : null,
  autoUpdateInterval   : 33,
  sizeAutoCapable      : true,
  scrollbars : {
    visibility       : "auto",
    autoHide         : "move",
    autoHideDelay    : 800,
    dragScrolling    : true,
    clickScrolling   : true,
    touchSupport     : true,
  },
  textarea : {
    dynWidth       : false,
    dynHeight      : true,
    inheritedAttrs : ["style", "class"]
  }
};

class Shidashi {

  constructor (Shiny){
    this._active_module = undefined;
    this._shiny = Shiny;
    this.$window = $(window);
    this.$document = $(document);
    this.$body = $("body");
    this.$aside = $("aside");
    this.$navIfarme = $(".navbar-nav-iframe");
    this.$iframeWrapper = $(".content-wrapper.iframe-mode");

    this._dummy = document.createElement("div");
    this._dummy2 = document.createElement("div");
    this._localStorage = window.localStorage;
    this._sessionStorage = window.sessionStorage;
    this._keyPrefix = "shidashi-session-";
    this._keyNotification = "shidashi-session";
    this._keyTheme = "shidashi-theme";
    this._listeners = {};
    this._storageDuration = 1000 * 60 * 60 * 24; // 1000 days
    this.sessionData = {};
    this.scroller = this.makeFancyScroll(
      "body:not(.overflow-hidden)",
      {
        overflowBehavior : {
            x : "hidden",
            y : "scroll"
        }
      }
    );
  }

  ensureShiny(then){
    if(!this._shiny){
      this._shiny = window.Shiny;
    }
    if(this._shiny && typeof(then) === "function"){
      try{
        then(this._shiny);
      }catch(e){
        console.warn(e);
      }

    }
  }

  // localStorage to save input data
  fromLocalStorage(key, defaultIfNotFound, ignoreDuration = false){
    try {
      const item = JSON.parse(this._localStorage.getItem(key));
      item.last_saved = new Date(item.last_saved);
      item._key = key;
      if( !ignoreDuration ){
        const now = new Date();
        if((now - item.last_saved) > this._storageDuration) {
          // item expired
          console.debug("Removing expired key: " + key);
          this._localStorage.removeItem(key);
        } else {
          return(item);
        }
      } else {
        return(item);
      }
    } catch (e) {
      console.debug("Removing corrupted key: " + key);
      this._localStorage.removeItem(key);
    }
    if(defaultIfNotFound === true){
      return({
        inputs : {},
        last_saved: new Date(),
        last_edit: this._private_id,
        inputs_changed: [],
        _key: key
      });
    } else {
      return (defaultIfNotFound);
    }

  }

  async cleanLocalStorage(maxEntries = 1000) {
    // Clean the localStorage
    const items = [];
    for(let key in this._localStorage){
      if(key.startsWith(this._keyPrefix)){
        const item = this.fromLocalStorage(key);
        if(maxEntries && item){
          items.push( item );
        }
      }
    }

    if(items.length && items.length > maxEntries){
      items.sort((v1, v2) => { return(v1.last_saved > v2.last_saved); });
      items.splice(items.length - maxEntries);
      items.forEach((item) => {
        this._localStorage.removeItem(item._key);
      });
    }
  }

  _setSharedId(shared_id) {
    if(typeof(this._shared_id) !== "string" && typeof(shared_id) === "string"){
      this._shared_id = shared_id;
      this._storage_key = this._keyPrefix + this._shared_id;
    }
    return this._storage_key;
  }
  _setPrivateId(private_id) {
    if(typeof(this._private_id) !== "string"){
      if(typeof(private_id) === "string"){
        this._private_id = private_id;
      } else {
        this._private_id = Math.random().toString(16).substr(2, 8);
      }
    }
    return this._private_id;
  }

  broadcastSessionData(shared_id, private_id){
    const storage_key = this._setSharedId(shared_id);
    if(!storage_key){ return; }
    const private_id_ = this._setPrivateId(private_id);

    const keys_changed = Object.keys(this.sessionData);
    if(!keys_changed.length){
      return;
    }

    const now = new Date();

    // load up from localStorage
    const stored = this.fromLocalStorage(storage_key, true, true);
    stored.last_saved = now;
    stored.last_edit = private_id_;
    stored.inputs_changed = keys_changed;
    for(let k in this.sessionData){
      stored.inputs[k] = this.sessionData[k];
    }
    this._localStorage.setItem(storage_key, JSON.stringify(stored));
    this._localStorage.setItem(this._keyNotification, JSON.stringify({
      "storage_key" : storage_key,
      "private_id": private_id_,
      "last_saved": now
    }));

  }
  broadcastEvent(type, message = {}) {
    const event = new CustomEvent("shidashi-event-" + type, {
      "detail": message
    });
    this._dummy.dispatchEvent(event);
    // also send to shiny
    this.ensureShiny(() => {
      if(typeof(this._shiny.onInputChange) !== "function"){ return; }
      this._shiny.onInputChange("@shidashi_event@", {
        type: type,
        message: message,
        shared_id: this._shared_id,
        private_id: this._private_id
      });
    });
  }
  registerListener(type, callback, replace = true) {
    const event_str = "shidashi-event-" + type;
    if(replace){
      const old_function = this._listeners[type];
      if(typeof(old_function) === "function"){
        this._dummy.removeEventListener(event_str, old_function);
      }
    }
    if(typeof(callback) === "function"){
      const cb_ = (evt) => {
        return(callback(evt.detail));
      };
      this._dummy.addEventListener(event_str, cb_);
      this._listeners[type] = cb_;
    }
  }

  _col2Hex(color){
    let col = color.trim();
    if(col.length < 4){ return("#000000"); }
    if(col[0] === "#"){
      if(col.length === 7){ return(col); }
      col = "#"+col[1]+col[1]+col[2]+col[2]+col[3]+col[3];
      return(col);
    }
    let parts = col.match(/rgb[a]{0,1}\((\d+),\s*(\d+),\s*(\d+)[\),]/);
    delete(parts[0]);
    for (var i = 1; i <= 3; ++i) {
      parts[i] = parseInt(parts[i]).toString(16);
      if (parts[i].length == 1) parts[i] = '0' + parts[i];
    }
    col = '#' + parts.join('');
    return(col);
  }
  _reportTheme(mode){
    if(typeof(mode) !== "string"){
      const isDark = this.isDarkMode();
      mode = isDark ? "dark": "light";
    }
    const $card_body = $(".card, .info-box");
    let bgcolor = this._col2Hex(this.$body.css("background-color"));
    if($card_body.length){
      bgcolor = this._col2Hex($($card_body[0]).css("background-color"));
    } else if (mode === "dark"){
      bgcolor = "#343a40";
    }
    this.broadcastEvent("theme.changed", {
      mode: mode,
      background: bgcolor,
      foreground: this._col2Hex(this.$body.css("color"))
    });
  }

  notifyIframes(method, args){
    if(this.$iframeWrapper.length){
      const $iframes = this.$iframeWrapper.find("iframe");
      $iframes.each((_, iframe) => {
        try {
          if(iframe.contentWindow.shidashi){
            iframe.contentWindow.shidashi[method](...args);
          }
        } catch (e) {}
      });
    }
  }

  // theme-mode
  asLightMode(){
    this.$body.removeClass("dark-mode");
    this.$aside.removeClass("sidebar-dark-primary")
      .addClass("sidebar-light-primary");
    this.$navIfarme.removeClass("navbar-dark")
      .addClass("navbar-light");
    if(this.$iframeWrapper.length){
      this._sessionStorage.setItem(
        this._keyTheme, "light"
      );
      const $iframes = this.$iframeWrapper.find("iframe");
      $iframes.each((_, iframe) => {
        if(iframe.contentWindow.shidashi){
          iframe.contentWindow.shidashi.asLightMode();
        }
      });
    }
    this._reportTheme("light");
  }

  asDarkMode(){

    this.$body.addClass("dark-mode");
    this.$aside.removeClass("sidebar-light-primary")
      .addClass("sidebar-dark-primary");
    this.$navIfarme.removeClass("navbar-light")
      .addClass("navbar-dark");
    if(this.$iframeWrapper.length){
      this._sessionStorage.setItem(
        this._keyTheme, "dark"
      );
      const $iframes = this.$iframeWrapper.find("iframe");
      $iframes.each((_, iframe) => {
        if(iframe.contentWindow.shidashi){
          iframe.contentWindow.shidashi.asDarkMode();
        }
      });
    }
    this._reportTheme("dark");
  }

  // Trigger actions
  click(selector) {
    if(!selector || selector === ''){ return; }
    const el = $(selector);
    if(!el.length){ return; }
    el.click();
  }

  triggerResize(timeout) {
    if( timeout ){
      setTimeout(() => {
        this.triggerResize();
      }, timeout);
    } else {
      this.$window.trigger("resize");
      this._shiny.unbindAll(this._dummy2);
    }

  }

  // tabset
  tabsetAdd(inputId, title, body, active = true){
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

    // this._shiny.unbindAll(el);

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


    this.ensureShiny(() => {
      this._shiny.bindAll($(elbody));
    });

    if(active){
      return(this.tabsetActivate(inputId, title));
    }

    return(true);

  }

  tabsetRemove(inputId, title) {
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
          this.ensureShiny(() => {
            this._shiny.unbindAll(tab);
          });
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
      $(active_tab).children("a.nav-link").click();
    }
    return(true);
  }

  tabsetActivate(inputId, title) {
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
    existing_items.each((_, item) => {
      const link = $(item).children(".nav-link");
      if(link.text() === title){
        link.click();
        activated = true;
      } else {
        link.removeClass("active");
        link.attr("aria-selected", "false");
      }
    });

    if(!activated){
      return("Tab with title '" + title + "' cannot be found.");
    }
    return(true);
  }

  // card, card2, cardset...
  card(args){
    // method: expand, minimize, maximize, ...
    if( !args.method ){ return; }
    if( args.inputId ){
      $(".card#" + args.inputId).CardWidget(args.method);
    } else if (args.title){
      $(`.card[data-title='${args.title}']`).CardWidget(args.method);
    }

  }

  toggleCard2(selector){
    $(selector).DirectChat("toggle");
  }

  flipBox(inputId){
    let el = document.getElementById(inputId);
    if(el && el.classList.contains("flip-box")) {
      if( el.classList.contains("active") ){
        el.classList.remove("active");
      } else {
        el.classList.add("active");
      }
    }
  }

  // html css operations
  addClass(selector, cls){
    $(selector).addClass(cls);
  }
  removeClass(selector, cls){
    $(selector).removeClass(cls);
  }

  // notification
  createNotification(options) {
    // see https://adminlte.io/docs/3.1//javascript/toasts.html
    this.$document.Toasts('create', options);
  }

  clearNotification(selector) {
    $(selector || ".toast").toast("hide");
  }

  // set progressOutput
  setProgress(inputId, value, max = 100, description = null){
    if(typeof(value) !== "number" || isNaN(value)){ return; }
    const el = document.getElementById(inputId);
    if(!el){ return; }

    let v = parseInt(value / max * 100);
    if(v < 0){ v = 0; }
    if(v > 100){ v = 100; }
    $(el).find(".progress-bar").css("width", `${v}%`);
    if(typeof(description) === "string"){
      $(el)
        .find(".progress-description.progress-message")
        .text(description);
    }
  }

  // theme-mode
  isDarkMode() {
    return(this.$body.hasClass("dark-mode"));
  }

  // scroller
  makeFancyScroll(selector, options = {}) {
    // https://kingsora.github.io/OverlayScrollbars/#!documentation/options
    const dark_mode = this.isDarkMode();

    const className = options.className || (dark_mode ? "os-theme-thin-light" : "os-theme-thin-dark");

    options.className = className;

    const instance = $(selector)
      .overlayScrollbars($.extend(default_scroll_opt, options))
      .overlayScrollbars();

    return(instance);
  }

  scrollTop(duration = 200) {
    if(this.scroller){
      this.scroller.scroll({ y : "0%" }, duration);
    }
  }

  // utils, shiny, ...
  async matchSelector(el, selector, next, strict = false) {
    const $el = $(el);
    const $els = $(selector);

    if(!$el.length || !$els.length){ return; }

    const el_ = $el[0];
    let resolved = false;

    const els = $els.toArray();
    let item;
    for( let i in els ){
      item = els[i];
      if(item === el_ || (!strict && item.contains(el_))){
        if(typeof(next) === "function"){
          return(next(item));
        } else {
          return(true);
        }
      }
    }
    return;
  }

  shinyHandler(action, callback) {
    if(!this._shiny){
      if( window.Shiny ){
        this._shiny = window.Shiny;
      } else {
        console.error("Cannot find window.Shiny object. Is R-shiny running?");
        return false;
      }
    }
    this._shiny.addCustomMessageHandler("shidashi." + action, callback);
  }
  shinySetInput(inputId, value, add_timestamp = true, children = false) {
    this.ensureShiny(() => {
      if( add_timestamp ){
        value.timestamp = new Date();
      }
      value._active_module = this._active_module;
      value.parent_frame = this.$body.hasClass("parent-frame");
      this._shiny.onInputChange(inputId, value);

      if(children){

        if(this.$iframeWrapper.length){
          const $iframes = this.$iframeWrapper.find("iframe");
          $iframes.each((_, iframe) => {
            if(iframe.contentWindow.shidashi){
              iframe.contentWindow.shidashi.ensureShiny(() => {
                iframe.contentWindow.shidashi._shiny.onInputChange(inputId, value);
              });
            }
          });
        }

      }

    });
  }

  shinyResetOutput(outputId, message = ""){
    const el = document.getElementById(outputId);
    if(el && el.parentElement){
      this.ensureShiny(() => {
        Object.keys(this._shiny.outputBindings.bindingNames).forEach((key) => {
          const binding = shidashi._shiny.outputBindings.bindingNames[key].binding;
          $(binding.find(el.parentElement)).each((_, el2) => {
            if($(el2)[0].id === el.id){

              binding.renderError(el, {
                message: message,
                type: "shiny-output-error-shiny.silent.error shiny-output-error-validation"
              });

            }
          });
        });
        value._active_module = this._active_module;
        value.parent_frame = this.$body.hasClass("parent-frame");
        this._shiny.onInputChange(inputId, value);

      });
    }

  }

  // Finalize function when document is ready
  _finalize_initialization(){
    if(this._initialized){ return; }
    this._initialized = true;

    // set theme first
    const theme = this._sessionStorage.getItem(this._keyTheme);
    if( theme === "light" ){
      this.asLightMode();
    } else if( theme === "dark"){
      this.asDarkMode();
    }

    // scroll-top widget
    const gotop_el = $(".back-to-top");
    const gotop_btn = $(".back-to-top .btn-go-top");
    const root_btn = $(".back-to-top [data-toggle='dropdown']");
    const menu = $(".back-to-top .dropdown-menu");
    const anchors = $(".shidashi-anchor");

    // Scroll-top widgets
    anchors.each((_, item) => {
      const $item = $(item);
      let item_id = $item.attr("id");
      if( typeof(item_id) !== "string" ){
        item_id = $item.text().replace(/[^a-zA-Z0-9_-]/gi, '-').replace(/(--)/gi, '');
        item_id = "shidashi-anchor-id-" + item_id;
        $item.attr("id", item_id);
      }
      const el = document.createElement("a");
      el.className = "dropdown-item";
      el.href = "#" + item_id;
      el.innerText = item.innerText;
      menu.append( el );
    });
    root_btn.mouseenter(() => {
      if(root_btn.attr("aria-expanded") === "false"){
        root_btn.dropdown("toggle");
      }
    });
    menu.mouseleave(() => {
      if(root_btn.attr("aria-expanded") === "true"){
        root_btn.dropdown("toggle");
      }
    });
    gotop_btn.click(() => { this.scrollTop() });

    // --------------- Triggers resize -------------------------
    this.$document.on('expanded.lte.cardwidget', (evt) => {

      if(evt.target){
        const card = $(evt.target).parents(".card.start-collapsed");

        if(card.length > 0){

          setTimeout(() => {
            this.ensureShiny(() => { this._shiny.unbindAll(card); });
            card.removeClass("start-collapsed");
            this.ensureShiny(() => { this._shiny.bindAll(card); });
          }, 200);

        }
      }
      this.triggerResize(50);

    });
    this.$document.on('maximized.lte.cardwidget', () => {
      this.triggerResize(50);
    });
    this.$document.on('minimized.lte.cardwidget', () => {
      this.triggerResize(50);
    });
    this.$document.on("loaded.lte.cardrefresh", () => {
      this.triggerResize(50);
    });

    // --------------- Notification system -----------
    this.$body.on('show.bs.toast', (evt)=>{
      this.ensureShiny(() => {
        this._shiny.bindAll($(evt.target));
      });
    });
    this.$body.on('hide.bs.toast', (evt)=>{
      this.ensureShiny(() => {
        this._shiny.unbindAll($(evt.target));
      });
    });

    // --------------- Fancy scroll ---------------
    this.makeFancyScroll(".fancy-scroll-y:not(.overflow-hidden), .overflow-y-auto", {
        overflowBehavior : {
            x : "hidden",
            y : "scroll"
        }
      });
    this.makeFancyScroll(".resize-vertical", {
        resize: "vertical",
        overflowBehavior : {
            x : "hidden",
            y : "scroll"
        },
        callbacks : {
          onHostSizeChanged : () => {
            this.triggerResize( 200 );
          }
        }
      });
    this.makeFancyScroll(".fancy-scroll-x, .overflow-x-auto", {
        overflowBehavior : {
          x : "scroll",
          y : "hidden"
        }
      });
    this.makeFancyScroll(".fancy-scroll, .overflow-auto", {
        overflowBehavior : {
          x : "scroll",
          y : "scroll"
        }
      });

    // register listener
    window.addEventListener('storage', (evt) => {
        if(evt.key !== this._keyNotification){ return; }

        const storage_key = this._storage_key;
        const private_id = this._private_id;

        if(!storage_key || !private_id){ return; }

        // When local storage changes
        try {
          const item = JSON.parse(this._localStorage.getItem(this._keyNotification));
          const last_saved = new Date(item.last_saved);
          if(new Date() - last_saved < this._storageDuration){
            if(item.storage_key === storage_key) {
              if(private_id !== item.private_id){
                this.ensureShiny(() => {
                  this._shiny.onInputChange("@shidashi@", this._localStorage.getItem(storage_key));
                });
              }
            }
          }
        } catch (e) {}
      });

    $(".theme-switch-wrapper .theme-switch input[type='checkbox']")
      .change((_) => {
        if(this.isDarkMode()){
          this.asLightMode();
        } else {
          this.asDarkMode();
        }
      });

    this.$document.on("click", (evt) => {

      this.matchSelector(
        evt.target,
        '.card-tools .btn-tool[data-card-widget="refresh"]',
        () => {
          this.triggerResize(50);
        }
      );

      this.matchSelector(
        evt.target,
        '.card-tools .btn-tool[data-card-widget="flip"]',
        (el) => {
          const $card = $(el).parents(".card");
          if(!$card.length){ return; }
          $($card[0]).find(".card-body .flip-box").toggleClass("active");
        }
      );


    });

    this.$document.on("dblclick", (evt) => {

      this.matchSelector(
        evt.target,
        '.flip-box',
        (item) => {
          const $el = $(item);
          const action = $el.attr("data-toggle");
          if(action === "click"){
            $el.toggleClass("active");
          } else if (action === "click-front"){
            $el.addClass("active");
          }
        }
      );

    });

  }

  _register_shiny() {
    if(!this._shiny){
      if( window.Shiny ){
        this._shiny = window.Shiny;
      } else {
        console.error("Cannot find window.Shiny object. Is R-shiny running?");
        return false;
      }
    }
    if(this._shiny_registered) { return; }
    this._shiny_registered = true;

    this.shinyHandler("click", (params) => {
      this.click(params.selector);
    });
    this.shinyHandler("box_flip", (params) => {
      this.flipBox(params.inputId);
    });

    this.shinyHandler("card_tabset_insert", (params) => {
      const added = this.tabsetAdd( params.inputId, params.title,
                                    params.body, params.active );
      if(params.notify_on_failure === true && added !== true){
        this.createNotification({
          "autohide": true,
          "delay" : 2000,
          "title" : "Cannot create new tab",
          "body"  : added,
          "class" : "bg-warning"
        });
      }
    });
    this.shinyHandler("card_tabset_remove", (params) => {
      const removed = this.tabsetRemove( params.inputId, params.title );
      if(params.notify_on_failure === true && removed !== true){
        this.createNotification({
          "autohide": true,
          "delay" : 2000,
          "title" : "Cannot remove tab " + params.title,
          "body"  : removed,
          "class" : "bg-warning"
        });
      }
    });
    this.shinyHandler("card_tabset_activate", (params) => {
      const activated = this.tabsetActivate( params.inputId, params.title );
      if(params.notify_on_failure === true && activated !== true){
        this.createNotification({
          "autohide": true,
          "delay" : 2000,
          "title" : "Cannot activate tab " + params.title,
          "body"  : activated,
          "class" : "bg-warning"
        });
      }
    });

    this.shinyHandler("cardwidget", (params) => {
      this.card(params);
    });
    this.shinyHandler("card2widget", (params) => {
      this.toggleCard2(params.selector);
    });

    this.shinyHandler("add_class", (params) => {
      this.addClass(params.selector, params.class);
    });
    this.shinyHandler("remove_class", (params) => {
      this.removeClass(params.selector, params.class);
    });

    this.shinyHandler("show_notification", (params) => {
      this.createNotification(params);
    });
    this.shinyHandler("clear_notification", (params) => {
      this.clearNotification(params.selector);
    });

    this.shinyHandler("set_progress", (params) => {
      this.setProgress(params.outputId, params.value,
        params.max || 100, params.description);
    });

    this.shinyHandler("make_scroll_fancy", (params) => {
      if(!params.selector || params.selector === ''){ return; }
      this.makeFancyScroll(
        params.selector,
        params.options || {}
      );
    });

    this.shinyHandler("cache_session_input", (params) => {
      this.sessionData = params.inputs;
      this.broadcastSessionData(params.shared_id, params.private_id);
    });

    this.shinyHandler("get_theme", (_) => {
      this._reportTheme();
    });

    this.shinyHandler("reset_output", (params) => {
      this.shinyResetOutput(params.outputId, params.message || "");
    });

  }
}

const shiny = window.Shiny;
const shidashi = new Shidashi(shiny);

window.shidashi = shidashi;

$(document).on("shiny:connected", () => {
  shidashi._finalize_initialization();
  shidashi._register_shiny(window.Shiny);
});

// Theme configuration
$('.content-wrapper').IFrame({
  onTabClick: (item) => {
    return item;
  },
  onTabChanged: (item) => {
    return item;
  },
  onTabCreated: (item) => {
    return item;
  },
  autoIframeMode: false,
  autoItemActive: true,
  autoShowNewTab: true,
  allowDuplicates: false,
  loadingScreen: false,
  useNavbarItems: false
});

})();


if (window.hljs) {
  hljs.configure({languages: []});
  hljs.initHighlightingOnLoad();
  if (document.readyState && document.readyState === "complete") {
    window.setTimeout(function() { hljs.initHighlighting(); }, 0);
  }
}
