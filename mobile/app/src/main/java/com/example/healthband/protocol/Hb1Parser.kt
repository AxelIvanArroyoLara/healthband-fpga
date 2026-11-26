
package com.example.healthband.protocol

import com.example.healthband.model.Measurement

/**
 * Representa el resultado de interpretar una trama HB1.
 *
 * Success contiene una medición correctamente interpretada.
 * Error contiene la explicación de un mensaje rechazado.
 */
sealed interface ParseResult {

    data class Success(
        val measurement: Measurement
    ) : ParseResult

    data class Error(
        val reason: String
    ) : ParseResult
}

/**
 * Interpreta mensajes del protocolo HealthBand HB1.
 *
 * Formato:
 * HB1,SEQ=000012,BPM=075,IBI=0800,Q=1
 *
 * El parser acepta fragmentos de texto y reconstruye mensajes
 * completos utilizando el salto de línea como delimitador.
 *
 * @param clock Función que proporciona la hora de recepción.
 */
class Hb1Parser(
    private val clock: () -> Long = System::currentTimeMillis
) {

    // Almacena los caracteres de una trama todavía incompleta.
    private val buffer = StringBuilder()
    private var discardUntilNewline = false

    // Conserva la última secuencia aceptada para detectar duplicados.
    private var lastSequence: Long? = null

    // Define el formato exacto de los campos del protocolo HB1.
    private val pattern = Regex(
        """^HB1,SEQ=(\d{6}),BPM=(\d{3}),IBI=(\d{4}),Q=([01])$"""
    )

    /**
     * Procesa un fragmento de texto recibido.
     *
     * Un fragmento puede contener una trama completa, una parte
     * de una trama o varias tramas consecutivas.
     *
     * @param chunk Fragmento recibido desde la fuente de datos.
     * @return Resultados de las tramas completas encontradas.
     */
    fun feed(chunk: String): List<ParseResult> {

        val results = mutableListOf<ParseResult>()

        for (character in chunk) {

            when {
                character == '\n' -> {
                    if (!discardUntilNewline) {
                        results.add(parseLine(buffer.toString().removeSuffix("\r")))
                    }
                    buffer.clear()
                    discardUntilNewline = false
                }
                discardUntilNewline -> Unit
                buffer.length == MAX_FRAME_LENGTH -> {
                    // Descarta la línea completa, incluido cualquier sufijo con apariencia de trama.
                    buffer.clear()
                    discardUntilNewline = true
                    results.add(ParseResult.Error("Trama demasiado larga"))
                }
                else -> buffer.append(character)
            }
        }

        return results
    }

    /**
     * Interpreta y valida una trama completa.
     *
     * @param line Trama sin el delimitador de final de línea.
     * @return Medición válida o descripción del error.
     */
    private fun parseLine(line: String): ParseResult {

        // Comprueba que la trama respete el formato esperado.
        val match = pattern.matchEntire(line)
            ?: return ParseResult.Error(
                "Formato HB1 incorrecto"
            )

        val (seqText, bpmText, ibiText, qualityText) =
            match.destructured

        val sequence = seqText.toLong()
        val bpm = bpmText.toInt()
        val ibi = ibiText.toInt()
        val isValid = qualityText == "1"

        // Rechaza mensajes repetidos o con secuencia decreciente.
        val previousSequence = lastSequence

        if (previousSequence != null) {

            if (sequence == previousSequence) {
                return ParseResult.Error(
                    "Secuencia duplicada: $sequence"
                )
            }

            if (sequenceDistance(previousSequence, sequence) >= SEQUENCE_MODULUS / 2) {
                return ParseResult.Error(
                    "Secuencia fuera de orden: $sequence"
                )
            }
        }

        // Los rangos de recepción solo se aplican a datos válidos.
        if (isValid) {

            if (bpm !in MIN_BPM..MAX_BPM) {
                return ParseResult.Error(
                    "BPM fuera de rango"
                )
            }

            if (ibi !in MIN_IBI..MAX_IBI) {
                return ParseResult.Error(
                    "IBI fuera de rango"
                )
            }
        }

        // La secuencia se actualiza únicamente al aceptar la trama.
        lastSequence = sequence

        return ParseResult.Success(
            Measurement(
                sequence = sequence,
                bpm = if (isValid) bpm else null,
                ibiMs = if (isValid) ibi else null,
                isValid = isValid,
                receivedAtMs = clock()
            )
        )
    }

    /**
     * Limpia el buffer y el historial de secuencias.
     *
     * Se utiliza al iniciar una nueva sesión independiente.
     */
    fun reset() {
        buffer.clear()
        lastSequence = null
        discardUntilNewline = false
    }

    companion object {
        const val SEQUENCE_MODULUS = 1_000_000L

        /** Calcula el avance en el contador circular de seis dígitos. */
        fun sequenceDistance(previous: Long, next: Long): Long =
            (next - previous + SEQUENCE_MODULUS) % SEQUENCE_MODULUS


        // Longitud máxima admitida para una trama incompleta.
        private const val MAX_FRAME_LENGTH = 128

        // Rangos experimentales para validar mensajes de prueba.
        private const val MIN_BPM = 30
        private const val MAX_BPM = 240

        private const val MIN_IBI = 250
        private const val MAX_IBI = 2500
    }
}
