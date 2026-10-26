/**
 * Plix — Google Apps Script API (solo lectura)
 *
 * 1. Abre tu Google Sheet → Extensiones → Apps Script
 * 2. Pega este archivo y completa SPREADSHEET_ID abajo
 * 3. Despliega → Nueva implementación → Aplicación web
 *    - Ejecutar como: Yo
 *    - Quién tiene acceso: Cualquiera
 * 4. Copia la URL /exec en scripts/sheets-config.js → apiUrl
 *
 * Seguridad: esta API es pública de lectura. Quien tenga la URL
 * podrá leer las hojas permitidas. No pongas datos privados en la hoja.
 * No uses claves de API (TMDB, etc.) en el frontend: van en TMDB.gs /
 * Propiedades del script.
 *
 * TMDB: pega también TMDB.gs y ejecuta guardarTmdbApiKey + menú Plix TMDB.
 */

/** @type {string} ID de la hoja (entre /d/ y /edit de la URL). Completar. */
var SPREADSHEET_ID = '1jLEj5B5Zs_m71pXJMbmbsr1Q54JQl9u7rDzjynU4r1Y';

/**
 * Nombres de hojas permitidos (allowlist).
 * Ajusta a tu estructura real. Vaciar una entrada no la desactiva:
 * solo se aceptan los nombres listados aquí.
 */
var ALLOWED_SHEETS = [
  'Peliculas',
  'Series',
  'Episodios',
  'Servidores',
  'Configuracion',
  'LzPlus',
  'Series LZ'
];

/**
 * Columnas fijas (0-based) de LzPlus / Series LZ.
 * A título · B URL video · E TMDB ID · F portada · G backdrop · H sinopsis · I tipo · J año · K duración
 */
var FIXED_LAYOUT_SHEETS = {
  LzPlus: {
    title: 0,
    videoUrl: 1,
    tmdbId: 4,
    cover: 5,
    backdrop: 6,
    synopsis: 7,
    type: 8,
    year: 9,
    runtime: 10,
    defaultType: 'pelicula'
  },
  'Series LZ': {
    title: 0,
    videoUrl: 1,
    tmdbId: 4,
    cover: 5,
    backdrop: 6,
    synopsis: 7,
    type: 8,
    year: 9,
    runtime: 10,
    defaultType: 'serie'
  }
};

/**
 * @param {GoogleAppsScript.Events.DoGet} e
 * @return {GoogleAppsScript.Content.TextOutput}
 */
function doGet(e) {
  try {
    var params = (e && e.parameter) ? e.parameter : {};
    var sheetName = String(params.sheet || params.hoja || '').trim();
    var callback = String(params.callback || '').trim();
    var onlyWithId =
      String(params.onlyWithId || params.only_with_id || '').trim() === '1' ||
      String(params.onlyWithId || params.only_with_id || '').toLowerCase() === 'true';

    if (!SPREADSHEET_ID) {
      return jsonResponse_(
        {
          ok: false,
          error: 'SPREADSHEET_ID no configurado en Apps Script',
          data: [],
          sheet: sheetName || null
        },
        callback,
        500
      );
    }

    if (!sheetName) {
      return jsonResponse_(
        {
          ok: false,
          error: 'Parámetro "sheet" obligatorio. Hojas permitidas: ' + ALLOWED_SHEETS.join(', '),
          data: [],
          sheet: null,
          allowedSheets: ALLOWED_SHEETS
        },
        callback,
        400
      );
    }

    if (ALLOWED_SHEETS.indexOf(sheetName) === -1) {
      return jsonResponse_(
        {
          ok: false,
          error: 'Hoja no permitida: ' + sheetName,
          data: [],
          sheet: sheetName,
          allowedSheets: ALLOWED_SHEETS
        },
        callback,
        403
      );
    }

    var ss = SpreadsheetApp.openById(SPREADSHEET_ID);
    var sheet = ss.getSheetByName(sheetName);

    if (!sheet) {
      return jsonResponse_(
        {
          ok: false,
          error: 'La hoja "' + sheetName + '" no existe en el documento',
          data: [],
          sheet: sheetName
        },
        callback,
        404
      );
    }

    var values = sheet.getDataRange().getValues();
    if (!values || values.length === 0) {
      return jsonResponse_(
        {
          ok: true,
          data: [],
          sheet: sheetName,
          headers: [],
          count: 0
        },
        callback,
        200
      );
    }

    var rawHeaders = values[0];
    var headers = [];
    var headerIndex = [];

    for (var c = 0; c < rawHeaders.length; c++) {
      var key = normalizeHeader_(rawHeaders[c]);
      if (!key) continue;
      headers.push(key);
      headerIndex.push(c);
    }

    var fixed = FIXED_LAYOUT_SHEETS[sheetName] || null;
    var rows = [];
    for (var r = 1; r < values.length; r++) {
      var row = values[r];
      if (isEmptyRow_(row, headerIndex.length ? headerIndex : null)) {
        if (!fixed || !String(row[fixed.tmdbId] || '').trim()) continue;
      }

      var obj = {};
      for (var i = 0; i < headerIndex.length; i++) {
        var col = headerIndex[i];
        obj[headers[i]] = cellToJson_(row[col]);
      }

      if (fixed) {
        applyFixedLayout_(obj, row, fixed);
      }

      if (onlyWithId) {
        var tid = String(obj.tmdb_id || '').trim();
        if (!tid || !/\d/.test(tid)) continue;
      }

      rows.push(obj);
    }

    return jsonResponse_(
      {
        ok: true,
        data: rows,
        sheet: sheetName,
        headers: headers,
        count: rows.length
      },
      callback,
      200
    );
  } catch (err) {
    return jsonResponse_(
      {
        ok: false,
        error: String(err && err.message ? err.message : err),
        data: [],
        sheet: null
      },
      (e && e.parameter && e.parameter.callback) ? String(e.parameter.callback) : '',
      500
    );
  }
}

/**
 * Garantiza tmdb_id (E) y url_video (B) aunque el encabezado tenga otro nombre.
 * @param {Object} obj
 * @param {Array} row
 * @param {Object} fixed
 */
function applyFixedLayout_(obj, row, fixed) {
  var title = cellToJson_(row[fixed.title]);
  var videoUrl = cellToJson_(row[fixed.videoUrl]);
  var tmdbId = cellToJson_(row[fixed.tmdbId]);
  var cover = cellToJson_(row[fixed.cover]);
  var backdrop = cellToJson_(row[fixed.backdrop]);
  var synopsis = cellToJson_(row[fixed.synopsis]);
  var type = cellToJson_(row[fixed.type]);
  var year = cellToJson_(row[fixed.year]);
  var runtime = cellToJson_(row[fixed.runtime]);

  if (title !== '') obj.titulo = title;
  if (videoUrl !== '') {
    obj.url_video = videoUrl;
    obj.url = videoUrl;
  }
  if (tmdbId !== '') {
    var idStr = String(tmdbId).replace(/^(movie|tv|pelicula|serie)\s*[:#-]?\s*/i, '').trim();
    obj.tmdb_id = idStr || String(tmdbId);
  }
  if (cover !== '') obj.portada = cover;
  if (backdrop !== '') obj.backdrop = backdrop;
  if (synopsis !== '') obj.sinopsis = synopsis;
  if (type !== '') obj.tipo = type;
  else if (fixed.defaultType) obj.tipo = fixed.defaultType;
  if (year !== '') obj.anio = year;
  if (runtime !== '') obj.duracion = runtime;
}

/**
 * @param {string} header
 * @return {string}
 */
function normalizeHeader_(header) {
  if (header === null || header === undefined) return '';
  return String(header)
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^\w]/g, '');
}

/**
 * @param {Array} row
 * @param {Array<number>|null} headerIndex
 * @return {boolean}
 */
function isEmptyRow_(row, headerIndex) {
  if (!headerIndex || !headerIndex.length) {
    for (var j = 0; j < row.length; j++) {
      if (row[j] !== null && row[j] !== undefined && String(row[j]).trim() !== '') {
        return false;
      }
    }
    return true;
  }
  for (var i = 0; i < headerIndex.length; i++) {
    var v = row[headerIndex[i]];
    if (v !== null && v !== undefined && String(v).trim() !== '') {
      return false;
    }
  }
  return true;
}

/**
 * @param {*} value
 * @return {*}
 */
function cellToJson_(value) {
  if (value === null || value === undefined) return '';
  if (Object.prototype.toString.call(value) === '[object Date]') {
    return Utilities.formatDate(value, Session.getScriptTimeZone(), "yyyy-MM-dd'T'HH:mm:ssXXX");
  }
  if (typeof value === 'boolean' || typeof value === 'number') return value;
  return String(value).trim();
}

/**
 * ContentService no permite códigos HTTP reales en Apps Script web apps;
 * el campo `status` va en el JSON. JSONP opcional para CORS en entornos estrictos.
 *
 * @param {Object} payload
 * @param {string} callback
 * @param {number} status
 * @return {GoogleAppsScript.Content.TextOutput}
 */
function jsonResponse_(payload, callback, status) {
  payload.status = status || 200;
  payload.generatedAt = new Date().toISOString();
  var body = JSON.stringify(payload);

  if (callback && /^[A-Za-z_$][0-9A-Za-z_$]*$/.test(callback)) {
    return ContentService
      .createTextOutput(callback + '(' + body + ')')
      .setMimeType(ContentService.MimeType.JAVASCRIPT);
  }

  return ContentService
    .createTextOutput(body)
    .setMimeType(ContentService.MimeType.JSON);
}
