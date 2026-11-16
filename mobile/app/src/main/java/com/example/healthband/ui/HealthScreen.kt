
package com.example.healthband.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

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
                        .statusBarsPadding()
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
                text = "Modo simulación",
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
                    Text(state.ageMs?.let { "Última trama aceptada hace ${it / 1000} s" }
                        ?: "Sin tramas recientes")

                    // La calidad depende de la validez del mensaje.
                    Text(
                        text = "Calidad: " +
                                when {
                                    state.status == ReadingStatus.STALE -> "Datos obsoletos"
                                    measurement == null -> "Sin datos"
                                    measurement.isValid -> "Válida"
                                    else -> "Inválida"
                                }
                    )

                    Text(
                        text = "Secuencia: " +
                                (measurement?.sequence ?: "--")
                    )

                    Text(
                        text = "Mensajes aceptados: " +
                                state.receivedCount
                    )

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
            state.lastError?.let { error ->

                Text(
                    text = "Último error: $error",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center
                )
            }

            // --- Controles de simulación ---

            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {

                    // El botón alterna entre iniciar y detener.
                    if (state.isRunning) {
                        viewModel.stopSimulation()
                    } else {
                        viewModel.startSimulation()
                    }
                }
            ) {

                Text(
                    text = if (state.isRunning) {
                        "Detener simulación"
                    } else {
                        "Iniciar simulación"
                    }
                )
            }

            // --- Aviso de uso experimental ---

            Text(
                text = "Datos simulados para desarrollo. " +
                        "No representan mediciones médicas.",
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
