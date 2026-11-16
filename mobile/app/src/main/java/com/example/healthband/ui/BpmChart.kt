package com.example.healthband.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Dibuja la serie de BPM; una posición nula interrumpe los segmentos. */
@Composable
fun BpmChart(points: List<Int?>) {
    val values = points.filterNotNull()
    if (values.isEmpty()) {
        Text("Sin lecturas válidas para graficar")
        return
    }
    val lower = values.min() - 5
    val upper = values.max() + 5
    val color = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.outlineVariant
    Text("$lower–$upper BPM", style = MaterialTheme.typography.labelSmall)
    Canvas(
        Modifier.fillMaxWidth().height(132.dp).semantics {
            contentDescription = "Gráfica de frecuencia cardíaca, de $lower a $upper BPM"
        }
    ) {
        val step = size.width / points.lastIndex.coerceAtLeast(1)
        for (fraction in listOf(0f, 0.5f, 1f)) {
            val y = size.height * fraction
            drawLine(grid, Offset(0f, y), Offset(size.width, y))
        }
        var previous: Offset? = null
        points.forEachIndexed { index, bpm ->
            val point = bpm?.let {
                Offset(index * step, size.height * (upper - it) / (upper - lower))
            }
            if (point != null) {
                previous?.let { drawLine(color, it, point, strokeWidth = 2.dp.toPx()) }
                drawCircle(color, radius = 2.dp.toPx(), center = point)
            }
            previous = point
        }
    }
}
