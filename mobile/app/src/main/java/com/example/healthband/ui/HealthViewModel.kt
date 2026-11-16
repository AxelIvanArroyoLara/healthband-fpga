package com.example.healthband.ui

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.healthband.ble.BleConfig
import com.example.healthband.ble.BleDevice
import com.example.healthband.ble.BleDiscovery
import com.example.healthband.ble.BleFailure
import com.example.healthband.ble.BleMeasurementSource
import com.example.healthband.data.MeasurementRepository
import com.example.healthband.data.MeasurementSource
import com.example.healthband.data.SimulatedMeasurementSource
import com.example.healthband.history.HealthDatabase
import com.example.healthband.history.HistoryRepository
import com.example.healthband.model.Measurement
import com.example.healthband.protocol.Hb1Parser
import com.example.healthband.protocol.ParseResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Coordina la sesión de adquisición y conserva su estado durante cambios de configuración.
 * @param staleTimeoutMs Tiempo sin tramas aceptadas antes de invalidar la lectura actual.
 */
class HealthViewModel(
    application: Application,
    private val staleTimeoutMs: Long
) : AndroidViewModel(application) {
    constructor(application: Application) : this(application, 4_000L)

    private val discovery = BleDiscovery(application)
    private val history = HistoryRepository(HealthDatabase.get(application))
    private val acquisition = Mutex()
    private val state = MutableStateFlow(HealthUiState())
    val uiState = state.asStateFlow()
    private var session: Job? = null
    private var scanJob: Job? = null
    private val scanState = MutableStateFlow(BleScanState())
    val bleScanState = scanState.asStateFlow()

    /** Informa si el sistema permite iniciar el escaneo. */
    fun bleUnavailableReason(): String? = discovery.unavailableReason()

    /** Busca dispositivos durante diez segundos y mantiene una lista acotada. */
    fun scanBle() {
        if (scanJob?.isActive == true || session?.isActive == true) return
        scanState.value = BleScanState(scanning = true)
        scanJob = viewModelScope.launch {
            try {
                withTimeoutOrNull(10_000) {
                    discovery.scan().collect { device ->
                        scanState.update { current ->
                            val devices = current.devices
                            when {
                                devices.any { it.address == device.address } ->
                                    current.copy(devices = devices.map { if (it.address == device.address) device else it })
                                devices.size < 40 -> current.copy(devices = devices + device)
                                else -> current
                            }
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: BleFailure) {
                scanState.update { it.copy(message = failure.message) }
            } catch (_: Exception) {
                scanState.update { it.copy(message = "No se pudo iniciar el escaneo BLE") }
            } finally {
                scanState.update { it.copy(scanning = false) }
            }
        }
    }

    /** Abre un enlace con el dispositivo elegido; una nueva selección permite reintentar. */
    fun connectBle(device: BleDevice, config: BleConfig) {
        startSession(isBle = true) { onReady ->
            BleMeasurementSource(getApplication(), config, device, onReady)
        }
    }

    /** Inicia una sesión nueva con contadores y gráfica vacíos. */
    fun startSimulation() = startSession(isBle = false) { SimulatedMeasurementSource() }

    private fun startSession(isBle: Boolean, source: (() -> Unit) -> MeasurementSource) {
        val previous = session
        if (previous?.isActive == true) return
        val scan = scanJob
        scan?.cancel()
        state.value = HealthUiState(
            isRunning = true,
            isBle = isBle,
            status = if (isBle) ReadingStatus.CONNECTING else ReadingStatus.WAITING
        )
        session = viewModelScope.launch {
            scan?.join()
            acquisition.withLock { collectSession(isBle, source) }
        }
    }

    /** Guarda el historial dentro del ciclo de vida de la adquisición activa. */
    private suspend fun collectSession(isBle: Boolean, source: (() -> Unit) -> MeasurementSource) {
        var startedAt = SystemClock.elapsedRealtime()
        var sessionId: Long? = null
        var previous: Measurement? = null
        var previousAt = startedAt
        val repository = MeasurementRepository(source {
            startedAt = SystemClock.elapsedRealtime()
            state.update { it.copy(status = ReadingStatus.WAITING) }
        })
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
                        val now = SystemClock.elapsedRealtime()
                        if (result is ParseResult.Success) {
                            val measurement = result.measurement
                            val id = sessionId ?: history.begin(!isBle, measurement.receivedAtMs).also {
                                sessionId = it
                            }
                            val prior = previous
                            val startsSegment = prior == null || !prior.isValid ||
                                Hb1Parser.sequenceDistance(prior.sequence, measurement.sequence) != 1L ||
                                now - previousAt >= staleTimeoutMs
                            history.record(id, measurement, startsSegment)
                            previous = measurement
                            previousAt = now
                        }
                        state.update { it.receive(result, now, staleTimeoutMs) }
                    }
                } finally {
                    ticker.cancel()
                }
            }
            clearReading(if (isBle) ReadingStatus.DISCONNECTED else ReadingStatus.STOPPED)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: BleFailure) {
            clearReading(
                if (failure.disconnected) ReadingStatus.DISCONNECTED else ReadingStatus.ERROR,
                failure.message
            )
        } catch (_: Exception) {
            clearReading(ReadingStatus.ERROR, "Se interrumpió la adquisición o la escritura del historial")
        } finally {
            // El cierre es breve y conserva la fecha incluso si el usuario detiene la adquisición.
            sessionId?.let { id ->
                withContext(NonCancellable) {
                    try {
                        history.finish(id, System.currentTimeMillis())
                    } catch (_: Exception) {
                        state.update { it.copy(lastError = "No se pudo confirmar el cierre del historial") }
                    }
                }
            }
        }
    }

    /** Cancela la adquisición y retira los valores actuales conservando la gráfica. */
    fun stopSession() {
        session?.cancel()
        clearReading(if (state.value.isBle) ReadingStatus.DISCONNECTED else ReadingStatus.STOPPED)
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


/** Estado de búsqueda de periféricos, separado de la recepción de mediciones. */
data class BleScanState(
    val scanning: Boolean = false,
    val devices: List<BleDevice> = emptyList(),
    val message: String? = null
)
