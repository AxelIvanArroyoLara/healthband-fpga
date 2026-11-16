
package com.example.healthband.data

import com.example.healthband.protocol.Hb1Parser
import com.example.healthband.protocol.ParseResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow

/**
 * Coordina la adquisición e interpretación de mediciones.
 *
 * Recibe fragmentos desde una fuente configurable y los
 * convierte en resultados mediante el parser HB1.
 *
 * @param source Fuente de datos utilizada.
 * @param parser Intérprete del protocolo.
 */
class MeasurementRepository(
    private val source: MeasurementSource,
    private val parser: Hb1Parser = Hb1Parser()
) {

    /**
     * Expone un flujo de mediciones y errores de interpretación.
     *
     * Cada colección inicia una sesión nueva del parser.
     *
     * @return Flow con los resultados de cada trama completa.
     */
    fun measurements(): Flow<ParseResult> = flow {

        // Reinicia el estado del parser para la nueva sesión.
        parser.reset()

        source.chunks().collect { chunk ->

            // Un fragmento puede producir ninguno, uno o varios mensajes.
            val results = parser.feed(chunk)

            for (result in results) {
                emit(result)
            }
        }
    }
}
