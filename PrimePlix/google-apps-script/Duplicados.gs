/**
 * Plix — Buscador de IDs TMDB duplicados (columna E)
 *
 * Menú: Plix TMDB → Buscar IDs duplicados (col E)
 *
 * - Escanea la columna E
 * - Lista cada ID repetido con filas y títulos (col A)
 * - Colorea en naranja las celdas E duplicadas
 * - Escribe un informe en una hoja "Duplicados_TMDB"
 */

var DUP_COL_ID = 5; // E
var DUP_COL_TITLE = 1; // A
var DUP_COLOR = '#fbbc04';
var DUP_REPORT_SHEET = 'Duplicados_TMDB';

/**
 * Busca duplicados en la hoja activa y genera informe.
 */
function buscarIdsDuplicados() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var result = escanearDuplicadosColumnaE_(sheet);
  mostrarResultadoDuplicados_(sheet.getName(), result);
}

/**
 * Busca en LzPlus + Series LZ (si existen).
 */
function buscarIdsDuplicadosHojasPrincipales() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var names = ['LzPlus', 'Series LZ'];
  var totalGroups = 0;
  var totalRows = 0;
  var lines = [];

  for (var i = 0; i < names.length; i++) {
    var sh = ss.getSheetByName(names[i]);
    if (!sh) continue;
    var r = escanearDuplicadosColumnaE_(sh);
    totalGroups += r.groups.length;
    totalRows += r.affectedRows;
    lines.push(
      names[i] + ': ' + r.groups.length + ' IDs duplicados (' + r.affectedRows + ' filas)'
    );
  }

  SpreadsheetApp.getUi().alert(
    'Duplicados en hojas principales\n\n' +
      (lines.length ? lines.join('\n') : 'No se encontraron las hojas.') +
      '\n\nTotal IDs repetidos: ' +
      totalGroups +
      '\nFilas afectadas: ' +
      totalRows +
      '\n\nRevisa la hoja "' +
      DUP_REPORT_SHEET +
      '" y las celdas naranjas en E.'
  );
}

/**
 * Quita el color naranja de la columna E (no borra datos).
 */
function limpiarMarcasDuplicados() {
  var sheet = SpreadsheetApp.getActiveSheet();
  var lastRow = sheet.getLastRow();
  if (lastRow < 2) return;
  sheet.getRange(2, DUP_COL_ID, lastRow, DUP_COL_ID).setBackground(null);
  SpreadsheetApp.getUi().alert(
    'Marcas naranjas quitadas en columna E de "' + sheet.getName() + '".'
  );
}

/**
 * @param {GoogleAppsScript.Spreadsheet.Sheet} sheet
 * @return {{groups:Array, affectedRows:number, scanned:number}}
 */
function escanearDuplicadosColumnaE_(sheet) {
  var lastRow = sheet.getLastRow();
  var out = { groups: [], affectedRows: 0, scanned: 0 };
  if (lastRow < 2) return out;

  var idRange = sheet.getRange(2, DUP_COL_ID, lastRow, DUP_COL_ID);
  var titleRange = sheet.getRange(2, DUP_COL_TITLE, lastRow, DUP_COL_TITLE);
  var ids = idRange.getValues();
  var titles = titleRange.getValues();

  // Mapa: id → [{row, title}]
  var map = {};
  for (var i = 0; i < ids.length; i++) {
    var raw = ids[i][0];
    var id = normalizeTmdbId_(raw);
    if (!id) continue;
    out.scanned++;
    var row = i + 2;
    var title = String(titles[i][0] || '').trim();
    if (!map[id]) map[id] = [];
    map[id].push({ row: row, title: title, raw: raw });
  }

  // Limpiar fondos previos en E y remarcar solo duplicados
  idRange.setBackground(null);

  var reportRows = [];
  reportRows.push([
    'Hoja',
    'TMDB_ID',
    'Veces',
    'Filas',
    'Títulos',
    'Acción sugerida'
  ]);

  var idsSorted = Object.keys(map).sort(function (a, b) {
    return Number(a) - Number(b);
  });

  for (var k = 0; k < idsSorted.length; k++) {
    var tid = idsSorted[k];
    var entries = map[tid];
    if (entries.length < 2) continue;

    out.groups.push({ id: tid, entries: entries });
    out.affectedRows += entries.length;

    var rowNums = [];
    var titleList = [];
    for (var e = 0; e < entries.length; e++) {
      rowNums.push(String(entries[e].row));
      titleList.push(
        'F' + entries[e].row + ': ' + (entries[e].title || '(sin título)')
      );
      sheet.getRange(entries[e].row, DUP_COL_ID).setBackground(DUP_COLOR);
      sheet
        .getRange(entries[e].row, DUP_COL_ID)
        .setNote(
          'ID duplicado ' +
            tid +
            ' también en filas: ' +
            rowNums.join(', ')
        );
    }

    reportRows.push([
      sheet.getName(),
      tid,
      entries.length,
      rowNums.join(', '),
      titleList.join(' | '),
      'Revisar cuál URL conservar y borrar/corregir la fila sobrante'
    ]);
  }

  escribirInformeDuplicados_(reportRows);
  return out;
}

/**
 * @param {*} raw
 * @return {string} id numérico o ''
 */
function normalizeTmdbId_(raw) {
  if (raw === null || raw === undefined || raw === '') return '';
  var s = String(raw).trim();
  var m = s.match(/(?:movie|tv|pelicula|serie)\s*[:#-]?\s*(\d+)/i);
  if (m) return m[1];
  if (/^\d+(\.0+)?$/.test(s)) return String(parseInt(s, 10));
  var only = s.match(/(\d{2,})/);
  return only ? only[1] : '';
}

/**
 * @param {Array<Array>} rows
 */
function escribirInformeDuplicados_(rows) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var report = ss.getSheetByName(DUP_REPORT_SHEET);
  if (!report) {
    report = ss.insertSheet(DUP_REPORT_SHEET);
  } else {
    report.clear();
  }

  if (rows.length <= 1) {
    report.getRange(1, 1, 1, 2).setValues([
      ['Sin duplicados', new Date()]
    ]);
    return;
  }

  report.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
  report.getRange(1, 1, 1, rows[0].length).setFontWeight('bold');
  report.setFrozenRows(1);
  report.autoResizeColumns(1, rows[0].length);

  // Ordenar informe dejando encabezado
  if (rows.length > 2) {
    report
      .getRange(2, 1, rows.length - 1, rows[0].length)
      .sort({ column: 3, ascending: false });
  }
}

/**
 * @param {string} sheetName
 * @param {Object} result
 */
function mostrarResultadoDuplicados_(sheetName, result) {
  var msg =
    '=== IDs DUPLICADOS (columna E) ===\n' +
    'Hoja: ' +
    sheetName +
    '\nIDs escaneados: ' +
    result.scanned +
    '\nIDs repetidos: ' +
    result.groups.length +
    '\nFilas afectadas: ' +
    result.affectedRows;

  if (result.groups.length) {
    msg += '\n\nEjemplos:';
    var max = Math.min(result.groups.length, 8);
    for (var i = 0; i < max; i++) {
      var g = result.groups[i];
      var rows = g.entries
        .map(function (x) {
          return 'F' + x.row;
        })
        .join(', ');
      msg += '\n• ID ' + g.id + ' → ' + g.entries.length + ' veces (' + rows + ')';
    }
    msg +=
      '\n\nLas celdas E duplicadas están en naranja.\nDetalle completo en la hoja "' +
      DUP_REPORT_SHEET +
      '".';
  } else {
    msg += '\n\n✓ No hay IDs duplicados.';
  }

  SpreadsheetApp.getUi().alert(msg);
}
