// Record from a microphone source from adb (app_process, as root) and print its level.
// Silent test: room noise alone gives a clearly non-zero RMS on a working mic.
// Usage: CLASSPATH=/data/local/tmp/rec.dex app_process / Rec [seconds] [source]
//   source: mic (default), camcorder, voice_recognition, unprocessed
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;

public class Rec {
    public static void main(String[] args) throws Exception {
        int seconds = args.length > 0 ? Integer.parseInt(args[0]) : 3;
        String name = args.length > 1 ? args[1] : "mic";
        int source = switch (name) {
            case "camcorder" -> MediaRecorder.AudioSource.CAMCORDER;
            case "voice_recognition" -> MediaRecorder.AudioSource.VOICE_RECOGNITION;
            case "unprocessed" -> MediaRecorder.AudioSource.UNPROCESSED;
            default -> MediaRecorder.AudioSource.MIC;
        };
        int rate = 48000;
        int min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT);
        AudioRecord rec = new AudioRecord(source, rate, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, Math.max(min, rate));
        if (rec.getState() != AudioRecord.STATE_INITIALIZED) {
            System.out.println("init failed (state " + rec.getState() + ")");
            System.exit(2);
        }
        short[] buf = new short[rate * seconds];
        rec.startRecording();
        int got = 0;
        while (got < buf.length) {
            int n = rec.read(buf, got, buf.length - got);
            if (n <= 0) break;
            got += n;
        }
        rec.stop();
        rec.release();
        // Skip the first 200 ms (AGC / pop).
        int skip = Math.min(got, rate / 5);
        double sum = 0;
        int peak = 0;
        for (int i = skip; i < got; i++) {
            sum += (double) buf[i] * buf[i];
            peak = Math.max(peak, Math.abs(buf[i]));
        }
        double rms = Math.sqrt(sum / Math.max(1, got - skip));
        System.out.printf("source=%s samples=%d rms=%.1f (%.1f dBFS) peak=%d (%.1f dBFS)%n", name, got,
                rms, 20 * Math.log10(Math.max(rms, 1e-9) / 32768), peak,
                20 * Math.log10(Math.max(peak, 1) / 32768.0));
    }
}
