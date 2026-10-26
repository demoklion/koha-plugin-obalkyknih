/*
 * Obálky knih covers for Koha (koha-plugin-obalkyknih)
 * Copyright 2026 Ján Dugovič, GPL-3.0-or-later
 *
 * Asks the plugin route for cover links by biblionumber and puts them into
 * Koha's cover sliders (results, detail, lists; OPAC and staff) and into any
 * element marked with data-obalkyknih-biblionumber / data-obalkyknih-isbn.
 * Images load straight from obalkyknih.cz; nothing is stored in Koha.
 */
(function () {
  "use strict";

  if (window.ObalkyKnih) return;

  var script = document.currentScript;
  var cfg = {};
  try {
    cfg = JSON.parse((script && script.getAttribute("data-obalkyknih-config")) || "{}");
  } catch (e) {
    cfg = {};
  }
  cfg.api = cfg.api || "/api/v1/contrib/obalkyknih/covers";
  cfg.interface = cfg.interface === "staff" ? "staff" : "opac";

  var BATCH = 50;
  // Koha's own slider waits up to 5 s for remote covers; we hold it at most 3 s.
  var HOLD_MS = 3000;
  var BOX = { icon: [54, 68], thumbnail: [27, 36], medium: [170, 240], preview510: [510, 720] };

  var STRINGS = {
    cs: {
      credit: "Obálky knih",
      cover: "Obálka knihy",
      coverOf: "Obálka knihy {title}",
      linkSuffix: "(více na Obálkách knih)",
      annotation: "Anotace",
      source: "Zdroj: {source}",
      toc: "Obsah",
      tocLink: "Obsah knihy (PDF, otevře se na Obálkách knih)",
    },
    en: {
      credit: "Obálky knih",
      cover: "Book cover",
      coverOf: "Cover of {title}",
      linkSuffix: "(more at Obálky knih)",
      annotation: "Summary",
      source: "Source: {source}",
      toc: "Table of contents",
      tocLink: "Table of contents (PDF, opens at Obálky knih)",
    },
  };
  var htmlLang = (document.documentElement.getAttribute("lang") || "en").toLowerCase();
  var T = /^(cs|sk)/.test(htmlLang) ? STRINGS.cs : STRINGS.en;

  function t(key, vars) {
    return T[key].replace(/\{(\w+)\}/g, function (_, k) {
      return vars && vars[k] != null ? vars[k] : "";
    });
  }

  // ------------------------------------------------------------ fetching

  var pending = {}; // key -> [resolve]
  var known = {}; // key -> item | null
  var queue = [];
  var timer = null;

  function lookupKey(key) {
    if (Object.prototype.hasOwnProperty.call(known, key)) return Promise.resolve(known[key]);
    return new Promise(function (resolve) {
      if (!pending[key]) {
        pending[key] = [];
        queue.push(key);
      }
      pending[key].push(resolve);
      if (!timer) timer = setTimeout(flush, 0);
    });
  }

  function flush() {
    timer = null;
    var keys = queue.splice(0, queue.length);
    for (var i = 0; i < keys.length; i += BATCH) request(keys.slice(i, i + BATCH));
  }

  function request(keys) {
    var params = new URLSearchParams();
    keys.forEach(function (k) {
      params.append(k.charAt(0) === "b" ? "biblionumber" : "isbn", k.slice(1));
    });
    params.append("interface", cfg.interface);
    fetch(cfg.api + "?" + params.toString(), {
      credentials: "same-origin",
      headers: { Accept: "application/json" },
    })
      .then(function (r) {
        return r.ok ? r.json() : { items: {} };
      })
      .catch(function () {
        return { items: {} };
      })
      .then(function (data) {
        var items = (data && data.items) || {};
        if (data && data.error && window.console) console.info("Obálky knih:", data.error);
        keys.forEach(function (k) {
          var item = items[k] || null;
          known[k] = item;
          (pending[k] || []).forEach(function (fn) {
            fn(item);
          });
          delete pending[k];
        });
      });
  }

  function lookup(opts) {
    var keys = [];
    (opts.biblionumbers || []).forEach(function (b) {
      if (/^\d+$/.test(String(b))) keys.push("b" + b);
    });
    (opts.isbns || []).forEach(function (i) {
      if (i) keys.push("i" + String(i).trim());
    });
    return Promise.all(keys.map(lookupKey)).then(function (vals) {
      var out = {};
      keys.forEach(function (k, n) {
        if (vals[n]) out[k] = vals[n];
      });
      return out;
    });
  }

  // ------------------------------------------------------------ building

  function coverUrl(item, size, keywords) {
    var url = item["cover_" + size + "_url"] || item.cover_medium_url;
    if (!url) return null;
    return url + (url.indexOf("?") < 0 ? "?" : "&") + "keywords=" + encodeURIComponent(keywords || "");
  }

  function searchKeywords() {
    var p = new URLSearchParams(location.search);
    return p.getAll("q").join(" ").slice(0, 200);
  }

  function makeImg(item, size, title, keywords, lazy) {
    var src = coverUrl(item, size, keywords);
    if (!src) return null;
    var img = document.createElement("img");
    // Obálky matches the catalogue origin; send only that, even on pages
    // with Referrer-Policy: no-referrer (set before src so it applies).
    img.referrerPolicy = "origin";
    img.src = src;
    img.alt = title ? t("coverOf", { title: title }) : t("cover");
    img.decoding = "async";
    if (lazy) img.loading = "lazy";
    var box = BOX[size] || BOX.medium;
    var w = item.orig_width,
      h = item.orig_height;
    // Reserve the right box up front so nothing jumps when the image arrives.
    if (w > 0 && h > 0) {
      var scale = Math.min(box[0] / w, box[1] / h, 1);
      img.width = Math.round(w * scale);
      img.height = Math.round(h * scale);
    } else {
      img.width = box[0];
      img.height = box[1];
    }
    img.className = "obalkyknih-img";
    return img;
  }

  function makeLink(item, child) {
    var a = document.createElement("a");
    a.href = item.backlink_url;
    a.className = "obalkyknih-link";
    a.appendChild(child);
    var sr = document.createElement("span");
    sr.className = "obalkyknih-sr";
    sr.textContent = " " + t("linkSuffix");
    a.appendChild(sr);
    return a;
  }

  function imgSettled(img) {
    return new Promise(function (resolve) {
      if (img.complete && img.naturalWidth > 1) return resolve(true);
      img.addEventListener("load", function () {
        resolve(img.naturalWidth > 1);
      });
      img.addEventListener("error", function () {
        resolve(false);
      });
    });
  }

  // ------------------------------------------------------- Koha sliders

  var holds = [];
  var kohaVerified = false;
  var wrappedVerify = false;

  // Lookups add image holds once they resolve, so wait until none are new.
  function allHolds() {
    var n = holds.length;
    return Promise.all(holds).then(function () {
      return holds.length > n ? allHolds() : null;
    });
  }

  // Koha's verify_cover_images() drops empty slides and whole empty
  // sliders on window load. Hold it until our images are in (or HOLD_MS).
  function wrapVerify() {
    var orig = window.verify_cover_images;
    if (typeof orig !== "function") return;
    wrappedVerify = true;
    // Some pages define verify_cover_images but never call it.
    window.addEventListener("load", function () {
      setTimeout(function () {
        if (kohaVerified) return;
        kohaVerified = true;
        document.querySelectorAll(".obalkyknih-coverimg[data-obalkyknih-pending]").forEach(function (div) {
          var slider = div.closest(".cover-slider, .cover-slides");
          if (slider && div.querySelector("img")) showLate(slider, slider.parentNode, div);
        });
      }, HOLD_MS + 6000);
    });
    window.verify_cover_images = function () {
      var self = this,
        args = arguments;
      var cap = new Promise(function (r) {
        setTimeout(r, HOLD_MS);
      });
      Promise.race([allHolds(), cap]).then(function () {
        kohaVerified = true;
        orig.apply(self, args);
        finishSlides();
      });
    };
  }

  // Our slides carry a bare <img> while Koha verifies them, so its lightbox
  // (which grabs every ".cover-image a") skips them; the backlink goes on now.
  function finishSlides() {
    document.querySelectorAll(".obalkyknih-coverimg[data-obalkyknih-pending]").forEach(function (div) {
      var img = div.querySelector("img");
      if (!img || !div.isConnected) return;
      div.removeAttribute("data-obalkyknih-pending");
      div.insertBefore(makeLink(div._okczItem, img), div.firstChild);
    });
  }

  function hasLocalCover(slider) {
    return !!slider.querySelector(".local-coverimg");
  }

  function addToSlider(slider, item, size, title, keywords) {
    if (!item || (cfg.localWins && hasLocalCover(slider))) return;
    if (slider.querySelector(".obalkyknih-coverimg")) return;
    var img = makeImg(item, size, title, keywords, false);
    if (!img) return;
    var div = document.createElement("div");
    div.className = "cover-image obalkyknih-coverimg";
    div.setAttribute("data-obalkyknih-pending", "");
    div._okczItem = item;
    div.appendChild(img);
    var hint = document.createElement("div");
    hint.className = "hint obalkyknih-credit";
    hint.textContent = t("credit");
    div.appendChild(hint);

    var parent = slider.parentNode;
    if (cfg.localWins) {
      slider.appendChild(div);
    } else {
      slider.insertBefore(div, slider.querySelector(".cover-image"));
    }

    var settled = imgSettled(img).then(function (ok) {
      if (!ok) {
        div.remove();
        return;
      }
      if (kohaVerified || !wrappedVerify) showLate(slider, parent, div);
    });
    holds.push(settled);
  }

  // Koha already ran (or never will): show the slide ourselves if the
  // slider has nothing visible, recreating a slider Koha removed as empty.
  function showLate(slider, parent, div) {
    if (!slider.isConnected) {
      if (!parent || !parent.isConnected) return;
      slider = document.createElement("div");
      slider.className = "cover-slider";
      parent.appendChild(slider);
      slider.appendChild(div);
    }
    var visible = Array.prototype.some.call(slider.querySelectorAll(".cover-image"), function (el) {
      return el !== div && el.offsetParent !== null;
    });
    if (!visible) {
      div.style.display = "block";
      slider.classList.remove("cover-slides");
    }
    finishSlides();
  }

  function titleOf(el) {
    return (el && (el.getAttribute("data-title") || "").trim()) || "";
  }

  function detailTitle() {
    var h = document.querySelector("#catalogue_detail_biblio .title, #catalogue_detail_biblio h1, h1.title");
    return h ? h.textContent.replace(/\s+/g, " ").replace(/[\s/:;,.]+$/, "").trim() : "";
  }

  function urlBiblionumber() {
    return new URLSearchParams(location.search).get("biblionumber");
  }

  function sliders() {
    var found = [];
    var detailSlider = document.querySelector("#biblio-cover-slider");
    var detailRoot = document.querySelector("#catalogue_detail_biblio");
    if (detailSlider) {
      var bn = (detailRoot && detailRoot.getAttribute("data-biblionumber")) || urlBiblionumber();
      if (bn) found.push({ el: detailSlider, bn: bn, size: cfg.sizeDetail, title: detailTitle(), detail: true });
    }
    // OPAC results and lists (24.11+), staff results.
    document.querySelectorAll(".cover-slider[data-biblionumber], td.bookcoverimg[data-biblionumber] .cover-slides").forEach(function (el) {
      if (el === detailSlider) return;
      var holder = el.hasAttribute("data-biblionumber") ? el : el.closest("[data-biblionumber]");
      var bn = holder && holder.getAttribute("data-biblionumber");
      if (!/^\d+$/.test(bn || "")) return;
      var title = titleOf(el) || titleOf(el.closest("[data-title]"));
      found.push({ el: el, bn: bn, size: cfg.sizeResults, title: title });
    });
    // OPAC lists in 24.11 have no slider: div.coverimages > a.p1.
    document.querySelectorAll("#opac-lists .coverimages, #opac-userlists .coverimages").forEach(function (box) {
      if (box.querySelector(".cover-slider")) return;
      var link = box.querySelector('a[href*="biblionumber="]');
      var m = link && /biblionumber=(\d+)/.exec(link.getAttribute("href"));
      if (!m) return;
      var slider = document.createElement("div");
      slider.className = "cover-slider";
      box.appendChild(slider);
      found.push({ el: slider, bn: m[1], size: cfg.sizeResults, title: "" });
    });
    return found;
  }

  // -------------------------------------------- annotation and contents

  function addExtras(item) {
    if (!item || (!cfg.showAnnotation && !cfg.showToc)) return;
    var root = document.querySelector("#catalogue_detail_biblio");
    if (!root || root.querySelector(".obalkyknih-extra")) return;
    var hasAnnot = cfg.showAnnotation && item.annotation && item.annotation.text;
    var hasToc = cfg.showToc && item.toc_thumbnail_url && item.toc_pdf_url;
    if (!hasAnnot && !hasToc) return;

    var sec = document.createElement("section");
    sec.className = "obalkyknih-extra";
    var level = cfg.interface === "staff" ? "h3" : "h2";

    if (hasAnnot) {
      var h = document.createElement(level);
      h.id = "obalkyknih-annotation";
      h.textContent = t("annotation");
      var p = document.createElement("p");
      p.className = "obalkyknih-annotation";
      p.textContent = item.annotation.text;
      sec.appendChild(h);
      sec.appendChild(p);
      var src = document.createElement("p");
      src.className = "obalkyknih-source";
      if (item.annotation.source) src.appendChild(document.createTextNode(t("source", { source: item.annotation.source }) + " · "));
      var credit = document.createElement("a");
      credit.href = item.backlink_url;
      credit.textContent = t("credit");
      src.appendChild(credit);
      sec.appendChild(src);
    }
    if (hasToc) {
      var h2 = document.createElement(level);
      h2.textContent = t("toc");
      sec.appendChild(h2);
      var a = document.createElement("a");
      a.href = item.toc_pdf_url;
      a.referrerPolicy = "origin";
      a.className = "obalkyknih-toc";
      var img = document.createElement("img");
      img.referrerPolicy = "origin";
      img.src = item.toc_thumbnail_url;
      img.alt = t("tocLink");
      img.width = 170;
      img.height = 240;
      img.loading = "lazy";
      img.decoding = "async";
      img.addEventListener("error", function () {
        a.remove();
        h2.remove();
      });
      a.appendChild(img);
      sec.appendChild(a);
    }
    root.appendChild(sec);
  }

  // ----------------------------------------------------- custom elements

  // <span data-obalkyknih-biblionumber="12" data-obalkyknih-size="medium">
  //   fallback content, e.g. a local cover
  // </span>
  // The content is replaced only when Obálky has a cover. The element gets
  // data-obalkyknih-state="cover" or "none".
  function renderElement(el) {
    if (el.hasAttribute("data-obalkyknih-state")) return Promise.resolve();
    el.setAttribute("data-obalkyknih-state", "loading");
    var bn = el.getAttribute("data-obalkyknih-biblionumber");
    var isbn = el.getAttribute("data-obalkyknih-isbn");
    var key = bn ? "b" + bn : isbn ? "i" + isbn.trim() : null;
    if (!key) {
      el.setAttribute("data-obalkyknih-state", "none");
      return Promise.resolve();
    }
    var size = el.getAttribute("data-obalkyknih-size") || cfg.sizeResults || "medium";
    var keywords = el.getAttribute("data-obalkyknih-keywords");
    if (keywords == null) keywords = cfg.sigla ? "advert" + cfg.sigla + " novinky" : "";
    var title = el.getAttribute("data-obalkyknih-title") || "";
    var keepLocal = cfg.localWins && el.hasAttribute("data-obalkyknih-local");
    return lookupKey(key).then(function (item) {
      if (!item || keepLocal) {
        el.setAttribute("data-obalkyknih-state", "none");
        return;
      }
      var img = makeImg(item, size, title, keywords, true);
      if (!img) {
        el.setAttribute("data-obalkyknih-state", "none");
        return;
      }
      var link = makeLink(item, img);
      // Swap only once the image really loaded, so a missing cover keeps
      // the fallback instead of showing a broken image.
      var probe = new Image();
      probe.referrerPolicy = "origin";
      probe.onload = function () {
        if (probe.naturalWidth <= 1) return el.setAttribute("data-obalkyknih-state", "none");
        el.replaceChildren(link);
        el.setAttribute("data-obalkyknih-state", "cover");
        el.dispatchEvent(new CustomEvent("obalkyknih:cover", { bubbles: true, detail: item }));
      };
      probe.onerror = function () {
        el.setAttribute("data-obalkyknih-state", "none");
      };
      probe.src = img.src;
    });
  }

  function scan(root) {
    var els = (root || document).querySelectorAll("[data-obalkyknih-biblionumber], [data-obalkyknih-isbn]");
    return Promise.all(Array.prototype.map.call(els, renderElement));
  }

  // ------------------------------------------------------------- start

  function start() {
    wrapVerify();
    var keywords = searchKeywords();
    sliders().forEach(function (s) {
      var key = "b" + s.bn;
      var hold = lookupKey(key).then(function (item) {
        addToSlider(s.el, item, s.size || "medium", s.title, keywords);
        if (s.detail) addExtras(item);
      });
      holds.push(hold);
    });
    scan(document);
  }

  window.ObalkyKnih = {
    version: "1",
    config: cfg,
    lookup: lookup,
    coverUrl: coverUrl,
    scan: scan,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
