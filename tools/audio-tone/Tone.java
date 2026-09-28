// Play a sine tone through the media stream from adb (app_process).
// Usage: CLASSPATH=/data/local/tmp/tone.dex app_process / Tone [hz] [seconds] [left|right|both]
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;

public class Tone {
    public static void main(String[] args) throws Exception {
        double hz = args.length > 0 ? Double.parseDouble(args[0]) : 1000;
        int seconds = args.length > 1 ? Integer.parseInt(args[1]) : 3;
        String ch = args.length > 2 ? args[2] : "both";
        int rate = 48000, frames = rate * seconds;
        short[] pcm = new short[frames * 2];
        for (int i = 0; i < frames; i++) {
            short v = (short) (Math.sin(2 * Math.PI * hz * i / rate) * 12000);
            pcm[2 * i] = ch.equals("right") ? 0 : v;
            pcm[2 * i + 1] = ch.equals("left") ? 0 : v;
        }
        AudioTrack track = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.length * 2).build();
        track.write(pcm, 0, pcm.length);
        track.play();
        System.out.println("playing " + hz + " Hz for " + seconds + " s (" + ch + ")");
        Thread.sleep(seconds * 1000L + 300);
        track.release();
    }
}
