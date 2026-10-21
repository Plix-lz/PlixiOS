# PLIX para iPhone (PlixiOS)

Reescritura nativa en **Swift + SwiftUI** de la app Android `PLIX2` (Java). No es un envoltorio web: `PLIX2` no contiene HTML/CSS/JS/PHP propios, así que no había nada que empaquetar en un `WKWebView`. El proyecto Android **no se modificó**; de él solo se copiaron imágenes (logos de plataformas, banderas, banners, ícono) a `PlixiOS/PlixiOS/Resources/Images`.

> **Estado de verificación:** este código se escribió en Windows, **sin Mac y sin Xcode**. No se compiló, no se ejecutó en simulador ni en iPhone y no tiene pruebas automatizadas. Solo se revisó leyendo el código. La primera compilación real será la del workflow de GitHub Actions (o la de un Mac); es esperable que aparezcan errores de compilación a corregir.

## Estructura

```
PlixOS/
├─ .github/workflows/ios-build.yml   Compila un IPA sin firmar en un Mac de GitHub
└─ PlixiOS/
   ├─ project.yml                    Definición del proyecto (XcodeGen genera el .xcodeproj)
   ├─ Config/
   │  ├─ App.xcconfig                Configuración pública
   │  ├─ Secrets.xcconfig.example    Plantilla de la clave TMDB (Secrets.xcconfig no se versiona)
   │  └─ Info.plist                  Permisos, ATS, orientación, pantalla de inicio
   └─ PlixiOS/
      ├─ App/        Entrada de la app, AppDelegate, navegación (AppRouter)
      ├─ Core/       HTTP, JSON ordenado, preferencias tipo SharedPreferences, Keychain, utilidades
      ├─ Models/     MediaItem, servidores, avatar, etc.
      ├─ Data/       TMDB, plataformas, logros, catálogos de imágenes, stores locales
      ├─ Stream/     Repositorio de enlaces, resolvedor Pelixplay, captura de streams con WKWebView
      ├─ Cloud/      Firebase: cuenta y respaldo, amigos, presencia, Cine Virtual (watch party)
      ├─ Player/     Reproductor AVPlayer + sincronización de Cine Virtual
      ├─ UI/         Pantallas SwiftUI
      └─ Resources/  Assets (ícono, splash), imágenes y sonido de logro
```

Requisitos: iOS 16 o superior, solo iPhone. Dependencias por Swift Package Manager: `FirebaseAuth` y `FirebaseFirestore`.

## 1. Secretos (no van en el código)

| Secreto | Para qué | Dónde se pone |
|---|---|---|
| Clave TMDB | Catálogo, búsqueda, detalles | `PlixiOS/Config/Secrets.xcconfig` (local) o secret `TMDB_API_KEY` (GitHub) |
| `GoogleService-Info.plist` | Cuenta, respaldo, amigos, Cine Virtual | `PlixiOS/PlixiOS/Resources/GoogleService-Info.plist` (local) o secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` (GitHub) |

Los dos archivos están en `.gitignore`. Sin `GoogleService-Info.plist` la app compila y funciona, pero las funciones en la nube se muestran como no disponibles.

La clave TMDB queda dentro del binario (igual que en Android, donde va en `BuildConfig`). Es una clave de lectura de una API pública; no es un secreto de servidor. No hay credenciales de servidor ni claves privadas en el cliente.

### Registrar la app iOS en Firebase

1. Abrí la consola de Firebase del **mismo proyecto** que usa la app Android.
2. *Agregar app* → iOS → Bundle ID `com.lzrdgz01.plix` (si lo cambiás, cambialo también en `project.yml`).
3. Descargá `GoogleService-Info.plist`.
4. En *Authentication → Sign-in method* tiene que estar activo **Correo/contraseña** (Android ya lo usa).
5. No hace falta cambiar `firestore.rules`: la app iOS lee y escribe exactamente los mismos documentos y campos que Android. *(Esto se comparó leyendo el código; no se probó contra Firestore real.)*

## 2. Compilar sin Mac (GitHub Actions)

1. Subí la carpeta `PlixOS` a un repositorio de GitHub (puede ser privado).
2. En el repo: *Settings → Secrets and variables → Actions → New repository secret*:
   - `TMDB_API_KEY` = tu clave TMDB.
   - `GOOGLE_SERVICE_INFO_PLIST_BASE64` = el plist en base64. En PowerShell:
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\ruta\GoogleService-Info.plist")) | Set-Clipboard
     ```
3. *Actions → iOS build (IPA sin firmar) → Run workflow*.
4. Al terminar, descargá el artefacto **PLIX-unsigned-ipa** (contiene `PLIX-unsigned.ipa`). Si falla, el artefacto **xcodebuild-log** tiene el log completo.

## 3. Compilar con Mac (opcional)

```bash
brew install xcodegen
cd PlixiOS
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # y escribí la clave
# copiar GoogleService-Info.plist a PlixiOS/Resources/
xcodegen generate
open PlixiOS.xcodeproj
```

En Xcode: target *PlixiOS → Signing & Capabilities → Team* = tu Apple ID; conectá el iPhone y *Run*.

## 4. Firmar e instalar el IPA desde Windows

Un IPA sin firmar no se instala directamente; hay que firmarlo con un Apple ID.

**Sideloadly (más simple):**
1. Instalá iTunes e iCloud de la web de Apple (no la versión de Microsoft Store) y [Sideloadly](https://sideloadly.io).
2. Conectá el iPhone por cable y confiá en la PC.
3. Arrastrá `PLIX-unsigned.ipa`, poné tu Apple ID y *Start*.
4. En el iPhone: *Ajustes → General → VPN y gestión de dispositivos* → confiar en tu Apple ID.
5. En iOS 16 o superior activá *Ajustes → Privacidad y seguridad → Modo de desarrollador* y reiniciá.

**AltStore** es una alternativa que puede re-firmar sola por Wi‑Fi.

Límites de Apple: con Apple ID **gratuito** la firma vence a los **7 días** (hay que re-firmar) y se permiten 3 apps a la vez. Con la **cuenta de desarrollador paga** (99 USD/año) dura 1 año y se puede usar TestFlight. Esta app no es apta para el App Store (reproduce contenido de servidores de terceros).

## 5. Informe de compatibilidad (Android → iOS)

| Función Android | iOS | Notas |
|---|---|---|
| Inicio, películas, series, Kids, géneros, plataformas | ✅ Portado | Mismas fuentes (TMDB + catálogos JSON de GitHub) |
| Búsqueda | ✅ Portado | Búsqueda de títulos alternativos simplificada |
| Detalle de película y serie, temporadas, episodios vistos | ✅ Portado | |
| Tráiler | ✅ Portado | `youtube-nocookie` embebido con navegación restringida |
| Mi lista, historial, progreso y reanudar | ✅ Portado | Mismo formato de preferencias que Android |
| Selector de servidores con idiomas | ✅ Portado | |
| Extracción de streams (WebView oculto) | ⚠️ Parcial | iOS no permite interceptar las peticiones de red del WebView; se usan scripts propios que observan `fetch`/XHR/DOM. Algunos servidores pueden fallar donde Android funciona |
| Reproductor (ExoPlayer) | ✅ AVPlayer | HLS y MP4. Calidad, audio, subtítulos, velocidad, brillo, bloqueo, siguiente episodio |
| DASH (`.mpd`, p. ej. OK.ru) | ❌ No soportado | AVPlayer no reproduce DASH; esos resultados se saltean y se pasa al siguiente servidor |
| Chromecast | 🔁 AirPlay | Se reemplazó por AirPlay nativo; no se integró el SDK de Google Cast |
| Cuenta (usuario + PIN), respaldo y restauración en la nube | ✅ Portado | Misma cuenta sirve en Android y iPhone. El PIN se guarda en el Keychain |
| Amigos, solicitudes, perfil público, presencia | ✅ Portado | |
| Cine Virtual: sala, chat, stickers, notas de voz, sincronización | ✅ Portado | Compatible con salas creadas desde Android (mismo formato de documentos y de audio AAC) |
| Logros, diseño (logo LzPlay) | ✅ Portado | |
| Avatares, fondos (incluye fondos en video) y stickers | ✅ Portado | Desde el repo `Plix-lz/img` |
| Actualizador interno de APK | ❌ Eliminado | iOS no permite instalar binarios descargados; las actualizaciones se hacen re-firmando un IPA nuevo |
| Chequeo previo de servidores caídos | ❌ Omitido | Se intenta reproducir y, si falla, se pasa al siguiente servidor |

### Sobre PHP

El proyecto no tiene PHP. El único PHP involucrado corre en **servidores remotos de terceros** (las páginas de los reproductores). La app iOS no ejecuta PHP ni incluye un servidor local; solo hace peticiones HTTPS a esos sitios. La autenticación de usuarios es con Firebase Auth, igual que en Android; no se movió lógica de autenticación a JavaScript.

## 6. Funciones sin conexión y con conexión

**Funcionan sin conexión:**
- Mi lista, historial, logros, diseño, estadísticas locales.
- Progreso guardado y episodios marcados como vistos.
- Imágenes ya vistas (caché en memoria y caché HTTP en disco).
- Catálogo de avatares, fondos y stickers ya descargado (caché de 6 h; si no hay red se usa la copia guardada).
- Cambios locales: se marcan y se suben a la nube al volver la conexión o al iniciar la app.
- Aviso visible de "sin conexión".

**Necesitan conexión:**
- Catálogo, búsqueda y detalles (TMDB y catálogos JSON).
- Buscar servidores y reproducir.
- Iniciar sesión, respaldar y restaurar.
- Amigos, presencia y Cine Virtual.

## 7. Seguridad

- **JavaScript:** solo se inyectan scripts propios incluidos en la app. No se ejecuta JS descargado.
- **Puente JS → Swift:** un único canal (`plixCapture`). Swift valida el tipo de cada campo, su longitud, el esquema `http/https` y que la URL parezca un stream real.
- **Navegación del WebView:**
  - Se bloquean ventanas emergentes, esquemas que no sean http/https y la navegación del marco principal hacia otros dominios.
  - Las alertas JS se suprimen.
  - Las protecciones de WKWebView quedan activas.
- **Tráiler:** el reproductor de YouTube solo puede navegar dentro de dominios de YouTube.
- **Credenciales:**
  - El PIN se guarda en el Keychain (solo en este dispositivo, `AfterFirstUnlockThisDeviceOnly`; no viaja a otros equipos). En las preferencias no se guarda ninguna contraseña.
  - La sesión la gestiona Firebase Auth.
- **Archivos locales:** las preferencias se escriben con protección de datos de iOS (`completeFileProtectionUntilFirstUserAuthentication`). El respaldo en la nube de PLIX excluye cachés y datos de sesión.
- **Red local:** no se expone ningún servicio ni servidor local.
- **Permisos:** solo micrófono (al grabar la primera nota de voz) y notificaciones (al llegar la primera solicitud de amistad). No se piden al iniciar la app.
- **ATS:** se permiten cargas no HTTPS solo para contenido multimedia y web (`NSAllowsArbitraryLoadsForMedia` / `InWebContent`), porque varios servidores de video usan HTTP. Las APIs propias (TMDB, Firebase, GitHub) usan HTTPS.

## 8. Limitaciones conocidas

- **Sin compilar ni probar** (ver arriba).
- Sin interceptación de red en WKWebView: la extracción de algunos servidores puede ser menos fiable que en Android.
- **Verificación humana:** los servidores que la piden muestran el WebView para que el usuario la complete.
- **DASH** no soportado.
- **Casting:** AirPlay en lugar de Chromecast.
- **Actualizaciones:** no hay actualizador interno.
- **Búsqueda:** la de títulos alternativos está simplificada.
- **Nube sin red:** si al iniciar no hay conexión, la sesión se mantiene y se muestra "Sin conexión con la nube"; la sincronización se reintenta luego.
- **Instalación:** con Apple ID gratuito hay que re-firmar cada 7 días.
- **Reproducción en segundo plano:** el audio puede seguir con la pantalla bloqueada (`UIBackgroundModes: audio`). Picture‑in‑Picture no está implementado.
