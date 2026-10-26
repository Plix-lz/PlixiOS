/**
 * Cliente reutilizable para la API de Google Apps Script (solo lectura).
 * Compatible con GitHub Pages: fetch JSON + fallback JSONP.
 */
(function (global) {
  "use strict";

  var STORAGE_PREFIX = "plix-sheets-cache:";
  var cache = Object.create(null);
  var inflight = Object.create(null);
  var lastError = null;
  var listeners = [];

  function getConfig() {
    return global.PLIX_SHEETS_CONFIG || {};
  }

  function isConfigured() {
    var url = (getConfig().apiUrl || "").trim();
    return Boolean(url);
  }

  function sheetName(key) {
    var sheets = getConfig().sheets || {};
    return sheets[key] || key;
  }

  function normalizeKey(value) {
    if (value === null || value === undefined) return "";
    return String(value)
      .trim()
      .toLowerCase()
      .replace(/\s+/g, "_")
      .replace(/[^\w]/g, "");
  }

  function pickField(row, aliases) {
    if (!row || !aliases || !aliases.length) return "";
    var map = Object.create(null);
    Object.keys(row).forEach(function (k) {
      map[normalizeKey(k)] = row[k];
    });
    for (var i = 0; i < aliases.length; i++) {
      var key = normalizeKey(aliases[i]);
      if (Object.prototype.hasOwnProperty.call(map, key) && map[key] !== "") {
        return map[key];
      }
    }
    return "";
  }

  function isActiveValue(value) {
    if (value === "" || value === null || value === undefined) return true;
    if (typeof value === "boolean") return value;
    if (typeof value === "number") return value !== 0;
    var s = String(value).trim().toLowerCase();
    return !(s === "0" || s === "false" || s === "no" || s === "inactivo" || s === "off");
  }

  function normalizeTmdbId(value) {
    var s = String(value || "").trim();
    if (!s) return "";
    var m = s.match(/^(movie|tv|pelicula|serie)\s*[:#-]?\s*(\d+)$/i);
    if (m) return m[2];
    if (/^\d+$/.test(s)) return s;
    var digits = s.match(/(\d{2,})/);
    return digits ? digits[1] : s;
  }

  function mapRow(raw) {
    var cols = getConfig().columns || {};
    var videoUrl =
      String(pickField(raw, cols.videoUrl) || "") ||
      String(pickField(raw, cols.url) || "");
    var mapped = {
      id: String(pickField(raw, cols.id) || ""),
      tmdbId: normalizeTmdbId(pickField(raw, cols.tmdbId)),
      title: String(pickField(raw, cols.title) || ""),
      type: String(pickField(raw, cols.type) || "").toLowerCase(),
      cover: String(pickField(raw, cols.cover) || ""),
      backdrop: String(pickField(raw, cols.backdrop) || ""),
      url: String(pickField(raw, cols.url) || "") || videoUrl,
      videoUrl: videoUrl,
      server: String(pickField(raw, cols.server) || ""),
      season: String(pickField(raw, cols.season) || ""),
      episode: String(pickField(raw, cols.episode) || ""),
      language: String(pickField(raw, cols.language) || ""),
      active: isActiveValue(pickField(raw, cols.active)),
      synopsis: String(pickField(raw, cols.synopsis) || ""),
      year: String(pickField(raw, cols.year) || ""),
      runtime: String(pickField(raw, cols.runtime) || ""),
      maturity: String(pickField(raw, cols.maturity) || ""),
      seriesId: String(pickField(raw, cols.seriesId) || ""),
      seriesTmdbId: String(pickField(raw, cols.seriesTmdbId) || ""),
      raw: raw
    };
    if (!mapped.id && mapped.tmdbId) mapped.id = "tmdb-" + mapped.tmdbId;
    return mapped;
  }

  function ttl() {
    var n = Number(getConfig().cacheTtlMs);
    return Number.isFinite(n) && n > 0 ? n : 5 * 60 * 1000;
  }

  function readSession(key) {
    try {
      var raw = sessionStorage.getItem(STORAGE_PREFIX + key);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || !parsed.expiresAt || Date.now() > parsed.expiresAt) {
        sessionStorage.removeItem(STORAGE_PREFIX + key);
        return null;
      }
      return parsed.payload;
    } catch (err) {
      return null;
    }
  }

  function writeSession(key, payload) {
    try {
      sessionStorage.setItem(
        STORAGE_PREFIX + key,
        JSON.stringify({ expiresAt: Date.now() + ttl(), payload: payload })
      );
    } catch (err) {
      /* quota / private mode */
    }
  }

  function clearSession(key) {
    try {
      if (key) sessionStorage.removeItem(STORAGE_PREFIX + key);
      else {
        Object.keys(sessionStorage).forEach(function (k) {
          if (k.indexOf(STORAGE_PREFIX) === 0) sessionStorage.removeItem(k);
        });
      }
    } catch (err) {
      /* ignore */
    }
  }

  function notifyError(err) {
    lastError = err;
    listeners.forEach(function (fn) {
      try {
        fn(err);
      } catch (e) {
        /* ignore listener errors */
      }
    });
  }

  function buildUrl(sheet, extra) {
    var base = (getConfig().apiUrl || "").trim();
    if (!base) throw new Error("PLIX_SHEETS_CONFIG.apiUrl no configurada");
    var url = new URL(base);
    url.searchParams.set("sheet", sheet);
    if (extra) {
      Object.keys(extra).forEach(function (k) {
        if (extra[k] != null && extra[k] !== "") {
          url.searchParams.set(k, String(extra[k]));
        }
      });
    }
    return url.toString();
  }

  /** Filas con TMDB ID (columna E), listas para cards. */
  function getCatalogItems(logicalKey, options) {
    return getSheet(logicalKey, options).then(function (res) {
      var rows = (res.data || []).filter(function (r) {
        return r && r.tmdbId && String(r.tmdbId).trim() !== "";
      });
      return {
        ok: res.ok !== false,
        disabled: Boolean(res.disabled),
        sheet: res.sheet,
        data: rows,
        count: rows.length
      };
    });
  }

  function parsePayload(payload, sheet) {
    if (!payload || typeof payload !== "object") {
      throw new Error("Respuesta inválida de Google Sheets");
    }
    if (payload.ok === false) {
      throw new Error(payload.error || "Error en la API de Sheets");
    }
    var rows = Array.isArray(payload.data) ? payload.data : [];
    return {
      ok: true,
      sheet: payload.sheet || sheet,
      headers: payload.headers || [],
      count: payload.count != null ? payload.count : rows.length,
      data: rows.map(mapRow).filter(function (r) {
        return r.active;
      }),
      generatedAt: payload.generatedAt || null
    };
  }

  function isFileProtocol() {
    try {
      return global.location && global.location.protocol === "file:";
    } catch (err) {
      return false;
    }
  }

  function fetchJson(url) {
    return fetch(url, {
      method: "GET",
      credentials: "omit",
      redirect: "follow",
      headers: { Accept: "application/json" }
    }).then(function (res) {
      if (!res.ok) {
        throw new Error("HTTP " + res.status + " al consultar Sheets");
      }
      var ctype = String(res.headers.get("content-type") || "").toLowerCase();
      return res.text().then(function (text) {
        var trimmed = String(text || "").trim();
        if (
          trimmed.charAt(0) === "<" ||
          /sign in|accounts\.google/i.test(trimmed) ||
          (ctype && ctype.indexOf("json") === -1 && trimmed.charAt(0) !== "{")
        ) {
          throw new Error(
            "La app de Apps Script pide login. Redeploy con acceso «Cualquiera»."
          );
        }
        try {
          return JSON.parse(trimmed);
        } catch (err) {
          throw new Error("La API no devolvió JSON válido");
        }
      });
    });
  }

  /** Fallback JSONP si fetch/CORS falla (Apps Script). */
  function fetchJsonp(url) {
    return new Promise(function (resolve, reject) {
      var cb = "plixSheetsCb" + Date.now() + Math.floor(Math.random() * 1e6);
      var script = document.createElement("script");
      var timer = setTimeout(function () {
        cleanup();
        reject(
          new Error(
            "Timeout JSONP. Revisa que el deploy de Apps Script sea «Cualquiera»."
          )
        );
      }, 20000);

      function cleanup() {
        clearTimeout(timer);
        delete global[cb];
        if (script.parentNode) script.parentNode.removeChild(script);
      }

      global[cb] = function (payload) {
        cleanup();
        resolve(payload);
      };

      script.onerror = function () {
        cleanup();
        reject(
          new Error(
            "No se pudo cargar Sheets (JSONP). Redeploy la app web con acceso «Cualquiera»."
          )
        );
      };

      var u = new URL(url);
      u.searchParams.set("callback", cb);
      script.src = u.toString();
      document.head.appendChild(script);
    });
  }

  function loadSheetPayload(url) {
    if (isFileProtocol()) {
      return fetchJsonp(url).catch(function (err) {
        return fetchJson(url).catch(function () {
          throw err;
        });
      });
    }
    return fetchJson(url).catch(function (err) {
      return fetchJsonp(url).catch(function () {
        throw err;
      });
    });
  }

  function requestSheet(sheet, options) {
    options = options || {};
    var force = Boolean(options.force);
    var query = options.query || null;
    var cacheKey = sheet + (query ? "?" + JSON.stringify(query) : "");

    if (!force) {
      var mem = cache[cacheKey];
      if (mem && Date.now() < mem.expiresAt) {
        return Promise.resolve(mem.payload);
      }
      var session = readSession(cacheKey);
      if (session) {
        cache[cacheKey] = { expiresAt: Date.now() + ttl(), payload: session };
        return Promise.resolve(session);
      }
    }

    if (!force && inflight[cacheKey]) {
      return inflight[cacheKey];
    }

    var promise = Promise.resolve()
      .then(function () {
        return loadSheetPayload(buildUrl(sheet, query));
      })
      .then(function (payload) {
        var parsed = parsePayload(payload, sheet);
        cache[cacheKey] = { expiresAt: Date.now() + ttl(), payload: parsed };
        writeSession(cacheKey, parsed);
        lastError = null;
        return parsed;
      })
      .catch(function (err) {
        var error = err instanceof Error ? err : new Error(String(err));
        notifyError(error);
        throw error;
      })
      .finally(function () {
        delete inflight[cacheKey];
      });

    inflight[cacheKey] = promise;
    return promise;
  }

  function getSheet(logicalKey, options) {
    if (!isConfigured()) {
      return Promise.resolve({
        ok: false,
        disabled: true,
        data: [],
        sheet: sheetName(logicalKey),
        headers: [],
        count: 0
      });
    }
    return requestSheet(sheetName(logicalKey), options);
  }

  function refresh(logicalKey) {
    if (logicalKey) {
      var name = sheetName(logicalKey);
      delete cache[name];
      clearSession(name);
      return getSheet(logicalKey, { force: true });
    }
    cache = Object.create(null);
    clearSession();
    var keys = Object.keys(getConfig().sheets || {});
    return Promise.all(
      keys.map(function (k) {
        return getSheet(k, { force: true }).catch(function () {
          return { ok: false, data: [], sheet: sheetName(k) };
        });
      })
    );
  }

  function normalizeTitle(title) {
    return String(title || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/\s*[-–—]\s*t\d+.*$/i, "")
      .replace(/\s*-\s*temporada.*$/i, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function findInRows(rows, query) {
    rows = rows || [];
    query = query || {};
    if (query.tmdbId) {
      var tid = normalizeTmdbId(query.tmdbId);
      var byTmdb = rows.find(function (r) {
        return r.tmdbId && normalizeTmdbId(r.tmdbId) === tid;
      });
      if (byTmdb) return byTmdb;
    }
    if (query.id) {
      var id = String(query.id);
      var byId = rows.find(function (r) {
        return r.id && r.id === id;
      });
      if (byId) return byId;
    }
    if (query.title) {
      var want = normalizeTitle(query.title);
      return (
        rows.find(function (r) {
          return normalizeTitle(r.title) === want;
        }) || null
      );
    }
    return null;
  }

  function findContent(query) {
    return Promise.all([
      getSheet("movies").catch(function () {
        return { data: [] };
      }),
      getSheet("series").catch(function () {
        return { data: [] };
      })
    ]).then(function (results) {
      var movies = results[0].data || [];
      var series = results[1].data || [];
      return (
        findInRows(movies, query) ||
        findInRows(series, query) ||
        null
      );
    });
  }

  /**
   * Busca por TMDB ID (columna E) y devuelve la fila con url_video (columna B).
   * @param {string|number} tmdbId
   * @return {Promise<Object|null>}
   */
  function findByTmdbId(tmdbId) {
    var tid = normalizeTmdbId(tmdbId);
    if (!tid) return Promise.resolve(null);
    return findContent({ tmdbId: tid });
  }

  /**
   * Solo la URL de video de Sheets para un TMDB ID.
   * @param {string|number} tmdbId
   * @return {Promise<string>}
   */
  function getVideoUrlByTmdbId(tmdbId) {
    return findByTmdbId(tmdbId).then(function (item) {
      if (!item) return "";
      return item.videoUrl || item.url || "";
    });
  }

  function getEpisodesFor(query) {
    return getSheet("episodes").then(function (res) {
      var rows = res.data || [];
      var sid = query && (query.seriesId || query.id || "");
      var stmdb = query && (query.seriesTmdbId || query.tmdbId || "");
      var title = query && query.title ? normalizeTitle(query.title) : "";
      var season = query && query.season != null ? String(query.season) : "";

      return rows
        .filter(function (ep) {
          var matchId = sid && (ep.seriesId === sid || ep.id === sid);
          var matchTmdb =
            stmdb && (ep.seriesTmdbId === stmdb || ep.tmdbId === stmdb);
          var matchTitle =
            title &&
            (normalizeTitle(ep.title) === title ||
              normalizeTitle(ep.raw && (ep.raw.serie || ep.raw.series)) === title);
          var ok = matchId || matchTmdb || matchTitle;
          if (!ok) return false;
          if (season && ep.season && String(ep.season) !== season) return false;
          return true;
        })
        .sort(function (a, b) {
          var sa = Number(a.season) || 0;
          var sb = Number(b.season) || 0;
          if (sa !== sb) return sa - sb;
          return (Number(a.episode) || 0) - (Number(b.episode) || 0);
        });
    });
  }

  function getServersFor(query) {
    return getSheet("servers").then(function (res) {
      var rows = res.data || [];
      if (!query) return rows;
      var contentId = String(query.id || query.contentId || "");
      var tmdbId = String(query.tmdbId || "");
      var title = query.title ? normalizeTitle(query.title) : "";
      return rows.filter(function (s) {
        if (contentId && (s.id === contentId || s.seriesId === contentId)) return true;
        if (tmdbId && s.tmdbId === tmdbId) return true;
        if (title && normalizeTitle(s.title) === title) return true;
        if (!contentId && !tmdbId && !title) return true;
        return false;
      });
    });
  }

  function onError(fn) {
    if (typeof fn === "function") listeners.push(fn);
    return function unsubscribe() {
      listeners = listeners.filter(function (f) {
        return f !== fn;
      });
    };
  }

  function prefetch() {
    if (!isConfigured()) return Promise.resolve([]);
    var keys = getConfig().prefetch || [];
    return Promise.all(
      keys.map(function (k) {
        return getSheet(k).catch(function (err) {
          return { ok: false, error: String(err && err.message), data: [] };
        });
      })
    );
  }

  global.PlixSheets = {
    isConfigured: isConfigured,
    getSheet: getSheet,
    getCatalogItems: getCatalogItems,
    refresh: refresh,
    findContent: findContent,
    findByTmdbId: findByTmdbId,
    getVideoUrlByTmdbId: getVideoUrlByTmdbId,
    findInRows: findInRows,
    getEpisodesFor: getEpisodesFor,
    getServersFor: getServersFor,
    normalizeTitle: normalizeTitle,
    normalizeTmdbId: normalizeTmdbId,
    mapRow: mapRow,
    onError: onError,
    prefetch: prefetch,
    getLastError: function () {
      return lastError;
    },
    clearCache: function () {
      cache = Object.create(null);
      clearSession();
    }
  };
})(window);
