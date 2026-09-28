#!/bin/bash
# Short perfetto trace while fling-scrolling Settings, then report composer
# commit time, SurfaceFlinger present time and app buffer waits.
# Usage: tools/hwc-trace.sh <build-id> <label>
set -uo pipefail
. "$(dirname "$0")/env"
R="$(dirname "$0")/remote.sh"
TP=$DIZI_ROOT/evox/out/host/linux-x86/bin/trace_processor_shell
id=${1:?build-id}; label=${2:?label}
out=$DIZI_ROOT/logs/$id/trace; mkdir -p "$out"
cfg=/tmp/hwc-trace.cfg
cat > $cfg <<'EOF'
buffers { size_kb: 65536 fill_policy: RING_BUFFER }
data_sources { config { name: "linux.ftrace" ftrace_config {
  ftrace_events: "sched/sched_switch" atrace_categories: "gfx" atrace_categories: "view" atrace_categories: "hal"
  atrace_apps: "com.android.settings" } } }
data_sources { config { name: "linux.process_stats" } }
duration_ms: 8000
EOF
scp -q -i "$DIZI_SSH_KEY" $cfg "$DIZI_HOST:$DIZI_REMOTE_DIR/hwc-trace.cfg"
"$R" adb push "$DIZI_REMOTE_DIR/hwc-trace.cfg" /data/misc/perfetto-configs/hwc-trace.cfg >/dev/null 2>&1
"$R" adb shell 'input keyevent WAKEUP; wm dismiss-keyguard; am start -a android.settings.SETTINGS >/dev/null 2>&1; sleep 2
	(perfetto --txt -c /data/misc/perfetto-configs/hwc-trace.cfg -o /data/misc/perfetto-traces/hwc.pftrace >/dev/null 2>&1 &)
	sleep 1; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do input swipe 1280 1200 1280 400 120; sleep 0.3; done; sleep 4' </dev/null
"$R" adb exec-out cat /data/misc/perfetto-traces/hwc.pftrace > "$out/hwc-$label.pftrace" </dev/null
cat > /tmp/hwc-trace.sql <<'EOF'
select s.name, count(*) n, round(avg(s.dur)/1e6,2) avg_ms, round(max(s.dur)/1e6,2) max_ms
from slice s join thread_track tt on s.track_id = tt.id join thread t using(utid) join process p using(upid)
where s.name in ('DisplayBase::PerformHwCommit::', 'present', 'eglSwapBuffersWithDamageKHR', 'waitForever', 'DrawFrames', 'dequeueBuffer')
group by s.name order by s.name;
EOF
echo "== $label"
"$TP" -q /tmp/hwc-trace.sql "$out/hwc-$label.pftrace" 2>/dev/null
