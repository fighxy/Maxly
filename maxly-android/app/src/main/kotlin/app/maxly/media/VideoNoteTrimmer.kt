package app.maxly.media

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Кусок кружка без перекодирования: дорожки копируются как есть от ключевого кадра не позже
 * начала куска до его конца. Начало может уйти на долю секунды раньше выбранного.
 */
object VideoNoteTrimmer {
    /** Длительность получившегося ролика, мс; `null` — не вышло. */
    fun trim(source: File, fromMs: Long, toMs: Long, target: File): Long? {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(source.path)
            val out = MediaMuxer(target.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = out
            val tracks = HashMap<Int, Int>()
            var bufferSize = 1 shl 20
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(index)
                tracks[index] = out.addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    bufferSize = maxOf(bufferSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            if (tracks.isEmpty()) return null
            rotation(source)?.let(out::setOrientationHint)
            val fromUs = fromMs * 1_000
            val toUs = toMs * 1_000
            extractor.seekTo(fromUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val baseUs = extractor.sampleTime.coerceAtLeast(0)
            out.start()
            val buffer = ByteBuffer.allocate(bufferSize)
            val info = MediaCodec.BufferInfo()
            var lastUs = baseUs
            while (true) {
                val track = extractor.sampleTrackIndex
                if (track < 0) break
                val time = extractor.sampleTime
                if (time > toUs) break
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val dest = tracks[track]
                if (dest != null && time >= baseUs) {
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = time - baseUs
                    info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    out.writeSampleData(dest, buffer, info)
                    lastUs = maxOf(lastUs, time)
                }
                extractor.advance()
            }
            out.stop()
            ((lastUs - baseUs) / 1_000).takeIf { it > 0 }
        } catch (e: Exception) {
            target.delete()
            null
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }

    private fun rotation(source: File): Int? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(source.path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }
}
