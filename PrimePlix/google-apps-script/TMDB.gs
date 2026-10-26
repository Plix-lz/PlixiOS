/**
 * Plix — Autocompletado con TMDB (solo en Apps Script).
 *
 * Cómo usarlo en TU hoja (títulos en col A, URL en col B):
 * 1. Extensiones → Apps Script → pega este archivo (y Code.gs si aún no).
 * 2. Ejecuta guardarTmdbApiKey una vez (o menú Plix TMDB → Guardar API key).
 * 3. Recarga la hoja (F5).
 * 4. Quédate en la pestaña con tus películas.
 * 5. Menú Plix TMDB → Enriquecer hoja actual (películas).
 *
 * Añade columnas: tmdb_id, portada, backdrop, sinopsis, tipo, anio, duracion.
 * No borra ni cambia las URLs de la columna URL / url_video.
 */

var TMDB_LANG = 'es-MX';
var TMDB_IMG = 'https://image.tmdb.org/t/p/';
var TMDB_API = 'https://api.themoviedb.org/3';
/** Filas a procesar por ejecución (Apps Script corta a ~6 min). */
var TMDB_BATCH_SIZE = 45;
/** Tiempo máximo por lote (ms), con margen antes del límite de Google. */
var TMDB_MAX_MS = 4.5 * 60 * 1000;

/**
 * Normaliza encabezados (propia de TMDB.gs para no depender de Code.gs).
 * @param {string} header
 * @return {string}
 */
function tmdbNormHeader_(header) {
  if (header === null || header === undefined) return '';
  return String(header)
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^\w]/g, '');
}

/**
 * Ejecutar UNA VEZ (editor o menú).
 */
function guardarTmdbApiKey() {
  PropertiesService.getScriptProperties().setProperty(
    'TMDB_API_KEY',
    '38e497c6c1a043d1341416e80915669f'
  );
  try {
    SpreadsheetApp.getUi().alert('Listo. API key de TMDB guardada.\nRecarga la hoja y usa Plix TMDB → Enriquecer hoja actual.');
  } catch (err) {
    Logger.log('TMDB_API_KEY guardada.');
  }
}

function getTmdbApiKey_() {
  var key = PropertiesService.getScriptProperties().getProperty('TMDB_API_KEY') || '';
  if (!key) {
    throw new Error('Falta TMDB_API_KEY. Usa Plix TMDB → Guardar API key TMDB.');
  }
  return key;
}

function onOpen() {
  var ui = SpreadsheetApp.getUi();
  ui.createMenu('Plix URLs')
    .addItem('⚡ Activar verificación automática', 'activarVerificacionAutomatica')
    .addItem('Desactivar verificación automática', 'desactivarVerificacionAutomatica')
    .addSeparator()
    .addItem('▶ Verificar URLs (lote) B→D', 'verificarUrlsHojaActual')
    .addItem('▶ Verificar desde el inicio', 'verificarUrlsDesdeInicio')
    .addItem('Reiniciar progreso URLs', 'reiniciarProgresoUrls')
    .addToUi();
  ui.createMenu('Plix TMDB')
    .addItem('1. Guardar API key TMDB', 'guardarTmdbApiKey')
    .addSeparator()
    .addItem('⚡ Activar auto por ID (columna E)', 'activarAutocompletadoPorIdTmdb')
    .addItem('Desactivar auto por ID', 'desactivarAutocompletadoPorIdTmdb')
    .addItem('▶ Actualizar todo desde IDs (col E)', 'actualizarTodoDesdeColumnaE')
    .addSeparator()
    .addItem('🔍 Buscar IDs duplicados (col E)', 'buscarIdsDuplicados')
    .addItem('🔍 Duplicados en LzPlus + Series LZ', 'buscarIdsDuplicadosHojasPrincipales')
    .addItem('Limpiar marcas naranjas de duplicados', 'limpiarMarcasDuplicados')
    .addSeparator()
    .addItem('Enriquecer lote (películas)', 'enrichHojaActualPeliculas')
    .addItem('Enriquecer lote (series)', 'enrichHojaActualSeries')
    .addItem('Reiniciar progreso TMDB', 'resetTmdbProgress')
    .addToUi();
}

/* ========== AUTOCOMPLETADO POR ID EN COLUMNA E ========== */

/** Columnas fijas de tu hoja LzPlus (1-based). */
var TMDB_COL = {
  title: 1, // A
  tmdbId: 5, // E
  cover: 6, // F
  backdrop: 7, // G
  synopsis: 8, // H
  type: 9, // I
  year: 10, // J
  runtime: 11 // K
};

var TMDB_TRIGGER_EDIT_ID = 'onEditTmdbId';

/**
 * Activa: al escribir un ID en la columna E se rellenan título (A) y datos.
 */
function activarAutocompletadoPorIdTmdb() {
  // Asegura API key
  try {
    getTmdbApiKey_();
  } catch (err) {
    guardarTmdbApiKey();
  }

  quitarTriggersTmdbId_();
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  ScriptApp.newTrigger(TMDB_TRIGGER_EDIT_ID)
    .forSpreadsheet(ss)
    .onEdit()
    .create();

  SpreadsheetApp.getUi().alert(
    'Autocompletado por ID ACTIVADO.\n\n' +
      '• Escribe un TMDB ID en la columna E → se actualiza el título (A)\n' +
      '  y portada, backdrop, sinopsis, tipo, año, duración.\n' +
      '• Para actualizar filas que ya tienen ID:\n' +
      '  Plix TMDB → Actualizar todo desde IDs (col E)'
  );
}

function desactivarAutocompletadoPorIdTmdb() {
  quitarTriggersTmdbId_();
  SpreadsheetApp.getUi().alert('Autocompletado por ID DESACTIVADO.');
}

function quitarTriggersTmdbId_() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === TMDB_TRIGGER_EDIT_ID) {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }
}

/**
 * Trigger: cambio en columna E (TMDB ID).
 * @param {GoogleAppsScript.Events.SheetsOnEdit} e
 */
function onEditTmdbId(e) {
  try {
    if (!e || !e.range) return;
    var range = e.range;
    var sheet = range.getSheet();
    var colE = TMDB_COL.tmdbId;

    if (range.getColumn() > colE || range.getLastColumn() < colE) return;

    var lock = LockService.getDocumentLock();
    if (!lock.tryLock(8000)) return;

    try {
      var startRow = range.getRow();
      var numRows = range.getNumRows();
      for (var i = 0; i < numRows; i++) {
        var row = startRow + i;
        if (row === 1) continue; // encabezado
        aplicarTmdbDesdeIdFila_(sheet, row, true);
        if (i < numRows - 1) Utilities.sleep(120);
      }
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    Logger.log('onEditTmdbId: ' + err);
  }
}

/**
 * Lote manual: todas las filas con ID en E → actualiza título A + datos.
 */
function actualizarTodoDesdeColumnaE() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) {
    SpreadsheetApp.getUi().alert('No hay filas.');
    return;
  }

  var started = Date.now();
  var updated = 0;
  var skipped = 0;
  var errors = [];
  var props = PropertiesService.getScriptProperties();
  var cursorKey = 'tmdb_id_batch_' + sheet.getSheetId();
  var startRow = Number(props.getProperty(cursorKey) || '2');
  if (startRow < 2) startRow = 2;

  for (var row = startRow; row <= lastRow; row++) {
    if (Date.now() - started > TMDB_MAX_MS || updated + skipped >= TMDB_BATCH_SIZE) {
      props.setProperty(cursorKey, String(row));
      SpreadsheetApp.getUi().alert(
        'Lote pausado en fila ' +
          row +
          '.\nActualizadas: ' +
          updated +
          '\nVuelve a ejecutar: Actualizar todo desde IDs'
      );
      return;
    }

    var id = String(sheet.getRange(row, TMDB_COL.tmdbId).getValue() || '').trim();
    if (!id || !/^\d+$/.test(id)) {
      skipped++;
      continue;
    }

    try {
      if (aplicarTmdbDesdeIdFila_(sheet, row, true)) updated++;
      else skipped++;
    } catch (err) {
      errors.push('F' + row + ': ' + (err.message || err));
    }
    Utilities.sleep(100);
  }

  props.deleteProperty(cursorKey);
  SpreadsheetApp.getUi().alert(
    'Listo.\nTítulos/datos actualizados: ' +
      updated +
      '\nSaltadas: ' +
      skipped +
      (errors.length ? '\nErrores:\n- ' + errors.slice(0, 5).join('\n- ') : '')
  );
}

/**
 * Rellena la fila usando el ID de la columna E.
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} row
 * @param {boolean} overwriteTitle si true, reemplaza el título en A
 * @return {boolean}
 */
function aplicarTmdbDesdeIdFila_(sheet, row, overwriteTitle) {
  var idRaw = String(sheet.getRange(row, TMDB_COL.tmdbId).getValue() || '').trim();
  if (!idRaw) return false;

  // Acepta "12345" o "movie:12345" / "tv:12345"
  var mediaHint = '';
  var id = idRaw;
  var m = idRaw.match(/^(movie|tv|pelicula|serie)\s*[:#-]?\s*(\d+)$/i);
  if (m) {
    mediaHint = m[1].toLowerCase();
    id = m[2];
  } else if (!/^\d+$/.test(idRaw)) {
    return false;
  }

  var tipoCelda = String(sheet.getRange(row, TMDB_COL.type).getValue() || '').toLowerCase();
  var details = null;
  var mediaType = 'movie';

  if (mediaHint === 'tv' || mediaHint === 'serie' || tipoCelda.indexOf('serie') !== -1) {
    details = tmdbGetDetailsSafe_('tv', id);
    mediaType = 'tv';
    if (!details) {
      details = tmdbGetDetailsSafe_('movie', id);
      mediaType = 'movie';
    }
  } else {
    details = tmdbGetDetailsSafe_('movie', id);
    mediaType = 'movie';
    if (!details) {
      details = tmdbGetDetailsSafe_('tv', id);
      mediaType = 'tv';
    }
  }

  if (!details) {
    sheet.getRange(row, TMDB_COL.title).setNote('TMDB: no se encontró ID ' + id);
    return false;
  }

  var mapped = mapTmdbDetails_(details, mediaType);

  // Título (A) + metadatos. Nunca toca url_video (B) ni el check (D).
  if (overwriteTitle) {
    if (mapped.title) {
      sheet.getRange(row, TMDB_COL.title).setValue(mapped.title);
      sheet.getRange(row, TMDB_COL.title).setNote('');
    }
    if (mapped.cover) sheet.getRange(row, TMDB_COL.cover).setValue(mapped.cover);
    if (mapped.backdrop) sheet.getRange(row, TMDB_COL.backdrop).setValue(mapped.backdrop);
    if (mapped.synopsis) sheet.getRange(row, TMDB_COL.synopsis).setValue(mapped.synopsis);
    if (mapped.type) sheet.getRange(row, TMDB_COL.type).setValue(mapped.type);
    if (mapped.year) sheet.getRange(row, TMDB_COL.year).setValue(mapped.year);
    if (mapped.runtime) sheet.getRange(row, TMDB_COL.runtime).setValue(mapped.runtime);
  } else {
    writeCellIfEmpty_(sheet, row, TMDB_COL.title, mapped.title);
    writeCellIfEmpty_(sheet, row, TMDB_COL.cover, mapped.cover);
    writeCellIfEmpty_(sheet, row, TMDB_COL.backdrop, mapped.backdrop);
    writeCellIfEmpty_(sheet, row, TMDB_COL.synopsis, mapped.synopsis);
    writeCellIfEmpty_(sheet, row, TMDB_COL.type, mapped.type);
    writeCellIfEmpty_(sheet, row, TMDB_COL.year, mapped.year);
    writeCellIfEmpty_(sheet, row, TMDB_COL.runtime, mapped.runtime);
  }

  // Normaliza el ID a solo número
  if (String(sheet.getRange(row, TMDB_COL.tmdbId).getValue()) !== mapped.tmdbId) {
    sheet.getRange(row, TMDB_COL.tmdbId).setValue(Number(mapped.tmdbId) || mapped.tmdbId);
  }

  return true;
}

/**
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} row
 * @param {number} col 1-based
 * @param {*} value
 */
function writeCellIfEmpty_(sheet, row, col, value) {
  if (value === null || value === undefined || value === '') return;
  var cell = sheet.getRange(row, col);
  var cur = cell.getValue();
  if (cur !== null && cur !== undefined && String(cur).trim() !== '') return;
  cell.setValue(value);
}

/**
 * @param {string} mediaType
 * @param {string|number} id
 * @return {Object|null}
 */
function tmdbGetDetailsSafe_(mediaType, id) {
  try {
    var path = mediaType === 'tv' ? '/tv/' : '/movie/';
    var url =
      TMDB_API +
      path +
      encodeURIComponent(String(id)) +
      '?api_key=' +
      encodeURIComponent(getTmdbApiKey_()) +
      '&language=' +
      encodeURIComponent(TMDB_LANG);
    var res = UrlFetchApp.fetch(url, {
      method: 'get',
      muteHttpExceptions: true,
      followRedirects: true
    });
    if (res.getResponseCode() < 200 || res.getResponseCode() >= 300) return null;
    return JSON.parse(res.getContentText());
  } catch (err) {
    return null;
  }
}

/** Usa la pestaña abierta. Procesa un lote; vuelve a ejecutar para continuar. */
function enrichHojaActualPeliculas() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var result = enrichSheetObjectWithTmdb_(sheet, 'movie', false);
  showEnrichResult_(sheet.getName(), result);
}

function enrichHojaActualSeries() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var result = enrichSheetObjectWithTmdb_(sheet, 'tv', false);
  showEnrichResult_(sheet.getName(), result);
}

function resetTmdbProgress() {
  var sheet = SpreadsheetApp.getActiveSheet();
  PropertiesService.getScriptProperties().deleteProperty(tmdbCursorKey_(sheet));
  SpreadsheetApp.getUi().alert(
    'Progreso reiniciado en "' +
      sheet.getName() +
      '".\nLas filas que ya tienen tmdb_id se seguirán saltando.'
  );
}

function tmdbCursorKey_(sheet) {
  return 'tmdb_next_row_' + sheet.getSheetId();
}

function enrichPeliculas() {
  var result = enrichSheetWithTmdb_('Peliculas', 'movie');
  showEnrichResult_('Peliculas', result);
}

function enrichSeries() {
  var result = enrichSheetWithTmdb_('Series', 'tv');
  showEnrichResult_('Series', result);
}

function enrichPeliculasYSeries() {
  var a = enrichSheetWithTmdb_('Peliculas', 'movie');
  var b = enrichSheetWithTmdb_('Series', 'tv');
  showEnrichResult_('Peliculas + Series', {
    updated: a.updated + b.updated,
    skipped: a.skipped + b.skipped,
    errors: a.errors.concat(b.errors)
  });
}

function showEnrichResult_(sheetName, result) {
  var msg =
    'Hoja: ' +
    sheetName +
    '\nActualizadas en este lote: ' +
    result.updated +
    '\nSaltadas (ya listas / vacías): ' +
    result.skipped +
    '\nFila siguiente: ' +
    (result.nextRow || '—');
  if (result.done) {
    msg += '\n\n✓ Terminado: no quedan filas pendientes.';
  } else {
    msg +=
      '\n\n⏱ Lote pausado a propósito (límite de tiempo de Google).\nVuelve a: Plix TMDB → Enriquecer lote… para continuar.';
  }
  if (result.errors.length) {
    msg += '\n\nErrores (máx. 8):\n- ' + result.errors.slice(0, 8).join('\n- ');
  }
  try {
    SpreadsheetApp.getUi().alert(msg);
  } catch (err) {
    Logger.log(msg);
  }
}

function enrichSheetWithTmdb_(sheetName, mediaType) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss && typeof SPREADSHEET_ID !== 'undefined' && SPREADSHEET_ID) {
    ss = SpreadsheetApp.openById(SPREADSHEET_ID);
  }
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    return {
      updated: 0,
      skipped: 0,
      errors: ['No existe la hoja "' + sheetName + '". Usa "Enriquecer hoja actual".']
    };
  }
  return enrichSheetObjectWithTmdb_(sheet, mediaType);
}

/**
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {string} mediaType
 * @param {boolean=} resetCursor
 * @return {{updated:number,skipped:number,errors:Array<string>,done:boolean,nextRow:number}}
 */
function enrichSheetObjectWithTmdb_(sheet, mediaType, resetCursor) {
  var out = { updated: 0, skipped: 0, errors: [], done: false, nextRow: 2 };
  var started = Date.now();
  prepareListaVipHeaders_(sheet);

  var values = sheet.getDataRange().getValues();
  if (!values.length) {
    out.done = true;
    return out;
  }

  var headers = values[0].map(function (h) {
    return tmdbNormHeader_(h);
  });

  if (!looksLikeHeaderRow_(headers, values[0])) {
    sheet.insertRowBefore(1);
    sheet
      .getRange(1, 1, 1, 4)
      .setValues([['titulo', 'url_video', 'con_recomendaciones', 'publicada']]);
    prepareListaVipHeaders_(sheet);
    values = sheet.getDataRange().getValues();
    headers = values[0].map(function (h) {
      return tmdbNormHeader_(h);
    });
  }

  var col = tmdbColMap_(headers);
  if (col.title < 0) col.title = 0;
  if (col.videoUrl < 0 && headers.length > 1) {
    if (headers[1] === 'url' || headers[1] === 'url_video' || headers[1] === '') {
      col.videoUrl = 1;
    }
  }

  var props = PropertiesService.getScriptProperties();
  var cursorKey = tmdbCursorKey_(sheet);
  var startRow = 2; // 1-based sheet row
  if (!resetCursor) {
    var saved = Number(props.getProperty(cursorKey) || '0');
    if (saved >= 2) startRow = saved;
  } else {
    props.deleteProperty(cursorKey);
  }

  var processed = 0;
  var r = startRow - 1; // index in values[]

  for (; r < values.length; r++) {
    if (processed >= TMDB_BATCH_SIZE || Date.now() - started > TMDB_MAX_MS) {
      out.nextRow = r + 1;
      props.setProperty(cursorKey, String(out.nextRow));
      out.done = false;
      return out;
    }

    var row = values[r];
    var sheetRow = r + 1;
    var title = col.title >= 0 ? String(row[col.title] || '').trim() : '';
    if (!title) {
      out.skipped++;
      continue;
    }

    // Ya tiene tmdb_id y portada → saltar (ahorra tiempo / reanudación)
    var hasId = col.tmdbId >= 0 && String(row[col.tmdbId] || '').trim() !== '';
    var hasCover = col.cover >= 0 && String(row[col.cover] || '').trim() !== '';
    if (hasId && hasCover) {
      out.skipped++;
      continue;
    }

    try {
      var changed = enrichOneRow_(sheet, sheetRow, row, col, mediaType);
      if (changed) out.updated++;
      else out.skipped++;
      processed++;
    } catch (err) {
      out.errors.push('Fila ' + sheetRow + ' (' + title + '): ' + (err.message || err));
      processed++;
    }
    Utilities.sleep(80);
  }

  props.deleteProperty(cursorKey);
  out.done = true;
  out.nextRow = values.length + 1;
  return out;
}

/**
 * @param {Array<string>} headers
 * @param {Array} rawRow
 * @return {boolean}
 */
function looksLikeHeaderRow_(headers, rawRow) {
  var known = {
    titulo: 1,
    title: 1,
    nombre: 1,
    url: 1,
    url_video: 1,
    tmdb_id: 1,
    portada: 1,
    sinopsis: 1,
    con_recomendaciones: 1,
    publicada: 1,
    backdrop: 1,
    tipo: 1
  };
  for (var i = 0; i < headers.length; i++) {
    if (headers[i] && known[headers[i]]) return true;
  }
  var b = rawRow[1] != null ? String(rawRow[1]).trim() : '';
  if (/^https?:\/\//i.test(b)) return false;
  return false;
}

/**
 * Asegura columnas TMDB a la derecha sin tocar A–D.
 * Escribe de 1 en 1 para evitar el error "datos 8 / rango 20".
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 */
function prepareListaVipHeaders_(sheet) {
  var needed = [
    'tmdb_id',
    'portada',
    'backdrop',
    'sinopsis',
    'tipo',
    'anio',
    'duracion',
    'activo'
  ];

  // Nombrar A1 si está vacío.
  if (!String(sheet.getRange(1, 1).getValue() || '').trim()) {
    sheet.getRange(1, 1).setValue('titulo');
  }
  // Normalizar encabezado URL → url_video.
  if (tmdbNormHeader_(sheet.getRange(1, 2).getValue()) === 'url') {
    sheet.getRange(1, 2).setValue('url_video');
  }

  var maxScan = Math.max(sheet.getLastColumn(), needed.length + 4, 12);
  var existing = {};
  var emptyCols = [];
  for (var c = 1; c <= maxScan; c++) {
    var n = tmdbNormHeader_(sheet.getRange(1, c).getValue());
    if (n) existing[n] = true;
    else if (c >= 5) emptyCols.push(c); // no reutilizar A–D
  }

  var emptyIdx = 0;
  for (var j = 0; j < needed.length; j++) {
    var name = needed[j];
    if (existing[name] || headerAliasExists_(existing, name)) continue;

    var col;
    if (emptyIdx < emptyCols.length) {
      col = emptyCols[emptyIdx++];
    } else {
      col = sheet.getLastColumn() + 1;
      if (col < 5) col = 5;
    }
    sheet.getRange(1, col).setValue(name);
    existing[name] = true;
  }
}

function headerAliasExists_(existing, canonical) {
  var aliases = {
    titulo: ['title', 'nombre', 'name'],
    tmdb_id: ['tmdb', 'tmdbid'],
    portada: ['cover', 'poster', 'imagen', 'img'],
    backdrop: ['fondo', 'banner', 'backdrop_path'],
    sinopsis: ['synopsis', 'descripcion', 'description', 'overview'],
    anio: ['year', 'ano'],
    duracion: ['runtime', 'duration'],
    tipo: ['type'],
    url_video: ['url', 'video', 'link', 'stream']
  };
  var list = aliases[canonical] || [];
  for (var i = 0; i < list.length; i++) {
    if (existing[list[i]]) return true;
  }
  return false;
}

function tmdbColMap_(headers) {
  function find(names) {
    for (var i = 0; i < names.length; i++) {
      var idx = headers.indexOf(names[i]);
      if (idx !== -1) return idx;
    }
    return -1;
  }
  return {
    id: find(['id']),
    tmdbId: find(['tmdb_id', 'tmdb', 'tmdbid']),
    title: find(['titulo', 'title', 'nombre', 'name']),
    type: find(['tipo', 'type']),
    cover: find(['portada', 'cover', 'poster', 'imagen', 'img']),
    backdrop: find(['backdrop', 'fondo', 'banner', 'backdrop_path']),
    synopsis: find(['sinopsis', 'synopsis', 'descripcion', 'description', 'overview']),
    year: find(['anio', 'ano', 'year']),
    runtime: find(['duracion', 'runtime', 'duration']),
    active: find(['activo', 'active', 'enabled']),
    videoUrl: find(['url_video', 'url', 'video', 'link', 'stream'])
  };
}

function enrichOneRow_(sheet, rowNumber, row, col, mediaType) {
  var tmdbId = col.tmdbId >= 0 ? String(row[col.tmdbId] || '').trim() : '';
  var title = col.title >= 0 ? String(row[col.title] || '').trim() : '';
  var details = null;

  if (tmdbId) {
    // Solo detalles si faltan portada o sinopsis
    var needDetail =
      (col.cover >= 0 && !String(row[col.cover] || '').trim()) ||
      (col.synopsis >= 0 && !String(row[col.synopsis] || '').trim()) ||
      (col.backdrop >= 0 && !String(row[col.backdrop] || '').trim());
    if (!needDetail) return false;
    details = tmdbGetDetails_(mediaType, tmdbId);
  } else if (title) {
    var clean = title.replace(/\s+\d+$/, '').trim();
    var hit = tmdbSearch_(mediaType, clean) || tmdbSearch_(mediaType, title);
    if (!hit) return false;
    // La búsqueda ya trae poster/backdrop/overview → 1 sola llamada (más rápido)
    details = hit;
  } else {
    return false;
  }

  if (!details) return false;

  var mapped = mapTmdbDetails_(details, mediaType);
  var changed = false;

  changed = writeIfEmpty_(sheet, rowNumber, col.tmdbId, row, col.tmdbId, mapped.tmdbId) || changed;
  // No sobrescribir el título original de la lista VIP (puede ser alias).
  // Solo rellenar si la celda de título estuviera vacía (no aplica en tu caso).
  changed = writeIfEmpty_(sheet, rowNumber, col.type, row, col.type, mapped.type) || changed;
  changed = writeIfEmpty_(sheet, rowNumber, col.cover, row, col.cover, mapped.cover) || changed;
  changed = writeIfEmpty_(sheet, rowNumber, col.backdrop, row, col.backdrop, mapped.backdrop) || changed;
  changed = writeIfEmpty_(sheet, rowNumber, col.synopsis, row, col.synopsis, mapped.synopsis) || changed;
  changed = writeIfEmpty_(sheet, rowNumber, col.year, row, col.year, mapped.year) || changed;
  changed = writeIfEmpty_(sheet, rowNumber, col.runtime, row, col.runtime, mapped.runtime) || changed;
  if (col.active >= 0) {
    changed = writeIfEmpty_(sheet, rowNumber, col.active, row, col.active, 'si') || changed;
  }
  return changed;
}

function writeIfEmpty_(sheet, rowNumber, colIndex, row, rowCol, value) {
  if (colIndex < 0 || value === null || value === undefined || value === '') return false;
  var current = rowCol >= 0 ? row[rowCol] : '';
  if (current !== null && current !== undefined && String(current).trim() !== '') {
    return false;
  }
  sheet.getRange(rowNumber, colIndex + 1).setValue(value);
  if (rowCol >= 0) row[rowCol] = value;
  return true;
}

function mapTmdbDetails_(details, mediaType) {
  var title =
    mediaType === 'tv'
      ? details.name || details.original_name || ''
      : details.title || details.original_title || '';
  var date =
    mediaType === 'tv' ? details.first_air_date || '' : details.release_date || '';
  var year = date ? String(date).slice(0, 4) : '';
  var runtime = '';
  if (mediaType === 'movie' && details.runtime) {
    runtime = formatRuntime_(details.runtime);
  } else if (mediaType === 'tv' && details.episode_run_time && details.episode_run_time.length) {
    runtime = formatRuntime_(details.episode_run_time[0]);
  }

  return {
    tmdbId: String(details.id || ''),
    title: title,
    type: mediaType === 'tv' ? 'serie' : 'pelicula',
    cover: details.poster_path ? TMDB_IMG + 'w500' + details.poster_path : '',
    backdrop: details.backdrop_path ? TMDB_IMG + 'w1280' + details.backdrop_path : '',
    synopsis: details.overview || '',
    year: year,
    runtime: runtime
  };
}

function formatRuntime_(minutes) {
  var m = Number(minutes) || 0;
  if (m <= 0) return '';
  if (m < 60) return m + ' min';
  var h = Math.floor(m / 60);
  var rest = m % 60;
  return rest ? h + ' h ' + rest + ' min' : h + ' h';
}

function tmdbSearch_(mediaType, query) {
  var path = mediaType === 'tv' ? '/search/tv' : '/search/movie';  var url =
    TMDB_API +
    path +
    '?api_key=' +
    encodeURIComponent(getTmdbApiKey_()) +
    '&language=' +
    encodeURIComponent(TMDB_LANG) +
    '&query=' +
    encodeURIComponent(query) +
    '&page=1';
  var data = tmdbFetchJson_(url);
  if (!data || !data.results || !data.results.length) return null;
  return data.results[0];
}

function tmdbGetDetails_(mediaType, id) {
  var path = mediaType === 'tv' ? '/tv/' : '/movie/';  var url =
    TMDB_API +
    path +
    encodeURIComponent(String(id)) +
    '?api_key=' +
    encodeURIComponent(getTmdbApiKey_()) +
    '&language=' +
    encodeURIComponent(TMDB_LANG);
  return tmdbFetchJson_(url);
}

function tmdbFetchJson_(url) {
  var res = UrlFetchApp.fetch(url, {
    method: 'get',
    muteHttpExceptions: true,
    followRedirects: true
  });
  var code = res.getResponseCode();
  var text = res.getContentText();
  if (code < 200 || code >= 300) {
    throw new Error('TMDB HTTP ' + code + ': ' + String(text).slice(0, 120));
  }
  return JSON.parse(text);
}
