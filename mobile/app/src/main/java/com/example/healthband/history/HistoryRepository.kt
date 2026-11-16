package com.example.healthband.history

import androidx.room.withTransaction
import com.example.healthband.model.Measurement
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Resumen de una sesión calculado sobre todas las lecturas válidas almacenadas. */
data class SessionSummary(
    val id: Long,
    val startedAtMs: Long,
    val endedAtMs: Long,
    val simulated: Boolean,
    val validCount: Long,
    val averageBpm: Double?,
    val minBpm: Int?,
    val maxBpm: Int?
)

/** Lectura histórica preparada para presentar y reconstruir segmentos. */
data class HistorySample(val bpm: Int, val startsSegment: Boolean)

/** Persiste el historial sin acoplar la interfaz a las entidades Room. */
class HistoryRepository(private val database: HealthDatabase) {
    private val dao = database.historyDao()

    fun sessions(): Flow<List<SessionSummary>> = dao.sessions()

    fun samples(id: Long, offset: Long): Flow<List<HistorySample>> =
        dao.samples(id, PAGE_SIZE, offset).map { rows ->
            rows.asReversed().map { HistorySample(it.bpm, it.startsSegment) }
        }

    /** Abre un periodo local con una marca de tiempo Unix. */
    suspend fun begin(simulated: Boolean, nowMs: Long): Long =
        dao.insertSession(SessionEntity(startedAtMs = nowMs, endedAtMs = nowMs, simulated = simulated))

    /** Actualiza la lectura y el cierre recuperable en una sola transacción. */
    suspend fun record(id: Long, measurement: Measurement, startsSegment: Boolean) {
        val bpm = measurement.bpm ?: return
        val ibi = measurement.ibiMs ?: return
        if (!measurement.isValid) return
        database.withTransaction {
            dao.insertSample(
                SampleEntity(
                    sessionId = id,
                    bpm = bpm,
                    ibiMs = ibi,
                    quality = 1,
                    receivedAtMs = measurement.receivedAtMs,
                    startsSegment = startsSegment
                )
            )
            dao.updateEnd(id, measurement.receivedAtMs)
        }
    }

    suspend fun finish(id: Long, nowMs: Long) = dao.updateEnd(id, nowMs)

    suspend fun delete(id: Long) = dao.delete(id)

    suspend fun deleteAll() = dao.deleteAll()

    companion object {
        const val PAGE_SIZE = 240
    }
}
