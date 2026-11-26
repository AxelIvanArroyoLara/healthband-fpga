
package com.example.healthband.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.healthband.analysis.AnomalyStatus

/**
 * Pantalla principal de HealthBand.
 *
 * Presenta las mediciones y el estado de la simulación.
 * Utiliza el ViewModel como única fuente de estado.
 *
 * @param viewModel ViewModel asociado a la pantalla.
 */
@Composable
fun HealthScreen(
    viewModel: HealthViewModel = viewModel()
) {

    // Observa el estado respetando el ciclo de vida de Android.
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var declaredRest by rememberSaveable { mutableStateOf(false) }

    // Obtiene la última medición para facilitar su presentación.
    val measurement = state.measurement

    Scaffold(
        topBar = {

            // Encabezado principal de la aplicación.
            Surface(
                tonalElevation = 3.dp
            ) {
                Text(
                    text = "HealthBand",
                    style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp)
                )
            }
        }
    ) { padding ->

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {

            // --- Identificación de la pantalla ---

            Text(
                text = "Monitor fisiológico",
                style = MaterialTheme.typography.titleLarge
            )

            Text(
                text = when {
                    !state.isBle -> "Fuente simulador"
                    state.simulated -> "Fuente Bluetooth LE · prueba"
                    else -> "Fuente Bluetooth LE"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary
            )

            // --- Tarjeta de mediciones ---

            ElevatedCard(
                modifier = Modifier.fillMaxWidth()
            ) {

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {

                    Text(
                        text = "Frecuencia cardíaca",
                        style = MaterialTheme.typography.titleMedium
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    // Si no existe una lectura válida, se muestra "--".
                    Text(
                        text = measurement
                            ?.bpm
                            ?.toString()
                            ?: "--",
                        style = MaterialTheme.typography.displayLarge,
                        fontWeight = FontWeight.Bold
                    )

                    Text(
                        text = "BPM",
                        style = MaterialTheme.typography.titleMedium
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 20.dp)
                    )

                    Text(
                        text = "Intervalo entre pulsos",
                        style = MaterialTheme.typography.bodyMedium
                    )

                    Text(
                        text = measurement
                            ?.ibiMs
                            ?.let { "$it ms" }
                            ?: "-- ms",
                        style = MaterialTheme.typography.headlineMedium
                    )
                }
            }

            // --- Estado de la simulación y estadísticas ---

            Card(
                modifier = Modifier.fillMaxWidth()
            ) {

                Column(
                    modifier = Modifier.padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {

                    Text(
                        text = "Estado del sistema",
                        fontWeight = FontWeight.Bold
                    )

                    Text(state.status.label)
                    if (state.isBle) {
                        state.deviceName?.let { Text("Periférico: $it") }
                        state.bleConfig?.let {
                            Text("Servicio: ${it.service}", style = MaterialTheme.typography.bodySmall)
                            Text("Notify: ${it.characteristic}", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    Text(state.ageMs?.let { "Última trama aceptada hace ${it / 1000} s" }
                        ?: "Sin tramas recientes")

                    // La calidad depende de la validez del mensaje.
                    Text(
                        text = "Calidad: " +
                                when {
                                    state.status == ReadingStatus.STALE -> "Datos obsoletos"
                                    state.status == ReadingStatus.INVALID -> "Inválida"
                                    measurement != null -> "Válida"
                                    else -> "Sin datos"
                                }
                    )

                    Text(
                        text = "Secuencia: " +
                                (state.lastSequence ?: "--")
                    )

                    Text(
                        text = "Mensajes aceptados: " +
                                state.receivedCount
                    )

                    Text("Lecturas guardadas: ${state.persistedCount}")

                    Text(
                        text = "Errores detectados: " +
                                state.errorCount
                    )
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("BPM recientes", style = MaterialTheme.typography.titleMedium)
                    BpmChart(state.recentBpm)
                }
            }

            // --- Visualización de errores ---

            // Solo presenta el mensaje cuando existe un error.
            state.storageError?.let { error ->
                Text("Historial · $error", color = MaterialTheme.colorScheme.error)
            }
            if (!state.isRunning && state.historyBusy) {
                Text("Finalizando el historial…")
            }

            state.lastError?.let { error ->

                Text(
                    text = "Último error: $error",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center
                )
            }

            if (state.isRunning) {
                AnalysisCard(state)
                Button(onClick = viewModel::stopSession, modifier = Modifier.fillMaxWidth()) {
                    Text(if (state.isBle) "Desconectar" else "Detener simulación")
                }
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = declaredRest, onCheckedChange = { declaredRest = it })
                    Text("Registrar como sesión de reposo")
                }
                Button(
                    onClick = { viewModel.startSimulation(declaredRest) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Iniciar simulación")
                }
                TextButton(onClick = { viewModel.startSimulation(declaredRest = false, sustainedDemo = true) }) {
                    Text("Simular elevación sostenida")
                }
                TextButton(onClick = { viewModel.startSimulation(declaredRest = false, communicationErrors = true) }) {
                    Text("Simular errores de comunicación")
                }
            }
            BleControls(viewModel, visible = !state.isRunning, declaredRest = declaredRest)
        }
    }
}

/** Presenta la calibración y el resultado experimental de la lectura actual. */
@Composable
private fun AnalysisCard(state: HealthUiState) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Análisis experimental", style = MaterialTheme.typography.titleMedium)
            val baseline = state.baseline
            if (baseline == null) {
                Text("Calibración pendiente. Se requieren al menos tres sesiones de reposo de esta fuente.")
            } else {
                Text("Referencia de reposo · ${formatBpm(baseline.bpm)} BPM · ${baseline.sessions} sesiones")
            }
            if (state.anomaly.status != AnomalyStatus.INSUFFICIENT || baseline != null) {
                Text(state.anomaly.status.label)
            }
            state.anomaly.episode?.let { episode ->
                Text("${episode.durationMs / 1000} s · Pico +" + formatBpm(episode.peakBpm - episode.baselineBpm) + " BPM")
            }
        }
    }
}
