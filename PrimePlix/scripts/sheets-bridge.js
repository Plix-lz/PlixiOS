/**
 * Puente entre Google Sheets y la UI existente de Plix.
 * No reemplaza el HTML estático: solo enriquece cuando hay datos
 * y la API está configurada. Si falla Sheets, la web sigue igual.
 */
(function () {
  "use strict";

  var toastEl = null;
  var playerEl = null;

  function cfg() {
    return window.PLIX_SHEETS_CONFIG || {};
  }

  function ensureToast() {
    if (toastEl) return toastEl;
    toastEl = document.createElement("div");
    toastEl.className = "plix-sheets-toast";
    toastEl.setAttribute("role", "status");
    toastEl.setAttribute("aria-live", "polite");
    toastEl.hidden = true;
    document.body.appendChild(toastEl);
    return toastEl;
  }

  function showToast(message, isError) {
    if (cfg().showErrorToast === false) return;
    var el = ensureToast();
    el.textContent = message;
    el.classList.toggle("is-error", Boolean(isError));
    el.hidden = false;
    clearTimeout(showToast._t);
    showToast._t = setTimeout(function () {
      el.hidden = true;
    }, 6000);
  }

  function ensurePlayer() {
    if (playerEl) return playerEl;
    playerEl = document.createElement("div");
    playerEl.className = "plix-player-overlay";
    playerEl.id = "plix-player-overlay";
    playerEl.hidden = true;
    playerEl.innerHTML =
      '<div class="plix-player-dialog" role="dialog" aria-modal="true" aria-label="Reproductor">' +
      '<div class="plix-player-toolbar">' +
      '<label class="plix-player-server-wrap" hidden>' +
      '<span class="sr-only">Servidor</span>' +
      '<select class="plix-player-server" aria-label="Seleccionar servidor"></select>' +
      "</label>" +
      '<button type="button" class="plix-player-close" aria-label="Cerrar reproductor">&times;</button>' +
      "</div>" +
      '<div class="plix-player-frame-wrap"><iframe class="plix-player-frame" title="Video" allowfullscreen allow="autoplay; encrypted-media; picture-in-picture" referrerpolicy="no-referrer"></iframe></div>' +
      '<p class="plix-player-note">El enlace de reproducción llega al navegador; ocultarlo en el código no lo protege.</p>' +
      "</div>";
    document.body.appendChild(playerEl);

    playerEl.querySelector(".plix-player-close").addEventListener("click", closePlayer);
    playerEl.addEventListener("click", function (e) {
      if (e.target === playerEl) closePlayer();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && playerEl && !playerEl.hidden) closePlayer();
    });
    return playerEl;
  }

  function closePlayer() {
    if (!playerEl) return;
    var frame = playerEl.querySelector(".plix-player-frame");
    if (frame) frame.src = "about:blank";
    playerEl.hidden = true;
    document.body.classList.remove("plix-player-open");
  }

  function openPlayer(sources, meta) {
    sources = (sources || []).filter(function (s) {
      return s && s.url;
    });
    if (!sources.length) {
      showToast("No hay URL de video para este título en Sheets.", true);
      return;
    }

    var el = ensurePlayer();
    var select = el.querySelector(".plix-player-server");
    var wrap = el.querySelector(".plix-player-server-wrap");
    var frame = el.querySelector(".plix-player-frame");

    select.innerHTML = "";
    sources.forEach(function (s, i) {
      var opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = s.label || s.server || s.language || "Opción " + (i + 1);
      select.appendChild(opt);
    });
    wrap.hidden = sources.length < 2;

    function load(index) {
      var src = sources[Number(index)] || sources[0];
      frame.src = src.url;
    }

    select.onchange = function () {
      load(select.value);
    };
    load(0);

    el.hidden = false;
    document.body.classList.add("plix-player-open");
    el.querySelector(".plix-player-close").focus();

    if (meta && meta.title) {
      el.setAttribute("aria-label", "Reproduciendo: " + meta.title);
    }
  }

  function collectPlaySources(item, servers) {
    var sources = [];
    if (item && item.videoUrl) {
      sources.push({
        url: item.videoUrl,
        server: item.server || "Principal",
        language: item.language || "",
        label: (item.server || "Principal") + (item.language ? " · " + item.language : "")
      });
    }
    (servers || []).forEach(function (s) {
      var url = s.videoUrl || s.url;
      if (!url) return;
      if (sources.some(function (x) {
        return x.url === url;
      })) {
        return;
      }
      sources.push({
        url: url,
        server: s.server || s.title || "Servidor",
        language: s.language || "",
        label:
          (s.server || s.title || "Servidor") +
          (s.language ? " · " + s.language : "")
      });
    });
    return sources;
  }

  function cardQuery(card) {
    if (!card) return {};
    return {
      tmdbId: card.getAttribute("data-tmdb-id") || "",
      id: card.getAttribute("data-content-id") || "",
      title:
        card.querySelector(".content-tooltip-title")?.textContent?.trim() ||
        card.querySelector(".content-image")?.getAttribute("alt")?.trim() ||
        ""
    };
  }

  function contentTypeOf(item, fallback) {
    var t = String((item && item.type) || fallback || "").toLowerCase();
    if (t.indexOf("serie") !== -1 || t === "tv" || t === "show") return "series";
    if (t.indexOf("pel") !== -1 || t === "movie" || t === "film") return "movie";
    return fallback === "series" ? "series" : "movie";
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function placeholderCover(title) {
    var label = String(title || "Plix")
      .slice(0, 22)
      .replace(/[<>&'"]/g, "");
    var svg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="600">' +
      '<rect fill="#1a242f" width="100%" height="100%"/>' +
      '<text x="50%" y="50%" fill="#9aa4af" text-anchor="middle" font-family="Arial,sans-serif" font-size="18">' +
      label +
      "</text></svg>";
    return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
  }

  function buildCardElement(item, defaultType) {
    var title = item.title || "Sin título";
    var cover = item.cover || placeholderCover(title);
    var synopsis = item.synopsis || "Disponible en Plix.";
    var year = item.year || "";
    var runtime = item.runtime || "";
    var type = contentTypeOf(item, defaultType);
    var maturity = item.maturity || (type === "series" ? "13+" : "13+");
    var tmdbId = item.tmdbId || "";
    var contentId = item.id || (tmdbId ? "tmdb-" + tmdbId : "");
    var videoUrl = item.videoUrl || item.url || "";

    var card = document.createElement("div");
    card.className = "content";
    card.setAttribute("data-sheets-generated", "1");
    if (tmdbId) card.setAttribute("data-tmdb-id", tmdbId);
    if (contentId) card.setAttribute("data-content-id", contentId);
    card.setAttribute("data-type", type);
    if (videoUrl) {
      card.setAttribute("data-has-stream", "1");
      card.setAttribute("data-video-url", videoUrl);
    }

    card.innerHTML =
      '<div class="content-container">' +
      '<div class="image-container">' +
      '<img class="content-image" src="' +
      escapeHtml(cover) +
      '" alt="' +
      escapeHtml(title) +
      '" loading="lazy" data-sheets-cover="1">' +
      '<div class="content-image-shadow"></div>' +
      "</div>" +
      '<div class="content-description">' +
      '<p class="content-tooltip-title">' +
      escapeHtml(title) +
      "</p>" +
      '<p class="prime-text"><span class="prime-check" aria-hidden="true"></span> Se incluye con Prime</p>' +
      '<div class="content-actions">' +
      '<a href="#" class="play-button"><i class="fa fa-play" aria-hidden="true"></i><span>Reproducir</span></a>' +
      '<button type="button" class="action-btn details-btn" aria-label="Más información">' +
      '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">' +
      '<rect x="3" y="5" width="18" height="12" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.8"/>' +
      '<circle cx="9" cy="20" r="1.2" fill="currentColor"/>' +
      '<circle cx="15" cy="20" r="1.2" fill="currentColor"/>' +
      "</svg></button>" +
      '<button type="button" class="action-btn add-btn" aria-label="Añadir a Mi lista">' +
      '<img src="icons/plus.png" alt=""></button>' +
      '<button type="button" class="action-btn hide-btn" aria-label="No me interesa">' +
      '<img src="icons/cancel.png" alt=""></button>' +
      "</div>" +
      '<div class="content-meta">' +
      '<span class="age-rating">' +
      escapeHtml(maturity) +
      "</span>" +
      '<img class="cc-icon" src="icons/subtitles.png" alt="Subtítulos">' +
      (year ? '<span class="year">' + escapeHtml(year) + "</span>" : "") +
      (runtime ? '<span class="runtime">' + escapeHtml(runtime) + "</span>" : "") +
      "</div>" +
      '<p class="content-tooltip-description">' +
      escapeHtml(synopsis) +
      "</p>" +
      "</div>" +
      "</div>";

    return card;
  }

  function wireCatalogRowControls(section) {
    if (!section || section.getAttribute("data-row-wired") === "1") return;
    var row = section.querySelector(".content-row");
    var prev = section.querySelector(".row-prev");
    var next = section.querySelector(".row-next");
    if (!row || !prev || !next) return;
    section.setAttribute("data-row-wired", "1");

    function scrollAmount() {
      return Math.max(row.clientWidth * 0.75, 220);
    }

    function updateButtons() {
      var maxScroll = Math.max(row.scrollWidth - row.clientWidth, 0);
      prev.disabled = row.scrollLeft <= 2;
      next.disabled = row.scrollLeft >= maxScroll - 2;
    }

    prev.addEventListener("click", function () {
      row.scrollBy({ left: -scrollAmount(), behavior: "smooth" });
    });
    next.addEventListener("click", function () {
      row.scrollBy({ left: scrollAmount(), behavior: "smooth" });
    });
    row.addEventListener("scroll", updateButtons, { passive: true });
    window.addEventListener("resize", updateButtons);
    updateButtons();
  }

  function renderCatalogRow(rowCfg, items) {
    var rowEl = document.querySelector(rowCfg.selector);
    var section = rowCfg.section ? document.querySelector(rowCfg.section) : null;
    if (!rowEl) return;

    rowEl.innerHTML = "";
    var defaultType = rowCfg.key === "series" ? "series" : "movie";
    var list = (items || []).filter(function (item) {
      return item && item.tmdbId;
    });

    if (!list.length) {
      if (section) section.hidden = true;
      return;
    }

    list.forEach(function (item) {
      rowEl.appendChild(buildCardElement(item, defaultType));
    });

    if (section) {
      section.hidden = false;
      wireCatalogRowControls(section);
    }
  }

  /**
   * Quita del DOM todo contenido que no venga de Sheets / no tenga ID en la hoja.
   * Evita “fantasmas” del HTML estático de demo.
   */
  function purgeGhostContent(knownIds) {
    knownIds = knownIds || Object.create(null);
    var only = cfg().onlyFromSheets !== false;

    document.querySelectorAll(".content").forEach(function (card) {
      var generated = card.getAttribute("data-sheets-generated") === "1";
      var tmdbId = card.getAttribute("data-tmdb-id") || "";
      var inSheets = tmdbId && knownIds[String(tmdbId)];

      if (generated && inSheets) return;
      if (!only && inSheets) return;

      card.remove();
    });

    document.querySelectorAll(".content-area").forEach(function (section) {
      var isCatalog = section.hasAttribute("data-sheets-catalog");
      var cards = section.querySelectorAll(".content");
      if (!cards.length) {
        if (isCatalog) section.hidden = true;
        else if (only) {
          section.hidden = true;
          section.setAttribute("data-plix-ghost-hidden", "1");
        }
        return;
      }
      if (isCatalog) section.hidden = false;
    });

    if (only && cfg().hideStaticHero !== false) {
      var hero = document.getElementById("heroSlider");
      if (hero) {
        hero.hidden = true;
        hero.setAttribute("data-plix-ghost-hidden", "1");
      }
    }

    document.body.classList.toggle("plix-only-sheets", only);
  }

  function hideStaticDemoUntilSheets() {
    if (cfg().onlyFromSheets === false) return;
    if (!window.PlixSheets || !PlixSheets.isConfigured()) return;

    document.body.classList.add("plix-only-sheets");
    document.querySelectorAll(".content-area:not([data-sheets-catalog])").forEach(function (section) {
      section.hidden = true;
      section.setAttribute("data-plix-ghost-hidden", "1");
    });
    if (cfg().hideStaticHero !== false) {
      var hero = document.getElementById("heroSlider");
      if (hero) {
        hero.hidden = true;
        hero.setAttribute("data-plix-ghost-hidden", "1");
      }
    }
  }

  function collectKnownTmdbIds(results) {
    var known = Object.create(null);
    (results || []).forEach(function (res) {
      (res.data || []).forEach(function (item) {
        if (item && item.tmdbId) known[String(item.tmdbId)] = true;
      });
    });
    return known;
  }

  function ensureEmptyCatalogNotice(totalCount, apiFailed) {
    var host = document.querySelector(".all-contents-area");
    if (!host) return;
    var existing = document.getElementById("plix-sheets-empty");
    if (totalCount > 0) {
      if (existing) existing.remove();
      return;
    }
    var msg = apiFailed
      ? "No se pudo leer Google Sheets. En Apps Script: Implementar → Nueva implementación → Aplicación web → Quién tiene acceso: Cualquiera. Luego pega la nueva URL /exec en scripts/sheets-config.js."
      : "No llegaron títulos con TMDB ID desde LzPlus. Revisa la columna E y que el deploy de Apps Script tenga acceso «Cualquiera».";
    if (existing) {
      existing.textContent = msg;
      return;
    }
    var note = document.createElement("p");
    note.id = "plix-sheets-empty";
    note.className = "plix-sheets-empty";
    note.textContent = msg;
    host.insertBefore(note, host.firstChild);
  }

  function renderCatalogFromSheets() {
    var catalog = cfg().catalog;
    if (!catalog || catalog.enabled === false) return Promise.resolve([]);
    if (!window.PlixSheets || !PlixSheets.isConfigured()) return Promise.resolve([]);

    var rows = catalog.rows || [];
    var anyFailed = false;

    return Promise.all(
      rows.map(function (rowCfg) {
        return PlixSheets.getCatalogItems(rowCfg.key)
          .then(function (res) {
            renderCatalogRow(rowCfg, res.data || []);
            return { ok: true, res: res };
          })
          .catch(function (err) {
            anyFailed = true;
            renderCatalogRow(rowCfg, []);
            return { ok: false, error: err, res: { data: [] } };
          });
      })
    ).then(function (results) {
      var known = collectKnownTmdbIds(
        results.map(function (r) {
          return r.res;
        })
      );
      purgeGhostContent(known);
      var total = Object.keys(known).length;
      ensureEmptyCatalogNotice(total, anyFailed && total === 0);
      return results;
    });
  }

  function attachStreamFromSheets(card, item) {
    if (!card || !item) return;
    var videoUrl = item.videoUrl || item.url || "";
    if (item.tmdbId) card.setAttribute("data-tmdb-id", item.tmdbId);
    if (item.id) card.setAttribute("data-content-id", item.id);
    if (videoUrl) {
      card.setAttribute("data-video-url", videoUrl);
      card.setAttribute("data-has-stream", "1");
    }
  }

  function enrichCard(card, item) {
    if (!card || !item) return;
    attachStreamFromSheets(card, item);
    card.setAttribute("data-type", contentTypeOf(item, card.getAttribute("data-type")));
    if (item.cover) {
      var img = card.querySelector(".content-image");
      if (img) {
        img.setAttribute("src", item.cover);
        img.setAttribute("data-sheets-cover", "1");
        if (item.title) img.setAttribute("alt", item.title);
      }
    }
    if (item.title) {
      var titleEl = card.querySelector(".content-tooltip-title");
      if (titleEl) titleEl.textContent = item.title;
    }
    if (item.synopsis) {
      var syn = card.querySelector(".content-tooltip-description");
      if (syn) syn.textContent = item.synopsis;
    }
    if (item.year) {
      var yearEl = card.querySelector(".year");
      if (yearEl) yearEl.textContent = item.year;
    }
    if (item.runtime) {
      var rt = card.querySelector(".runtime");
      if (rt) rt.textContent = item.runtime;
    }
  }

  /**
   * Carga en cada card la URL de Sheets (col B) buscando por TMDB ID (col E).
   * Si la card ya tiene data-tmdb-id, usa ese ID. Si no, intenta por título.
   */
  function bindVideoUrlsByTmdbId() {
    if (!window.PlixSheets || !PlixSheets.isConfigured()) return Promise.resolve();

    return Promise.all([
      PlixSheets.getSheet("movies").catch(function () {
        return { data: [] };
      }),
      PlixSheets.getSheet("series").catch(function () {
        return { data: [] };
      })
    ]).then(function (results) {
      var all = (results[0].data || []).concat(results[1].data || []);
      var byId = Object.create(null);
      all.forEach(function (row) {
        if (!row || !row.tmdbId) return;
        byId[String(row.tmdbId)] = row;
      });

      document.querySelectorAll(".content").forEach(function (card) {
        var tmdbId = card.getAttribute("data-tmdb-id") || "";
        var item = null;
        if (tmdbId && byId[String(tmdbId)]) {
          item = byId[String(tmdbId)];
        } else {
          item = PlixSheets.findInRows(all, cardQuery(card));
        }
        if (item) attachStreamFromSheets(card, item);
      });
    });
  }

  function enrichCardsFromSheets() {
    if (!window.PlixSheets || !PlixSheets.isConfigured()) return Promise.resolve();
    /* Con onlyFromSheets el HTML estático se elimina; no hace falta enriquecer fantasmas. */
    if (cfg().onlyFromSheets !== false) return Promise.resolve();

    return Promise.all([
      PlixSheets.getSheet("movies").catch(function () {
        return { data: [] };
      }),
      PlixSheets.getSheet("series").catch(function () {
        return { data: [] };
      })
    ]).then(function (results) {
      var all = (results[0].data || []).concat(results[1].data || []);
      document.querySelectorAll(".content:not([data-sheets-generated])").forEach(function (card) {
        var q = cardQuery(card);
        var match = PlixSheets.findInRows(all, q);
        if (match) enrichCard(card, match);
      });
    });
  }

  function mergeDetailData(base, sheetItem, episodes) {
    if (!sheetItem) return base;
    var next = Object.assign({}, base);
    if (sheetItem.title) next.title = sheetItem.title;
    if (sheetItem.cover) next.img = sheetItem.cover;
    if (sheetItem.backdrop) next.backdrop = sheetItem.backdrop;
    if (sheetItem.synopsis) next.synopsis = sheetItem.synopsis;
    if (sheetItem.year) next.year = sheetItem.year;
    if (sheetItem.runtime) next.runtime = sheetItem.runtime;
    if (sheetItem.maturity) next.maturity = sheetItem.maturity;
    next.tmdbId = sheetItem.tmdbId || base.tmdbId || "";
    next.contentId = sheetItem.id || base.contentId || "";
    next.videoUrl = sheetItem.videoUrl || "";
    next.server = sheetItem.server || "";
    next.fromSheets = true;

    if (episodes && episodes.length) {
      next.sheetEpisodes = episodes.map(function (ep, i) {
        return {
          n: Number(ep.episode) || i + 1,
          title: ep.title || "Episodio " + (Number(ep.episode) || i + 1),
          synopsis: ep.synopsis || base.synopsis || "",
          runtime: ep.runtime || "",
          date: "",
          maturity: ep.maturity || base.maturity || "13+",
          img: ep.cover || base.img,
          videoUrl: ep.videoUrl || ep.url || "",
          server: ep.server || "",
          language: ep.language || "",
          season: ep.season || "1"
        };
      });
      var seasons = {};
      episodes.forEach(function (ep) {
        var s = String(ep.season || "1");
        seasons[s] = true;
      });
      var seasonKeys = Object.keys(seasons).sort(function (a, b) {
        return Number(a) - Number(b);
      });
      if (seasonKeys.length) {
        next.seasons = seasonKeys.map(function (s) {
          return "Temporada " + s;
        });
        next.seasonCount =
          seasonKeys.length +
          (seasonKeys.length === 1 ? " temporada" : " temporadas");
        next.type = "series";
      }
    }
    return next;
  }

  function resolvePlayForCard(card) {
    if (!card) return Promise.resolve(null);

    var inlineUrl = card.getAttribute("data-video-url") || "";
    var tmdbId = card.getAttribute("data-tmdb-id") || "";
    var q = cardQuery(card);

    /* 1) URL ya cargada desde Sheets (ID → col B) */
    if (inlineUrl) {
      return Promise.resolve({
        item: {
          videoUrl: inlineUrl,
          tmdbId: tmdbId,
          id: card.getAttribute("data-content-id") || "",
          title: q.title || ""
        },
        servers: []
      });
    }

    if (!window.PlixSheets || !PlixSheets.isConfigured()) {
      return Promise.resolve(null);
    }

    /* 2) Buscar por TMDB ID en Sheets (col E → URL col B) */
    var lookup = tmdbId
      ? PlixSheets.findByTmdbId(tmdbId)
      : PlixSheets.findContent(q);

    return lookup
      .then(function (item) {
        if (!item) return null;
        if (item.videoUrl || item.url) {
          attachStreamFromSheets(card, item);
        }
        return PlixSheets.getServersFor({
          id: item.id,
          tmdbId: item.tmdbId,
          title: item.title
        })
          .catch(function () {
            return [];
          })
          .then(function (servers) {
            return { item: item, servers: servers };
          });
      })
      .catch(function () {
        return null;
      });
  }

  function wirePlayClicks() {
    document.addEventListener(
      "click",
      function (e) {
        var play =
          e.target.closest(".play-button") ||
          e.target.closest(".hero-btn-play") ||
          e.target.closest(".detail-play") ||
          e.target.closest(".detail-episode-play");
        if (!play) return;
        if (!window.PlixSheets || !PlixSheets.isConfigured()) return;

        var card = play.closest(".content");
        var episodeBtn = play.classList.contains("detail-episode-play");

        if (episodeBtn) {
          var epArticle = play.closest(".detail-episode");
          var videoUrl = epArticle && epArticle.getAttribute("data-video-url");
          if (videoUrl) {
            e.preventDefault();
            e.stopPropagation();
            openPlayer(
              [
                {
                  url: videoUrl,
                  label: epArticle.getAttribute("data-server") || "Servidor"
                }
              ],
              { title: epArticle.querySelector("h3")?.textContent || "Episodio" }
            );
          }
          return;
        }

        if (play.classList.contains("detail-play")) {
          e.preventDefault();
          e.stopPropagation();
          var root = document.querySelector(".detail-root");
          var title = root?.querySelector(".detail-title")?.textContent?.trim() || "";
          var tmdbId = root?.getAttribute("data-tmdb-id") || "";
          var contentId = root?.getAttribute("data-content-id") || "";
          var inlineVideo = root?.getAttribute("data-video-url") || "";

          if (inlineVideo) {
            PlixSheets.getServersFor({ id: contentId, tmdbId: tmdbId, title: title })
              .catch(function () {
                return [];
              })
              .then(function (servers) {
                openPlayer(
                  collectPlaySources(
                    { videoUrl: inlineVideo, server: root.getAttribute("data-server") || "" },
                    servers
                  ),
                  { title: title }
                );
              });
            return;
          }

          PlixSheets.findContent({ tmdbId: tmdbId, id: contentId, title: title })
            .then(function (item) {
              if (!item) {
                showToast("Sin URL de video en Sheets para este título.", true);
                return;
              }
              return PlixSheets.getServersFor({
                id: item.id,
                tmdbId: item.tmdbId,
                title: item.title
              }).then(function (servers) {
                openPlayer(collectPlaySources(item, servers), { title: item.title });
              });
            })
            .catch(function () {
              showToast("No se pudo cargar el video desde Sheets.", true);
            });
          return;
        }

        if (!card) return;

        e.preventDefault();
        e.stopPropagation();
        resolvePlayForCard(card).then(function (pack) {
          if (!pack || !pack.item) {
            showToast("Sin coincidencia en Sheets. Se mantiene el contenido local.", true);
            if (window.PlixDetail && typeof PlixDetail.openFromCard === "function") {
              PlixDetail.openFromCard(card);
            }
            return;
          }
          var sources = collectPlaySources(pack.item, pack.servers);
          if (!sources.length) {
            if (window.PlixDetail) PlixDetail.openFromCard(card);
            showToast("Hay ficha en Sheets pero sin url_video / servidores.", true);
            return;
          }
          openPlayer(sources, { title: pack.item.title });
        });
      },
      true
    );
  }

  function patchDetailApi() {
    if (!window.PlixDetail || !window.PlixSheets) return;

    var originalOpen = PlixDetail.openFromCard;
    if (typeof originalOpen !== "function") return;

    PlixDetail.openFromCard = function (card) {
      if (!PlixSheets.isConfigured()) {
        originalOpen(card);
        return;
      }

      var q = cardQuery(card);
      var baseOpen = function () {
        originalOpen(card);
      };

      Promise.all([
        PlixSheets.findContent(q).catch(function () {
          return null;
        }),
        PlixSheets.getEpisodesFor(q).catch(function () {
          return [];
        })
      ])
        .then(function (results) {
          var item = results[0];
          var episodes = results[1] || [];
          if (!item && !episodes.length) {
            baseOpen();
            return;
          }

          /* Extrae base del DOM y fusiona; reutiliza open() del detalle */
          var title =
            q.title ||
            card.querySelector(".content-tooltip-title")?.textContent?.trim() ||
            "Título";
          var img =
            card.querySelector(".content-image")?.getAttribute("src") || "";
          var synopsis =
            card.querySelector(".content-tooltip-description")?.textContent?.trim() ||
            "";
          var type =
            card.getAttribute("data-type") === "series" ||
            /t\d+|temporada|serie/i.test(title)
              ? "series"
              : "movie";
          if (item && item.type) {
            if (item.type.indexOf("serie") !== -1) type = "series";
            else if (item.type.indexOf("pel") !== -1 || item.type === "movie") type = "movie";
          }

          var base = {
            type: type,
            title: title,
            img: img,
            synopsis: synopsis || "Descubre esta historia disponible en Plix.",
            runtime: card.querySelector(".runtime")?.textContent?.trim() || "",
            year: card.querySelector(".year")?.textContent?.trim() || "2024",
            genres: ["Drama"],
            maturity: card.querySelector(".age-rating")?.textContent?.trim() || "13+",
            imdb: type === "series" ? "8,0" : "5,8",
            cast:
              type === "series"
                ? ["Elenco principal", "Actriz invitada", "Actor secundario"]
                : ["Protagonista", "Coprotagonista", "Reparto"],
            labelBadge: "",
            hvm: { icon: "trending", text: "Disponible en Plix" },
            seasons: type === "series" ? ["Temporada 1"] : [],
            seasonCount: type === "series" ? "1 temporada" : ""
          };

          var merged = mergeDetailData(base, item, episodes);
          PlixDetail.open(merged);

          requestAnimationFrame(function () {
            var root = document.querySelector(".detail-root");
            if (!root) return;
            if (merged.tmdbId) root.setAttribute("data-tmdb-id", merged.tmdbId);
            if (merged.contentId) root.setAttribute("data-content-id", merged.contentId);
            if (merged.videoUrl) root.setAttribute("data-video-url", merged.videoUrl);
            if (merged.server) root.setAttribute("data-server", merged.server);

            if (merged.sheetEpisodes && merged.sheetEpisodes.length) {
              var epPanel = root.querySelector('[data-panel="episodes"] .detail-episodes');
              var count = root.querySelector(".detail-episodes-header .detail-section-title");
              if (epPanel && window.PlixDetailRenderEpisodes) {
                epPanel.innerHTML = PlixDetailRenderEpisodes(merged.sheetEpisodes);
                if (count) {
                  count.textContent = merged.sheetEpisodes.length + " episodios";
                }
                epPanel.querySelectorAll(".detail-episode").forEach(function (node, i) {
                  var ep = merged.sheetEpisodes[i];
                  if (ep && ep.videoUrl) node.setAttribute("data-video-url", ep.videoUrl);
                  if (ep && ep.server) node.setAttribute("data-server", ep.server);
                });
              }
            }
          });
        })
        .catch(function () {
          baseOpen();
        });
    };
  }

  function init() {
    if (!window.PlixSheets) return;

    PlixSheets.onError(function (err) {
      var only = cfg().onlyFromSheets !== false;
      showToast(
        only
          ? "No se pudo cargar Google Sheets. Sin IDs no se muestran títulos. (" +
              (err && err.message ? err.message : "error") +
              ")"
          : "No se pudo actualizar desde Google Sheets. Se muestra el contenido local. (" +
              (err && err.message ? err.message : "error") +
              ")",
        true
      );
      if (only) {
        purgeGhostContent(Object.create(null));
        ensureEmptyCatalogNotice(0);
      }
    });

    wirePlayClicks();
    patchDetailApi();

    if (!PlixSheets.isConfigured()) return;

    hideStaticDemoUntilSheets();

    /* Evita reutilizar un caché vacío/fallido de pruebas anteriores. */
    try {
      PlixSheets.clearCache();
    } catch (err) {
      /* ignore */
    }

    PlixSheets.prefetch()
      .then(function () {
        return renderCatalogFromSheets();
      })
      .then(function () {
        return enrichCardsFromSheets();
      })
      .then(function () {
        return bindVideoUrlsByTmdbId();
      })
      .catch(function () {
        /* ya notificado por onError */
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  window.PlixSheetsBridge = {
    openPlayer: openPlayer,
    closePlayer: closePlayer,
    enrichCardsFromSheets: enrichCardsFromSheets,
    bindVideoUrlsByTmdbId: bindVideoUrlsByTmdbId,
    renderCatalogFromSheets: renderCatalogFromSheets,
    showToast: showToast
  };
})();
