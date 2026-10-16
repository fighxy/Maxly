package app.maxly.presentation.chat

import org.junit.Test
import org.junit.Assert.assertEquals

class BubbleMetaLayoutTest {
    @Test fun shortReplyUnderWideQuoteFillsQuoteWidth() {
        // «Спасибо» шириной 90, цитата 240: блок текста тянется до 240, время у края пузыря.
        val fill = BubbleMetaLayout.fillWidth(listOf(240), maxWidth = 400)
        assertEquals(240, fill)
        assertEquals(240 - 10 - 50, BubbleMetaLayout.metaX(maxOf(fill, 90), metaWidth = 50, endPadding = 10))
    }

    @Test fun reactionRowWiderThanTextMovesTimeToEdge() {
        val fill = BubbleMetaLayout.fillWidth(listOf(130), maxWidth = 400)
        assertEquals(130 - 10 - 40, BubbleMetaLayout.metaX(maxOf(fill, 70), 40, 10))
    }

    @Test fun textDefinesWidthKeepsTimeAtTextEnd() {
        val fill = BubbleMetaLayout.fillWidth(listOf(100), maxWidth = 400)
        val textWidth = 300
        assertEquals(300 - 10 - 50, BubbleMetaLayout.metaX(maxOf(fill, textWidth), 50, 10))
    }

    @Test fun noOtherBlocks() {
        assertEquals(0, BubbleMetaLayout.fillWidth(emptyList(), 400))
    }

    @Test fun neverWiderThanBubbleMax() {
        assertEquals(400, BubbleMetaLayout.fillWidth(listOf(900), 400))
        assertEquals(400, BubbleMetaLayout.bubbleWidth(listOf(100, 900), 400))
    }

    @Test fun bubbleWidthUnchangedByFill() {
        // Ширина пузыря = максимум блоков — та же, что у обычной колонки.
        assertEquals(240, BubbleMetaLayout.bubbleWidth(listOf(90, 240, 120), 400))
    }

    @Test fun metaNeverStartsBeforeBlock() {
        assertEquals(0, BubbleMetaLayout.metaX(30, 50, 10))
    }
}
