
package com.example.healthband.data

import com.example.healthband.protocol.Hb1Parser
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.util.Locale

/**
 * Fuente de mediciones simuladas para desarrollo y pruebas.
 *
 * Genera tramas del protocolo HB1 sin utilizar hardware real.
 * Introduce errores de transporte únicamente en el escenario de prueba explícito.
 *
 * @param intervalMs Tiempo entre ciclos de generación.
 * @param sustainedDemo Genera una elevación continua de prueba entre las tramas 6 y 28.
 * @param communicationErrors Inserta tramas malformadas y duplicados para probar el parser.
 */
class SimulatedMeasurementSource(
    private val intervalMs: Long = 1000L,
    private val sustainedDemo: Boolean = false,
    private val communicationErrors: Boolean = false
) : MeasurementSource {

    /**
     * Genera continuamente fragmentos de mensajes HB1.
     *
     * La generación termina cuando se cancela el Flow.
     */
    override fun chunks(): Flow<String> = flow {

        var sequence = 0L

        while (true) {

            sequence++

            // Selecciona un escenario de prueba según la secuencia.
            val message = when {
                sustainedDemo -> {
                    val bpm = if (sequence in 6L..28L) 105 else 75
                    formatMessage(sequence, bpm, 60000 / bpm, 1)
                }

                // Simula pérdida de contacto o medición inválida.
                communicationErrors && sequence % 15L == 0L -> {
                    formatMessage(
                        sequence = sequence,
                        bpm = 0,
                        ibi = 0,
                        quality = 0
                    )
                }

                // Genera un mensaje malformado deliberadamente.
                communicationErrors && sequence % 11L == 0L -> {
                    "MENSAJE_INVALIDO\n"
                }

                // Genera una medición fisiológica de prueba.
                else -> {
                    val bpm = 70 + (sequence % 11).toInt()

                    val ibi = 60000 / bpm

                    formatMessage(
                        sequence = sequence,
                        bpm = bpm,
                        ibi = ibi,
                        quality = 1
                    )
                }
            }

            // Divide algunas tramas para probar su reconstrucción.
            if (sequence % 5L == 0L) {

                val middle = message.length / 2

                emit(message.substring(0, middle))

                delay(100L)

                emit(message.substring(middle))

            } else {

                emit(message)
            }

            // Reenvía una trama para comprobar detección de duplicados.
            if (communicationErrors && sequence % 13L == 0L) {
                emit(message)
            }

            // Simula el intervalo de transmisión entre mediciones.
            delay(intervalMs)
        }
    }

    /**
     * Construye una trama con el formato HB1.
     *
     * @param sequence Número secuencial.
     * @param bpm Frecuencia cardíaca.
     * @param ibi Intervalo entre pulsaciones en milisegundos.
     * @param quality Indicador de validez.
     * @return Mensaje completo, incluyendo salto de línea.
     */
    private fun formatMessage(
        sequence: Long,
        bpm: Int,
        ibi: Int,
        quality: Int
    ): String {

        return String.format(
            Locale.US,
            "HB1,SEQ=%06d,BPM=%03d,IBI=%04d,Q=%d\n",
            sequence % Hb1Parser.SEQUENCE_MODULUS,
            bpm,
            ibi,
            quality
        )
    }
}
