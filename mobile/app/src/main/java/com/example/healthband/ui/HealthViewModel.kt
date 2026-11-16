package com.example.healthband.ui

import android.os.SystemClock
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.healthband.data.MeasurementRepository
import com.example.healthband.data.SimulatedMeasurementSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Coordina la sesión de adquisición y conserva su estado durante cambios de configuración.
 * @param staleTimeoutMs Tiempo sin tramas aceptadas antes de invalidar la lectura actual.
 */
class HealthViewModel(
    private val staleTimeoutMs: Long = 4_000L
) : ViewModel() {
    private val repository = MeasurementRepository(SimulatedMeasurementSource())
    private val state = MutableStateFlow(HealthUiState())
    val uiState = state.asStateFlow()
    private var session: Job? = null

    /** Inicia una sesión nueva con contadores y gráfica vacíos. */
    fun startSimulation() {
        if (session?.isActive == true) return
        state.value = HealthUiState(isRunning = true, status = ReadingStatus.WAITING)
        val startedAt = SystemClock.elapsedRealtime()
        session = viewModelScope.launch {
            try {
                coroutineScope {
                    val ticker = launch {
                        while (true) {
                            delay(200)
                            state.update { it.tick(SystemClock.elapsedRealtime(), startedAt, staleTimeoutMs) }
                        }
                    }
                    try {
                        repository.measurements().collect { result ->
                            state.update { it.receive(result, SystemClock.elapsedRealtime(), staleTimeoutMs) }
                        }
                    } finally {
                        ticker.cancel()
                    }
                }
                clearReading(ReadingStatus.STOPPED)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                clearReading(ReadingStatus.ERROR, "La fuente de mediciones se interrumpió")
            }
        }
    }

    /** Cancela la adquisición y retira los valores actuales conservando la gráfica. */
    fun stopSimulation() {
        session?.cancel()
        session = null
        clearReading(ReadingStatus.STOPPED)
    }

    private fun clearReading(status: ReadingStatus, error: String? = null) {
        state.update {
            it.copy(
                isRunning = false,
                measurement = null,
                ageMs = null,
                status = status,
                errorCount = it.errorCount + if (error == null) 0 else 1,
                lastError = error ?: it.lastError
            )
        }
    }
}
