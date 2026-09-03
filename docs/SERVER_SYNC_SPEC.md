# Server Sync Specification — merge-by-id for report answers

Дата: 2026-09-03
Реализовано: предложение спецификации для безопасной синхронизации "подвопросов" (answers) в отчётах.

Цель
- Обеспечить корректное слияние параллельных изменений в массивных полях (подвопросах/answers), чтобы две параллельные вставки от разных пользователей не терялись.
- Поддержать анонимные правки (share/guest) с минимальным риском потери данных.
- Сохранить обратную совместимость со старыми отчетами (answers без id).

Ключевые идеи
- Каждый подответ (TranslationAnswer) получает уникальный id (UUID v4), authorId (user / anon token), createdAt, optional fingerprint.
- Клиент формирует минимальные операции (add/update/remove/move) по id и отправляет их в PATCH /reports/:id с baseVersion.
- Сервер применяет операции атомарно в транзакции, выполняет merge-by-id (union), возвращает 409 с детальным описанием конфликтов при concurrent edits.

Поле в answer (минимум)
- id: string (UUID v4) — уникальный идентификатор
- text: string
- _empty: bool
- authorId: string? — форматы: "user:<id>", "share:<token>:<anonId>", "anon:<uuid>"
- authorDisplayName: string? — для UI
- authorIsAnonymous: bool
- createdAt: int (ms since epoch)
- updatedAt: int? (ms)
- fingerprint: string? — sha256(content+context), опционально

Формат authorId для анонимов
- Если сервер предоставляет anonymousId в share flow: "share:<token>:<anonymousId>"
- Если сервера нет anon id: создать device-scoped "anon:<uuid>" и сохранять локально

PATCH /reports/:id — новый контракт (merge-by-id)
Request body (JSON):
{
  "baseVersion": <int>,
  "changes": {
    "questions": {
      "<questionIndex>": {
        "order": ["id1","id2","id3"], // опц.
        "answers": [
          {"action":"add", "answer": { id, text, _empty, authorId, authorDisplayName, authorIsAnonymous, createdAt, fingerprint }, "afterId":"id2" /* opt */},
          {"action":"update", "id":"id3", "fields": {"text":"new text", "updatedAt": 169...}},
          {"action":"remove","id":"id4"},
          {"action":"move","id":"id7","afterId":"id2"}
        ]
      }
    },
    "metadata": { /* optional */ }
  }
}

Семантика обработки на сервере
- baseVersion обязателен; сервер сравнивает с текущей версией отчёта.
- Сервер применяет изменения в транзакции:
  - add: если id уже существует — трактуется как update; если нет — вставка (afterId/append)
  - update: validate id exists; проверить concurrent changes (updatedAt) — при расхождении → конфликт
  - remove: пометка удаления
  - move/order: применить новую упорядоченность
- После успешного применения увеличить report.version, вернуть 200 и merged snapshot/newVersion.
- При конфликте вернуть 409 с детальным conflicts[] (см. ниже).

409 — формат конфликта (пример)
Status: 409
{
  "success": false,
  "code": "VERSION_CONFLICT",
  "currentVersion": <int>,
  "conflicts": [
    {
      "id": "uuid-123",
      "path": "questions.3.answers",
      "field": "text",
      "serverValue": "текст от другого пользователя",
      "clientValue": "мой локальный текст",
      "serverEditor": "user:42" | "share:token:anon1",
      "serverUpdatedAt": 169xxxxxxx,
      "clientUpdatedAt": 169yyyyyyy
    }
  ]
}

Legacy reports (answers without id) — миграция
- Клиент при первом открытии/перед sync:
  - присваивает UUID каждому answer без id, вычисляет fingerprint (sha256(questionIndex + text + optional timestamp)), проставляет authorId:
    - если пользователь залогинен → authorId = user:<id>
    - иначе authorIsAnonymous = true и authorId = anon:<uuid> или share:<token>:<anonId>
  - сохраняет report.json локально (migration). Не обязан сразу перезаписывать сервер.
- Сервер при получении legacy answers может:
  - генерировать id и вернуть mapping (newIds) в ответе, или
  - принять client-provided ids (preferred) и выполнять dedup по fingerprint при желании.
- Для дедупа сервер может объединять элементы с одинаковым fingerprint.

Media flow (существующее)
- Клиент загружает файлы через POST /files/upload (multipart) или presign PUT flow.
- После успешной загрузки получает fileId и включает serverFileId в media references при PATCH.
- Сервер валидирует права на fileId.

Security & validation
- Если caller authenticated user U — server SHOULD set authorId = user:U.id for add actions (игнорировать client-supplied user id), для anonymous accept share:/anon: values.
- Ограничить ops per PATCH (например max 200), лимиты длины полей.
- Audit: хранить authorId/createdAt/updatedAt в БД.

Dedup и ordering
- Клиент может указывать order array; сервер применяет ordering post-merge.
- Для миграции сервер может выполнять optional dedup по fingerprint; если дедуп выполнен — вернуть mapping.

Тесты (обязательные сценарии)
- Параллельные добавления: A добавил C, B добавил D — после синка оба присутствуют.
- Concurrent edits same id → сервер возвращает 409 с конфликтом.
- Migration: старые отчёты -> client assigns ids -> server accepts and dedups by fingerprint.
- Anonymous share edits: use share:<token>:<anonId> and persist authorIsAnonymous true.

Rollout план (low-risk)
1. Server: поддержка backward-compatible PATCH (принимать старый формат и новый), feature flag на strict merge-by-id.
2. Client: migration + client-generated ids + new PATCH format.
3. Server: включить merge-by-id, вернуть 409 при конфликте.
4. Client: UI для конфликта, claim-anon mapping (optional).

Примеры ответов
- Success 200:
{
  "success": true,
  "newVersion": 43,
  "report": { /* merged snapshot */ },
  "applied": { "ops": 12 }
}
- Legacy id mapping:
{
  "success": true,
  "newVersion": 43,
  "newIds": {
    "localIndex_0": "uuid-abc",
    "localIndex_1": "uuid-def"
  },
  "report": { /* ... */ }
}

Следующие deliverables (я могу создать в PR)
- docs/SERVER_SYNC_SPEC.md (этот файл) — уже добавлен в ветку feature/sync-reports.
- Пример псевдокода merge handler (Node/Python) — могу приложить.
- Client PR (зависит от серверной поддержки) с изменениями моделей, миграцией и id-based diff.

Контактные вопросы для backend команды
- Хотите ли вы, чтобы сервер выполнял dedup по fingerprint автоматически или возвращал кандидаты для ручечной проверки?
- Какая политика по authorId доверия: should server override client-supplied user:<id> and set it to requestor's id?
- Хотите ли endpoint для claiming anonymous edits (map share:...:anon -> user:<id>)?

---

