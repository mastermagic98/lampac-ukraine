# Migration Plan v1

## Strategy
Expand -> Backfill -> Switch -> Stabilize -> (Optional) Contract.

## Phase 1: Schema bootstrap
1. Apply extensions + enums.
2. Create core tables (`content`, `season`, `episode`).
3. Create source tables (`stream_source`, `stream_subtitle`).
4. Create jobs/cache/state tables.
5. Create triggers + indexes.

## Phase 2: Backfill
1. Backfill content with normalized IDs and titles.
2. Backfill seasons/episodes.
3. Backfill streams and compute hashes (`m3u8_url_hash`, subtitle hashes).
4. Parse subtitles into `stream_subtitle`.
5. Build `content_source_state`.

## Phase 3: App dual-mode
1. Enable write to new schema (`new_db_write_enabled=true`).
2. Keep old read path active temporarily.
3. Validate parity on контрольний набір тайтлів.

## Phase 4: Read switch
1. Enable new read path (`new_db_read_enabled=true`).
2. Keep legacy fallback flag ready.
3. Enable enrichment scheduler/jobs.

## Phase 5: Stabilization
1. Monitor 24-48h:
   - 5xx
   - p95
   - queue lag
   - provider coverage
2. Fix selector/parser regressions quickly.

## Rollback
### Fast rollback
- `new_db_read_enabled=false`
- `legacy_read_fallback_enabled=true`
- `enrichment_jobs_enabled=false` (if needed)

### Partial rollback
- Disable problematic provider/broker via runtime config.

### Full rollback
- Restore DB snapshot taken pre-deploy.

## Post-deploy verification SQL
```sql
SELECT to_regclass('public.content'),
       to_regclass('public.stream_source'),
       to_regclass('public.enrichment_job');

SELECT enumlabel FROM pg_enum
WHERE enumtypid = 'provider_code'::regtype
ORDER BY enumsortorder;

SELECT COUNT(*) FROM stream_source
WHERE m3u8_url IS NULL AND embed_url IS NULL;
```
Expected for last query: `0`.

## Done criteria
- New schema read path stable.
- Correct provider priority in Lampac responses.
- Queue lag within target.
- No critical parsing regressions.
