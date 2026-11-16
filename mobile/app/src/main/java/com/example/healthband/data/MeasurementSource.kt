package com.example.healthband.data

import kotlinx.coroutines.flow.Flow

/**
 * Contrato para las fuentes de datos de HealthBand.
 *
 * Cada implementación proporciona fragmentos de texto que
 * posteriormente serán interpretados por el parser HB1.
 *
 * Las fuentes pueden ser simuladas o basadas en Bluetooth.
 */
interface MeasurementSource {

    /**
     * Proporciona un flujo de fragmentos del protocolo.
     *
     * @return Flow con los fragmentos recibidos.
     */
    fun chunks(): Flow<String>
}
