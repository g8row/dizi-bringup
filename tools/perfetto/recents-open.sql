-- Jank per transition phase, from a tools/recents-open-trace.sh trace.
-- Windows are the WM Shell transition perf sessions (PerfSession-d0-Transition), labelled by the
-- preceding playTransition (TO_FRONT = Recents -> app, OPEN = app -> home); everything else is
-- "other" (entering overview, idle). trace_processor_shell -q only prints the last statement, so
-- this is one query.
-- trace_processor_shell -q tools/perfetto/recents-open.sql <trace>
WITH win AS (
  SELECT s.ts, s.ts + s.dur AS end_ts,
         (SELECT REPLACE(p.name, 'playTransition: ', '') FROM slice p
          WHERE p.name LIKE 'playTransition: %' AND p.ts <= s.ts + 50000000
          ORDER BY p.ts DESC LIMIT 1) AS kind
  FROM slice s WHERE s.name = 'PerfSession-d0-Transition'
),
sf AS (
  -- SurfaceFlinger's display frames are the timeline slices without a layer.
  SELECT a.ts, a.dur, a.jank_type FROM actual_frame_timeline_slice a WHERE a.layer_name IS NULL
),
f AS (
  SELECT COALESCE((SELECT w.kind FROM win w WHERE sf.ts >= w.ts AND sf.ts < w.end_ts), 'other') AS phase,
         sf.jank_type FROM sf
),
g AS (
  SELECT COALESCE((SELECT w.kind FROM win w WHERE c.ts >= w.ts AND c.ts < w.end_ts), 'other') AS phase,
         c.value FROM counter c JOIN counter_track ct ON c.track_id = ct.id WHERE ct.name = 'gpufreq'
)
SELECT f.phase,
       COUNT(*) AS frames,
       SUM(f.jank_type NOT IN ('None', 'Buffer Stuffing')) AS janky,
       ROUND(100.0 * SUM(f.jank_type NOT IN ('None', 'Buffer Stuffing')) / COUNT(*), 1) AS jank_pct,
       SUM(f.jank_type LIKE '%SurfaceFlinger GPU Deadline Missed%') AS sf_gpu,
       SUM(f.jank_type LIKE '%App Deadline Missed%') AS app,
       (SELECT ROUND(AVG(value) / 1e6) FROM g WHERE g.phase = f.phase) AS avg_gpu_mhz,
       (SELECT ROUND(MIN(value) / 1e6) FROM g WHERE g.phase = f.phase) AS min_gpu_mhz,
       (SELECT COUNT(*) FROM g WHERE g.phase = f.phase) AS gpu_samples
FROM f GROUP BY f.phase ORDER BY f.phase;
