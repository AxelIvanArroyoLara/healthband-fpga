package com.example.healthband.integration

import android.app.Application
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.healthband.analysis.AnomalyStatus
import com.example.healthband.ble.BleFailure
import com.example.healthband.data.MeasurementSource
import com.example.healthband.data.SimulatedMeasurementSource
import com.example.healthband.history.HealthDatabase
import com.example.healthband.history.HistoryRepository
import com.example.healthband.model.Measurement
import com.example.healthband.ui.HealthViewModel
import com.example.healthband.ui.ReadingStatus
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Integra las fuentes, el monitor, el detector y Room sin periférico físico. */
@RunWith(AndroidJUnit4::class)
class AcquisitionTest {
    @Test
    fun simulatorPersistsSustainedEpisodeUsingCalibratedHistory() = runBlocking {
        withTestMonitor { viewModel, history, elapsed ->
            repeat(3) {
                val id = history.begin(simulated = true, nowMs = 1, declaredRest = true)
                repeat(20) { index ->
                    history.record(id, Measurement(index.toLong(), 75, 800, true, 2), index == 0)
                }
                history.finish(id, 3)
            }

            val demo = SimulatedMeasurementSource(intervalMs = 0, sustainedDemo = true)
            val source = object : MeasurementSource {
                override fun chunks() = demo.chunks().transformWhile { chunk ->
                    emit(chunk)
                    if (chunk.endsWith('\n')) elapsed.addAndGet(1000)
                    elapsed.get() < 31_000
                }
            }
            withContext(Dispatchers.Main) {
                viewModel.startSession(isBle = false, declaredRest = false) { source }
            }
            val detected = viewModel.uiState.first { it.anomaly.status == AnomalyStatus.SUSTAINED }
            assertEquals(75.0, requireNotNull(detected.baseline).bpm, 0.0)
            assertEquals(105, detected.measurement?.bpm)
            val summary = history.sessions().first().first()
            assertFalse(summary.declaredRest)
            val episode = history.episodes(summary.id).first().single()
            assertEquals(105, episode.progress.peakBpm)
            assertTrue(episode.progress.durationMs >= 15_000)
            // Espera el cierre antes de liberar la base de datos de la prueba.
            viewModel.uiState.first { !it.isRunning }
        }
    }

    @Test
    fun interruptedTransportExpiresAndCanReconnectWithFreshParser() = runBlocking {
        withTestMonitor { viewModel, history, elapsed ->
            suspend fun open(channel: Channel<String>) {
                withContext(Dispatchers.Main) {
                    viewModel.startSession(isBle = true, declaredRest = false) { ready ->
                        object : MeasurementSource {
                            override fun chunks() = flow {
                                ready()
                                for (chunk in channel) emit(chunk)
                            }
                        }
                    }
                }
            }

            val first = Channel<String>(4)
            open(first)
            first.send("HB1,SEQ=900001,BPM=075,")
            first.send("IBI=0800,Q=1\n")
            viewModel.uiState.first { it.status == ReadingStatus.VALID }
            elapsed.set(4_000)
            val stale = viewModel.uiState.first { it.status == ReadingStatus.STALE }
            assertNull(stale.measurement)
            assertEquals(listOf(75), stale.recentBpm)
            first.send("HB1,SEQ=900002,BPM=100,")
            first.close(BleFailure("Enlace interrumpido en la prueba", disconnected = true))
            val disconnected = viewModel.uiState.first { it.status == ReadingStatus.DISCONNECTED }
            assertNull(disconnected.measurement)
            assertFalse(disconnected.isRunning)

            val second = Channel<String>(4)
            open(second)
            second.send("HB1,SEQ=000001,BPM=081,IBI=0740,Q=1\n")
            val reconnected = viewModel.uiState.first { it.status == ReadingStatus.VALID }
            assertEquals(81, reconnected.measurement?.bpm)
            assertEquals(1, reconnected.receivedCount)
            assertEquals(0, reconnected.errorCount)
            assertEquals(2, history.sessions().first().size)
            second.close()
            viewModel.uiState.first { it.status == ReadingStatus.DISCONNECTED }
        }
    }

    private suspend fun withTestMonitor(
        block: suspend (HealthViewModel, HistoryRepository, AtomicLong) -> Unit
    ) {
        val application = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application
        val database = Room.inMemoryDatabaseBuilder(application, HealthDatabase::class.java).build()
        val repository = HistoryRepository(database)
        val elapsed = AtomicLong(0)
        val monitor = HealthViewModel(application, 4_000, repository, elapsed::get)
        try {
            withTimeout(12_000) { block(monitor, repository, elapsed) }
        } finally {
            withContext(Dispatchers.Main) { monitor.stopSession() }
            monitor.viewModelScope.coroutineContext[Job]?.children?.toList()?.joinAll()
            database.close()
        }
    }
}
