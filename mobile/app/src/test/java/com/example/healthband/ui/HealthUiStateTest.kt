package com.example.healthband.ui

import com.example.healthband.model.Measurement
import com.example.healthband.protocol.ParseResult
import org.junit.Assert.*
import org.junit.Test

/** Verifica la transición temporal del dashboard con un reloj controlado. */
class HealthUiStateTest {
    @Test
    fun invalidStaleAndRecoveryKeepChartGaps() {
        var state = HealthUiState(isRunning = true, status = ReadingStatus.WAITING)
        assertEquals(ReadingStatus.STALE, state.tick(4_000, 0, 4_000).status)
        state = state.receive(reading(1, 72), 100, 4_000)
        state = state.receive(reading(2, null), 1_000, 4_000)
        assertEquals(ReadingStatus.INVALID, state.status)
        assertNull(state.measurement?.bpm)
        state = state.receive(reading(3, 74), 2_000, 4_000)
        state = state.receive(ParseResult.Error("Duplicado"), 5_999, 4_000)
        assertEquals(ReadingStatus.VALID, state.tick(5_999, 0, 4_000).status)
        state = state.tick(6_000, 0, 4_000)
        assertEquals(ReadingStatus.STALE, state.status)
        assertNull(state.measurement)
        state = state.receive(reading(4, 76), 6_100, 4_000)
        assertEquals(ReadingStatus.VALID, state.status)
        assertEquals(listOf(72, null, 74, null, 76), state.recentBpm)
        assertEquals("Duplicado", state.lastError)
    }

    @Test
    fun seriesIsBoundedAndASkippedSequenceBreaksTheLine() {
        var state = HealthUiState(isRunning = true)
        repeat(100) { state = state.receive(reading(it.toLong(), 75), it.toLong(), 4_000) }
        state = state.receive(reading(101, 80), 101, 4_000)
        assertEquals(60, state.recentBpm.size)
        assertEquals(listOf(null, 80), state.recentBpm.takeLast(2))
        assertEquals(101, state.receivedCount)
    }

    private fun reading(sequence: Long, bpm: Int?) =
        ParseResult.Success(Measurement(sequence, bpm, bpm?.let { 60_000 / it }, bpm != null, 0))
}
