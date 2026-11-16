package com.example.healthband.analysis

import kotlin.math.abs

/** Parámetros experimentales para la referencia y la persistencia de una elevación. */
data class AnomalyConfig(
    val minimumSessions: Int = 3,
    val minimumSessionSamples: Int = 20,
    val minimumRiseBpm: Double = 12.0,
    val relativeRise: Double = 0.15,
    val madMultiplier: Double = 3.0,
    val sustainedMs: Long = 15_000,
    val sustainedSamples: Int = 10,
    val maximumGapMs: Long = 2_500
) {
    init {
        require(minimumSessions >= 2 && minimumSessionSamples >= 2)
        require(minimumRiseBpm > 0 && relativeRise >= 0 && madMultiplier >= 0)
        require(sustainedMs > 0 && sustainedSamples >= 2 && maximumGapMs > 0)
    }
}

/** Referencia de reposo con dispersión robusta y número de sesiones utilizadas. */
data class Baseline(val bpm: Double, val mad: Double, val sessions: Int) {
    companion object {
        /** Da el mismo peso a cada sesión, incluso si difieren en duración. */
        fun calculate(samplesBySession: List<List<Int>>, config: AnomalyConfig): Baseline? {
            val eligible = samplesBySession.filter { it.size >= config.minimumSessionSamples }
            if (eligible.size < config.minimumSessions) return null
            val center = median(eligible.map { session -> median(session.map(Int::toDouble)) })
            val mad = median(eligible.map { session -> median(session.map { abs(it - center) }) })
            return Baseline(center, mad, eligible.size)
        }

        private fun median(values: List<Double>): Double {
            val sorted = values.sorted()
            return (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2
        }
    }
}

/** Resultado del análisis experimental de la señal actual. */
enum class AnomalyStatus(val label: String) {
    USUAL("Dentro de la referencia de reposo"),
    BRIEF("Elevación breve en observación"),
    SUSTAINED("Frecuencia inusual respecto a tus sesiones de reposo"),
    INVALID("Señal inválida para análisis"),
    NO_DATA("Sin datos recientes para análisis"),
    INSUFFICIENT("Línea base insuficiente")
}

/** Estado acumulado de un episodio confirmado por varias muestras consecutivas. */
data class EpisodeProgress(
    val startedElapsedMs: Long,
    val startedAtMs: Long,
    val durationMs: Long,
    val peakBpm: Int,
    val baselineBpm: Double
)

/** Clasificación actual y, cuando aplica, progreso persistible del episodio. */
data class AnomalyReading(val status: AnomalyStatus, val episode: EpisodeProgress? = null)

/** Contexto subjetivo que el usuario puede asociar a un episodio guardado. */
enum class EpisodeContext(val label: String) {
    REST("Reposo"),
    ACTIVITY("Actividad física"),
    PERCEIVED_STRESS("Estrés percibido"),
    STIMULANTS("Consumo de estimulantes"),
    OTHER("Otro"),
    UNKNOWN("Desconocido")
}

/**
 * Detecta elevaciones sostenidas con una referencia fija para la sesión.
 * La continuidad y la duración usan tiempo monotónico, incluso si cambia la hora del sistema.
 */
class AnomalyDetector(
    private val baseline: Baseline?,
    private val config: AnomalyConfig = AnomalyConfig()
) {
    private val threshold = baseline?.let {
        it.bpm + maxOf(config.minimumRiseBpm, it.bpm * config.relativeRise, 1.4826 * it.mad * config.madMultiplier)
    }
    private var lastAtMs: Long? = null
    private var run: ElevatedRun? = null

    /** Clasifica una lectura y actualiza el episodio mientras persista la elevación. */
    fun receive(bpm: Int?, now: Long, wallTimeMs: Long): AnomalyReading {
        val previous = lastAtMs
        if (previous != null && (now < previous || now - previous > config.maximumGapMs)) run = null
        lastAtMs = now
        val limit = threshold
        if (bpm == null || limit == null || bpm < limit) {
            run = null
            return AnomalyReading(when {
                bpm == null -> AnomalyStatus.INVALID
                limit == null -> AnomalyStatus.INSUFFICIENT
                else -> AnomalyStatus.USUAL
            })
        }

        val current = run ?: ElevatedRun(now, wallTimeMs, bpm).also { run = it }
        current.count++
        current.peak = maxOf(current.peak, bpm)
        val duration = now - current.start
        if (duration < config.sustainedMs || current.count < config.sustainedSamples) {
            return AnomalyReading(AnomalyStatus.BRIEF)
        }
        return AnomalyReading(
            AnomalyStatus.SUSTAINED,
            EpisodeProgress(current.start, current.wallTimeMs, duration, current.peak, requireNotNull(baseline).bpm)
        )
    }

    /** Cierra cualquier fluctuación al perder la continuidad de la señal. */
    fun noData(): AnomalyReading {
        run = null
        lastAtMs = null
        return AnomalyReading(AnomalyStatus.NO_DATA)
    }

    private class ElevatedRun(val start: Long, val wallTimeMs: Long, var peak: Int, var count: Int = 0)
}
