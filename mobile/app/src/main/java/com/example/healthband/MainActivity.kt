package com.example.healthband

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.healthband.ui.HealthScreen
import com.example.healthband.ui.HealthViewModel
import com.example.healthband.ui.HistoryScreen

/** Mantiene la adquisición en el ViewModel de la actividad al cambiar de pantalla. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface {
                    val monitor: HealthViewModel = viewModel()
                    val state by monitor.uiState.collectAsStateWithLifecycle()
                    var tab by rememberSaveable { mutableIntStateOf(0) }
                    val screens = rememberSaveableStateHolder()
                    Column {
                        PrimaryTabRow(selectedTabIndex = tab, modifier = Modifier.statusBarsPadding()) {
                            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Monitor") })
                            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Historial") })
                        }
                        screens.SaveableStateProvider(tab) {
                            if (tab == 0) HealthScreen(monitor) else HistoryScreen(activeSession = state.isRunning || state.historyBusy)
                        }
                    }
                }
            }
        }
    }
}
