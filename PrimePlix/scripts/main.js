(function () {
    const header = document.getElementById("header");
    const menuToggle = document.getElementById("menuToggle");
    const navOverlay = document.getElementById("navOverlay");
    const searchToggle = document.getElementById("searchToggle");
    const searchWrap = document.querySelector(".search-wrap");
    const categories = document.querySelector(".categories");
    const profileArea = document.getElementById("profileArea");
    const profileToggle = document.getElementById("profileToggle");
    const homeView = document.getElementById("home-view");
    const categoriesView = document.getElementById("categories-view");
    const profilesView = document.getElementById("profiles-view");
    const profilesPage = document.getElementById("profilesPage");
    const profilesEditBtn = document.getElementById("profilesEditBtn");
    const navItems = document.querySelectorAll(".header-menu .nav-item[data-view]");

    function isMobile() {
        return window.matchMedia("(max-width: 900px)").matches;
    }

    function closeNav() {
        if (!header) return;
        header.classList.remove("nav-open");
        if (menuToggle) menuToggle.setAttribute("aria-expanded", "false");
        if (categories) categories.classList.remove("is-open");
    }

    const profileEdit = document.getElementById("profileEdit");
    const profileEditForm = document.getElementById("profileEditForm");
    const profileEditName = document.getElementById("profileEditName");
    const profileEditAvatar = document.getElementById("profileEditAvatar");
    const profileEditAvatarBtn = document.getElementById("profileEditAvatarBtn");
    const profileEditCancel = document.getElementById("profileEditCancel");
    const profileEditSave = document.getElementById("profileEditSave");
    const profileEditPinBtn = document.getElementById("profileEditPinBtn");
    const avatarModal = document.getElementById("avatarModal");
    const pinModal = document.getElementById("pinModal");
    const pinModalInput = document.getElementById("pinModalInput");
    const pinModalToggle = document.getElementById("pinModalToggle");
    const pinModalForm = document.getElementById("pinModalForm");
    const pinModalAvatar = document.getElementById("pinModalAvatar");
    const avatarPickerList = document.getElementById("avatarPickerList");

    let editingProfileId = null;
    let editBaseline = { name: "", avatar: "" };
    let editDraft = { name: "", avatar: "" };

    function setProfilesEditing(editing) {
        if (!profilesPage) return;
        profilesPage.classList.toggle("is-editing", editing);
        if (profilesEditBtn) {
            profilesEditBtn.textContent = editing ? "Edición terminada" : "Editar perfil";
        }
    }

    function closeAvatarModal() {
        if (!avatarModal) return;
        avatarModal.hidden = true;
        document.body.classList.remove("modal-open");
    }

    function closePinModal() {
        if (!pinModal) return;
        pinModal.hidden = true;
        if (pinModalInput) {
            pinModalInput.value = "";
            pinModalInput.type = "password";
        }
        if (pinModalToggle) pinModalToggle.textContent = "Mostrar PIN";
        document.body.classList.remove("modal-open");
    }

    function closeProfileModals() {
        closeAvatarModal();
        closePinModal();
    }

    function updateEditDirtyState() {
        if (!profileEditSave || !profileEditName) return;
        const name = (profileEditName.value || "").trim();
        const avatar = editDraft.avatar || "";
        const changed =
            name !== editBaseline.name ||
            avatar !== editBaseline.avatar;
        const valid = name.length >= 1 && name.length <= 50;
        profileEditSave.disabled = !(changed && valid);
    }

    function setEditAvatar(url) {
        editDraft.avatar = url || "";
        if (profileEditAvatar) {
            profileEditAvatar.style.backgroundImage = url ? "url('" + url + "')" : "";
        }
        if (pinModalAvatar && url) {
            pinModalAvatar.style.backgroundImage = "url('" + url + "')";
        }
        if (avatarPickerList) {
            avatarPickerList.querySelectorAll("[data-avatar]").forEach(function (btn) {
                const selected = btn.getAttribute("data-avatar") === url;
                btn.classList.toggle("is-selected", selected);
                btn.setAttribute("aria-pressed", String(selected));
            });
        }
        updateEditDirtyState();
    }

    function showWhoIsWatching() {
        closeProfileModals();
        editingProfileId = null;
        if (profileEdit) profileEdit.hidden = true;
        if (profilesPage) profilesPage.hidden = false;
    }

    function openProfileEdit(profileCard) {
        if (!profileEdit || !profileCard) return;
        const id = profileCard.getAttribute("data-profile-id");
        const nameEl = profileCard.querySelector(".profile-card-name");
        const avatarEl = profileCard.querySelector(".profile-card-avatar");
        const name = nameEl ? nameEl.textContent.trim() : "";
        let avatar = "";
        if (avatarEl) {
            const bg = avatarEl.style.backgroundImage || "";
            const match = bg.match(/url\(["']?(.*?)["']?\)/i);
            if (match && match[1]) {
                avatar = match[1];
            } else {
                const img = avatarEl.querySelector("img");
                if (img && img.getAttribute("src")) avatar = img.getAttribute("src");
            }
        }

        editingProfileId = id;
        editBaseline = { name: name, avatar: avatar };
        editDraft = { name: name, avatar: avatar };

        if (profileEditName) profileEditName.value = name;
        setEditAvatar(avatar);

        if (profilesPage) profilesPage.hidden = true;
        profileEdit.hidden = false;
        if (profileEditName) {
            window.setTimeout(function () {
                profileEditName.focus();
                profileEditName.select();
            }, 0);
        }
        updateEditDirtyState();
        window.scrollTo({ top: 0, behavior: "auto" });
    }

    function saveProfileEdit() {
        if (!editingProfileId || !profileEditName) return false;
        const name = profileEditName.value.trim();
        if (!name || name.length > 50) return false;

        const card = profilesPage && profilesPage.querySelector(
            '.profile-card[data-profile-id="' + editingProfileId + '"]'
        );
        if (!card) return false;

        const nameEl = card.querySelector(".profile-card-name");
        const avatarEl = card.querySelector(".profile-card-avatar");
        const switchBtn = card.querySelector("[data-profile-switch]");

        if (nameEl) nameEl.textContent = name;
        if (avatarEl) {
            avatarEl.style.backgroundImage = "url('" + editDraft.avatar + "')";
            const img = avatarEl.querySelector("img");
            if (img) {
                img.src = editDraft.avatar;
                img.alt = "";
            }
        }
        if (switchBtn) {
            switchBtn.setAttribute("aria-label", "Cambiar al perfil de " + name);
        }

        try {
            window.localStorage.setItem(
                "plix-profile-" + editingProfileId,
                JSON.stringify({ name: name, avatar: editDraft.avatar })
            );
        } catch (err) { /* ignore */ }

        editBaseline = { name: name, avatar: editDraft.avatar };
        showWhoIsWatching();
        setProfilesEditing(true);
        return true;
    }

    function openAvatarModal() {
        if (!avatarModal) return;
        closePinModal();
        setEditAvatar(editDraft.avatar);
        avatarModal.hidden = false;
        document.body.classList.add("modal-open");
    }

    function openPinModal() {
        if (!pinModal) return;
        closeAvatarModal();
        if (pinModalAvatar && editDraft.avatar) {
            pinModalAvatar.style.backgroundImage = "url('" + editDraft.avatar + "')";
        }
        if (pinModalInput) {
            pinModalInput.value = "";
            pinModalInput.type = "password";
        }
        if (pinModalToggle) pinModalToggle.textContent = "Mostrar PIN";
        pinModal.hidden = false;
        document.body.classList.add("modal-open");
        if (pinModalInput) {
            window.setTimeout(function () {
                pinModalInput.focus();
            }, 0);
        }
    }

    function showView(viewName) {
        const isCategories = viewName === "categories";
        const isProfiles = viewName === "profiles";
        const isHome = !isCategories && !isProfiles;

        if (homeView) {
            homeView.classList.toggle("is-active", isHome);
            homeView.hidden = !isHome;
        }
        if (categoriesView) {
            categoriesView.classList.toggle("is-active", isCategories);
            categoriesView.hidden = !isCategories;
        }
        if (profilesView) {
            profilesView.classList.toggle("is-active", isProfiles);
            profilesView.hidden = !isProfiles;
        }

        document.body.classList.toggle("profiles-mode", isProfiles);
        if (!isProfiles) {
            setProfilesEditing(false);
            showWhoIsWatching();
        }

        navItems.forEach(function (item) {
            if (isCategories) {
                item.classList.toggle("is-active", item.getAttribute("data-view") === "categories");
            } else if (isHome && item.classList.contains("main-page")) {
                item.classList.add("is-active");
            } else {
                item.classList.remove("is-active");
            }
        });
        if (header) {
            header.classList.toggle("is-scrolled", isCategories || window.scrollY > 24);
        }
        if (isProfiles) {
            document.title = "Prime Video: ¿Quién está viendo?";
            window.scrollTo({ top: 0, behavior: "auto" });
        } else if (isCategories) {
            document.title = "Prime Video: Categorías";
            window.scrollTo({ top: 0, behavior: "auto" });
        } else {
            document.title = "Prime Video";
        }
        closeNav();
        closeProfile();
    }

    function viewFromHash() {
        const hash = (window.location.hash || "").toLowerCase();
        if (hash === "#perfiles" || hash === "#profiles") return "profiles";
        if (hash === "#categorias" || hash === "#categories") return "categories";
        return "home";
    }

    function goProfiles(event) {
        if (event) event.preventDefault();
        closeProfile();
        if (window.location.hash !== "#perfiles") {
            window.location.hash = "perfiles";
        } else {
            showView("profiles");
        }
    }

    function closeProfile() {
        if (!profileArea) return;
        profileArea.classList.remove("is-open");
        if (profileToggle) profileToggle.setAttribute("aria-expanded", "false");
    }

    function closeSearch() {
        if (searchWrap) searchWrap.classList.remove("is-open");
        if (header) header.classList.remove("search-open");
    }

    if (menuToggle && header) {
        menuToggle.addEventListener("click", function () {
            const open = header.classList.toggle("nav-open");
            menuToggle.setAttribute("aria-expanded", String(open));
            if (!open && categories) categories.classList.remove("is-open");
            closeProfile();
            closeSearch();
        });
    }

    if (navOverlay) {
        navOverlay.addEventListener("click", closeNav);
    }

    if (searchToggle && searchWrap && header) {
        searchToggle.addEventListener("click", function (event) {
            event.stopPropagation();
            const open = searchWrap.classList.toggle("is-open");
            header.classList.toggle("search-open", open);
            if (open) {
                closeNav();
                closeProfile();
                const input = searchWrap.querySelector(".search-bar");
                if (input) input.focus();
            }
        });
    }

    function goHome(event) {
        if (event) event.preventDefault();
        if (window.location.hash && window.location.hash !== "#inicio") {
            window.location.hash = "inicio";
        } else {
            showView("home");
        }
    }

    function goCategories(event) {
        if (event) event.preventDefault();
        if (window.location.hash !== "#categorias") {
            window.location.hash = "categorias";
        } else {
            showView("categories");
        }
    }

    const logoLink = document.querySelector(".logo-link");
    if (logoLink) {
        logoLink.addEventListener("click", goHome);
    }

    navItems.forEach(function (item) {
        const link = item.querySelector("a");
        if (!link) return;
        link.addEventListener("click", function (event) {
            const view = item.getAttribute("data-view");
            if (view === "categories") {
                goCategories(event);
                return;
            }
            if (view === "home" && (item.classList.contains("main-page") || link.getAttribute("href") === "#inicio")) {
                goHome(event);
            }
        });
    });

    window.addEventListener("hashchange", function () {
        showView(viewFromHash());
    });

    showView(viewFromHash());

    if (profileToggle && profileArea) {
        profileToggle.addEventListener("click", function (event) {
            event.stopPropagation();
            const open = profileArea.classList.toggle("is-open");
            profileToggle.setAttribute("aria-expanded", String(open));
            if (open) {
                closeNav();
                closeSearch();
            }
        });
    }

    document.querySelectorAll("[data-profiles-action]").forEach(function (link) {
        link.addEventListener("click", function (event) {
            const action = link.getAttribute("data-profiles-action");
            goProfiles(event);
            if (action === "edit") {
                window.setTimeout(function () {
                    setProfilesEditing(true);
                }, 0);
            } else {
                setProfilesEditing(false);
            }
        });
    });

    if (profilesEditBtn && profilesPage) {
        profilesEditBtn.addEventListener("click", function () {
            setProfilesEditing(!profilesPage.classList.contains("is-editing"));
        });
    }

    const profilesAddBtn = document.getElementById("profilesAddBtn");
    if (profilesAddBtn) {
        profilesAddBtn.addEventListener("click", function () {
            setProfilesEditing(false);
        });
    }

    if (profilesPage) {
        profilesPage.querySelectorAll(".profile-card[data-profile-id]").forEach(function (card) {
            try {
                const saved = window.localStorage.getItem("plix-profile-" + card.getAttribute("data-profile-id"));
                if (saved) {
                    const data = JSON.parse(saved);
                    const nameEl = card.querySelector(".profile-card-name");
                    const avatarEl = card.querySelector(".profile-card-avatar");
                    const switchBtn = card.querySelector("[data-profile-switch]");
                    if (data.name && nameEl) nameEl.textContent = data.name;
                    if (data.avatar && avatarEl) {
                        avatarEl.style.backgroundImage = "url('" + data.avatar + "')";
                        const img = avatarEl.querySelector("img");
                        if (img) img.src = data.avatar;
                    }
                    if (data.name && switchBtn) {
                        switchBtn.setAttribute("aria-label", "Cambiar al perfil de " + data.name);
                    }
                }
            } catch (err) { /* ignore */ }
        });

        profilesPage.querySelectorAll("[data-profile-switch]").forEach(function (btn) {
            btn.addEventListener("click", function () {
                if (profilesPage.classList.contains("is-editing")) {
                    const card = btn.closest(".profile-card");
                    if (card) openProfileEdit(card);
                    return;
                }
                goHome();
            });
        });

        const profilesLogo = profilesPage.querySelector(".profiles-page-logo");
        if (profilesLogo) {
            profilesLogo.addEventListener("click", goHome);
        }
    }

    if (profileEditCancel) {
        profileEditCancel.addEventListener("click", function () {
            showWhoIsWatching();
            setProfilesEditing(true);
        });
    }

    if (profileEditForm) {
        profileEditForm.addEventListener("submit", function (event) {
            event.preventDefault();
            saveProfileEdit();
        });
    }

    if (profileEditName) {
        profileEditName.addEventListener("input", function () {
            editDraft.name = profileEditName.value;
            updateEditDirtyState();
        });
    }

    if (profileEditAvatarBtn) {
        profileEditAvatarBtn.addEventListener("click", openAvatarModal);
    }

    if (profileEditPinBtn) {
        profileEditPinBtn.addEventListener("click", openPinModal);
    }

    if (avatarModal) {
        avatarModal.querySelectorAll("[data-avatar-close]").forEach(function (el) {
            el.addEventListener("click", closeAvatarModal);
        });
    }

    if (avatarPickerList) {
        avatarPickerList.addEventListener("click", function (event) {
            const item = event.target.closest("[data-avatar]");
            if (!item) return;
            setEditAvatar(item.getAttribute("data-avatar") || "");
            closeAvatarModal();
        });
    }

    if (pinModal) {
        pinModal.querySelectorAll("[data-pin-close]").forEach(function (el) {
            el.addEventListener("click", closePinModal);
        });
    }

    if (pinModalToggle && pinModalInput) {
        pinModalToggle.addEventListener("click", function () {
            const show = pinModalInput.type === "password";
            pinModalInput.type = show ? "text" : "password";
            pinModalToggle.textContent = show ? "Ocultar PIN" : "Mostrar PIN";
        });
    }

    if (pinModalForm && pinModalInput) {
        pinModalForm.addEventListener("submit", function (event) {
            event.preventDefault();
            const pin = pinModalInput.value.replace(/\D/g, "");
            if (pin.length !== 5) {
                pinModalInput.setCustomValidity("Tu PIN debe tener 5 números");
                pinModalInput.reportValidity();
                return;
            }
            pinModalInput.setCustomValidity("");
            try {
                const key = "plix-profile-pin-" + (editingProfileId || "account");
                window.localStorage.setItem(key, pin);
            } catch (err) { /* ignore */ }
            closePinModal();
        });

        pinModalInput.addEventListener("input", function () {
            pinModalInput.value = pinModalInput.value.replace(/\D/g, "").slice(0, 5);
            pinModalInput.setCustomValidity("");
        });
    }

    document.addEventListener("keydown", function (event) {
        if (event.key !== "Escape") return;
        if (avatarModal && !avatarModal.hidden) {
            closeAvatarModal();
            return;
        }
        if (pinModal && !pinModal.hidden) {
            closePinModal();
            return;
        }
        if (profileEdit && !profileEdit.hidden) {
            showWhoIsWatching();
            setProfilesEditing(true);
        }
    });

    document.addEventListener("click", function (event) {
        if (profileArea && !profileArea.contains(event.target)) {
            closeProfile();
        }
        if (searchWrap && searchToggle && !searchWrap.contains(event.target) && !searchToggle.contains(event.target)) {
            closeSearch();
        }
    });

    window.addEventListener("scroll", function () {
        if (!header) return;
        if (document.body.classList.contains("profiles-mode")) return;
        const onCategories = categoriesView && categoriesView.classList.contains("is-active");
        header.classList.toggle("is-scrolled", onCategories || window.scrollY > 24);
    }, { passive: true });

    window.addEventListener("resize", function () {
        if (!isMobile()) {
            closeNav();
            closeSearch();
        }
    });

    /* ---------- Hero slider (StandardHero fade) ---------- */
    const sliderArea = document.getElementById("heroSlider");
    if (sliderArea) {
        const track = sliderArea.querySelector(".sliders");
        const slides = track ? Array.from(track.querySelectorAll(".hero-slide")) : [];
        const prevBtn = sliderArea.querySelector(".slider-prev");
        const nextBtn = sliderArea.querySelector(".slider-next");
        const bulletsWrap = sliderArea.querySelector(".bullets");
        let index = slides.findIndex(function (slide) {
            return slide.classList.contains("is-active");
        });
        if (index < 0) index = 0;
        let timer = null;
        let startX = 0;
        let deltaX = 0;
        let dragging = false;

        function goTo(i) {
            if (!slides.length) return;
            index = (i + slides.length) % slides.length;
            slides.forEach(function (slide, slideIndex) {
                const active = slideIndex === index;
                slide.classList.toggle("is-active", active);
                slide.setAttribute("aria-hidden", String(!active));
            });
            if (bulletsWrap) {
                bulletsWrap.querySelectorAll("button").forEach(function (btn, btnIndex) {
                    btn.classList.toggle("is-active", btnIndex === index);
                    btn.setAttribute("aria-selected", String(btnIndex === index));
                });
            }
        }

        function next() { goTo(index + 1); }
        function prev() { goTo(index - 1); }

        function startAuto() {
            stopAuto();
            timer = setInterval(next, 6500);
        }

        function stopAuto() {
            if (timer) clearInterval(timer);
            timer = null;
        }

        if (bulletsWrap) {
            bulletsWrap.innerHTML = "";
            slides.forEach(function (_, i) {
                const btn = document.createElement("button");
                btn.type = "button";
                btn.setAttribute("aria-label", "Diapositiva " + (i + 1));
                btn.setAttribute("role", "tab");
                btn.addEventListener("click", function () {
                    goTo(i);
                    startAuto();
                });
                bulletsWrap.appendChild(btn);
            });
        }

        if (prevBtn) {
            prevBtn.addEventListener("click", function () {
                prev();
                startAuto();
            });
        }
        if (nextBtn) {
            nextBtn.addEventListener("click", function () {
                next();
                startAuto();
            });
        }

        sliderArea.addEventListener("mouseenter", stopAuto);
        sliderArea.addEventListener("mouseleave", startAuto);

        if (track) {
            track.addEventListener("touchstart", function (event) {
                if (!event.touches.length) return;
                dragging = true;
                startX = event.touches[0].clientX;
                deltaX = 0;
                stopAuto();
            }, { passive: true });

            track.addEventListener("touchmove", function (event) {
                if (!dragging || !event.touches.length) return;
                deltaX = event.touches[0].clientX - startX;
            }, { passive: true });

            track.addEventListener("touchend", function () {
                if (!dragging) return;
                dragging = false;
                if (Math.abs(deltaX) > 50) {
                    if (deltaX < 0) next();
                    else prev();
                }
                startAuto();
            });
        }

        goTo(index);
        startAuto();
    }

    /* ---------- Content rows ---------- */
    document.querySelectorAll(".content-area").forEach(function (area) {
        const row = area.querySelector(".content-row");
        const prev = area.querySelector(".row-prev");
        const next = area.querySelector(".row-next");
        if (!row || !prev || !next) return;

        function scrollAmount() {
            return Math.max(row.clientWidth * 0.75, 220);
        }

        function updateButtons() {
            const maxScroll = Math.max(row.scrollWidth - row.clientWidth, 0);
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
    });
})();
