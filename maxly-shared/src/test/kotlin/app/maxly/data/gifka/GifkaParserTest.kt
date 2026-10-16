package app.maxly.data.gifka

import app.maxly.domain.GifkaType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GifkaParserTest {
    // Сокращённая форма ответа GET /v1/search (поля как в документации и живом ответе).
    private val search = """
        {"query":"кот","variants":["кот"],"total":220,"facets":{"gif":220,"sticker":0},"items":[
          {"id":"a1","type":"gif","status":"ready","title":"Кот в очках","width":410,"height":512,
           "renditions":[
             {"kind":"mp4","width":410,"height":512,"url":"https://media.example/a1/410.mp4"},
             {"kind":"mp4","width":240,"height":300,"url":"https://media.example/a1/240.mp4"},
             {"kind":"webp","width":200,"height":250,"url":"https://media.example/a1/200.webp"},
             {"kind":"poster","width":410,"height":512,"url":"https://media.example/a1/poster.webp"},
             {"kind":"poster_jpeg","width":320,"height":400,"url":"https://media.example/a1/poster.jpg"}],
           "download":{"gif":"https://api.example/v1/media/a1/download/gif","gifReady":true,"tgs":null}},
          {"id":"a2","type":"gif","status":"processing","renditions":[{"kind":"mp4","url":"https://x/2.mp4"}]},
          {"id":"a3","type":"gif","status":"ready","renditions":[]},
          {"id":"a4","type":"sticker","status":"ready","altText":"Привет","renditions":[{"kind":"webp","url":"https://x/4.webp"}],"download":null},
          {"type":"gif","renditions":[{"kind":"mp4","url":"https://x/5.mp4"}]}
        ]}
    """.trimIndent()

    @Test
    fun parsesReadyItemsWithSmallestPreviews() {
        val page = GifkaParser.page(search)
        assertEquals(220, page.total)
        assertEquals(listOf("a1", "a4"), page.items.map { it.id })
        val cat = page.items[0]
        assertEquals(GifkaType.GIF, cat.type)
        assertEquals("Кот в очках", cat.title)
        assertEquals(410, cat.width)
        assertEquals("https://media.example/a1/240.mp4", cat.mp4Url)
        assertEquals("https://media.example/a1/200.webp", cat.webpUrl)
        assertEquals("https://media.example/a1/poster.jpg", cat.posterUrl)
        assertEquals("https://api.example/v1/media/a1/download/gif", cat.gifDownloadUrl)
    }

    @Test
    fun stickerFallsBackToAltTextAndHasNoDownload() {
        val sticker = GifkaParser.page(search).items[1]
        assertEquals(GifkaType.STICKER, sticker.type)
        assertEquals("Привет", sticker.title)
        assertNull(sticker.mp4Url)
        assertNull(sticker.gifDownloadUrl)
    }

    @Test
    fun trendingWithoutTotal() {
        val page = GifkaParser.page("""{"items":[{"id":"t","type":"gif","renditions":[{"kind":"webp","url":"https://x/t.webp"}]}]}""")
        assertNull(page.total)
        assertEquals("t", page.items.single().id)
    }

    @Test
    fun emptyAndBrokenBodies() {
        assertTrue(GifkaParser.page("{}").items.isEmpty())
        assertTrue(runCatching { GifkaParser.page("<html>") }.exceptionOrNull() is GifkaError.Server)
    }
}
