package com.example.healthband.ble

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/** Dispositivo encontrado durante un escaneo, retenido solo en memoria. */
data class BleDevice(val address: String, val name: String, val hasAdvertisedName: Boolean = true)

/** Expone los permisos de escaneo en primer plano según la versión de Android. */
fun blePermissions(): Array<String> = if (Build.VERSION.SDK_INT >= 31) {
    arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
} else {
    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
}

/** Comprueba adaptador y permisos antes de iniciar un escaneo acotado por el llamador. */
class BleDiscovery(private val context: Context) {
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter

    /** Comprueba los permisos de la operación sin exigir ubicación para reconectar. */
    @SuppressLint("MissingPermission")
    fun unavailableReason(forScan: Boolean = true): String? = when {
        !context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) || adapter == null ->
            "Bluetooth LE no está disponible en este dispositivo"
        forScan && blePermissions().any { context.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED } ->
            "Se requieren permisos para buscar dispositivos BLE"
        !forScan && Build.VERSION.SDK_INT >= 31 &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED ->
            "Se requiere permiso para conectar el dispositivo BLE"
        adapter?.isEnabled != true -> "Activa Bluetooth en los ajustes de Android"
        else -> null
    }

    /** Devuelve anuncios disponibles y detiene el escáner al cancelar la colección. */
    @SuppressLint("MissingPermission")
    fun scan(): Flow<BleDevice> = callbackFlow {
        unavailableReason()?.let { throw BleFailure(it) }
        val scanner = adapter?.bluetoothLeScanner ?: throw BleFailure("Escáner BLE no disponible")
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = result.scanRecord?.deviceName
                trySend(BleDevice(result.device.address, name ?: "Dispositivo sin nombre", name != null))
            }

            override fun onScanFailed(errorCode: Int) {
                close(BleFailure("Error de escaneo BLE ($errorCode)"))
            }
        }
        // El anuncio puede omitir el UUID. El servicio se verifica después en GATT.
        scanner.startScan(callback)
        awaitClose { runCatching { scanner.stopScan(callback) } }
    }
}
