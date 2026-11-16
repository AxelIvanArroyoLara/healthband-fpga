package com.example.healthband.integration

import com.example.healthband.data.MeasurementRepository
import com.example.healthband.data.MeasurementSource
import com.example.healthband.protocol.ParseResult
import com.example.healthband.ui.HealthUiState
import com.example.healthband.ui.ReadingStatus
import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** Comprueba la delimitación y la reducción de estado con lotes reproducibles. */
class Hb1PipelineTest {
    @Test
    fun acceptsOneHundredValidFramesAndRejectsTenMalformedAcrossFragmentBoundaries() = runBlocking {
        val stream = buildString {
            for (sequence in 1..100) {
                append(frame(sequence))
                if (sequence % 10 == 0) append("TRAMA_INCORRECTA\n")
            }
        }
        val source = object : MeasurementSource {
            override fun chunks() = stream.chunked(19).asFlow()
        }
        val repository = MeasurementRepository(source)
        repeat(2) {
            var state = HealthUiState(isRunning = true, status = ReadingStatus.WAITING)
            repository.measurements().collect { result ->
                state = state.receive(result, now = state.receivedCount * 1000L, timeoutMs = 4_000)
            }
            assertEquals(100, state.receivedCount)
            assertEquals(10, state.errorCount)
            assertEquals("Formato HB1 incorrecto", state.lastError)
            assertEquals(100L, state.measurement?.sequence)
            assertEquals(List(60) { 75 }, state.recentBpm)
        }
    }

    @Test
    fun rejectedSequenceAndInvalidQualityCannotCoverSignalLoss() = runBlocking {
        val source = object : MeasurementSource {
            override fun chunks() = listOf(
                frame(1), frame(1), frame(0), frame(3, quality = 0), frame(4)
            ).asFlow()
        }
        val states = mutableListOf<HealthUiState>()
        var state = HealthUiState(isRunning = true, status = ReadingStatus.WAITING)
        MeasurementRepository(source).measurements().collect { result ->
            state = state.receive(result, now = states.size * 1000L, timeoutMs = 4_000)
            if (result is ParseResult.Error) assertEquals(1L, state.measurement?.sequence)
            states += state
        }
        assertEquals(ReadingStatus.INVALID, states[3].status)
        assertNull(states[3].measurement?.bpm)
        assertNull(states[3].measurement?.ibiMs)
        assertEquals(listOf(75, null, 75), states[4].recentBpm)
        assertEquals(2, states[4].errorCount)
        state = state.tick(now = 8_000, startedAt = 0, timeoutMs = 4_000)
        assertEquals(ReadingStatus.STALE, state.status)
        assertNull(state.measurement)
    }

    private fun frame(sequence: Int, quality: Int = 1) =
        "HB1,SEQ=${sequence.toString().padStart(6, '0')},BPM=075,IBI=0800,Q=$quality\n"
}
