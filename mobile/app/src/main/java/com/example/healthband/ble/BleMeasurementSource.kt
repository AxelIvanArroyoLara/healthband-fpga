package com.example.healthband.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattConnectionSettings
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import com.example.healthband.data.MeasurementSource
import java.util.UUID
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.transform
import kotlinx.coroutines.launch

/** Describe una interrupción del transporte con un mensaje apto para la interfaz. */
class BleFailure(message: String, val disconnected: Boolean = false) : Exception(message) {
    companion object {
        /** Distingue una pérdida de enlace de un intento interrumpido antes de recibir mediciones. */
        internal fun linkEnded(status: Int, wasSubscribed: Boolean): BleFailure = if (wasSubscribed) {
            BleFailure("El dispositivo BLE se desconectó ($status)", disconnected = true)
        } else {
            BleFailure("La conexión BLE terminó antes de confirmar la suscripción ($status)")
        }
    }
}

/**
 * Abre un GATT por colección y entrega los fragmentos ASCII al repositorio.
 * La primera señal de conexión indica que el periférico confirmó la suscripción CCCD.
 */
@SuppressLint("MissingPermission")
class BleMeasurementSource(
    private val context: Context,
    private val config: BleConfig,
    private val device: BleDevice,
    private val onReady: () -> Unit
) : MeasurementSource {
    override fun chunks(): Flow<String> = notifications().transform { chunk ->
        if (chunk == null) onReady() else emit(chunk)
    }

    private fun notifications(): Flow<String?> = callbackFlow {
        BleDiscovery(context).unavailableReason(forScan = false)?.let { throw BleFailure(it) }
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
            ?: throw BleFailure("Adaptador BLE no disponible")
        val subscriptionLock = Any()
        var subscribed = false
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when {
                    newState == BluetoothProfile.STATE_DISCONNECTED -> synchronized(subscriptionLock) {
                        close(BleFailure.linkEnded(status, subscribed))
                    }
                    status != BluetoothGatt.GATT_SUCCESS ->
                        close(BleFailure("Falló la conexión GATT ($status)"))
                    newState == BluetoothProfile.STATE_CONNECTED ->
                        operation("No se pudo iniciar el descubrimiento GATT") { gatt.discoverServices() }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    close(BleFailure("Falló el descubrimiento GATT ($status)"))
                    return
                }
                val characteristic = gatt.getService(config.service)?.getCharacteristic(config.characteristic)
                val descriptor = characteristic?.getDescriptor(CCCD)
                if (characteristic == null || descriptor == null) {
                    close(BleFailure("Servicio, característica o descriptor CCCD ausente"))
                    return
                }
                val subscription = when {
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 ->
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0 ->
                        BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    else -> {
                        close(BleFailure("La característica no admite notificaciones ni indicaciones"))
                        return
                    }
                }
                operation("No se pudo solicitar la suscripción GATT") {
                    gatt.setCharacteristicNotification(characteristic, true) &&
                        writeSubscription(gatt, descriptor, subscription)
                }
            }

            override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                if (descriptor.uuid != CCCD || !matchesConfig(descriptor.characteristic)) return
                synchronized(subscriptionLock) {
                    if (subscribed) return
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        close(BleFailure("El dispositivo rechazó la suscripción ($status)"))
                    } else if (trySend(null).isSuccess) {
                        // La confirmación y la caducidad comparten el mismo orden que los fragmentos.
                        subscribed = true
                    }
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray
            ) = deliver(characteristic, value)

            @Deprecated("Compatibilidad con Android 12 y anteriores")
            override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                @Suppress("DEPRECATION")
                characteristic.value?.let { deliver(characteristic, it) }
            }

            private fun matchesConfig(characteristic: BluetoothGattCharacteristic): Boolean =
                characteristic.uuid == config.characteristic && characteristic.service.uuid == config.service

            private fun deliver(characteristic: BluetoothGattCharacteristic, bytes: ByteArray) {
                if (!matchesConfig(characteristic)) return
                synchronized(subscriptionLock) {
                    if (!subscribed) return
                    if (trySend(bytes.toString(Charsets.US_ASCII)).isFailure) {
                        // La pérdida de bytes podría convertir fragmentos vecinos en una trama incorrecta.
                        close(BleFailure("Se saturó la recepción BLE"))
                    }
                }
            }

            private fun operation(error: String, block: () -> Boolean) {
                if (!runCatching(block).getOrDefault(false)) close(BleFailure(error))
            }
        }
        val gatt = openGatt(adapter.getRemoteDevice(device.address), callback)
            ?: throw BleFailure("No se pudo abrir la conexión GATT")
        val timeout = launch {
            delay(15_000)
            synchronized(subscriptionLock) {
                if (!subscribed) close(BleFailure("Tiempo de espera agotado al conectar BLE"))
            }
        }
        awaitClose {
            timeout.cancel()
            runCatching { gatt.disconnect() }
            runCatching { gatt.close() }
        }
    }

    /** En API 37 usa un ejecutor explícito para despachar los eventos GATT en orden. */
    @Suppress("DEPRECATION")
    private fun openGatt(remote: BluetoothDevice, callback: BluetoothGattCallback): BluetoothGatt? =
        if (Build.VERSION.SDK_INT >= 37) {
            val settings = BluetoothGattConnectionSettings.Builder()
                .setAutoConnectEnabled(false)
                .setTransport(BluetoothDevice.TRANSPORT_LE)
                .build()
            remote.connectGatt(settings, context.mainExecutor, callback)
        } else {
            remote.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        }

    @Suppress("DEPRECATION")
    private fun writeSubscription(
        gatt: BluetoothGatt,
        descriptor: BluetoothGattDescriptor,
        value: ByteArray
    ): Boolean = if (Build.VERSION.SDK_INT >= 33) {
        gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
    } else {
        descriptor.value = value
        gatt.writeDescriptor(descriptor)
    }

    private companion object {
        // UUID estándar de Bluetooth SIG para configurar notificaciones del cliente.
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
