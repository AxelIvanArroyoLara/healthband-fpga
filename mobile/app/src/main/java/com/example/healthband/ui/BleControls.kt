package com.example.healthband.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.Alignment
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.healthband.ble.BleConfig
import com.example.healthband.ble.blePermissions

/** Configura los UUID y permite elegir un periférico sin almacenar su dirección. */
@Composable
fun BleControls(viewModel: HealthViewModel, visible: Boolean, declaredRest: Boolean) {
    val scan by viewModel.bleScanState.collectAsStateWithLifecycle()
    var service by rememberSaveable { mutableStateOf(BleConfig.default.service.toString()) }
    var characteristic by rememberSaveable { mutableStateOf(BleConfig.default.characteristic.toString()) }
    var permissionMessage by rememberSaveable { mutableStateOf<String?>(null) }
    var expanded by rememberSaveable { mutableStateOf(false) }
    var testSource by rememberSaveable { mutableStateOf(false) }
    val config = BleConfig.parse(service, characteristic)
    fun checkAndScan() {
        val reason = viewModel.bleUnavailableReason()
        permissionMessage = reason
        if (reason == null) viewModel.scanBle()
    }
    val permissions = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { checkAndScan() }

    if (!visible) return

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { expanded = !expanded }) {
                Text(if (expanded) "Ocultar configuración BLE" else "Configurar Bluetooth LE")
            }
            if (config == null) Text("BLE sin configurar. Se requieren los UUID del ESP32.")
            if (expanded) {
                OutlinedTextField(
                    value = service,
                    onValueChange = { service = it },
                    label = { Text("UUID del servicio") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = characteristic,
                    onValueChange = { characteristic = it },
                    label = { Text("UUID de la característica") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = testSource, onCheckedChange = { testSource = it })
                    Text("Fuente BLE sintética (modo prueba o FPGA sintética)")
                }
                Button(
                    enabled = config != null && !scan.scanning,
                    onClick = { permissions.launch(blePermissions()) }
                ) {
                    Text(if (scan.scanning) "Buscando dispositivos…" else "Buscar dispositivos")
                }
                (permissionMessage ?: scan.message)?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                if (config != null) {
                    scan.devices.forEach { device ->
                        TextButton(onClick = { viewModel.connectBle(device, config, declaredRest, testSource) }) {
                            Text("${device.name} · ${device.address}")
                        }
                    }
                }
            }
        }
    }
}
