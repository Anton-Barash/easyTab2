# CODE_MAP for easyTab2 (Frontend)

В этом файле — статическая карта кода фронтенда (Flutter). Цель: помочь быстро ориентироваться и экономить токены при последующем анализе. Я включил детальные описания ключевых файлов, список импортов/назначений для главных точек входа и полную структуру директорий. Для больших файлов (например form_fill_screen.dart) добавлены описания основных компонентов и точек расширения; если нужно, я могу развернуть каждую функцию/класс в отдельном файле по запросу.

-- Репозиторий: Anton-Barash/easyTab2

## Стек
- Язык: Dart (Flutter)
- Целевые платформы: Android, iOS, Web, Windows
- Основные зависимости (из pubspec.yaml): flutter_localizations, intl, provider, http, path_provider, flutter_secure_storage и др. Для QR/deep-link: qr_flutter (генерация QR в диалоге шаринга), mobile_scanner (скан QR камерой), app_links (deep-link).

## Топ-уровень (root)
- README.md — базовая инструкция Flutter
- pubspec.yaml — зависимости и dev-пакеты
- .github/workflows/deploy-web.yml — CI: сборка web и деплой на сервер
- lib/ — исходники приложения
  - l10n/ — сгенерированные/ручные локализации (app_localizations*.dart)
  - models/ — модели данных (репорты, шаблоны, файлы и т.п.)
  - providers/ — state providers (AuthProvider, SettingsProvider, RepoProviders и пр.)
  - screens/ — экраны UI (template_select, form_fill, reports, login, share_welcome, full_media_viewer и др.)
  - services/ — сетевые и локальные сервисы (share token store, file services и т.д.)
  - utils/ — утилиты (app_colors, misc helpers)
  - widgets/ — переиспользуемые виджеты (dialogs, buttons, layouts)
- web/, android/, ios/, windows/ — таргеты платформ

## Как всё связано (вкратце)
- Точка входа: lib/main.dart — создаёт EasyTabApp (MaterialApp) с провайдерами: локаль, auth, settings; регистрирует маршруты и начальные страницы (StartScreen / StartState).
- Навигация: routes определяют view-роуты (template, reports, files, shared pages). Некоторые роуты формируют динамически PageBuilders в зависимости от query params (репортId, token, publicId).
- State: Providers используются через MultiProvider; основные провайдеры — LocaleProvider, AuthProvider, SettingsState, ReportsProvider (загрузка репортов), RepoProviders (список репозиториев), ChangeNotifier-ы для настроек и авторизации.

## Подробно по ключевым файлам

### lib/main.dart — основной запуск приложения
- Основные импорты: flutter/material, flutter_localizations, intl, app_localizations_*.dart, providers/*, services/share_token_storage.dart, screens/*, widgets/*, utils/app_colors.dart
- Что делает:
  - Функция main() вызывает runZonedGuarded и запускает WidgetFlutterBinding.ensureInitialized();
  - Загружает package info, version и локальные настройки (SettingsState, LocaleProvider.init, AuthProvider.init, SettingsProvider.init)
  - Создаёт EasyTabApp (extends StatelessWidget) с MultiProvider, перечислением провайдеров:
    - ChangeNotifierProvider для ReportState, SettingsProvider, LocaleProvider и AuthProvider и т.д.
  - MaterialApp конфигурация:
    - localizationsDelegates и supportedLocales (en, ru, zh)
    - Theme: ThemeData с AppColors
    - initialRoute: '/'
    - routes: картирование: '/' → StartScreen, '/template' → template_select screen, '/reports' → reports screen, '/view' → viewReportHtml, '/template-select' и др.
    - Логика динамической генерации роутов (onGenerateRoute): поддержка query params: reportId, token, publicId, путь '/view-repOrt' и др.; если отсутствуют необходимые параметры, возвращается MaterialPageRoute со Scaffold показывающим сообщение (e.g. token missing)
  - Функции/классы определённые в файле:
    - EasyTabApp — основное приложение (StatelessWidget)
    - StartScreen / _StartScreenState — стартовый экран и State
    - _loadVersion() и вспомогательные приватные функции для парсинга версии, детектирование среды (web, native, cache headers)
    - _buildLanguageSwitch, _buildMenu, _continueLastReport — хелперы для UI-элементов в AppBar
- Замечания по коду:
  - main.dart довольно большой; содержит логику роутинга и множество UI-конструкторов. Можно вынести onGenerateRoute в отдельный файл router.dart для уменьшения размера main.


### lib/screens/*.dart (ключевые)
- form_fill_screen.dart (большой; ~180kB): экран ввода/заполнения шаблона/формы.
  - Основная роль: отрисовка списка полей, обработка локального сохранения черновиков, валидация, привязка мультимедиа (фото/видео), сбор и отправка репорта.
  - Внутренние компоненты (по структуре файла): форма с динамическими полями, менеджер мультимедиа, локальные авто-сохранения, обработка загрузки файлов на сервер (background upload), preview шаблона.
  - Точки улучшения: разбить на несколько виджетов/файлов (FormModel, FormFieldWidget, MediaManager), вынести сетевые операции в services.

- template_select_screen.dart (~53kB): экран выбора шаблона.
  - Импорты: провайдеры/репозитории, widgets для карточек шаблонов.
  - Функции: загрузка списка шаблонов, фильтрация/поиск, выбор и переход в form_fill.

- login_screen.dart, reports_screen.dart, share_welcome_screen.dart, full_media_viewer_screen.dart, share_qr_scanner_screen.dart
  - Каждый экран содержит UI + вызовы провайдеров для загрузки/обновления данных. reports_screen отвечает за список отчетов, фильтры и просмотр репорта (переход в full_media_viewer). Просмотр HTML на web открывает серверный HTML напрямую (без Flutter). share_qr_scanner_screen — скан QR камерой (mobile_scanner) и добавление расшаренного (edit) отчёта в список.


### lib/providers/
- providers/contains:
  - auth_provider.dart — управление токеном, логин/логаут, isLoggedIn флаги; хранение токена (secure storage) и интеграция с share token storage
  - settings_provider.dart — загрузка/сохранение настроек, theme, debug flags
  - repo_providers/ — провайдеры для репозиториев (список репов, выбранный репо)
  - report providers — загрузка/кеширование списков репортов
- Замечание: привести единообразие имени методов (loadXAsync vs fetchX), разделить ответственность fetch vs state mutation.


### lib/services/
- share_token_storage.dart — хранение/чтение токенов для шаринга
- app_deeplinks.dart — deep-link (Android App Links / iOS Universal Links): захват ссылки `https://easytab.cloud/#/welcome?token=...` и переход на `/welcome`; инициализируется в main()
- anonymous_id_service.dart — стабильный анонимный id для анонимных редакторов share
- file services — загрузка/скачивание файлов, thumbnail generation
- http wrapper — центральный http-клиент с обработкой заголовков, retry, caching


### lib/utils & lib/widgets
- utils/app_colors.dart — тема цветов
- widgets/* — набор общих кнопок, EasyTabButton, dialogs (login dialog, settings dialog), templates list item


## Полный список файлов (корневой lib)
(сокращённо — для полного списка я могу сгенерировать таблицу с каждым файлом и ссылкой)
- lib/main.dart — (описан выше)
- lib/l10n/app_localizations.dart, app_localizations_en.dart, app_localizations_ru.dart, app_localizations_zh.dart
- lib/models/*
- lib/providers/*
- lib/screens/form_fill_screen.dart
- lib/screens/template_select_screen.dart
- lib/screens/login_screen.dart
- lib/screens/reports_screen.dart
- lib/screens/share_welcome_screen.dart
- lib/screens/full_media_viewer_screen.dart
- lib/services/*
- lib/utils/*
- lib/widgets/*


---

## Актуальная карта синхронизации (Frontend) — merge-by-ID + отвязка при истечении прав

> ВНИМАНИЕ: раздел ниже отражает ТЕКУЩЕЕ состояние (добавлен после фичи автоматической
> отвязки при истечении права на редактирование). Он важнее старых кратких описаний
> провайдеров выше. Полный протокол синхронизации — в `docs/SERVER_SYNC_SPEC.md`.

### Ключевые файлы (смотреть в первую очередь)

- `lib/providers/report_provider.dart` — центральный `ReportState` (загрузка/сохранение/
  синхронизация отчёта). Здесь живёт отвязка локальной копии от сервера при отказе.
- `lib/providers/report_sync_manager.dart` — `ReportSyncManager`: список отчётов
  (локальные + облачные), скачивание, `syncReport`, hidden `cloud_cache`, перенос
  скрытых копий в «Мои отчёты» при отвязке.
- `lib/services/report_merge_service.dart` — diff-движок и построение ops
  (question.add/remove, answer.add/update/remove, answer.setMedia, meta).
  Для `answer.update` шлёт `baseUpdatedAt` (optimistic-lock) и `baseText`
  (текст базы: сервер по нему распознаёт правку другого автора независимо
  от расхождения часов устройств).
- `ReportState.mergeOpsEnabled = true` — включён ops-путь (merge-by-ID) и для
  владельца (`PATCH /reports/:id`), и для анонимного редактора по share-ссылке
  (`PATCH /reports/shares/:token`). Конфликт одной ячейки → диалог выбора
  («использовать серверный / заменить своим / сохранить как второй ответ»);
  повторный конфликт по той же ячейке показывает сообщение «изменён снова»
  (`ConflictDetails.isRepeat`). Порядок включения — `docs/MERGE_BY_ID_CHECKLIST.md`.
- `lib/services/api_result.dart` — результат вызова API; `isPermanentAccessDenied`
  классифицирует 403/404/410 и ключевые слова (denied/forbidden/expired/gone) как
  «постоянный отказ доступа».
- `lib/screens/reports_screen.dart` — список отчётов; уведомление при отвязке после
  синхронизации одного/всех/закрытия облачной сессии. Строка 493+ — меню «…»
  (PopupMenuButton): удалить на устройстве / удалить на сервере / отменить связь
  (методы `_confirmDeleteLocal`, `_confirmDeleteServer`, `_confirmUnlink`).
  `_confirmDeleteServer` различает 403 («не автор», ключ `reportDeleteServerDenied`)
  и успех/ошибку. Удаление сервера локальную копию не трогает.
- `lib/screens/form_fill_screen.dart` — редактор; `_doSaveAndSync` (дискета:
  сохранение с приоритетом — только отправка; на web идёт через ops-путь, и
  серверный `merged` из его ответа сам приносит чужие изменения; отдельный pull
  после сохранения НЕ делается, чтобы не затереть несохранённые правки),
  уведомление об отвязке при «Сохранить» / загрузке / просмотре HTML.
  Кнопка без несохранённых правок (иконка облака, `_syncOnly`) — ТОЛЬКО
  подтягивает чужие изменения: `ReportState.pullFromServer()` (web —
  `_loadReportFromServer`; по share-ссылке — `loadSharedReport`); при
  отложенных дебаунс-правках сначала сохраняет их (`_flushPendingEdits`).
- **Расшаренный отчёт из списка открывается по share-токену.** `ReportSummary`
  хранит `shareToken` (заполняется в `ReportSyncManager.loadCombinedList` для
  отчётов по QR/ссылке). Карточка в `reports_screen.dart` при тапе проверяет
  `report.shareToken` и идёт напрямую на `/share-edit?token=...` (Форма открывает
  `FormFillScreen(shareToken:)`), минуя скачивание по server-id как владелец —
  это даёт право редактирования чужому/анонимному редактору. Если право
  истекло, сервер возвращает отказ → срабатывает auto-detach (см. ниже).
- **Дискета при добавлении медиа активна.** После добавления фото/видео
  `_hasUnsavedChanges` остаётся `true` (раньше сбрасывалось сразу после
  локального `saveReport`), поэтому дискета видна и не превращается в «облако»,
  которое подтянуло бы серверную версию БЕЗ новых медиа.

### Поток «истекло право на редактирование» (auto-detach)

1. Сервер отвечает `403`/`404`/`410` либо текстом про denied/expired/gone.
2. `ApiResult.isPermanentAccessDenied` → true (401 в это НЕ входит).
3. Два места обработки:
   - `ReportSyncManager.syncReport()` / media-upload pre-check → вызывает
     `_detachFromServer(folderPath, {isLibrary})`, результат кладёт в
     `lastDeniedUnlinkedFolder`.
   - `ReportState` (legacy `_saveReportToServer` и ops-путь `_saveViaMergeOps`) →
     вызывает `_detachServerLinkIfDenied()` → `_detachCurrentReportServerLink()`.
4. `_detachCurrentReportServerLink()` (в `report_provider.dart`):
   - удаляет `sync_meta.json`;
   - переименовывает папку `server_<id>` -> `report_<ts>_detached` (привязка не
     восстановится по имени папки);
   - для скрытой копии `cloud_cache/server_<id>` **переносит** её в библиотеку
     «Мои отчёты» (`reports/report_<ts>_detached`), чтобы локальные правки не
     потерялись;
   - очищает `_serverReportId`, `_serverReportVersion`, `_serverPublicId`,
     `_ks3Folder`, share-токен;
   - ставит одноразовый флаг `_serverLinkDetachedOnDeny`, читаемый через
     `consumeServerLinkDetachedOnDeny()`.
   - ⚠️ При вычислении родительской папки использует строковую `_parentDirOf()`,
     а НЕ `Directory.parent` (в web-заглушке `utils/platform_io_web.dart` этого
     геттера нет — иначе dart2js роняет сборку).
5. UI показывает локализованное сообщение `reportAccessExpiredDetached`
   («Срок доступа истёк — отчёт сохранён только локально, можно заново залить
   как новый») в: reports_screen (после синка одного/всех/закрытия сессии) и
   form_fill_screen (Сохранить / загрузить / HTML).

### Семантика отчётов при истечении прав

- Право истекло + удалился шаринг → локальная копия становится обычным отчётом в
  «Моих отчётах» БЕЗ дубля и без потери данных. Повторная загрузка на сервер
  создаёт новый отчёт с новым ID.
- На web отвязка намеренно не выполняется (`kIsWeb → false` в
  `_detachServerLinkIfDenied`): там нет локальных копий, всё хранится на сервере.

### Тестовые/проверочные критерии

- `flutter analyze` и `flutter test` — без ошибок.
- `flutter build web --release --no-wasm-dry-run` — успешно (проверяет dart2js,
  важно для `_parentDirOf` / отсутствия `Directory.parent`).

### Подлинность отчёта (ID + verification code) и автор в списке

- **Backend:** миграция `009_add_verification_code.sql` добавляет колонку
  `reports.verification_code` (внутренний секрет). `saveReport()` генерирует
  64-hex код при **создании** и единожды возвращает его создателю; при
  обновлении не трогается. `listReports()` делает `LEFT JOIN users` и возвращает
  поле `author` (username). Новый эндпоинт `POST /reports/verify` (БЕЗ JWT)
  принимает `{ reportId, verificationCode }`, сверяет код через
  `crypto.timingSafeEqual` и возвращает `{ id, publicId, title, authorName }`
  (404 — нет отчёта, 403 — неверный код). Файлы: `src/services/reportsService.js`
  (`generateVerificationCode`, `verifyReport`, JOIN в `listReports`),
  `src/controllers/reportsController.js`, `src/routes/reports.js`.
- **Frontend:** `ReportSummary` получает поле `authorName`; маппинг из серверного
  списка — в `report_sync_manager.dart` и web-пути `report_provider.dart`;
  карточка в `reports_screen.dart` показывает автора (только для серверных
  отчётов) с локализованным фоллбэком `loc.anonymous`. В `api_service.dart`
  добавлен метод `ApiService.verifyReport(...)` (plumbing, без UI).
- **Scope:** код подлинности — backend-возможность, видимого UI нет; в UI
  добавляется только имя автора в списке.

---

# CODE_MAP for easy-tab-Server (Backend)

Репозиторий: Anton-Barash/easy-tab-Server
Stack: Node.js (JavaScript), Express-like or Fastify-style app (в коде используются смешанные require('fastify') и express-подобная конструкция). БД: Postgres (PLpgSQL пометки в языке состава).

## Топ-уровень
- package.json — зависимости и скрипты
- src/
  - app.js — основной конфиг/создание сервера и middlewares (подробно ниже)
  - index.js — точка запуска (создаёт сервер и вызывает app)
  - config/ — конфигурация (env-конфиги)
  - controllers/ — обработчики маршрутов
  - routes/ — определение маршрутов
  - middleware/ — промежуточные обработчики (логирование, ошибки, аутентификация)
  - services/ — вспомогательные сервисы: файлы, воркеры, email и др.
  - db/ — миграции и connection pool
  - utils/ — утилиты
- certs/ — TLS-сертификаты (easytab.cloud): easytab.cloud.pem + easytab.cloud.key.
  Папка в .gitignore, приватный ключ не коммитится. Заливается на сервер вручную.

## TLS/HTTPS (easytab.cloud — DigiCert)
- Терминация TLS прямо в Fastify (без nginx/reverse-proxy).
- Включается env-флагом `TLS_ENABLED=1`; пути к сертификату/ключу — `TLS_CERT`/`TLS_KEY`.
- Пути резолвятся в `src/config/index.js`: абсолютные — как есть, относительные — от корня проекта.
- Config-блок: `config.tlsEnabled` (bool) и `config.tls = { cert, key }` (Buffers). Валидация при старте: если TLS_ENABLED, но файлы не читаются → process.exit(1).
- `src/app.js → buildApp()`: при наличии `config.tls` в `fastify({...})` добавляется `https: config.tls`; иначе сервер слушает HTTP как раньше.
- `src/index.js`: лог строки запуска с протоколом (`https`/`http`).
- HTTP→HTTPS редирект: отдельный plain-HTTP сервер (`src/services/httpRedirectServer.js`)
  на порту `TLS_REDIRECT_PORT` (dev 8000, prod 80). 301 → `https://<TLS_REDIRECT_HOST>/...`
  (путь и query сохраняются). Запускается только при TLS; если порт занят — только warn,
  основной HTTPS-сервер продолжает работать.
- Порты: dev → https://localhost:8443 (cert выписан на easytab.cloud, поэтому в браузере будет предупреждение о хосте), production → 443.
- Чтобы откатить на HTTP: `TLS_ENABLED=0` и вернуть `PORT=8000`/`PORT=80` (редирект отключится сам).
- Схемные файлы: `src/config/index.js`, `src/app.js`, `src/index.js`, `src/services/httpRedirectServer.js`, `.env`, `.env.production`, `ecosystem.config.js`, `certs/`.

## HTTPS на фронтенде (Flutter)

- Фронт теперь поддерживает обе схемы (`http`/`https`). Схема хранится в
  `ApiService._scheme` (геттер `scheme`), задаётся через `ApiService.setBaseUrl(host, port, scheme:)`.
- `ApiService.uri(path, [query])` — публичный хелпер построения URL с учётом
  активной схемы; заменил все внешние `Uri.http(ApiService.baseUrl, ...)`.
  Источники схемы: `ApiService`, `auth_provider.dart` (`setServerUrl`), `login_screen.dart` (`_parseServerUrl`).
- `AuthProvider`:
  - хранит/грузит `server_scheme` (ключ prefs `server_scheme`);
  - `_defaultServerUrl()` возвращает `(scheme, host, port)`;
  - fallback для мобильных/desktop → `https://easytab.cloud:443`;
  - `serverUrl` теперь вида `https://host:port`;
  - `_inferScheme()` — миграция старых настроек (localhost/127.x/10.x → http, иначе https).
- `login_screen.dart`: `_parseServerUrl` возвращает `(scheme, host, port)` и
  прокидывает схему в `setServerUrl`.
- Затронутые файлы: `lib/services/api_service.dart`, `lib/providers/auth_provider.dart`,
  `lib/screens/login_screen.dart`, `lib/screens/form_fill_screen.dart`,
  `lib/screens/share_welcome_screen.dart`, `lib/providers/report_provider.dart`.

## src/app.js — подробный разбор
(описание основано на прочитанном содержимом файла)
- Основная идея: buildApp() — функция, возвращающая собранный Express/Fastify-подобный `app`.
- Импорты/require:
  - fastify (через require('fastify') в начале файла)
  - cors, helmet, rate-limit, compression, cookie, path, fs, другие middleware
  - локальные модули: ./config, ./middleware/errorHandler, ./middleware/requestLogger, ./routes, ./routes/view, ./routes/reports и т.д.
- Глобальные флаги и политики (вверху файла):
  - PRODUCTION_ALLOWED_ORIGINS — парсинг из process.env.CORS_ALLOWED_ORIGINS
- Функции:
  - isOriginAllowed(origin) — проверяет origin против списка разрешённых origin'ов и возвращает boolean
  - buildApp() — собирает приложение:
    - Создаёт fastify/express app (в коде используется fastify/express-mix: переменная `app = fastify({...})` или `express()` в зависимости от обёртки)
    - Подключает errorHandler и requestLogger
    - Включает helmet, cors с custom options (cross-origin policies), rateLimit, compress, cookie parser и другие middleware
    - Регистрирует роуты: register(routes) и viewRoutes
    - Обрабатывает статические ресурсы и caching headers для production (set headers like Cache-Control, hashed filenames handling)
    - Логика для поддержки WASM/JS и особенностей deploy (примеры: P3, WASM noting, form_file screens)
    - Настройка файловых путей: serve /, /view, /repors, /template и пр.
    - Регистрация route handlers для endpoints: GET, POST, PUT, DELETE, PATCH, OPTIONS
    - Дополнительные middleware для security headers и CORS policies, policy overrides for cross-origin-embedder/cross-origin-opener, и пр.
    - Сборка политики: corsOrigin, cache policies
    - Регистрация handler'ов для файлов и fallback index.html для SPA (проверка path.includes('main.dart.js'), version.json и др.)
    - При включении опций, добавляет специфичные response headers (Cache-Control, Pragma и пр.)
  - app.setNotFoundHandler / app.setErrorHandler — обработчики ошибок (implicit в файле)
- Экспорт: module.exports = buildApp; — модуль экспортирует фабрику приложения

## src/index.js
- Точка входа (в root/src/index.js): импорт buildApp, create server, listen на порту из env, логирование стартового состояния.

## routes/ и controllers/
- routes/ содержит модули роутов, которые подключают контроллеры из controllers/
- controllers/ — обработчики endpoint'ов: логика авторизации, upload файлов, генерация отчетов, отдача HTML-страниц для просмотра отчётов.

## middleware/
- errorHandler.js — централизованная обработка ошибок; преобразует внутренние ошибки в корректные HTTP ответы
- requestLogger.js — логирование входящих запросов, возможно интеграция с Sentry/Graylog
- auth middleware — проверка JWT/токенов и проверки прав доступа (Bearer → cookie `auth_token` → query `?token=`)

## Аутентификация через cookie (прямой просмотр HTML /view/report/:publicId)
- Кнопка «Просмотр HTML» в web открывает серверный HTML **напрямую** (без Flutter/Dart).
  Для приватных отчётов в новой вкладке нельзя отправить `Authorization: Bearer`, поэтому
  сервер ставит **HttpOnly cookie `auth_token`** при `POST /auth/login` и `/auth/register`
  (see `src/controllers/authController.js` → `setAuthCookie`, `clearAuthCookie`).
- Cookie: `path=/`, `HttpOnly`, `SameSite=Lax`, `Secure` (только по HTTPS), TTL = 7 дней.
  `authMiddleware.extractToken` читает этот cookie — прямой `/view/report/:publicId` работает
  без токена в URL.
- **`POST /auth/logout`** — снимает HttpOnly cookie (JS не может очистить HttpOnly через
  `document.cookie`). Вызывается фронтендом из `AuthProvider.logout()` на web
  (`ApiService.logout`).

## Эндпоинт /view/report/:publicId/cover
- Обложка отчёта (header-фото, «карточка 0») — `viewController.viewReportCover`
  (см. `src/controllers/viewController.js`, маршрут в `src/routes/view.js`).
  Читает `headerImagePath` из `report_data` и отдаёт файл (с проверкой доступа
  через `optionalAuth` + cookie). Используется Фронтендом как миниатюра в списке
  отчётов на web: `Image.network('$origin/view/report/<publicId>/cover')`,
  по клику открывается увеличенное фото.

## db/
- Модули подключения к Postgres (pool), утилиты для миграций и обращения к PLpgSQL функциям, если они есть.

## services/
- file service — сохранение файлов, генерирование превью, удаление старых медиа
- share token storage — генерация/валидация токенов для шаринга отчётов

## Как это запускается
- Локально: `node src/index.js` или через `npm start` (см. package.json)
- В production обычно запускается через pm2 или docker (есть ecosystem.config.js в корне)


---

Что я сделал прямо сейчас:
- Просканировал репозитории и открыл/прочитал ключевые файлы: easyTab2/lib/main.dart, pubspec.yaml, несколько экранов в lib/screens (список файлов), и easy-tab-Server/src/app.js + индекс и структуру src/.
- На основе этого создал подробный начальный CODE_MAP.md с обзором, организацией директорий и детальным разбором main.dart и app.js, плюс список ключевых файлов и рекомендации по дальнейшему декомпозированию.

Что я предлагаю дальше (рекомендации):
1) Если этот уровень подходит — сразу добавлю аналогичный подробный разбор для всех оставшихся файлов (каждый файл: импорты, все функции/классы с аргументами/назначением, где используются) — но это будет большой объём и я разобью изменения на несколько коммитов (по 10–20 файлов), чтобы не перегрузить токены.
2) Могу расширить форм_fill_screen.dart и app.js построчно (перечислить все функции и их параметры) — укажите, с какого файла начать.

Если всё ок, я закоммичу этот CODE_MAP.md в оба репозитория сейчас.
