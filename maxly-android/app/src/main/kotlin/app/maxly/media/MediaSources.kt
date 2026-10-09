package app.maxly.media

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

/** Источники Media3 для голосовых и видео: CDN принимает только User-Agent Android-клиента. */
@OptIn(UnstableApi::class)
object MediaSources {
    fun factory(context: Context, userAgent: String): DefaultMediaSourceFactory {
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
        return DefaultMediaSourceFactory(context).setDataSourceFactory(DefaultDataSource.Factory(context, http))
    }
}
