package com.example.healthband.ble

import org.junit.Assert.*
import org.junit.Test

/** Valida los UUID de entrada sin depender del adaptador del dispositivo. */
class BleConfigTest {
    @Test
    fun requiresTwoCanonicalUuids() {
        val uuid = "12345678-1234-1234-1234-123456789abc"
        assertNull(BleConfig.parse("", ""))
        assertNull(BleConfig.parse(uuid, "1-2-3-4-5"))
        assertNotNull(BleConfig.parse(" $uuid ", uuid))
    }
}
