# Деплой и E2E: merge-by-ID

Инструкция: развернуть сервер с ops-контрактом, включить клиентский флаг и
прогнать сквозные проверки двух пользователей.
Контракт: `SERVER_SYNC_SPEC.md`. Чек-лист: `MERGE_BY_ID_CHECKLIST.md`.

---

## 1. Предпосылки

- Сервер: Node.js ≥ 20, PostgreSQL (таблица `reports`, как в проекте), S3/KS3-совместимое
  хранилище, доступ к `.env`.
- Клиент: Flutter SDK (используемая версия в проекте), доступ к серверу по сети.
- Для «двух пользователей» удобнее web-клиент в двух браузерах (профили/инкогнито)
  + при желании мобильный клиент к тому же серверу.

---

## 2. Деплой сервера

### 2.1 Окружение (.env)

Скопировать шаблон и заполнить (пример для local dev; в production значения меняются):

```bash
cd easy_tab_Server
cp .env.example .env   # если примера нет — создать по таблице ниже
```

| Переменная | Назначение |
|---|---|
| `PORT` | порт (по умолчанию 3000) |
| `NODE_ENV` | `development` или `production` |
| `JWT_SECRET` | ≥32 символа (production) |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | Postgres |
| `KS3_ACCESS_KEY`, `KS3_SECRET_KEY`, `KS3_BUCKET`, `KS3_REGION` | S3/KS3 |
| `CORS_ALLOWED_ORIGINS` | список origin'ов клиента (production) |

В production проверка обязательных переменных выполняется автоматически при старте
(`validateConfig`) — сервер не запустится с неполной конфигурацией.

### 2.2 Установка и запуск

```bash
cd easy_tab_Server
npm install

# локально (development):
npm start          # или: npm run dev (авто-перезапуск)

# production через PM2:
npm run pm2:start  # использует ecosystem.config.js (env production)
```

Health-проверка:

```bash
curl http://localhost:3000/health   # или /api/health — по факту в routes/health.js
```

Проверить, что ops-эндпоинт на месте (без авторизации вернёт 401, но не 404):

```bash
curl -i -X PATCH http://localhost:3000/reports/shares/token -H 'Content-Type: application/json' -d '{"ops":[]}'
```

### 2.3 Прогон серверных автотестов

```bash
cd easy_tab_Server
node --test tests/reportOps.test.js   # 10 кейсов merge-by-ID
npm test                              # все тесты (могут требовать БД/.env)
```

---

## 3. Сборка/запуск клиента

### 3.1 Адрес сервера

В приложении адрес задаётся через `ApiService.setBaseUrl(host, port)` (AuthProvider
при логине/настройках). По умолчанию `localhost:8000`. Для E2E указать хост/порт
развёрнутого сервера (например `http://<server>:3000`).

### 3.2 Включить ops

В `lib/providers/report_provider.dart`:

```dart
static const bool mergeOpsEnabled = false;  // → true
```

Затем собрать/запустить клиент:

```bash
cd easy_tab
flutter pub get

# web (удобно для двух пользователей в двух браузерах):
flutter run -d chrome --web-port 8000

# Android (эмулятор к серверу на хосте: server = 10.0.2.2, если сервер на localhost):
flutter run -d <device>
```

Быстрая проверка анализа и unit-тестов:

```bash
flutter analyze
flutter test test/report_merge_test.dart   # 8 кейсов diff-движка
```

---

## 4. Сценарии E2E (два пользователя)

Открыть один и тот же отчёт в **двух браузерах** (или браузер+мобильный),
оба авторизованы под одним/двумя аккаунтами с правом редактирования.

| # | Сценарий | Ожидание |
|---|---|---|
| 1 | Пользователь A добавляет ответ в вопрос; B добавляет ответ в тот же вопрос | Оба ответа сохранены, дубликатов нет |
| 2 | A добавляет вопрос; B добавляет вопрос | Оба вопроса сохранены в детерминированном порядке |
| 3 | A правит RU-текст строки, B правит EN-текст **той же** строки | Автослияние без диалога |
| 4 | A и B правят **одну и ту же** ячейку (rid+lang) с одной базы | У второго появляется диалог (серверный/свой/оба), повторная отправка применяется |
| 5 | В строке с переводами: «уточнить формулировку» | Переводы сохраняются |
| 6 | Legacy-отчёт (schemaVersion 1): открыть, сохранить, снова открыть | Миграция + «посев» canonical, id стабильны |
| 7 | Параллельная миграция одного legacy двумя клиентами | Без дубликатов вопросов/строк (dedup) |
| 8 | Добавить фото к ответу (serverFileId) → синхронизация | Медиа синхронизируется (`answer.setMedia`); удаление не оставляет мусора |
| 9 | Share-ссылка (permissions=edit): аноним правит | ops применяются, автор `share:<token>:<anonId>`, правки видны владельцу |

Как проверять конфликт (#4): оба открывают отчёт → A сохраняет новую редакцию RU →
B не перезагружаясь правит тот же RU и жмёт сохранить → B получает диалог.

Логи сервера при успешном merge:

```text
patchReportOps: merged report <id> for user <uid>, ops=N
patchReportOps: version changed ...   # ретрай при гонке
patchReportOps (share): ...           # при share-ops (action 'save')
```

Метрика: 409 должен появляться только по сценарию #4 (одна ячейка).

---

## 5. Откат

- Вернуть `mergeOpsEnabled = false` и пересобрать клиентов.
- Сервер по-прежнему принимает legacy-формат (POST/PATCH с `reportData`) — обратная
  совместимость сохранена.

---

## 6. Полезные ссылки

- Контракт merge-by-ID — `docs/SERVER_SYNC_SPEC.md`
- Чек-лист включения — `docs/MERGE_BY_ID_CHECKLIST.md`
- Unit-тесты: Flutter `test/report_merge_test.dart`, сервер `tests/reportOps.test.js`
