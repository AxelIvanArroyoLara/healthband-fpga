package com.example.healthband.ble

import java.util.UUID

/** Identificadores GATT que deben coincidir con la configuración real del puente. */
data class BleConfig(val service: UUID, val characteristic: UUID) {
    companion object {
        /** UUID de salida del puente HB1, editables desde el monitor. */
        val default = BleConfig(
            UUID.fromString("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
            UUID.fromString("6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
        )

        private val uuidPattern = Regex("[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")

        /** Acepta únicamente UUID completos en formato canónico. */
        fun parse(service: String, characteristic: String): BleConfig? {
            val serviceText = service.trim()
            val characteristicText = characteristic.trim()
            if (!uuidPattern.matches(serviceText) || !uuidPattern.matches(characteristicText)) return null
            return BleConfig(UUID.fromString(serviceText), UUID.fromString(characteristicText))
        }
    }
}
