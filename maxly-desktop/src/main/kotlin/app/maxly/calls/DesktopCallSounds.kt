package app.maxly.calls

import app.maxly.presentation.calls.CallTones
import app.maxly.ui.calls.CallSounds
import javax.sound.sampled.AudioFormat
import javax.sound.sampled.AudioSystem
import javax.sound.sampled.Clip

/** Гудки и звонок входящего через Java Sound: PCM из [CallTones] по кругу. */
class DesktopCallSounds : CallSounds {
    private var clip: Clip? = null
    private var playing: String? = null

    override fun ringback() = play("ringback") { CallTones.ringback() }

    override fun ringtone() = play("ringtone") { CallTones.ringtone() }

    override fun stop() {
        playing = null
        clip?.let {
            runCatching { it.stop() }
            runCatching { it.close() }
        }
        clip = null
    }

    private fun play(name: String, pcm: () -> ByteArray) {
        if (playing == name) return
        stop()
        playing = name
        clip = runCatching {
            val bytes = pcm()
            AudioSystem.getClip().apply {
                open(AudioFormat(CallTones.SAMPLE_RATE.toFloat(), 16, 1, true, false), bytes, 0, bytes.size)
                loop(Clip.LOOP_CONTINUOUSLY)
            }
        }.getOrNull()
    }
}
