# Lampac Export Contract v1

## 1) Призначення

Цей контракт описує формат даних, який віддає агрегатор у Lampac:
- для **фільмів**
- для **серіалів / епізодів**
- з урахуванням пріоритетів провайдерів:
  1) ashdi
  2) hdvbua
  3) tortuga
  4) uaflix/zetvideo
  5) uafilm
  6) vidsrc (fallback)

---

## 2) Загальні правила

1. Відповідь завжди містить `content` + `sources`.
2. `sources` відсортовані за `provider_priority`.
3. Якщо `is_active=false` — джерело не віддавати (за замовчуванням).
4. Якщо немає `m3u8`, але є embed-only (vidsrc), джерело віддавати з `playback_mode=embed`.
5. Субтитри повертаються масивом `subtitles[]`.
6. Для серіалів обов’язково вказувати `season_number` і `episode_number` у source-елементах.

---

## 3) Ендпоінти (рекомендовано)

## 3.1 Фільм
`GET /api/lampac/movie/{tmdb_id}`
або
`GET /api/lampac/movie/imdb/{imdb_id}`

## 3.2 Серіал (список сезонів/епізодів)
`GET /api/lampac/series/{tmdb_id}`

## 3.3 Конкретний епізод
`GET /api/lampac/series/{tmdb_id}/season/{season}/episode/{episode}`

---

## 4) JSON Schema (логічна модель)

```json
{
  "content": {
    "id": 0,
    "tmdb_id": 0,
    "imdb_id": "tt0000000",
    "type": "movie|series",
    "title_ua": "string",
    "title_original": "string",
    "year": 2025,
    "original_language": "uk",
    "poster": "https://...",
    "description": "string"
  },
  "episode": {
    "season_number": 1,
    "episode_number": 1,
    "title": "string"
  },
  "sources": [
    {
      "source_id": 0,
      "provider": "ashdi|hdvbua|tortuga|uaflix_zetvideo|uafilm|vidsrc_fallback",
      "provider_priority": 1,
      "discovery_source": "uakino.ac|uaserials.my|...",
      "voice_group": "DniproFilm|HDrezka Studio|...",
      "quality": "1080p|720p|480p|auto",
      "is_active": true,

      "playback_mode": "m3u8|embed",
      "m3u8_url": "https://.../index.m3u8",
      "embed_url": "https://.../embed/..",
      "poster_url": "https://.../screen.jpg",

      "headers": {
        "Referer": "https://uafilm.me/"
      },

      "subtitles": [
        {
          "label": "Українські",
          "lang": "uk",
          "url": "https://...vtt",
          "default": true
        }
      ],

      "meta": {
        "content_type": "movie|series",
        "season_number": 1,
        "episode_number": 1
      }
    }
  ],
  "export_meta": {
    "generated_at": "2026-03-27T12:00:00Z",
    "version": "v1",
    "fallback_used": false
  }
}
```

---

## 5) Обов’язкові поля

### На рівні `content`
- `type`
- `title_ua` (або fallback на `title_original`)
- мінімум один із: `tmdb_id` / `imdb_id`

### На рівні `sources[]`
- `provider`
- `provider_priority`
- `playback_mode`
- якщо `playback_mode=m3u8` => `m3u8_url` required
- якщо `playback_mode=embed` => `embed_url` required

---

## 6) Нормалізація даних

1. `provider_priority` виставляти явно в payload.
2. `voice_group` брати з folder-рівня (якщо є).
3. `subtitles`:
   - порожній рядок => `[]`
   - malformed (`"[")` => `[]`, записати warning в логах, але не ламати response.
4. `headers.Referer` додавати тільки коли реально потрібен.
5. URL приводити до canonical вигляду (без службових query для dedup), але `embed_url` можна віддавати raw якщо потрібно для playback.

---

## 7) Поведінка fallback

- Якщо немає активних джерел від провайдерів 1-5:
  - дозволити `vidsrc_fallback`.
  - `export_meta.fallback_used=true`.

---

## 8) Коди помилок (API)

- `404 CONTENT_NOT_FOUND` — контент не знайдено.
- `404 EPISODE_NOT_FOUND` — епізод не знайдено.
- `204 NO_ACTIVE_SOURCES` — джерела відсутні (або можна `200` з `sources: []`, на ваш вибір).
- `202 ENRICHMENT_IN_PROGRESS` — для on-demand запиту, коли джерела ще збираються.
- `500 INTERNAL_ERROR` — внутрішня помилка.

---

## 9) Мінімальні acceptance criteria

1. Для movie і episode повертаються `sources[]`, відсортовані за пріоритетом.
2. Embed-only джерела підтримуються (`playback_mode=embed`).
3. Некоректні subtitle не ламають відповідь.
4. У відповіді присутній `export_meta.generated_at`.
