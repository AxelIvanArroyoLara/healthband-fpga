package com.example.healthband.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import com.example.healthband.data.MeasurementSource
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.transform
import kotlinx.coroutines.launch

/** Describe una interrupción del transporte con un mensaje apto para la interfaz. */
class BleFailure(message: String, val disconnected: Boolean = false) : Exception(message)

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
        BleDiscovery(context).unavailableReason()?.let { throw BleFailure(it) }
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
            ?: throw BleFailure("Adaptador BLE no disponible")
        val subscribed = AtomicBoolean(false)
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when {
                    newState == BluetoothProfile.STATE_DISCONNECTED ->
                        close(BleFailure("El dispositivo BLE se desconectó ($status)", disconnected = true))
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
                if (descriptor.uuid != CCCD) return
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    close(BleFailure("El dispositivo rechazó la suscripción ($status)"))
                } else if (subscribed.compareAndSet(false, true)) {
                    trySend(null)
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

            private fun deliver(characteristic: BluetoothGattCharacteristic, bytes: ByteArray) {
                if (characteristic.uuid != config.characteristic || characteristic.service.uuid != config.service) return
                if (trySend(bytes.toString(Charsets.US_ASCII)).isFailure) {
                    // La pérdida de bytes podría convertir fragmentos vecinos en una trama incorrecta.
                    close(BleFailure("Se saturó la recepción BLE"))
                }
            }

            private fun operation(error: String, block: () -> Boolean) {
                if (!runCatching(block).getOrDefault(false)) close(BleFailure(error))
            }
        }
        val gatt = adapter.getRemoteDevice(device.address)
            .connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            ?: throw BleFailure("No se pudo abrir la conexión GATT")
        val timeout = launch {
            delay(15_000)
            if (!subscribed.get()) close(BleFailure("Tiempo de espera agotado al conectar BLE"))
        }
        awaitClose {
            timeout.cancel()
            runCatching { gatt.disconnect() }
            runCatching { gatt.close() }
        }
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
