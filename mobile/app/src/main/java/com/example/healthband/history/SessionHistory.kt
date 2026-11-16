package com.example.healthband.history

import com.example.healthband.analysis.AnomalyConfig
import com.example.healthband.analysis.Baseline
import com.example.healthband.analysis.EpisodeProgress
import com.example.healthband.model.Measurement

/** Operaciones de historial que necesita una adquisición para guardar una sesión en orden. */
interface SessionHistory {
    suspend fun baseline(simulated: Boolean, config: AnomalyConfig): Baseline?

    /** Abre la sesión y confirma su primera muestra en la misma transacción. */
    suspend fun recordFirst(
        simulated: Boolean,
        declaredRest: Boolean,
        measurement: Measurement,
        episode: EpisodeProgress?
    ): Long

    suspend fun record(id: Long, measurement: Measurement, startsSegment: Boolean, episode: EpisodeProgress? = null)

    suspend fun finish(id: Long, nowMs: Long)
}
