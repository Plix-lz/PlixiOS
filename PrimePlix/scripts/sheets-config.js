/**
 * Configuración de Google Sheets / Apps Script para Plix.
 * Completa apiUrl con la URL /exec del despliegue. Deja vacío para
 * desactivar Sheets y usar solo el contenido estático del HTML.
 *
 * Catálogo dinámico: filas con TMDB ID en columna E se convierten en cards.
 * La URL de video sale de la columna B (misma fila).
 * Los metadatos (portada, título, etc.) deben estar rellenados con Plix TMDB
 * en la hoja (menú → Actualizar todo desde IDs).
 */
window.PLIX_SHEETS_CONFIG = {
  /** URL de la aplicación web de Apps Script (termina en /exec). */
  apiUrl: "https://script.google.com/macros/s/AKfycbwPLkpawclmWF1l0I-WFay4BwYYCCF11AIne9EQ3t9AE151qlQzZt0Qw1644aMFLYcr/exec",

  /**
   * Claves lógicas → nombre real de la hoja en tu documento.
   * Cambia los valores si usas otros nombres.
   */
  sheets: {
    movies: "LzPlus",
    series: "Series LZ",
    episodes: "Episodios",
    servers: "Servidores",
    config: "Configuracion"
  },

  /**
   * Mapeo de campos canónicos → posibles encabezados (ya normalizados
   * a minúsculas_con_guion_bajo por la API). El cliente prueba en orden.
   */
  columns: {
    id: ["id"],
    tmdbId: ["tmdb_id", "tmdbid", "tmdb"],
    title: ["titulo", "title", "nombre", "name"],
    type: ["tipo", "type"],
    cover: ["portada", "cover", "poster", "imagen", "img"],
    backdrop: ["backdrop", "fondo", "banner", "backdrop_path"],
    url: ["url", "link"],
    videoUrl: ["url_video", "video", "video_url", "stream", "embed", "url", "link"],
    server: ["servidor", "server", "host"],
    season: ["temporada", "season", "temp"],
    episode: ["episodio", "episode", "cap", "capitulo"],
    language: ["idioma", "language", "lang", "audio"],
    active: ["activo", "active", "enabled"],
    synopsis: ["sinopsis", "synopsis", "descripcion", "description"],
    year: ["anio", "año", "year"],
    runtime: ["duracion", "runtime", "duration"],
    maturity: ["clasificacion", "maturity", "age", "edad"],
    seriesId: ["serie_id", "series_id", "show_id", "parent_id"],
    seriesTmdbId: ["serie_tmdb_id", "series_tmdb_id", "show_tmdb_id"]
  },

  /**
   * Filas del home que se rellenan con cards generadas desde Sheets.
   * Solo se muestran ítems que tengan tmdbId (columna E).
   */
  catalog: {
    enabled: true,
    /** Solo filas con ID en E. */
    onlyWithId: true,
    /**
     * Por ahora solo películas (LzPlus). Cuando tengas series,
     * añade de nuevo la fila "series" abajo.
     */
    rows: [
      {
        key: "movies",
        selector: '[data-sheets-row="movies"]',
        section: '[data-sheets-catalog="movies"]',
        emptyMessage: "Añade TMDB IDs en la columna E de LzPlus."
      }
    ]
  },

  /**
   * Si true: la web solo muestra títulos que existan en Sheets (columna E).
   * Oculta el HTML estático de demo para no dejar contenidos “fantasma”.
   */
  onlyFromSheets: true,

  /** Ocultar también el hero estático cuando onlyFromSheets está activo. */
  hideStaticHero: true,

  /** Caché en memoria + sessionStorage (ms). */
  cacheTtlMs: 5 * 60 * 1000,

  /** Prefetch al cargar la página (solo películas por ahora). */
  prefetch: ["movies"],

  /** Mostrar aviso discreto si falla Sheets (no deja la web en blanco). */
  showErrorToast: true
};
