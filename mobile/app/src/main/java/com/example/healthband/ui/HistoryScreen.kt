package com.example.healthband.ui

import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.healthband.history.HistoryRepository
import com.example.healthband.history.SessionSummary
import java.text.NumberFormat

/** Presenta sesiones, estadísticas y páginas de la gráfica histórica. */
@Composable
fun HistoryScreen(activeSession: Boolean, viewModel: HistoryViewModel = viewModel()) {
    val sessions by viewModel.sessions.collectAsStateWithLifecycle()
    val selection by viewModel.selectedPage.collectAsStateWithLifecycle()
    val details by viewModel.details.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    var confirm by rememberSaveable { mutableStateOf<Long?>(null) }
    val selected = sessions.firstOrNull { it.id == selection?.sessionId }
    BackHandler(enabled = selection != null) { viewModel.closeDetails() }

    LazyColumn(
        modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        if (selected == null) {
            if (sessions.isEmpty()) item { Text("Todavía no hay sesiones guardadas") }
            items(sessions, key = { it.id }) { session ->
                ElevatedCard(onClick = { viewModel.select(session.id) }, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        SessionInfo(session)
                    }
                }
            }
            if (sessions.isNotEmpty()) item {
                TextButton(enabled = !activeSession, onClick = { confirm = 0L }) {
                    Text("Eliminar todo el historial")
                }
            }
        } else {
            item { TextButton(onClick = viewModel::closeDetails) { Text("Todas las sesiones") } }
            item { SessionInfo(selected) }
            item {
                val detail = details?.takeIf { it.page == selection }
                if (detail == null) {
                    Text("Cargando lecturas…")
                } else {
                    val points = buildList {
                        for (sample in detail.samples) {
                            if (isNotEmpty() && sample.startsSegment) add(null)
                            add(sample.bpm)
                        }
                    }
                    BpmChart(points)
                    if (detail.samples.isNotEmpty()) {
                        val offset = detail.page.offset
                        val pageSize = HistoryRepository.PAGE_SIZE
                        Text("Página ${offset / pageSize + 1} desde el cierre")
                        Row {
                            TextButton(enabled = offset > 0, onClick = { viewModel.changePage(offset - pageSize) }) {
                                Text("Más recientes")
                            }
                            TextButton(
                                enabled = offset + pageSize < selected.validCount,
                                onClick = { viewModel.changePage(offset + pageSize) }
                            ) { Text("Más antiguas") }
                        }
                    }
                }
            }
            item {
                TextButton(enabled = !activeSession, onClick = { confirm = selected.id }) { Text("Eliminar sesión") }
            }
        }
    }

    confirm?.let { id ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(if (id == 0L) "¿Eliminar todo el historial?" else "¿Eliminar esta sesión?") },
            confirmButton = {
                TextButton(enabled = !activeSession, onClick = {
                    confirm = null
                    viewModel.delete(id.takeIf { it != 0L })
                }) { Text("Eliminar") }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text("Cancelar") } }
        )
    }
}

/** Usa el formato de fecha y número de la configuración regional del dispositivo. */
@Composable
private fun SessionInfo(session: SessionSummary) {
    val context = LocalContext.current
    val flags = DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_SHOW_TIME or DateUtils.FORMAT_SHOW_YEAR
    val interval = DateUtils.formatDateRange(context, session.startedAtMs, session.endedAtMs, flags)
    Text(if (session.simulated) "Simulador" else "Bluetooth LE", style = MaterialTheme.typography.titleMedium)
    Text(interval)
    Text("${session.validCount} lecturas válidas")
    session.averageBpm?.let {
        val format = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }
        Text("Promedio ${format.format(it)} · Mín. ${session.minBpm} · Máx. ${session.maxBpm} BPM")
    }
}
