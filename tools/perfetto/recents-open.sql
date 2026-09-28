-- Jank per Recents phase: SF frame timeline (actual_frame_timeline_slice) bucketed by the
-- RPHASE logcat markers, plus the average GPU clock in each phase.
-- trace_processor_shell -q tools/perfetto/recents-open.sql <trace>
DROP VIEW IF EXISTS phases;
CREATE VIEW phases AS
SELECT ts, LEAD(ts) OVER (ORDER BY ts) AS end_ts, msg AS phase
FROM android_logs WHERE tag = 'RPHASE';

SELECT p.phase,
       COUNT(*) AS frames,
       SUM(a.jank_type != 'None') AS janky,
       ROUND(100.0 * SUM(a.jank_type != 'None') / COUNT(*), 1) AS jank_pct,
       SUM(a.jank_type LIKE '%SurfaceFlinger GPU Deadline Missed%') AS sf_gpu,
       SUM(a.jank_type LIKE '%App Deadline Missed%') AS app
FROM actual_frame_timeline_slice a
JOIN process_track t ON a.track_id = t.id
JOIN process pr USING (upid)
JOIN phases p ON a.ts >= p.ts AND a.ts < p.end_ts
WHERE pr.name = '/system/bin/surfaceflinger'
GROUP BY p.phase ORDER BY p.phase;

SELECT p.phase, ROUND(AVG(c.value) / 1e6) AS avg_gpu_mhz, ROUND(MIN(c.value) / 1e6) AS min_gpu_mhz
FROM counter c JOIN gpu_counter_track g ON c.track_id = g.id
JOIN phases p ON c.ts >= p.ts AND c.ts < p.end_ts
WHERE g.name = 'gpufreq'
GROUP BY p.phase ORDER BY p.phase;
