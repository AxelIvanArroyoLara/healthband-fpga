package com.example.healthband.ui

import com.example.healthband.analysis.AnomalyReading
import com.example.healthband.analysis.AnomalyStatus
import com.example.healthband.analysis.Baseline
import com.example.healthband.ble.BleConfig
import com.example.healthband.model.Measurement
import com.example.healthband.protocol.Hb1Parser
import com.example.healthband.protocol.ParseResult

/** Estado de la lectura actual, independiente de los mensajes rechazados. */
enum class ReadingStatus(val label: String) {
    STOPPED("Simulador detenido"),
    CONNECTING("Conectando por Bluetooth"),
    DISCONNECTED("Dispositivo BLE desconectado"),
    WAITING("Esperando mediciones"),
    VALID("Medición válida"),
    INVALID("Medición inválida"),
    STALE("Datos obsoletos"),
    ERROR("Error de comunicación")
}

/** Estado observable de una sesión de adquisición. */
data class HealthUiState(
    val isRunning: Boolean = false,
    val isBle: Boolean = false,
    val simulated: Boolean = !isBle,
    val deviceName: String? = null,
    val bleConfig: BleConfig? = null,
    val status: ReadingStatus = ReadingStatus.STOPPED,
    val measurement: Measurement? = null,
    val recentBpm: List<Int?> = emptyList(),
    val ageMs: Long? = null,
    val baseline: Baseline? = null,
    val anomaly: AnomalyReading = AnomalyReading(AnomalyStatus.NO_DATA),
    val receivedCount: Int = 0,
    val persistedCount: Int = 0,
    val storageError: String? = null,
    val historyBusy: Boolean = false,
    val errorCount: Int = 0,
    val lastError: String? = null,
    val lastSequence: Long? = null,
    private val lastAtMs: Long? = null
) {
    /** Actualiza la edad y expira la lectura mediante tiempo monotónico. */
    fun tick(now: Long, startedAt: Long, timeoutMs: Long): HealthUiState {
        if (!isRunning || status == ReadingStatus.CONNECTING) return this
        val age = lastAtMs?.let { now - it }
        return if ((age ?: (now - startedAt)) >= timeoutMs) {
            copy(
                status = ReadingStatus.STALE,
                measurement = null,
                ageMs = age,
                anomaly = AnomalyReading(AnomalyStatus.NO_DATA)
            )
        } else {
            copy(ageMs = age)
        }
    }

    /** Aplica una trama aceptada o registra el rechazo sin reiniciar su antigüedad. */
    fun receive(result: ParseResult, now: Long, timeoutMs: Long): HealthUiState = when (result) {
        is ParseResult.Error -> copy(errorCount = errorCount + 1, lastError = result.reason)
        is ParseResult.Success -> {
            val reading = result.measurement
            val gap = lastSequence?.let { Hb1Parser.sequenceDistance(it, reading.sequence) > 1 } == true ||
                lastAtMs?.let { now - it >= timeoutMs } == true
            val bpm = reading.bpm.takeIf { reading.isValid }
            val points = if (gap && recentBpm.lastOrNull() != null && bpm != null) {
                recentBpm + listOf(null, bpm)
            } else {
                recentBpm + bpm
            }
            copy(
                measurement = reading,
                status = if (reading.isValid) ReadingStatus.VALID else ReadingStatus.INVALID,
                recentBpm = points.takeLast(60),
                ageMs = 0,
                receivedCount = receivedCount + 1,
                lastSequence = reading.sequence,
                lastAtMs = now
            )
        }
    }
}
