package com.example.healthband.ble

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Clasifica la terminación GATT según si el enlace llegó a entregar datos. */
class BleFailureTest {
    @Test
    fun interruptionBeforeCccdIsConnectionFailure() {
        val error = BleFailure.linkEnded(status = 133, wasSubscribed = false)
        assertFalse(error.disconnected)
        assertTrue(error.message.orEmpty().contains("133"))
    }

    @Test
    fun interruptionAfterCccdIsDisconnectEvenWithGattError() {
        val error = BleFailure.linkEnded(status = 8, wasSubscribed = true)
        assertTrue(error.disconnected)
        assertTrue(error.message.orEmpty().contains("8"))
    }
}
