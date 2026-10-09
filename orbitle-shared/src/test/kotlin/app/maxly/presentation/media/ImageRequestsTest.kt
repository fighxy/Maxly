package app.maxly.presentation.media

import com.max.core.api.MaxMessage
import com.max.core.media.ImageShape
import com.max.core.media.ImageSizes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ImageRequestsTest {
    private val url = "https://cdn.example/photo?expires=10"

    @Test
    fun squarePicksFirstStepNotSmallerThanSizeTimesDensity() {
        // 40 dp × 2.5 = 100 px: sqr_96 меньше, первый подходящий — sqr_128.
        assertEquals(ImageSizes.sizedUrl(url, ImageShape.SQUARE, 100), ImageRequests.square(url, 40f, 2.5f))
        assertEquals("sqr_128", ImageRequests.square(url, 40f, 2.5f)!!.substringAfter("fn="))
    }

    @Test
    fun widthPicksFirstStepNotSmallerThanSizeTimesDensity() {
        // 200 dp × 2 = 400 px: w_320 меньше, первый подходящий — w_480.
        assertEquals(ImageSizes.sizedUrl(url, ImageShape.WIDTH, 400), ImageRequests.width(url, 200f, 2f))
        assertEquals("w_480", ImageRequests.width(url, 200f, 2f)!!.substringAfter("fn="))
    }

    @Test
    fun tinyRequestUsesSmallestStepAndHugeRequestStaysOnTheLadder() {
        assertEquals("sqr_32", ImageRequests.square(url, 1f, 1f)!!.substringAfter("fn="))
        assertEquals("sqr_720", ImageRequests.square(url, 10_000f, 3f)!!.substringAfter("fn="))
        assertEquals("w_180", ImageRequests.width(url, 0f, 2f)!!.substringAfter("fn="))
        assertEquals("w_1440", ImageRequests.width(url, 5_000f, 2f)!!.substringAfter("fn="))
    }

    @Test
    fun localFileAndBlankStayUntouched() {
        assertEquals("file:///tmp/a.jpg", ImageRequests.square("file:///tmp/a.jpg", 48f, 3f))
        assertEquals("content://media/1", ImageRequests.width("content://media/1", 200f, 2f))
        assertNull(ImageRequests.square(null, 40f, 2f))
        assertEquals("", ImageRequests.width("", 40f, 2f))
    }

    @Test
    fun fullScreenKeepsTheOriginal() {
        assertEquals(url, ImageRequests.original(url))
        assertEquals(url, ImageRequests.sized(url, ImageShape.WIDTH, 400f, 2f, fullScreen = true))
    }
}

class PhotoRefreshQueueTest {
    @Test
    fun skipsDuplicatesAndWaitsForTheInterval() {
        val queue = PhotoRefreshQueue(maxPerRequest = 2, minIntervalMs = 1_000)
        val first = PhotoRefreshKey(7, 9, 1)
        val second = PhotoRefreshKey(7, 9, 2)
        val third = PhotoRefreshKey(7, 10, 3)
        queue.enqueue(listOf(first, first, second, PhotoRefreshKey(7, 9, 0)))
        assertEquals(listOf(first, second), queue.take(1_000))
        assertNull(queue.take(1_500))
        queue.enqueue(listOf(third, second))
        assertEquals(listOf(third), queue.take(2_000))
        assertEquals(0, queue.pendingCount)
    }

    @Test
    fun failureReturnsTheBatchAndSuccessForgetsIt() {
        val queue = PhotoRefreshQueue(maxPerRequest = 10, minIntervalMs = 0)
        val key = PhotoRefreshKey(1, 2, 3)
        queue.enqueue(listOf(key))
        val batch = queue.take(0)!!
        queue.requeue(batch)
        assertEquals(listOf(key), queue.take(1))
        queue.complete(listOf(key))
        queue.enqueue(listOf(key))
        assertEquals(listOf(key), queue.take(2))
    }

    @Test
    fun mediaGroupsPhotosOfOneMessage() {
        val media = PhotoRefreshQueue.media(
            listOf(
                PhotoRefreshKey(7, 9, 1),
                PhotoRefreshKey(7, 9, 2),
                PhotoRefreshKey(8, 3, 4),
            ),
        )
        assertEquals(2, media.size)
        assertEquals(listOf(1L, 2L), media.first { it.messageId == 9L }.photoIds)
        assertEquals(7L, media.first { it.messageId == 9L }.chatId)
    }

    @Test
    fun expiredPhotosUseTheFreshUrlWhenItIsAlreadyKnown() {
        val message = MaxMessage(
            id = 9,
            chatId = 7,
            sender = 1,
            text = "",
            time = 1,
            type = "USER",
            cid = null,
            status = null,
            prevMessageId = null,
            unread = null,
            mark = null,
            elements = emptyList(),
            attaches = listOf(
                mapOf("_type" to "PHOTO", "photoId" to 5L, "baseUrl" to "https://cdn.example/old?expires=10"),
                mapOf("_type" to "PHOTO", "photoId" to 6L, "baseUrl" to "https://cdn.example/fresh?expires=100"),
                mapOf("_type" to "FILE", "fileId" to 1L),
            ),
            link = null,
            reactionInfo = null,
            raw = emptyMap<String, String>(),
        )
        val expired = PhotoRefreshKeys.expired(7, listOf(message), emptyMap<String, String>(), nowMs = 10)
        assertEquals(listOf(PhotoRefreshKey(7, 9, 5)), expired)
        val still = PhotoRefreshKeys.expired(7, listOf(message), mapOf("5" to "https://cdn.example/new?expires=50"), nowMs = 10)
        assertEquals(emptyList<PhotoRefreshKey>(), still)
    }
}
