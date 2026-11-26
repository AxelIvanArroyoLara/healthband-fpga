package com.example.healthband.integration

import com.example.healthband.protocol.Hb1Parser
import com.example.healthband.protocol.ParseResult
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test

/** Verifica los datos del testbench UART después de fragmentarlos con el código C del puente. */
class Hb1ContractTest {
    @Test
    fun receivesExactlyOneHundredRtlFramesAtEachMtu() {
        val directory = System.getProperty("hb1ContractDir")
        assumeNotNull(directory)
        val rtl = File(directory, "rtl.txt").readText(Charsets.US_ASCII)
        assertEquals(3_600, rtl.length)
        val lines = rtl.lineSequence().filter { it.isNotEmpty() }.toList()
        assertEquals(100, lines.size)
        assertTrue(lines.all { it.length == 35 })
        val groups = File(directory, "notifications.txt").readText().split("MTU ").drop(1)
        assertEquals(listOf("23 CAP 0", "39 CAP 0", "247 CAP 7"), groups.map { it.lineSequence().first() })

        for (group in groups) {
            val fragments = group.lineSequence().drop(1).filter { it.isNotEmpty() }.map { hex ->
                hex.chunked(2).map { it.toInt(16).toChar() }.joinToString("")
            }.toList()
            assertEquals(rtl, fragments.joinToString(""))
            val parser = Hb1Parser { 0 }
            val readings = fragments.flatMap(parser::feed).map { result ->
                assertTrue(result.toString(), result is ParseResult.Success)
                (result as ParseResult.Success).measurement
            }
            assertEquals((0L..99L).toList(), readings.map { it.sequence })
            for ((line, reading) in lines.zip(readings)) {
                val isValid = line.endsWith("Q=1")
                assertEquals(isValid, reading.isValid)
                assertEquals(if (isValid) line.substringAfter("BPM=").take(3).toInt() else null, reading.bpm)
                assertEquals(if (isValid) line.substringAfter("IBI=").take(4).toInt() else null, reading.ibiMs)
            }
        }
    }
}
