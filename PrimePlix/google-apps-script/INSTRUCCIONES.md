# Integración Google Sheets → Plix

## Qué hace

Apps Script publica un endpoint **solo lectura** que convierte filas de tu hoja en JSON. El frontend (`scripts/google-sheets-api.js`) consulta ese endpoint, cachea la respuesta y enriquece fichas / reproducción **sin borrar** el HTML estático.

Si `apiUrl` está vacío o la API falla, la web sigue con el contenido local.

## 1. Identificar el ID de tu Google Sheet

En la barra del navegador:

`https://docs.google.com/spreadsheets/d/ESTE_ES_EL_ID/edit`

Copia `ESTE_ES_EL_ID` (entre `/d/` y `/edit`).

## 2. Nombres de hojas (configurables)

Por defecto el allowlist del script acepta:

| Clave en `sheets-config.js` | Nombre de hoja |
| --- | --- |
| `movies` | `Peliculas` |
| `series` | `Series` |
| `episodes` | `Episodios` |
| `servers` | `Servidores` |
| `config` | `Configuracion` |

Si usas otros nombres:

1. Cámbialos en `ALLOWED_SHEETS` de `Code.gs`.
2. Cámbialos en `PLIX_SHEETS_CONFIG.sheets` de `scripts/sheets-config.js`.

Encabezados sugeridos (no obligatorios; el cliente los mapea):

`id`, `tmdb_id`, `titulo`, `tipo`, `portada`, `url`, `url_video`, `servidor`, `temporada`, `episodio`, `idioma`, `activo`

## 3. Desplegar Apps Script

1. Abre la hoja → **Extensiones → Apps Script**.
2. Pega el contenido de `Code.gs`.
3. Pon tu ID en `SPREADSHEET_ID = '...'`.
4. Guarda el proyecto.
5. **Implementar → Nueva implementación → Tipo: Aplicación web**.
   - **Ejecutar como:** Yo
   - **Quién tiene acceso:** Cualquiera
6. Autoriza los permisos (solo acceso a esa hoja / spreadsheets).
7. Copia la URL que termina en `/exec`.

## 4. Configurar el proyecto

En `scripts/sheets-config.js`:

```js
apiUrl: "https://script.google.com/macros/s/XXXX/exec",
```

Opcional: ajusta `sheets`, `columns`, `cacheTtlMs`.

## 5. Probar que la API devuelve JSON

En el navegador o con curl (sustituye URL y hoja):

```text
https://script.google.com/macros/s/XXXX/exec?sheet=Peliculas
```

Debes ver algo como:

```json
{
  "ok": true,
  "data": [ { "titulo": "...", "tmdb_id": "..." } ],
  "sheet": "Peliculas",
  "headers": ["titulo", "tmdb_id"],
  "count": 1,
  "status": 200
}
```

Prueba también una hoja no permitida (`?sheet=Secretos`) → `ok: false` y status 403 en el JSON.

## 6. Cards automáticas desde columna E + URL (columna B)

En `LzPlus` y `Series LZ` el layout fijo es:

| Columna | Uso |
| --- | --- |
| A | Título (lo rellena TMDB) |
| B | URL de video |
| E | TMDB ID (obligatorio para mostrar la card) |
| F–K | Portada, backdrop, sinopsis, tipo, año, duración |

Flujo:

1. Pon el **TMDB ID** en la columna **E** y la **URL** en la **B** (misma fila).
2. En la hoja: **Plix TMDB → Actualizar todo desde IDs (col E)** (o activa el auto por ID).
3. Redeploy / guarda `Code.gs` si aún no tiene el mapeo fijo de columnas.
4. Al abrir la web, aparecen filas **Películas** y **Series** con una card por cada ID.
5. Al reproducir, se usa la URL de la columna B de esa misma fila.

Solo se muestran filas que tengan ID en E. Sin ID → no hay card.

## 7. Cómo coincide el contenido estático

1. `data-tmdb-id` / `data-content-id` en la tarjeta (si existen).
2. Título normalizado (ignora sufijos tipo `- T1`).

Para forzar match estable, añade en el HTML de una tarjeta:

```html
<div class="content" data-tmdb-id="1396" data-content-id="breaking-bad">
```

## 8. Seguridad (importante)

- No pongas tokens ni claves privadas en el JavaScript público.
- La app web con acceso “Cualquiera” **es pública de lectura**: quien tenga la URL `/exec` puede leer las hojas del allowlist.
- Ocultar URLs en el código **no las protege**: si el navegador las recibe, se pueden inspeccionar.
- Para datos privados o escritura hace falta un backend con autenticación (no aplica a GitHub Pages estático solo).

## 9. CORS

El cliente usa `fetch` con `redirect: follow` y, si falla, **JSONP** (`callback=`). Ambos están soportados en `Code.gs`.

## 10. Autocompletado con TMDB

La clave de TMDB **no** va en el JavaScript público (GitHub Pages). Vive solo en Apps Script.

1. En el mismo proyecto Apps Script, crea un archivo y pega `TMDB.gs`.
2. Ejecuta la función `guardarTmdbApiKey` (una vez) → autoriza UrlFetch.
3. Recarga la hoja de cálculo → menú **Plix TMDB**.
4. En cada fila pon al menos `tmdb_id` **o** `titulo`.
5. Usa **Enriquecer Películas** / **Enriquecer Series**.

Rellena solo celdas vacías: `tmdb_id`, `titulo`, `tipo`, `portada`, `backdrop`, `sinopsis`, `anio`, `duracion`, `id`, `activo`.  
No toca `url_video`.

Si el repo es público: después de guardar la key, bórrala del código de `guardarTmdbApiKey` y déjala solo en **Configuración del proyecto → Propiedades del script**.

## 11. Verificar URLs activas (columna B → D)

1. Pega `URLCheck.gs` y actualiza el menú en `TMDB.gs`.
2. Recarga la hoja (F5).
3. **Plix URLs → ⚡ Activar verificación automática** (una vez; autoriza).
4. Comportamiento:
   - Al editar una URL en la **columna B**, se verifica esa fila al momento.
   - Cada **1 hora** barre por lotes `LzPlus` y `Series LZ` (ajustable en `URL_AUTO_SHEETS`).
   - Si una URL vuelve a funcionar, el barrido la pone en **✓** sola.
5. Columna **D**: ✓ verde / ? amarillo / ✗ rojo.
6. Manual: **Verificar desde el inicio** o **Verificar URLs (lote)**.
7. Para apagar: **Desactivar verificación automática**.

Nota: la prueba sale desde servidores de Google. Un **?** amarillo no es “caída”: el host puede bloquear a Google pero abrir en el navegador.

## 12. Pasos manuales (no se pueden hacer desde Cursor)

- Crear / editar tu Google Sheet y rellenar filas (E = ID, B = URL).
- Pegar `Code.gs` (+ `TMDB.gs`), poner `SPREADSHEET_ID` y desplegar / **actualizar** la aplicación web.
- Copiar la URL `/exec` a `sheets-config.js`.
- Verificar el JSON: `?sheet=LzPlus` debe traer `tmdb_id`, `url_video`, `portada`, etc.
- Ejecutar `guardarTmdbApiKey` y **Actualizar todo desde IDs (col E)**.
- Recargar la web: deben aparecer las cards de Películas / Series.
