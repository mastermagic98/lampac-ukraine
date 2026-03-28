CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'content_kind') THEN
    CREATE TYPE content_kind AS ENUM ('movie', 'series');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'provider_code') THEN
    CREATE TYPE provider_code AS ENUM (
      'ashdi','hdvbua','tortuga','uaflix_zetvideo','uafilm','vidsrc_fallback'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_trigger_type') THEN
    CREATE TYPE job_trigger_type AS ENUM ('schedule','lampa_request','manual');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
    CREATE TYPE job_status AS ENUM ('queued','running','done','partial','failed','canceled');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS content (
  id BIGSERIAL PRIMARY KEY,
  content_type content_kind NOT NULL,
  title_ua TEXT,
  title_original TEXT,
  title_search_norm TEXT,
  year INT,
  tmdb_id BIGINT,
  imdb_id CITEXT,
  original_language VARCHAR(8),
  description TEXT,
  poster_url TEXT,
  backdrop_url TEXT,
  runtime_minutes INT,
  rating_imdb NUMERIC(3,1),
  rating_tmdb NUMERIC(4,2),
  strict_uk_original BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_content_year CHECK (year IS NULL OR year BETWEEN 1888 AND 2100),
  CONSTRAINT chk_imdb_format CHECK (imdb_id IS NULL OR imdb_id ~ '^tt[0-9]{6,12}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_content_tmdb ON content (tmdb_id) WHERE tmdb_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_content_imdb ON content (imdb_id) WHERE imdb_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_content_type_year ON content (content_type, year);
CREATE INDEX IF NOT EXISTS ix_content_title_norm_trgm ON content USING gin (title_search_norm gin_trgm_ops);

CREATE TABLE IF NOT EXISTS season (
  id BIGSERIAL PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content(id) ON DELETE CASCADE,
  season_number INT NOT NULL,
  title_season TEXT,
  release_year INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_season_num CHECK (season_number > 0),
  CONSTRAINT uq_season UNIQUE (content_id, season_number)
);

CREATE TABLE IF NOT EXISTS episode (
  id BIGSERIAL PRIMARY KEY,
  content_id BIGINT NOT NULL REFERENCES content(id) ON DELETE CASCADE,
  season_id BIGINT NOT NULL REFERENCES season(id) ON DELETE CASCADE,
  episode_number INT NOT NULL,
  title_episode TEXT,
  air_date DATE,
  tmdb_episode_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_episode_num CHECK (episode_number > 0),
  CONSTRAINT uq_episode UNIQUE (season_id, episode_number)
);

CREATE TABLE IF NOT EXISTS stream_source (
  id BIGSERIAL PRIMARY KEY,
  provider provider_code NOT NULL,
  discovery_source TEXT,
  source_variant TEXT,
  voice_group TEXT,

  content_id BIGINT NOT NULL REFERENCES content(id) ON DELETE CASCADE,
  season_id BIGINT REFERENCES season(id) ON DELETE CASCADE,
  episode_id BIGINT REFERENCES episode(id) ON DELETE CASCADE,

  source_page_url TEXT,
  embed_url_raw TEXT,
  embed_url TEXT,
  watch_url TEXT,

  m3u8_url TEXT,
  m3u8_url_hash CHAR(64),
  poster_url TEXT,

  quality_label TEXT,
  referer_required BOOLEAN NOT NULL DEFAULT FALSE,
  referer_value TEXT,

  requires_embed_playback BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  subtitle_raw TEXT,
  raw_payload JSONB,
  parse_errors JSONB,

  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_checked_at TIMESTAMPTZ,
  fail_count INT NOT NULL DEFAULT 0,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_fail_count CHECK (fail_count >= 0),
  CONSTRAINT chk_stream_has_url CHECK (m3u8_url IS NOT NULL OR embed_url IS NOT NULL),
  CONSTRAINT chk_episode_requires_season CHECK (episode_id IS NULL OR season_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS ix_stream_provider_active ON stream_source (provider, is_active);
CREATE INDEX IF NOT EXISTS ix_stream_content ON stream_source (content_id);
CREATE INDEX IF NOT EXISTS ix_stream_episode ON stream_source (episode_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_stream_m3u8
ON stream_source (provider, m3u8_url_hash, COALESCE(episode_id,0), COALESCE(season_id,0), COALESCE(voice_group,''))
WHERE m3u8_url_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_stream_embed
ON stream_source (provider, COALESCE(embed_url,''), COALESCE(episode_id,0), COALESCE(season_id,0), COALESCE(voice_group,''))
WHERE m3u8_url_hash IS NULL AND embed_url IS NOT NULL;

CREATE TABLE IF NOT EXISTS stream_subtitle (
  id BIGSERIAL PRIMARY KEY,
  stream_source_id BIGINT NOT NULL REFERENCES stream_source(id) ON DELETE CASCADE,
  label TEXT,
  lang_code VARCHAR(16),
  url TEXT NOT NULL,
  url_hash CHAR(64),
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_subtitle_hash
ON stream_subtitle (stream_source_id, url_hash)
WHERE url_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_subtitle_url
ON stream_subtitle (stream_source_id, url)
WHERE url_hash IS NULL;

CREATE TABLE IF NOT EXISTS enrichment_job (
  id BIGSERIAL PRIMARY KEY,
  trigger_type job_trigger_type NOT NULL,
  status job_status NOT NULL DEFAULT 'queued',

  content_id BIGINT REFERENCES content(id) ON DELETE SET NULL,
  tmdb_id BIGINT,
  imdb_id CITEXT,
  requested_by TEXT,
  request_payload JSONB,

  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  error_message TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_job_status ON enrichment_job (status, created_at DESC);

CREATE TABLE IF NOT EXISTS provider_attempt (
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES enrichment_job(id) ON DELETE CASCADE,
  provider provider_code NOT NULL,
  broker_name TEXT,
  query_text TEXT,
  query_mode TEXT,
  status job_status NOT NULL DEFAULT 'queued',
  found_count INT NOT NULL DEFAULT 0,
  duration_ms INT,
  error_message TEXT,
  debug_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_attempt_job ON provider_attempt (job_id);
CREATE INDEX IF NOT EXISTS ix_attempt_provider_status ON provider_attempt (provider, status);

CREATE TABLE IF NOT EXISTS resolver_cache (
  id BIGSERIAL PRIMARY KEY,
  normalized_title TEXT NOT NULL,
  year INT,
  content_type content_kind,
  tmdb_id BIGINT,
  imdb_id CITEXT,
  confidence NUMERIC(4,3) NOT NULL DEFAULT 0,
  source TEXT,
  payload JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_resolver_key
ON resolver_cache (normalized_title, COALESCE(year,0), COALESCE(content_type::text,''));

CREATE TABLE IF NOT EXISTS content_source_state (
  content_id BIGINT PRIMARY KEY REFERENCES content(id) ON DELETE CASCADE,
  has_ashdi BOOLEAN NOT NULL DEFAULT FALSE,
  has_hdvbua BOOLEAN NOT NULL DEFAULT FALSE,
  has_tortuga BOOLEAN NOT NULL DEFAULT FALSE,
  has_uaflix_zetvideo BOOLEAN NOT NULL DEFAULT FALSE,
  has_uafilm BOOLEAN NOT NULL DEFAULT FALSE,
  has_vidsrc_fallback BOOLEAN NOT NULL DEFAULT FALSE,
  last_enriched_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_content_updated_at') THEN
    CREATE TRIGGER trg_content_updated_at BEFORE UPDATE ON content
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_season_updated_at') THEN
    CREATE TRIGGER trg_season_updated_at BEFORE UPDATE ON season
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_episode_updated_at') THEN
    CREATE TRIGGER trg_episode_updated_at BEFORE UPDATE ON episode
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_stream_updated_at') THEN
    CREATE TRIGGER trg_stream_updated_at BEFORE UPDATE ON stream_source
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_job_updated_at') THEN
    CREATE TRIGGER trg_job_updated_at BEFORE UPDATE ON enrichment_job
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_attempt_updated_at') THEN
    CREATE TRIGGER trg_attempt_updated_at BEFORE UPDATE ON provider_attempt
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END$$;
