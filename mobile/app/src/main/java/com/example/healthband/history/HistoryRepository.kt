package com.example.healthband.history

import androidx.room.withTransaction
import com.example.healthband.analysis.AnomalyConfig
import com.example.healthband.analysis.Baseline
import com.example.healthband.analysis.EpisodeContext
import com.example.healthband.analysis.EpisodeProgress
import com.example.healthband.model.Measurement
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Resumen de una sesión calculado sobre todas las lecturas válidas almacenadas. */
data class SessionSummary(
    val id: Long,
    val startedAtMs: Long,
    val endedAtMs: Long,
    val simulated: Boolean,
    val declaredRest: Boolean,
    val validCount: Long,
    val averageBpm: Double?,
    val minBpm: Int?,
    val maxBpm: Int?
)

/** Lectura histórica preparada para presentar y reconstruir segmentos. */
data class HistorySample(val bpm: Int, val startsSegment: Boolean)

/** Episodio y contexto preparados para el historial. */
data class HistoryEpisode(val progress: EpisodeProgress, val context: EpisodeContext?)

/** Persiste el historial sin acoplar la interfaz a las entidades Room. */
class HistoryRepository(private val database: HealthDatabase) : SessionHistory {
    private val dao = database.historyDao()

    fun sessions(): Flow<List<SessionSummary>> = dao.sessions()

    fun samples(id: Long, offset: Long): Flow<List<HistorySample>> =
        dao.samples(id, PAGE_SIZE, offset).map { rows ->
            rows.asReversed().map { HistorySample(it.bpm, it.startsSegment) }
        }

    /** Abre un periodo local con una marca de tiempo Unix. */
    suspend fun begin(simulated: Boolean, nowMs: Long, declaredRest: Boolean = false): Long =
        dao.insertSession(SessionEntity(
            startedAtMs = nowMs, endedAtMs = nowMs, simulated = simulated, declaredRest = declaredRest
        ))

    override suspend fun recordFirst(
        simulated: Boolean,
        declaredRest: Boolean,
        measurement: Measurement,
        episode: EpisodeProgress?
    ): Long {
        require(measurement.isValid && measurement.bpm != null && measurement.ibiMs != null)
        return database.withTransaction {
            val id = begin(simulated, measurement.receivedAtMs, declaredRest)
            writeSample(id, measurement, startsSegment = true, episode)
            id
        }
    }

    /** Actualiza la lectura, el episodio y el cierre recuperable en una sola transacción. */
    override suspend fun record(
        id: Long,
        measurement: Measurement,
        startsSegment: Boolean,
        episode: EpisodeProgress?
    ) {
        if (!measurement.isValid || measurement.bpm == null || measurement.ibiMs == null) return
        database.withTransaction { writeSample(id, measurement, startsSegment, episode) }
    }

    private suspend fun writeSample(
        id: Long,
        measurement: Measurement,
        startsSegment: Boolean,
        episode: EpisodeProgress?
    ) {
        dao.insertSample(
            SampleEntity(
                sessionId = id,
                bpm = requireNotNull(measurement.bpm),
                ibiMs = requireNotNull(measurement.ibiMs),
                quality = 1,
                receivedAtMs = measurement.receivedAtMs,
                startsSegment = startsSegment
            )
        )
        if (episode != null) {
            dao.upsertEpisode(EpisodeUpdate(
                id, episode.startedElapsedMs, episode.startedAtMs,
                episode.durationMs, episode.peakBpm, episode.baselineBpm
            ))
        }
        dao.updateEnd(id, measurement.receivedAtMs)
    }

    /** Calcula la referencia con sesiones de reposo de la misma fuente y sin episodios confirmados. */
    override suspend fun baseline(simulated: Boolean, config: AnomalyConfig): Baseline? = database.withTransaction {
        val ids = dao.baselineSessionIds(simulated, config.minimumSessionSamples)
        val sampleLimit = maxOf(300, config.minimumSessionSamples)
        Baseline.calculate(ids.map { dao.baselineSamples(it, sampleLimit) }, config)
    }

    fun episodes(id: Long): Flow<List<HistoryEpisode>> = dao.episodes(id).map { rows ->
        rows.map {
            HistoryEpisode(
                EpisodeProgress(it.startedElapsedMs, it.startedAtMs, it.durationMs, it.peakBpm, it.baselineBpm),
                EpisodeContext.entries.firstOrNull { context -> context.name == it.context }
            )
        }
    }

    suspend fun setEpisodeContext(id: Long, episode: Long, context: EpisodeContext) =
        dao.setEpisodeContext(id, episode, context.name)

    override suspend fun finish(id: Long, nowMs: Long) = dao.updateEnd(id, nowMs)

    suspend fun delete(id: Long) = dao.delete(id)

    suspend fun deleteAll() = dao.deleteAll()

    companion object {
        const val PAGE_SIZE = 240
    }
}
