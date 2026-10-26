/**
 * Plix — Verificar URLs (columna B → estado en columna D)
 *
 * Menú: Plix URLs
 *  - Activar verificación automática (una vez)
 *  - Verificar desde el inicio / lote manual
 *
 * Automático:
 *  1) Al editar una URL en la columna B → verifica esa fila al instante
 *  2) Cada hora → barrido por lotes de todas las URLs (si vuelven a
 *     funcionar, pasan a ✓ verde solas)
 *
 * ✓ verde  = OK
 * ? amarillo = no verificable desde Google (no se trata como caída)
 * ✗ rojo   = caída clara (404/410)
 */

var URL_BATCH_SIZE = 30;
var URL_MAX_MS = 4.5 * 60 * 1000;

/** Hojas a barrer en el escaneo automático (ajusta nombres si hace falta). */
var URL_AUTO_SHEETS = ['LzPlus', 'Series LZ'];

/** Cada cuántas horas corre el barrido (1–6 recomendado). */
var URL_AUTO_HOURS = 1;

var URL_TRIGGER_EDIT = 'onEditVerificarUrl';
var URL_TRIGGER_TIME = 'barridoAutomaticoUrls';

function verificarUrlsHojaActual() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var result = verificarUrlsSheet_(sheet, false);
  showUrlCheckResult_(sheet.getName(), result);
}

function verificarUrlsDesdeInicio() {
  var sheet = SpreadsheetApp.getActiveSheet();
  PropertiesService.getScriptProperties().deleteProperty(urlCursorKey_(sheet));
  var result = verificarUrlsSheet_(sheet, true);
  showUrlCheckResult_(sheet.getName(), result);
}

function reiniciarProgresoUrls() {
  var sheet = SpreadsheetApp.getActiveSheet();
  PropertiesService.getScriptProperties().deleteProperty(urlCursorKey_(sheet));
  SpreadsheetApp.getUi().alert(
    'Progreso reiniciado.\nUsa: Plix URLs → Verificar desde el inicio'
  );
}

function urlCursorKey_(sheet) {
  return 'url_check_next_' + sheet.getSheetId();
}

/* ========== AUTOMATIZACIÓN ========== */

/**
 * Ejecutar UNA VEZ desde el menú (autoriza UrlFetch + crea triggers).
 */
function activarVerificacionAutomatica() {
  quitarTriggersPlixUrls_();

  var ss = SpreadsheetApp.getActiveSpreadsheet();

  // Al editar columna B
  ScriptApp.newTrigger(URL_TRIGGER_EDIT)
    .forSpreadsheet(ss)
    .onEdit()
    .create();

  // Barrido periódico
  ScriptApp.newTrigger(URL_TRIGGER_TIME)
    .timeBased()
    .everyHours(URL_AUTO_HOURS)
    .create();

  // Recordar hojas a escanear (+ la activa)
  var props = PropertiesService.getScriptProperties();
  var names = URL_AUTO_SHEETS.slice();
  var active = ss.getActiveSheet().getName();
  if (names.indexOf(active) === -1) names.push(active);
  props.setProperty('url_auto_sheets', JSON.stringify(names));
  props.setProperty('url_auto_sheet_idx', '0');

  SpreadsheetApp.getUi().alert(
    'Verificación automática ACTIVADA.\n\n' +
      '• Al cambiar una URL en la columna B → se verifica esa fila.\n' +
      '• Cada ' +
      URL_AUTO_HOURS +
      ' h → barrido automático de:\n  ' +
      names.join(', ') +
      '\n\nSi una URL vuelve a funcionar, pasará a ✓ sola en el barrido.\n' +
      'Para apagar: Plix URLs → Desactivar verificación automática'
  );
}

/**
 * Quita los triggers de edición y barrido.
 */
function desactivarVerificacionAutomatica() {
  quitarTriggersPlixUrls_();
  SpreadsheetApp.getUi().alert('Verificación automática DESACTIVADA.');
}

function quitarTriggersPlixUrls_() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    var h = triggers[i].getHandlerFunction();
    if (h === URL_TRIGGER_EDIT || h === URL_TRIGGER_TIME) {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }
}

/**
 * Trigger instalable onEdit: solo columna B.
 * @param {GoogleAppsScript.Events.SheetsOnEdit} e
 */
function onEditVerificarUrl(e) {
  try {
    if (!e || !e.range) return;
    var range = e.range;
    var sheet = range.getSheet();

    // Solo columna B
    if (range.getColumn() > 2 || range.getLastColumn() < 2) return;
    if (range.getRow() < 1) return;

    var lock = LockService.getDocumentLock();
    if (!lock.tryLock(5000)) return;

    try {
      var startRow = range.getRow();
      var numRows = range.getNumRows();
      for (var i = 0; i < numRows; i++) {
        var row = startRow + i;
        if (row === 1) {
          // si B1 es encabezado "url", saltar
          var v = String(sheet.getRange(row, 2).getValue() || '').toLowerCase();
          if (v.indexOf('url') !== -1 || v === 'titulo') continue;
        }
        verificarFilaUrl_(sheet, row);
        if (i < numRows - 1) Utilities.sleep(80);
      }
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    Logger.log('onEditVerificarUrl: ' + err);
  }
}

/**
 * Verifica una sola fila (col B → col D).
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} row 1-based
 */
function verificarFilaUrl_(sheet, row) {
  var url = String(sheet.getRange(row, 2).getValue() || '').trim();
  var colD = 4;

  if (!url) {
    sheet.getRange(row, colD).clearContent().clearNote().setBackground(null);
    return;
  }
  if (!/^https?:\/\//i.test(url) || /image\.tmdb\.org/i.test(url)) return;

  try {
    sheet.getRange(row, colD).clearDataValidations();
  } catch (e1) {
    /* ignore */
  }

  var status = classifyVideoUrl_(url);
  paintStatusCell_(sheet, row, colD, status);
}

/**
 * Barrido horario: procesa un lote y continúa en la siguiente hora.
 * Si una URL muerta vuelve a responder → ✓ automáticamente.
 */
function barridoAutomaticoUrls() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) return;

  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    if (!ss) {
      // En triggers time-based a veces hace falta openById
      if (typeof SPREADSHEET_ID !== 'undefined' && SPREADSHEET_ID) {
        ss = SpreadsheetApp.openById(SPREADSHEET_ID);
      } else {
        return;
      }
    }

    var props = PropertiesService.getScriptProperties();
    var names;
    try {
      names = JSON.parse(props.getProperty('url_auto_sheets') || '[]');
    } catch (e) {
      names = [];
    }
    if (!names || !names.length) names = URL_AUTO_SHEETS.slice();

    var idx = Number(props.getProperty('url_auto_sheet_idx') || '0');
    if (idx < 0 || idx >= names.length) idx = 0;

    var sheetName = names[idx];
    var sheet = ss.getSheetByName(sheetName);
    if (!sheet) {
      props.setProperty('url_auto_sheet_idx', String((idx + 1) % names.length));
      return;
    }

    var result = verificarUrlsSheet_(sheet, false);
    Logger.log(
      'Barrido ' +
        sheetName +
        ' ok=' +
        result.ok +
        ' dead=' +
        result.fail +
        ' unk=' +
        result.unknown +
        ' done=' +
        result.done
    );

    if (result.done) {
      // Siguiente hoja en el próximo disparo
      props.setProperty('url_auto_sheet_idx', String((idx + 1) % names.length));
      props.deleteProperty(urlCursorKey_(sheet));
    }
  } finally {
    lock.releaseLock();
  }
}

/**
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {boolean} resetCursor
 * @return {Object}
 */
function verificarUrlsSheet_(sheet, resetCursor) {
  var out = {
    ok: 0,
    fail: 0,
    unknown: 0,
    skipped: 0,
    errors: [],
    done: false,
    nextRow: 2,
    samples: []
  };
  var started = Date.now();
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) {
    out.done = true;
    return out;
  }

  // Columna D = Publicada (fija). No usar "activo" de TMDB.
  var colB = 2; // 1-based
  var colD = 4; // 1-based
  var firstDataRow = 2;

  // Si la fila 1 no es encabezado (B1 es http), empezar en 1
  var b1 = String(sheet.getRange(1, colB).getValue() || '');
  if (/^https?:\/\//i.test(b1)) firstDataRow = 1;

  try {
    sheet.getRange(firstDataRow, colD, lastRow, colD).clearDataValidations();
  } catch (err) {
    /* ignore */
  }

  var props = PropertiesService.getScriptProperties();
  var cursorKey = urlCursorKey_(sheet);
  var startSheetRow = firstDataRow;
  if (!resetCursor) {
    var saved = Number(props.getProperty(cursorKey) || '0');
    if (saved >= firstDataRow) startSheetRow = saved;
  } else {
    props.deleteProperty(cursorKey);
  }

  var processed = 0;

  for (var sheetRow = startSheetRow; sheetRow <= lastRow; sheetRow++) {
    if (processed >= URL_BATCH_SIZE || Date.now() - started > URL_MAX_MS) {
      out.nextRow = sheetRow;
      props.setProperty(cursorKey, String(sheetRow));
      out.done = false;
      return out;
    }

    var url = String(sheet.getRange(sheetRow, colB).getValue() || '').trim();

    if (!url || !/^https?:\/\//i.test(url)) {
      out.skipped++;
      continue;
    }
    if (/image\.tmdb\.org/i.test(url)) {
      out.skipped++;
      continue;
    }

    try {
      var status = classifyVideoUrl_(url); // ok | dead | unknown
      paintStatusCell_(sheet, sheetRow, colD, status);
      if (status === 'ok') out.ok++;
      else if (status === 'dead') out.fail++;
      else out.unknown++;

      if (out.samples.length < 4) {
        out.samples.push('F' + sheetRow + '=' + status + ' · ' + url.slice(0, 48));
      }
      processed++;
    } catch (err) {
      // Error de red desde Google ≠ URL muerta
      paintStatusCell_(sheet, sheetRow, colD, 'unknown');
      out.unknown++;
      out.errors.push('Fila ' + sheetRow + ': ' + (err.message || err));
      processed++;
    }
    Utilities.sleep(40);
  }

  props.deleteProperty(cursorKey);
  out.done = true;
  out.nextRow = lastRow + 1;
  return out;
}

/**
 * Clasifica la URL con varias estrategias.
 * Solo "dead" si hay evidencia clara de que no existe.
 * @param {string} url
 * @return {string} ok|dead|unknown
 */
function classifyVideoUrl_(url) {
  var origin = '';
  try {
    origin = url.match(/^https?:\/\/[^\/]+/i)[0];
  } catch (e) {
    origin = '';
  }

  var probes = [
    { method: 'get', headers: { Range: 'bytes=0-1023' } },
    {
      method: 'get',
      headers: {
        Range: 'bytes=0-1023',
        Referer: origin ? origin + '/' : '',
        Origin: origin || ''
      }
    },
    { method: 'head', headers: null },
    {
      method: 'get',
      headers: {
        Referer: 'https://www.google.com/',
        Range: 'bytes=0-511'
      }
    }
  ];

  var sawBlock = false; // 401/403/405/429/503 → no marcar muerto
  var sawHardDead = false;
  var lastCode = 0;

  for (var i = 0; i < probes.length; i++) {
    var result = fetchProbe_(url, probes[i].method, probes[i].headers);
    lastCode = result.code;

    if (result.ok) return 'ok';

    if (result.code === 404 || result.code === 410 || result.code === 451) {
      sawHardDead = true;
      continue; // probar otras estrategias por si un CDN miente en HEAD
    }

    if (
      result.code === 401 ||
      result.code === 403 ||
      result.code === 405 ||
      result.code === 429 ||
      result.code === 503 ||
      result.code === 502 ||
      result.code === 500
    ) {
      sawBlock = true;
      continue;
    }

    if (result.code === 0) {
      sawBlock = true; // SSL / timeout / bloqueo de red desde Google
    }
  }

  // Si alguna prueba dio 404 pero otra no fue concluyente, insistir:
  // muchos hosts dan 403 a bots y 200 al navegador.
  if (sawHardDead && !sawBlock) return 'dead';
  if (sawHardDead && sawBlock) return 'unknown';
  if (sawBlock) return 'unknown';

  // Último recurso: sin código útil
  if (lastCode === 404 || lastCode === 410) return 'dead';
  return 'unknown';
}

/**
 * @param {string} url
 * @param {string} method
 * @param {Object|null} headers
 * @return {{code:number,ok:boolean}}
 */
function fetchProbe_(url, method, headers) {
  try {
    var opts = {
      method: method,
      muteHttpExceptions: true,
      followRedirects: true,
      validateHttpsCertificates: false
    };
    opts.headers = {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      Accept: '*/*',
      'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8'
    };
    if (headers) {
      for (var k in headers) {
        if (headers[k]) opts.headers[k] = headers[k];
      }
    }

    var res = UrlFetchApp.fetch(url, opts);
    var code = res.getResponseCode();

    // Éxito claro
    if (code === 200 || code === 206) {
      // Evitar HTML de error disfrazado de 200
      if (method === 'get') {
        var body = '';
        try {
          body = res.getContentText('UTF-8').slice(0, 80).toLowerCase();
        } catch (e1) {
          body = '';
        }
        if (
          body.indexOf('<!doctype') === 0 ||
          body.indexOf('<html') !== -1 ||
          body.indexOf('not found') !== -1 ||
          body.indexOf('access denied') !== -1
        ) {
          return { code: 404, ok: false };
        }
      }
      return { code: code, ok: true };
    }

    // Redirects ya deberían resolverse; si quedan, contar como ok blando
    if (code >= 300 && code < 400) return { code: code, ok: true };

    return { code: code, ok: false };
  } catch (err) {
    return { code: 0, ok: false };
  }
}

/**
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @param {number} row
 * @param {number} col 1-based
 * @param {string} status ok|dead|unknown
 */
function paintStatusCell_(sheet, row, col, status) {
  var cell = sheet.getRange(row, col);
  cell.setFontWeight('bold');
  cell.setHorizontalAlignment('center');
  cell.setVerticalAlignment('middle');

  if (status === 'ok') {
    cell.setValue('✓');
    cell.setBackground('#34a853');
    cell.setFontColor('#ffffff');
    cell.setNote('URL responde OK desde el verificador');
  } else if (status === 'dead') {
    cell.setValue('✗');
    cell.setBackground('#ea4335');
    cell.setFontColor('#ffffff');
    cell.setNote('URL caída (404/410 u error definitivo)');
  } else {
    // unknown — NO marcar como caída
    cell.setValue('?');
    cell.setBackground('#f9ab00');
    cell.setFontColor('#202124');
    cell.setNote(
      'No se pudo verificar desde los servidores de Google (bloqueo 403/red). ' +
        'Puede funcionar en el navegador. No se marca como caída.'
    );
  }
}

function showUrlCheckResult_(sheetName, result) {
  var msg =
    '=== VERIFICACIÓN DE URLs (columna D) ===\n' +
    'Hoja: ' +
    sheetName +
    '\n✓ Verdes (OK): ' +
    result.ok +
    '\n? Amarillas (dudosas, NO caídas): ' +
    result.unknown +
    '\n✗ Rojas (caídas claras): ' +
    result.fail +
    '\nSaltadas: ' +
    result.skipped +
    '\nSiguiente fila: ' +
    result.nextRow;
  if (result.samples && result.samples.length) {
    msg += '\n\nMuestras:\n- ' + result.samples.join('\n- ');
  }
  if (result.done) msg += '\n\n✓ Lote completo.';
  else
    msg +=
      '\n\n⏱ Pausado. Continúa con:\nPlix URLs → Verificar URLs (lote) B→D';
  if (result.errors.length) {
    msg += '\n\nErrores:\n- ' + result.errors.slice(0, 4).join('\n- ');
  }
  msg +=
    '\n\nNota: si el host bloquea a Google, verás ? amarillo aunque en tu PC abra bien.';
  SpreadsheetApp.getUi().alert(msg);
}
