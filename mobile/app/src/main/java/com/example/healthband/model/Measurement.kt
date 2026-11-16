
package com.example.healthband.model

/**
 * Representa una medición fisiológica recibida por HealthBand.
 *
 * Los datos pueden provenir de un simulador o de un dispositivo real.
 * La clase no depende de la interfaz gráfica ni del transporte utilizado.
 *
 * @property sequence Número secuencial del mensaje recibido.
 * @property bpm Frecuencia cardíaca en pulsaciones por minuto.
 * @property ibiMs Intervalo entre pulsaciones en milisegundos.
 * @property isValid Indica si la medición puede utilizarse.
 * @property receivedAtMs Hora de recepción en milisegundos Unix.
 */
data class Measurement(
    val sequence: Long,
    val bpm: Int?,
    val ibiMs: Int?,
    val isValid: Boolean,
    val receivedAtMs: Long
)
