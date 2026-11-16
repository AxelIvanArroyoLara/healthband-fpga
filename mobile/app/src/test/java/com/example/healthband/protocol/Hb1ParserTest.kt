package com.example.healthband.protocol

import org.junit.Assert.*
import org.junit.Test

/** Comprueba el contrato HB1 con fragmentos independientes del transporte. */
class Hb1ParserTest {
    @Test
    fun reconstructsFragmentsAndPreservesInvalidQuality() {
        val parser = Hb1Parser { 42L }
        assertTrue(parser.feed("HB1,SEQ=000001,").isEmpty())
        val results = parser.feed("BPM=072,IBI=0833,Q=1\r\nHB1,SEQ=000002,BPM=000,IBI=0000,Q=0\n")
        val valid = (results[0] as ParseResult.Success).measurement
        val invalid = (results[1] as ParseResult.Success).measurement
        assertEquals(72, valid.bpm)
        assertEquals(42L, valid.receivedAtMs)
        assertFalse(invalid.isValid)
        assertNull(invalid.bpm)
        assertNull(invalid.ibiMs)
    }

    @Test
    fun onlyAcceptedFramesAdvanceSequenceAndWrapIsSupported() {
        val parser = Hb1Parser()
        assertTrue(parser.feed(frame("999998")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("999999", 999)).single() is ParseResult.Error)
        assertTrue(parser.feed(frame("999999")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("000000")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("000000")).single() is ParseResult.Error)
        assertTrue(parser.feed(frame("999999")).single() is ParseResult.Error)
        parser.reset()
        assertTrue(parser.feed(frame("123456")).single() is ParseResult.Success)
    }

    @Test
    fun oversizedLineCannotInjectFrameAndParserRecovers() {
        val parser = Hb1Parser()
        assertTrue(parser.feed("x".repeat(10_000)).single() is ParseResult.Error)
        assertTrue(parser.feed(frame("000001")).isEmpty())
        assertTrue(parser.feed(frame("000001")).single() is ParseResult.Success)
    }

    @Test
    fun FPGAResetRemainsAmbiguousUntilANewCollection() {
        val parser = Hb1Parser()
        assertTrue(parser.feed(frame("001000")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("000001")).single() is ParseResult.Error)
        assertTrue(parser.feed(frame("001001")).single() is ParseResult.Success)
        parser.reset()
        assertTrue(parser.feed(frame("000001")).single() is ParseResult.Success)

        // Tras 999990, el valor 000010 coincide con un avance circular ordinario.
        parser.reset()
        assertTrue(parser.feed(frame("999990")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("000010")).single() is ParseResult.Success)
    }

    @Test
    fun halfOfSequenceRangeIsRejectedWithoutMovingTheCurrentSequence() {
        val parser = Hb1Parser()
        assertTrue(parser.feed(frame("000000")).single() is ParseResult.Success)
        assertTrue(parser.feed(frame("500000")).single() is ParseResult.Error)
        assertTrue(parser.feed(frame("499999")).single() is ParseResult.Success)
    }

    @Test
    fun invalidQualityStillConsumesSequenceButMalformedValuesDoNot() {
        val parser = Hb1Parser()
        val stream = "HB1,SEQ=000001,BPM=075,IBI=9999,Q=1\n" +
            "HB1,SEQ=000001,BPM=999,IBI=9999,Q=0\r\n" +
            frame("000001") +
            frame("000002").replace("\n", "\r\r\n") +
            frame("000002")
        val results = parser.feed(stream)
        assertTrue(results[0] is ParseResult.Error)
        val invalid = (results[1] as ParseResult.Success).measurement
        assertFalse(invalid.isValid)
        assertNull(invalid.bpm)
        assertTrue(results[2] is ParseResult.Error)
        assertTrue(results[3] is ParseResult.Error)
        assertTrue(results[4] is ParseResult.Success)
    }

    private fun frame(sequence: String, bpm: Int = 72) =
        "HB1,SEQ=$sequence,BPM=${bpm.toString().padStart(3, '0')},IBI=0833,Q=1\n"
}
