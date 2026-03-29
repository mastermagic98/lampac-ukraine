-- Lampac Export Queries v1 (reference implementation)
-- Requires schema from docs/specs/db-mapping-v1.sql

-- 1) Helper: provider priority mapping
CREATE OR REPLACE FUNCTION lampac_provider_priority(p provider_code)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
AS $$
SELECT CASE p
  WHEN 'ashdi' THEN 1
  WHEN 'hdvbua' THEN 2
  WHEN 'tortuga' THEN 3
  WHEN 'uaflix_zetvideo' THEN 4
  WHEN 'uafilm' THEN 5
  WHEN 'vidsrc_fallback' THEN 6
  ELSE 999
END
$$;

-- 2) Movie export payload by TMDB ID
-- Usage: SELECT lampac_export_movie_by_tmdb(872585, false);
CREATE OR REPLACE FUNCTION lampac_export_movie_by_tmdb(
  p_tmdb_id BIGINT,
  p_include_inactive BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
WITH c AS (
  SELECT *
  FROM content
  WHERE tmdb_id = p_tmdb_id
    AND content_type = 'movie'
  LIMIT 1
),
src AS (
  SELECT
    s.*,
    lampac_provider_priority(s.provider) AS provider_priority
  FROM stream_source s
  JOIN c ON c.id = s.content_id
  WHERE s.episode_id IS NULL
    AND (p_include_inactive OR s.is_active = TRUE)
),
src_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'source_id', s.id,
      'provider', s.provider::TEXT,
      'provider_priority', s.provider_priority,
      'discovery_source', s.discovery_source,
      'voice_group', s.voice_group,
      'quality', s.quality_label,
      'is_active', s.is_active,
      'playback_mode', CASE WHEN s.m3u8_url IS NOT NULL THEN 'm3u8' ELSE 'embed' END,
      'm3u8_url', s.m3u8_url,
      'embed_url', s.embed_url,
      'poster_url', s.poster_url,
      'headers', CASE
        WHEN s.referer_required AND s.referer_value IS NOT NULL
          THEN jsonb_build_object('Referer', s.referer_value)
        ELSE '{}'::jsonb
      END,
      'subtitles', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'label', st.label,
            'lang', st.lang_code,
            'url', st.url,
            'default', st.is_default
          )
          ORDER BY st.id
        )
        FROM stream_subtitle st
        WHERE st.stream_source_id = s.id
      ), '[]'::jsonb),
      'meta', jsonb_build_object(
        'content_type', 'movie',
        'season_number', NULL,
        'episode_number', NULL
      )
    )
    ORDER BY s.provider_priority, s.id
  ) AS sources
  FROM src s
)
SELECT jsonb_build_object(
  'content', jsonb_build_object(
    'id', c.id,
    'tmdb_id', c.tmdb_id,
    'imdb_id', c.imdb_id,
    'type', c.content_type::TEXT,
    'title_ua', COALESCE(c.title_ua, c.title_original),
    'title_original', c.title_original,
    'year', c.year,
    'original_language', c.original_language,
    'poster', c.poster_url,
    'description', c.description
  ),
  'sources', COALESCE(sp.sources, '[]'::jsonb),
  'export_meta', jsonb_build_object(
    'generated_at', NOW(),
    'version', 'v1',
    'fallback_used', COALESCE((
      SELECT EXISTS (
        SELECT 1
        FROM src s
        WHERE s.provider = 'vidsrc_fallback'
      )
    ), FALSE)
  )
)
FROM c
LEFT JOIN src_payload sp ON TRUE;
$$;

-- 3) Episode export payload by TMDB ID + season + episode
-- Usage: SELECT lampac_export_episode_by_tmdb(1399, 1, 1, false);
CREATE OR REPLACE FUNCTION lampac_export_episode_by_tmdb(
  p_tmdb_id BIGINT,
  p_season INT,
  p_episode INT,
  p_include_inactive BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
WITH c AS (
  SELECT *
  FROM content
  WHERE tmdb_id = p_tmdb_id
    AND content_type = 'series'
  LIMIT 1
),
se AS (
  SELECT s.*
  FROM season s
  JOIN c ON c.id = s.content_id
  WHERE s.season_number = p_season
  LIMIT 1
),
ep AS (
  SELECT e.*
  FROM episode e
  JOIN se ON se.id = e.season_id
  WHERE e.episode_number = p_episode
  LIMIT 1
),
src AS (
  SELECT
    s.*,
    lampac_provider_priority(s.provider) AS provider_priority
  FROM stream_source s
  JOIN ep ON ep.id = s.episode_id
  WHERE (p_include_inactive OR s.is_active = TRUE)
),
src_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'source_id', s.id,
      'provider', s.provider::TEXT,
      'provider_priority', s.provider_priority,
      'discovery_source', s.discovery_source,
      'voice_group', s.voice_group,
      'quality', s.quality_label,
      'is_active', s.is_active,
      'playback_mode', CASE WHEN s.m3u8_url IS NOT NULL THEN 'm3u8' ELSE 'embed' END,
      'm3u8_url', s.m3u8_url,
      'embed_url', s.embed_url,
      'poster_url', s.poster_url,
      'headers', CASE
        WHEN s.referer_required AND s.referer_value IS NOT NULL
          THEN jsonb_build_object('Referer', s.referer_value)
        ELSE '{}'::jsonb
      END,
      'subtitles', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'label', st.label,
            'lang', st.lang_code,
            'url', st.url,
            'default', st.is_default
          )
          ORDER BY st.id
        )
        FROM stream_subtitle st
        WHERE st.stream_source_id = s.id
      ), '[]'::jsonb),
      'meta', jsonb_build_object(
        'content_type', 'series',
        'season_number', p_season,
        'episode_number', p_episode
      )
    )
    ORDER BY s.provider_priority, s.id
  ) AS sources
  FROM src s
)
SELECT jsonb_build_object(
  'content', jsonb_build_object(
    'id', c.id,
    'tmdb_id', c.tmdb_id,
    'imdb_id', c.imdb_id,
    'type', c.content_type::TEXT,
    'title_ua', COALESCE(c.title_ua, c.title_original),
    'title_original', c.title_original,
    'year', c.year,
    'original_language', c.original_language,
    'poster', c.poster_url,
    'description', c.description
  ),
  'episode', jsonb_build_object(
    'season_number', p_season,
    'episode_number', p_episode,
    'title', ep.title_episode
  ),
  'sources', COALESCE(sp.sources, '[]'::jsonb),
  'export_meta', jsonb_build_object(
    'generated_at', NOW(),
    'version', 'v1',
    'fallback_used', COALESCE((
      SELECT EXISTS (
        SELECT 1
        FROM src s
        WHERE s.provider = 'vidsrc_fallback'
      )
    ), FALSE)
  )
)
FROM c
JOIN ep ON TRUE
LEFT JOIN src_payload sp ON TRUE;
$$;

-- 4) Full series export payload (seasons -> episodes -> sources)
-- Usage: SELECT lampac_export_series_by_tmdb(1399, false);
CREATE OR REPLACE FUNCTION lampac_export_series_by_tmdb(
  p_tmdb_id BIGINT,
  p_include_inactive BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE SQL
STABLE
AS $$
WITH c AS (
  SELECT *
  FROM content
  WHERE tmdb_id = p_tmdb_id
    AND content_type = 'series'
  LIMIT 1
),
base AS (
  SELECT
    s.id AS season_id,
    s.season_number,
    e.id AS episode_id,
    e.episode_number,
    e.title_episode
  FROM season s
  JOIN c ON c.id = s.content_id
  LEFT JOIN episode e ON e.season_id = s.id
),
src AS (
  SELECT
    b.season_number,
    b.episode_number,
    b.episode_id,
    ss.id AS source_id,
    ss.provider,
    lampac_provider_priority(ss.provider) AS provider_priority,
    ss.discovery_source,
    ss.voice_group,
    ss.quality_label,
    ss.is_active,
    ss.m3u8_url,
    ss.embed_url,
    ss.poster_url,
    ss.referer_required,
    ss.referer_value
  FROM base b
  LEFT JOIN stream_source ss ON ss.episode_id = b.episode_id
  WHERE ss.id IS NULL OR (p_include_inactive OR ss.is_active = TRUE)
),
episode_payload AS (
  SELECT
    b.season_number,
    b.episode_number,
    jsonb_build_object(
      'episode', jsonb_build_object(
        'season_number', b.season_number,
        'episode_number', b.episode_number,
        'title', b.title_episode
      ),
      'sources', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'source_id', s.source_id,
            'provider', s.provider::TEXT,
            'provider_priority', s.provider_priority,
            'discovery_source', s.discovery_source,
            'voice_group', s.voice_group,
            'quality', s.quality_label,
            'is_active', s.is_active,
            'playback_mode', CASE WHEN s.m3u8_url IS NOT NULL THEN 'm3u8' ELSE 'embed' END,
            'm3u8_url', s.m3u8_url,
            'embed_url', s.embed_url,
            'poster_url', s.poster_url,
            'headers', CASE
              WHEN s.referer_required AND s.referer_value IS NOT NULL
                THEN jsonb_build_object('Referer', s.referer_value)
              ELSE '{}'::jsonb
            END,
            'subtitles', COALESCE((
              SELECT jsonb_agg(
                jsonb_build_object(
                  'label', st.label,
                  'lang', st.lang_code,
                  'url', st.url,
                  'default', st.is_default
                )
                ORDER BY st.id
              )
              FROM stream_subtitle st
              WHERE st.stream_source_id = s.source_id
            ), '[]'::jsonb),
            'meta', jsonb_build_object(
              'content_type', 'series',
              'season_number', b.season_number,
              'episode_number', b.episode_number
            )
          )
          ORDER BY s.provider_priority, s.source_id
        )
        FROM src s
        WHERE s.episode_id = b.episode_id
      ), '[]'::jsonb)
    ) AS episode_json
  FROM base b
  WHERE b.episode_id IS NOT NULL
),
season_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'season_number', b.season_number,
      'episodes', COALESCE((
        SELECT jsonb_agg(ep.episode_json ORDER BY ep.episode_number)
        FROM episode_payload ep
        WHERE ep.season_number = b.season_number
      ), '[]'::jsonb)
    )
    ORDER BY b.season_number
  ) AS seasons
  FROM (SELECT DISTINCT season_number FROM base) b
)
SELECT jsonb_build_object(
  'content', jsonb_build_object(
    'id', c.id,
    'tmdb_id', c.tmdb_id,
    'imdb_id', c.imdb_id,
    'type', c.content_type::TEXT,
    'title_ua', COALESCE(c.title_ua, c.title_original),
    'title_original', c.title_original,
    'year', c.year,
    'original_language', c.original_language,
    'poster', c.poster_url,
    'description', c.description
  ),
  'seasons', COALESCE(sp.seasons, '[]'::jsonb),
  'export_meta', jsonb_build_object(
    'generated_at', NOW(),
    'version', 'v1',
    'fallback_used', COALESCE((
      SELECT EXISTS (
        SELECT 1
        FROM src s
        WHERE s.provider = 'vidsrc_fallback'
      )
    ), FALSE)
  )
)
FROM c
LEFT JOIN season_payload sp ON TRUE;
$$;
