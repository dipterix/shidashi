// Tabset
$(function() {

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

Shiny.addCustomMessageHandler("shinytemplates.insert_card_tab", (params) => {
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

Shiny.addCustomMessageHandler("shinytemplates.clear_notification", (params) => {
  $(params.selector).toast("hide");
});


});



// Notification
$(function() {

Shiny.addCustomMessageHandler(
  "shinytemplates.show_notification",
  (params) => {
    $(document).Toasts('create', params);
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
  loadingScreen: 750,
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
  window.ssss = session_data;

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
