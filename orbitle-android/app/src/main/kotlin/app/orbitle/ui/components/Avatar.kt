package app.orbitle.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.orbitle.presentation.chatlist.ChatAvatar
import app.orbitle.ui.theme.AvatarPalette
import coil3.compose.SubcomposeAsyncImage

/** Круглый аватар: фото или инициалы на градиенте, точка «в сети». */
@Composable
fun Avatar(avatar: ChatAvatar, size: Dp, modifier: Modifier = Modifier, online: Boolean = false) {
    Box(modifier.size(size)) {
        val (top, bottom) = AvatarPalette.pair(avatar.colorIndex)
        val gradient = Modifier.clip(CircleShape).background(Brush.verticalGradient(listOf(top, bottom)))
        when (val kind = avatar.kind) {
            ChatAvatar.Kind.SavedMessages -> Box(
                Modifier.size(size).clip(CircleShape).background(Brush.verticalGradient(listOf(Color(0xFF7B88FF), Color(0xFF4B59E6)))),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Bookmark, contentDescription = null, tint = Color.White, modifier = Modifier.size(size * 0.5f))
            }
            is ChatAvatar.Kind.Photo -> SubcomposeAsyncImage(
                model = kind.url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size).clip(CircleShape),
                loading = { Initials(kind.initials, size, gradient) },
                error = { Initials(kind.initials, size, gradient) },
            )
            is ChatAvatar.Kind.Initials -> Initials(kind.text, size, gradient)
        }
        if (online) {
            val dot = size * 0.28f
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .size(dot)
                    .border(2.dp, MaterialTheme.colorScheme.surface, CircleShape)
                    .clip(CircleShape)
                    .background(Color(0xFF34C759)),
            )
        }
    }
}

@Composable
private fun Initials(text: String, size: Dp, background: Modifier) {
    Box(background.size(size), contentAlignment = Alignment.Center) {
        Text(
            text,
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            fontSize = (size.value * 0.38f).sp,
            maxLines = 1,
        )
    }
}
