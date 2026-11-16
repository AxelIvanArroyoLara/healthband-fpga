package com.example.healthband.ui

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.healthband.analysis.AnomalyConfig
import com.example.healthband.analysis.AnomalyDetector
import com.example.healthband.analysis.AnomalyReading
import com.example.healthband.analysis.AnomalyStatus
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
import com.example.healthband.history.SessionHistory
import com.example.healthband.history.SessionHistoryWriter
import com.example.healthband.model.Measurement
import com.example.healthband.protocol.Hb1Parser
import com.example.healthband.protocol.ParseResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Coordina la sesión de adquisición y conserva su estado durante cambios de configuración.
 * @param staleTimeoutMs Tiempo sin tramas aceptadas antes de invalidar la lectura actual.
 * @param monotonicNowMs Reloj de intervalos de la adquisición, independiente del reloj Unix.
 */
class HealthViewModel internal constructor(
    application: Application,
    private val staleTimeoutMs: Long,
    private val history: SessionHistory,
    private val monotonicNowMs: () -> Long
) : AndroidViewModel(application) {
    constructor(application: Application) : this(
        application, 4_000L, HistoryRepository(HealthDatabase.get(application)), SystemClock::elapsedRealtime
    )

    private val discovery = BleDiscovery(application)
    private val acquisition = Mutex()
    private val anomalyConfig = AnomalyConfig()
    private val state = MutableStateFlow(HealthUiState())
    val uiState = state.asStateFlow()
    private var currentRun: AcquisitionRun? = null
    private var scanJob: Job? = null
    private val scanState = MutableStateFlow(BleScanState())
    val bleScanState = scanState.asStateFlow()

    /** Informa si el sistema permite iniciar el escaneo. */
    fun bleUnavailableReason(): String? = discovery.unavailableReason()

    /** Busca dispositivos durante diez segundos y mantiene una lista acotada. */
    fun scanBle() {
        if (scanJob?.isActive == true || state.value.isRunning) return
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
    fun connectBle(device: BleDevice, config: BleConfig, declaredRest: Boolean) {
        startSession(isBle = true, declaredRest = declaredRest) { onReady ->
            BleMeasurementSource(getApplication(), config, device, onReady)
        }
    }

    /** Inicia una sesión nueva con contadores y gráfica vacíos. */
    fun startSimulation(declaredRest: Boolean, sustainedDemo: Boolean = false) =
        startSession(isBle = false, declaredRest = declaredRest && !sustainedDemo) {
            SimulatedMeasurementSource(sustainedDemo = sustainedDemo)
        }

    /** Inicia la colección de una fuente y serializa el cierre de la sesión anterior. */
    internal fun startSession(
        isBle: Boolean,
        declaredRest: Boolean,
        source: (() -> Unit) -> MeasurementSource
    ) {
        if (state.value.isRunning) return
        val scan = scanJob
        scan?.cancel()
        val run = AcquisitionRun()
        currentRun = run
        state.value = HealthUiState(
            isRunning = true,
            isBle = isBle,
            status = if (isBle) ReadingStatus.CONNECTING else ReadingStatus.WAITING,
            historyBusy = state.value.historyBusy
        )
        run.pipeline = viewModelScope.launch {
            scan?.join()
            acquisition.withLock { collectSession(run, isBle, declaredRest, source) }
        }
    }

    /** Ejecuta la captura y el historial como hijos de una adquisición, con un cierre ordenado. */
    private suspend fun collectSession(
        run: AcquisitionRun,
        isBle: Boolean,
        declaredRest: Boolean,
        source: (() -> Unit) -> MeasurementSource
    ) = coroutineScope {
        val writer = SessionHistoryWriter(history, !isBle, declaredRest) { error ->
            updateRun(run) { it.copy(storageError = error) }
        }
        var detector = AnomalyDetector(null, anomalyConfig)
        state.update { it.copy(historyBusy = true) }

        val persistence = launch {
            writer.save(
                anomalyConfig,
                onBaseline = { baseline ->
                    detector = AnomalyDetector(baseline, anomalyConfig)
                    updateRun(run) { it.copy(baseline = baseline) }
                },
                onStored = { updateRun(run) { it.copy(persistedCount = it.persistedCount + 1) } }
            )
        }
        val capture = launch(start = CoroutineStart.LAZY) {
            collectReadings(run, isBle, source, writer) { detector }
        }
        run.capture = capture
        try {
            capture.join()
            writer.close(System.currentTimeMillis())
            // La fuente ya está cerrada. Una escritura suspendida no retiene el siguiente inicio indefinidamente.
            val saved = withTimeoutOrNull(5_000) {
                persistence.join()
                true
            }
            if (saved == null) {
                updateRun(run) { it.copy(storageError = "Se agotó el tiempo para guardar el historial pendiente.") }
                persistence.cancelAndJoin()
            }
        } finally {
            writer.close(System.currentTimeMillis())
            state.update { it.copy(historyBusy = false) }
        }
    }

    /** Interpreta y publica las lecturas antes de entregarlas al escritor. */
    private suspend fun collectReadings(
        run: AcquisitionRun,
        isBle: Boolean,
        source: (() -> Unit) -> MeasurementSource,
        writer: SessionHistoryWriter,
        detector: () -> AnomalyDetector
    ) {
        var startedAt = monotonicNowMs()
        var previous: Measurement? = null
        var previousAt = startedAt
        try {
            val repository = MeasurementRepository(source {
                startedAt = monotonicNowMs()
                updateRun(run) { it.copy(status = ReadingStatus.WAITING) }
            })
            coroutineScope {
                val ticker = launch {
                    while (true) {
                        delay(200)
                        updateRun(run) {
                            val ticked = it.tick(monotonicNowMs(), startedAt, staleTimeoutMs)
                            if (ticked.status == ReadingStatus.STALE) detector().noData()
                            ticked
                        }
                    }
                }
                try {
                    repository.measurements().collect { result ->
                        val now = monotonicNowMs()
                        if (result is ParseResult.Success) {
                            val measurement = result.measurement
                            val prior = previous
                            val startsSegment = prior == null || !prior.isValid ||
                                Hb1Parser.sequenceDistance(prior.sequence, measurement.sequence) != 1L ||
                                now - previousAt >= staleTimeoutMs
                            val analysis = detector().receive(
                                measurement.bpm.takeIf { measurement.isValid }, now, measurement.receivedAtMs
                            )
                            previous = measurement
                            previousAt = now
                            updateRun(run) { it.receive(result, now, staleTimeoutMs).copy(anomaly = analysis) }
                            if (measurement.isValid) writer.enqueue(measurement, startsSegment, analysis.episode)
                        } else {
                            updateRun(run) { it.receive(result, now, staleTimeoutMs) }
                        }
                    }
                } finally {
                    ticker.cancel()
                }
            }
            if (currentRun === run) clearReading(if (isBle) ReadingStatus.DISCONNECTED else ReadingStatus.STOPPED)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: BleFailure) {
            if (currentRun === run) clearReading(
                if (failure.disconnected) ReadingStatus.DISCONNECTED else ReadingStatus.ERROR,
                failure.message
            )
        } catch (_: Exception) {
            if (currentRun === run) clearReading(ReadingStatus.ERROR, "Se interrumpió la fuente de mediciones")
        }
    }

    /** Retira la lectura de inmediato y deja al escritor confirmar su cola dentro del plazo de cierre. */
    fun stopSession() {
        if (!state.value.isRunning) return
        val run = currentRun
        val capture = run?.capture
        if (capture != null) capture.cancel() else run?.pipeline?.cancel()
        clearReading(if (state.value.isBle) ReadingStatus.DISCONNECTED else ReadingStatus.STOPPED)
    }

    private fun updateRun(run: AcquisitionRun, transform: (HealthUiState) -> HealthUiState) {
        if (currentRun === run) state.update(transform)
    }

    /** Separa la captura cancelable del cierre del historial y de los inicios todavía en espera. */
    private class AcquisitionRun {
        var pipeline: Job? = null
        var capture: Job? = null
    }

    private fun clearReading(status: ReadingStatus, error: String? = null) {
        state.update {
            it.copy(
                isRunning = false,
                measurement = null,
                ageMs = null,
                status = status,
                anomaly = AnomalyReading(AnomalyStatus.NO_DATA),
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
