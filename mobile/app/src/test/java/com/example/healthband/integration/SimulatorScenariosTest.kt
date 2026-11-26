package com.example.healthband.integration

import com.example.healthband.data.MeasurementRepository
import com.example.healthband.data.SimulatedMeasurementSource
import com.example.healthband.protocol.ParseResult
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Verifica los tres escenarios a través del mismo parser que usa la adquisición. */
class SimulatorScenariosTest {
    @Test
    fun normalSimulationRemainsValidAndConsecutive() = runBlocking {
        val results = readings(SimulatedMeasurementSource(intervalMs = 0), 20)
        val measurements = results.map { (it as ParseResult.Success).measurement }
        assertEquals((1L..20L).toList(), measurements.map { it.sequence })
        assertTrue(measurements.all { it.isValid })
    }

    @Test
    fun communicationScenarioIncludesRejectionsAndInvalidQuality() = runBlocking {
        val results = readings(SimulatedMeasurementSource(intervalMs = 0, communicationErrors = true), 16)
        val errors = results.filterIsInstance<ParseResult.Error>()
        assertEquals(2, errors.size)
        assertTrue(errors.any { it.reason == "Formato HB1 incorrecto" })
        assertTrue(errors.any { it.reason.startsWith("Secuencia duplicada") })
        assertTrue(results.filterIsInstance<ParseResult.Success>().any { !it.measurement.isValid })
    }

    @Test
    fun sustainedSimulationStartsAndEndsAtTheDocumentedSamples() = runBlocking {
        val results = readings(SimulatedMeasurementSource(intervalMs = 0, sustainedDemo = true), 29)
        val bpm = results.map { (it as ParseResult.Success).measurement.bpm }
        assertEquals(List(5) { 75 } + List(23) { 105 } + listOf(75), bpm)
    }

    private suspend fun readings(source: SimulatedMeasurementSource, count: Int) =
        MeasurementRepository(source).measurements().take(count).toList()
}
