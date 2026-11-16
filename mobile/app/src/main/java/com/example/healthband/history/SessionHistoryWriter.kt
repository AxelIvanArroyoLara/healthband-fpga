package com.example.healthband.history

import com.example.healthband.analysis.AnomalyConfig
import com.example.healthband.analysis.Baseline
import com.example.healthband.analysis.EpisodeProgress
import com.example.healthband.model.Measurement
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Persiste un prefijo ordenado de una adquisición desde una cola acotada a su ciclo de vida. */
internal class SessionHistoryWriter(
    private val history: SessionHistory,
    private val simulated: Boolean,
    private val declaredRest: Boolean,
    private val onError: (String) -> Unit
) {
    private val pending = Channel<PendingSample>(32)
    private var sealed = false
    private var endedAtMs: Long? = null

    /** Entrega trabajo al escritor sin suspender a la fuente, incluso si Room está ocupado. */
    fun enqueue(measurement: Measurement, startsSegment: Boolean, episode: EpisodeProgress?) {
        if (sealed) return
        if (pending.trySend(PendingSample(measurement, startsSegment, episode)).isFailure) {
            // Conserva el prefijo encolado. Un hueco por saturación no puede parecer un registro continuo.
            sealed = true
            pending.close()
            onError("Se saturó el historial. Solo se guardarán las lecturas ya en cola.")
        }
    }

    /** Sella una detención normal con el instante en que terminó la captura. */
    fun close(nowMs: Long) {
        if (sealed) return
        sealed = true
        endedAtMs = nowMs
        pending.close()
    }

    /** Lee la referencia y confirma las muestras en orden desde una única corrutina. */
    suspend fun save(config: AnomalyConfig, onBaseline: (Baseline?) -> Unit, onStored: () -> Unit) {
        var id: Long? = null
        var drained = false
        try {
            onBaseline(loadBaseline(config))
            for ((measurement, startsSegment, episode) in pending) {
                val activeId = id
                if (activeId == null) {
                    id = history.recordFirst(simulated, declaredRest, measurement, episode)
                } else {
                    history.record(activeId, measurement, startsSegment, episode)
                }
                onStored()
            }
            drained = true
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            onError("No se pudo guardar el historial. Se conservarán las lecturas confirmadas.")
        } finally {
            sealed = true
            pending.cancel()
            // Cada muestra confirma un punto de cierre. Solo un drenaje completo actualiza su fin.
            val finalEnd = endedAtMs
            if (drained && id != null && finalEnd != null) finish(id, finalEnd)
        }
    }

    private suspend fun loadBaseline(config: AnomalyConfig): Baseline? = try {
        history.baseline(simulated, config)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        onError("No se pudo consultar la referencia de reposo.")
        null
    }

    private suspend fun finish(id: Long, end: Long) = withContext(NonCancellable) {
        try {
            val finished = withTimeoutOrNull(2_000) {
                history.finish(id, end)
                true
            }
            if (finished == null) onError("El historial conserva el último cierre confirmado.")
        } catch (_: Exception) {
            onError("El historial conserva el último cierre confirmado.")
        }
    }

    private data class PendingSample(
        val measurement: Measurement,
        val startsSegment: Boolean,
        val episode: EpisodeProgress?
    )
}
