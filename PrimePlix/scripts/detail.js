(function () {
  "use strict";

  const SERIES_HINT = /(?:\s[-–—]\s*T\d+|temporada|serie\b|series\b|capitulo|capítulo)/i;

  const RELATED = [
    { title: "Enamorándome de mi ex", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/2eb8637aa1f3d21492ba6a207715607481d19785b5ba2aa14fa329fd223c5113._UR1920,1080_SX624_FMjpg_.jpg" },
    { title: "Los Caballeros no Tienen Memoria", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/f994036de66f32c024c7fbc382031c25c02c1f386c868b4d9425f7e6f23b5351._UR1920,1080_SX624_FMpng_.png" },
    { title: "El Curioso Caso De Benjamin Button", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/6128084a323e5d3989e42ef7e04f1ea351fde09c338a0740bc0f0f9a9adb8b90._UR1920,1080_SX624_FMjpg_.jpg" },
    { title: "Algo Azul", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/6c5363f0577f273bfdd5b6836d755e29d12dadacb1fc456e22f2643a3c4a92c4._UR1920,1080_SX624_FMjpg_.jpg" },
    { title: "Reacher - T1", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/1a5b45adc19d43122dee2807018f669b3002d936569104228d0fb44b30efc615._UR1920,1080_SX624_FMpng_.png", type: "series" },
    { title: "Citadel - T1", img: "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/3c401ac4e19a002c9b7ef6d1aad1c5871c2843c0397b16949bcba0cec4c954c5._UR1920,1080_SX624_FMpng_.png", type: "series" }
  ];

  const EPISODE_IMGS = [
    "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/5b633b16af3a2fc47002f7019fa71836bff6ed93c1a72e81521a3bcd7cc601cc._BR-6_AC_SX720_FMjpg_.jpg",
    "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/9e57c810d9a1ccfad2b26db8d47201531f059f250e4feba399fde0b195ed2d11._BR-6_AC_SX720_FMjpg_.jpg",
    "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/304bf0b62a27fc09b012e5d81fadb5300f5538795ea81becc2e3477552ec2c36._BR-6_AC_SX720_FMjpg_.jpg",
    "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/08300b44ae0eac661e451e2f7504c481cee3440a35640c170b4146938bd05d9b._BR-6_AC_SX720_FMjpg_.jpg",
    "https://images-na.ssl-images-amazon.com/images/S/pv-target-images/161e7315bed724113a9985ae2b1f79a00791910fa040ea23da96608246e2c9e3._BR-6_AC_SX720_FMjpg_.jpg",
    "https://m.media-amazon.com/images/S/pv-target-images/ded025bfa47522c2fb8f1e8a1e526114c224ae2190ea773d103a3c11756365b9._BR-6_AC_SX720_FMjpg_.jpg"
  ];

  const ICONS = {
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>',
    plus: '<img src="icons/plus.png" alt="">',
    like: '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M21.3 10.08a3 3 0 0 0-2.3-1.08H14.44l.56-1.43a4.5 4.5 0 0 0-.48-3.8A4.4 4.4 0 0 0 11.11 2a1.5 1.5 0 0 0-1.41.59L7.35 9H5a3 3 0 0 0-3 3v7a3 3 0 0 0 3 3h12.73a3 3 0 0 0 2.95-2.46l1.27-7a3 3 0 0 0-.65-2.46ZM7 20H5a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1h2v9Zm13-7.82-1.27 7A1 1 0 0 1 17.73 20H9V10.21l2.72-6.12a2.4 2.4 0 0 1 1.52.87 2.5 2.5 0 0 1 .22 1.91L13.1 8.3a2.5 2.5 0 0 0 1.34 2.7H19a1 1 0 0 1 .77.36 1 1 0 0 1 .23.82Z" fill="currentColor"/></svg>',
    dislike: '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path fill-rule="evenodd" d="M20.27 15.72a3 3 0 0 0 1.68-3.26l-1.27-7A3 3 0 0 0 17.73 3H5a3 3 0 0 0-3 3v7a3 3 0 0 0 3 3h2.35l2.85 6.41a1.5 1.5 0 0 0 1.41.59 4.4 4.4 0 0 0 4.4-2.46 4.5 4.5 0 0 0 .49-3.81l.56-1.43h4.56ZM18.73 5.82 20 12.82a1 1 0 0 1-.23.82 1 1 0 0 1-.77.36h-4.56a2.5 2.5 0 0 0-1.34 2.7l.53 1.43a2.5 2.5 0 0 1-.22 1.91 2.4 2.4 0 0 1-1.52.87L9 14.79V5h8.73a1 1 0 0 1 1 1ZM7 5H5a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h2V5Z" fill="currentColor"/></svg>',
    share: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11A2.99 2.99 0 0 0 21 5a3 3 0 1 0-5.91.7L8.04 9.81A3 3 0 1 0 8 14c.18 0 .36-.02.53-.06l7.12 4.16c-.05.21-.08.43-.08.65a3 3 0 1 0 3-3Z"/></svg>',
    download: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 3a1 1 0 0 1 1 1v9.59l2.3-2.3a1 1 0 1 1 1.4 1.42l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 1 1 1.4-1.42L11 13.6V4a1 1 0 0 1 1-1ZM5 18a1 1 0 0 1 1 1h12a1 1 0 1 1 0 2H6a1 1 0 0 1-1-1v-1Z"/></svg>',
    close: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M18.3 5.71a1 1 0 0 0-1.41 0L12 10.59 7.11 5.7A1 1 0 0 0 5.7 7.11L10.59 12 5.7 16.89a1 1 0 1 0 1.41 1.41L12 13.41l4.89 4.89a1 1 0 0 0 1.41-1.41L13.41 12l4.89-4.89a1 1 0 0 0 0-1.4Z"/></svg>',
    trending: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6h-6z"/></svg>',
    award: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2 9.2 8.6 2 9.2l5.5 4.5L5.6 21 12 17.3 18.4 21l-1.9-7.3L22 9.2l-7.2-.6L12 2Z"/></svg>',
    cc: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M4.5 4A2.5 2.5 0 0 0 2 6.5v11A2.5 2.5 0 0 0 4.5 20h15a2.5 2.5 0 0 0 2.5-2.5v-11A2.5 2.5 0 0 0 19.5 4h-15ZM8 13h8v1.5H8V13Zm-2 3h3V17.5H6V16Zm5 0h7V17.5h-7V16Z"/></svg>'
  };

  let overlay;
  let root;
  let lastFocus = null;

  function qs(sel, el) {
    return (el || document).querySelector(sel);
  }

  function qsa(sel, el) {
    return Array.from((el || document).querySelectorAll(sel));
  }

  function isSeriesCard(card, title) {
    if (card?.dataset?.type === "series") return true;
    if (card?.dataset?.type === "movie") return false;
    return SERIES_HINT.test(title || "");
  }

  function parseGenres(text) {
    return (text || "")
      .split(/[•·|,]/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function extractFromCard(card) {
    const title =
      card.querySelector(".content-tooltip-title")?.textContent?.trim() ||
      card.querySelector(".title")?.textContent?.trim() ||
      card.querySelector(".content-image")?.getAttribute("alt")?.trim() ||
      card.getAttribute("aria-label") ||
      "Título";
    const img =
      card.querySelector(".content-image")?.getAttribute("src") ||
      card.querySelector("img")?.getAttribute("src") ||
      "";
    const synopsis =
      card.querySelector(".content-tooltip-description")?.textContent?.trim() ||
      card.querySelector(".synopsis")?.textContent?.trim() ||
      "Descubre esta historia disponible en Plix.";
    const runtime = card.querySelector(".runtime")?.textContent?.trim() || "";
    const year = card.querySelector(".year")?.textContent?.trim() || "2024";
    const genreText = card.querySelector(".genre")?.textContent?.trim() || "Drama";
    const maturity = card.querySelector(".age-rating")?.textContent?.trim() || "13+";
    const type = isSeriesCard(card, title) ? "series" : "movie";

    return {
      type,
      title,
      img,
      synopsis,
      runtime,
      year,
      genres: parseGenres(genreText),
      maturity,
      imdb: type === "series" ? "8,0" : "5,8",
      cast: type === "series"
        ? ["Tom Hiddleston", "Hugh Laurie", "Olivia Colman"]
        : ["Diane Lane", "Arnaud Viard", "Alec Baldwin"],
      labelBadge: type === "series" ? "" : "EL MEJOR DRAMA",
      hvm: type === "series"
        ? { icon: "award", text: "Ganadora de 3 GOLDEN GLOBES®" }
        : { icon: "trending", text: "N.º 4 en películas de drama" },
      seasons: type === "series" ? ["Temporada 1", "Temporada 2"] : [],
      seasonCount: type === "series" ? "2 temporadas" : ""
    };
  }

  function buildEpisodes(data) {
    const count = 6;
    const synopses = [
      "El protagonista se enfrenta a un giro inesperado que cambia el rumbo de su misión.",
      "Surgen nuevas alianzas mientras el enemigo acecha desde las sombras.",
      "Un secreto del pasado sale a la luz y pone en peligro a todos.",
      "La tensión crece cuando descubren una filtración en el equipo.",
      "Una carrera contra el tiempo obliga a tomar decisiones imposibles.",
      "El enfrentamiento final revela quiénes son realmente los aliados."
    ];
    return Array.from({ length: count }, (_, i) => ({
      n: i + 1,
      title: `Episodio ${i + 1}`,
      synopsis: synopses[i],
      runtime: i % 2 === 0 ? "1 h" : `${50 + i} min`,
      date: `${18 + i} abr 2016`,
      maturity: data.maturity || "16+",
      img: EPISODE_IMGS[i % EPISODE_IMGS.length] || data.img
    }));
  }

  function ensureOverlay() {
    if (overlay) return overlay;

    overlay = document.createElement("div");
    overlay.className = "detail-overlay";
    overlay.id = "detail-overlay";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");
    overlay.setAttribute("aria-label", "Detalle del título");
    overlay.innerHTML = `
      <button type="button" class="detail-close" aria-label="Cerrar">${ICONS.close}</button>
      <div class="detail-root"></div>
    `;
    document.body.appendChild(overlay);

    qs(".detail-close", overlay).addEventListener("click", closeDetail);
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) closeDetail();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && overlay.classList.contains("is-open")) {
        closeDetail();
      }
    });

    root = qs(".detail-root", overlay);
    return overlay;
  }

  function iconBtn(label, iconHtml, extraClass) {
    return `<button type="button" class="detail-icon-btn ${extraClass || ""}" aria-label="${label}">${iconHtml}</button>`;
  }

  function renderMeta(data) {
    const parts = [];
    parts.push(`<span>IMDb ${data.imdb}/10</span>`);
    parts.push(`<span class="sep">•</span><span>${data.year}</span>`);
    if (data.type === "series" && data.seasonCount) {
      parts.push(`<span class="sep">•</span><span>${data.seasonCount}</span>`);
    } else if (data.runtime) {
      parts.push(`<span class="sep">•</span><span>${data.runtime}</span>`);
    }
    data.genres.forEach((g, i) => {
      parts.push(`<span class="sep">•</span><a href="#">${g}</a>`);
      if (i === data.genres.length - 1 && data.type === "movie") {
        parts.push(`<span class="sep">•</span><span>Romántico</span>`);
      }
      if (i === data.genres.length - 1 && data.type === "series") {
        parts.push(`<span class="sep">•</span><span>Oscura</span>`);
      }
    });
    return parts.join("");
  }

  function renderRelated(data) {
    const items = RELATED.filter((r) => r.title !== data.title).slice(0, 8);
    return items
      .map(
        (r) => `
      <button type="button" class="detail-related-card" data-related-title="${r.title}" data-related-type="${r.type || "movie"}" data-related-img="${r.img}">
        <img src="${r.img}" alt="" loading="lazy">
        <span>${r.title}</span>
      </button>`
      )
      .join("");
  }

  function renderEpisodes(episodes) {
    return episodes
      .map(
        (ep) => `
      <article class="detail-episode">
        <div class="detail-episode-shot">
          <img src="${ep.img}" alt="" loading="lazy">
          <button type="button" class="detail-episode-play" aria-label="Reproducir T1 E${ep.n}">
            <span>${ICONS.play}</span>
          </button>
        </div>
        <div class="detail-episode-body">
          <h3>${ep.n}. ${ep.title}</h3>
          <p>${ep.synopsis}</p>
          <div class="detail-episode-meta">
            <span class="detail-maturity">${ep.maturity}</span>
            <span class="detail-icon-badge" aria-label="Subtítulos">${ICONS.cc}</span>
            <span>${ep.runtime}</span>
            <span>${ep.date}</span>
          </div>
        </div>
        <button type="button" class="detail-episode-dl" aria-label="Descargar episodio ${ep.n}">${ICONS.download}</button>
      </article>`
      )
      .join("");
  }

  function renderDetails(data) {
    const directors = data.type === "series" ? "Susanne Bier" : "Eleanor Coppola";
    const studio = data.type === "series" ? "The Ink Factory" : "Protagonist Pictures";
    const warnings =
      data.type === "series"
        ? "desnudez, violencia, consumo de tabaco, lenguaje malsonante, contenido sexual"
        : "consumo de tabaco";
    const audio =
      data.type === "series"
        ? "Español (España), English, Español (Latinoamérica)"
        : "English, Español (Latinoamérica)";
    const subs =
      data.type === "series"
        ? "Español (España), English [CC], Español (Latinoamérica)"
        : "Español (Latinoamérica) [CC]";

    return `
      <div class="detail-details-grid">
        <div>
          <div class="detail-block">
            <h3>${data.title.replace(/\s[-–—]\s*T\d+.*$/i, "").replace(/\s*-\s*Temporada.*$/i, "")}</h3>
            <div class="detail-meta" style="margin-bottom:12px">${renderMeta(data)}</div>
            <p>${data.synopsis}</p>
          </div>
          <div class="detail-block">
            <h3>Creadores y reparto</h3>
            <dl class="detail-dl">
              <dt>Dirección</dt>
              <dd><a href="#">${directors}</a></dd>
              <dt>Reparto</dt>
              <dd>${data.cast.map((c) => `<a href="#">${c}</a>`).join(", ")}</dd>
              <dt>Estudio</dt>
              <dd>${studio}</dd>
            </dl>
          </div>
        </div>
        <div>
          <div class="detail-block">
            <h3>Advertencias de contenido</h3>
            <div class="detail-maturity-row" style="margin-bottom:10px">
              <span class="detail-maturity">${data.maturity}</span>
            </div>
            <p>${warnings}</p>
          </div>
          <div class="detail-block">
            <h3>Idiomas de audio</h3>
            <div class="detail-maturity-row" style="margin-bottom:10px">
              <span class="detail-label-badge">5.1</span>
            </div>
            <p>${audio}</p>
          </div>
          <div class="detail-block">
            <h3>Subtítulos</h3>
            <div class="detail-maturity-row" style="margin-bottom:10px">
              <span class="detail-icon-badge">${ICONS.cc}</span>
            </div>
            <p>${subs}</p>
          </div>
        </div>
      </div>
      <p class="detail-terms">Al hacer clic en Reproducir, aceptas nuestros <a href="#">Términos de uso</a>.</p>
      <div class="detail-footer-links">
        <div>
          <h4>Comentarios</h4>
          <button type="button">Envíanos tus comentarios</button>
        </div>
        <div>
          <h4>Ayuda</h4>
          <a href="#">Obtener ayuda</a>
        </div>
      </div>`;
  }

  function render(data) {
    ensureOverlay();
    const playLabel =
      data.type === "series" ? "Reproducir T1 E1" : "Reproducir";
    const episodes = data.type === "series" ? buildEpisodes(data) : [];
    const seasonOptions = (data.seasons || [])
      .map((s, i) => `<option value="${i + 1}" ${i === 0 ? "selected" : ""}>${s}</option>`)
      .join("");

    const tabs =
      data.type === "series"
        ? `
        <button type="button" class="detail-tab is-active" data-tab="episodes">Episodios</button>
        <button type="button" class="detail-tab" data-tab="related">Relacionado</button>
        <button type="button" class="detail-tab" data-tab="details">Detalles</button>`
        : `
        <button type="button" class="detail-tab is-active" data-tab="related">Relacionado</button>
        <button type="button" class="detail-tab" data-tab="details">Detalles</button>`;

    root.innerHTML = `
      <section class="detail-atf">
        <div class="detail-hero-bg"><img src="${data.img}" alt=""></div>
        <div class="detail-atf-inner">
          <a class="detail-channel" href="#" aria-label="Prime Video">
            <img src="https://m.media-amazon.com/images/G/01/digital/video/merch/subs/benefit-id/m-r/Prime/logos/channels-logo-color._CB554929912_SY35_FMpng_.png" alt="prime video">
          </a>
          <h1 class="detail-title">${data.title}</h1>
          <div class="detail-actions">
            <button type="button" class="detail-play">${ICONS.play}<span>${playLabel}</span></button>
            <div class="detail-icon-actions">
              ${iconBtn(data.type === "series" ? "Añadir temporada a Mi lista" : "Añadir a Mi lista", ICONS.plus)}
              ${iconBtn("Me gusta", ICONS.like)}
              ${iconBtn("No es para mí", ICONS.dislike)}
              ${iconBtn("Compartir", ICONS.share)}
              ${iconBtn(data.type === "series" ? "Descargar episodio 1" : "Descargar", ICONS.download)}
            </div>
          </div>
          <div class="detail-entitlement">
            <span class="prime-check" aria-hidden="true"></span>
            <span>Se incluye con Prime</span>
          </div>
          <div class="detail-badges-row">
            ${data.labelBadge ? `<span class="detail-label-badge">${data.labelBadge}</span>` : ""}
            ${
              data.hvm
                ? `<div class="detail-hvm">${ICONS[data.hvm.icon] || ""}${data.hvm.text}</div>`
                : ""
            }
          </div>
          <p class="detail-synopsis">${data.synopsis}</p>
          <div class="detail-meta">${renderMeta(data)}</div>
          <p class="detail-cast"><strong>Reparto:</strong> ${data.cast
            .map((c) => `<a href="#">${c}</a>`)
            .join(", ")}</p>
          <div class="detail-maturity-row">
            <span class="detail-maturity">${data.maturity}</span>
            <span class="detail-icon-badge" aria-label="Subtítulos">${ICONS.cc}</span>
          </div>
          ${
            data.type === "series"
              ? `<div class="detail-season-wrap">
                  <label class="sr-only" for="detail-season">Temporada</label>
                  <select id="detail-season" class="detail-season-select" aria-label="Selector de temporada">${seasonOptions}</select>
                </div>`
              : ""
          }
        </div>
      </section>
      <section class="detail-btf">
        <div class="detail-tabs" role="tablist">${tabs}</div>
        ${
          data.type === "series"
            ? `<div class="detail-panel is-active" data-panel="episodes">
                <div class="detail-episodes-header">
                  <h2 class="detail-section-title" style="margin:0">${episodes.length} episodios</h2>
                </div>
                <div class="detail-episodes">${renderEpisodes(episodes)}</div>
              </div>`
            : ""
        }
        <div class="detail-panel ${data.type === "movie" ? "is-active" : ""}" data-panel="related">
          <h2 class="detail-section-title">Otros clientes también vieron</h2>
          <div class="detail-related-row">${renderRelated(data)}</div>
        </div>
        <div class="detail-panel" data-panel="details">
          ${renderDetails(data)}
        </div>
      </section>
    `;

    wireDetailUI(data);
  }

  function wireDetailUI(data) {
    qsa(".detail-tab", root).forEach((tab) => {
      tab.addEventListener("click", () => {
        const name = tab.dataset.tab;
        qsa(".detail-tab", root).forEach((t) => t.classList.toggle("is-active", t === tab));
        qsa(".detail-panel", root).forEach((p) =>
          p.classList.toggle("is-active", p.dataset.panel === name)
        );
      });
    });

    qsa(".detail-icon-btn", root).forEach((btn) => {
      btn.addEventListener("click", () => btn.classList.toggle("is-active"));
    });

    qsa(".detail-related-card", root).forEach((card) => {
      card.addEventListener("click", () => {
        const next = {
          type: card.dataset.relatedType === "series" ? "series" : "movie",
          title: card.dataset.relatedTitle,
          img: card.dataset.relatedImg,
          synopsis: "Descubre más títulos similares disponibles en Plix.",
          runtime: card.dataset.relatedType === "series" ? "" : "1 h 40 min",
          year: "2020",
          genres: card.dataset.relatedType === "series" ? ["Drama", "Suspense"] : ["Comedia", "Romance"],
          maturity: "13+",
          imdb: "7,2",
          cast:
            card.dataset.relatedType === "series"
              ? ["Elenco principal", "Actriz invitada", "Actor secundario"]
              : ["Protagonista", "Coprotagonista", "Reparto"],
          labelBadge: "",
          hvm: { icon: "trending", text: "Popular en Plix" },
          seasons: card.dataset.relatedType === "series" ? ["Temporada 1"] : [],
          seasonCount: card.dataset.relatedType === "series" ? "1 temporada" : ""
        };
        render(next);
        overlay.scrollTop = 0;
      });
    });

    const season = qs("#detail-season", root);
    if (season) {
      season.addEventListener("change", () => {
        const epPanel = qs('[data-panel="episodes"] .detail-episodes', root);
        const count = qs(".detail-episodes-header .detail-section-title", root);
        if (epPanel) {
          const eps = buildEpisodes(data);
          epPanel.innerHTML = renderEpisodes(eps);
          if (count) count.textContent = `${eps.length} episodios`;
        }
      });
    }
  }

  function openDetail(data) {
    ensureOverlay();
    lastFocus = document.activeElement;
    render(data);
    overlay.classList.add("is-open");
    document.body.classList.add("detail-open");
    overlay.scrollTop = 0;
    qs(".detail-close", overlay)?.focus();
  }

  function closeDetail() {
    if (!overlay) return;
    overlay.classList.remove("is-open");
    document.body.classList.remove("detail-open");
    if (lastFocus && typeof lastFocus.focus === "function") {
      lastFocus.focus();
    }
  }

  function openFromCard(card) {
    if (!card) return;
    openDetail(extractFromCard(card));
  }

  function init() {
    ensureOverlay();

    document.addEventListener("click", (e) => {
      const detailsBtn = e.target.closest(".details-btn");
      if (detailsBtn) {
        e.preventDefault();
        e.stopPropagation();
        openFromCard(detailsBtn.closest(".content"));
        return;
      }

      const card = e.target.closest(".content");
      if (!card) return;
      if (e.target.closest(".play-button, .action-btn, a")) return;
      openFromCard(card);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  window.PlixDetail = { open: openDetail, close: closeDetail, openFromCard };
})();
