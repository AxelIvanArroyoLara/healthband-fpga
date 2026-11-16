package com.example.healthband.analysis

import org.junit.Assert.*
import org.junit.Test

/** Escenarios sintéticos reproducibles con avance explícito del tiempo monotónico. */
class AnomalyDetectorTest {
    private val config = AnomalyConfig()
    private val baseline = Baseline(75.0, 2.0, 3)

    @Test
    fun calibrationRequiresIndependentSessionsAndResistsOutliers() {
        val short = List(19) { 75 }
        val stable = List(20) { 75 }
        assertNull(Baseline.calculate(listOf(stable, stable, short), config))
        val reference = Baseline.calculate(listOf(stable, stable, List(2_000) { 150 }), config)
        assertEquals(Baseline(75.0, 0.0, 3), reference)
        assertEquals(AnomalyStatus.INSUFFICIENT, AnomalyDetector(null).receive(140, 0, 0).status)
    }

    @Test
    fun stableNoiseAndShortSpikeNeverConfirm() {
        val detector = AnomalyDetector(baseline)
        val stable = listOf(70, 80, 76, 74, 82, 77, 78)
        repeat(40) {
            assertEquals(AnomalyStatus.USUAL, detector.receive(stable[it % stable.size], it * 1000L, 0).status)
        }
        assertEquals(AnomalyStatus.BRIEF, detector.receive(120, 40_000, 0).status)
        assertEquals(AnomalyStatus.USUAL, detector.receive(75, 41_000, 0).status)
    }

    @Test
    fun sustainedElevationIsConfirmedAtFifteenSecondsAndTracksDuration() {
        val detector = AnomalyDetector(baseline)
        repeat(15) {
            assertEquals(AnomalyStatus.BRIEF, detector.receive(100, it * 1000L, 91).status)
        }
        val confirmed = detector.receive(105, 15_000, -42)
        assertEquals(AnomalyStatus.SUSTAINED, confirmed.status)
        assertEquals(EpisodeProgress(0, 91, 15_000, 105, 75.0), confirmed.episode)
        assertEquals(16_000L, detector.receive(99, 16_000, -1_000).episode?.durationMs)
    }

    @Test
    fun sparseInvalidAndMissingSignalCannotBridgeAWindow() {
        val detector = AnomalyDetector(baseline)
        repeat(8) {
            assertEquals(AnomalyStatus.BRIEF, detector.receive(100, it * 2_500L, 0).status)
        }
        assertEquals(AnomalyStatus.INVALID, detector.receive(null, 18_000, 0).status)
        assertEquals(AnomalyStatus.BRIEF, detector.receive(100, 19_000, 0).status)
        assertEquals(AnomalyStatus.NO_DATA, detector.noData().status)
        assertEquals(AnomalyStatus.BRIEF, detector.receive(100, 42_000, 0).status)
        assertEquals(AnomalyStatus.BRIEF, detector.receive(100, 59_000, 0).status)
    }
}
