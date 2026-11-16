package com.example.healthband.integration

import android.app.Application
import androidx.lifecycle.viewModelScope
import androidx.room.Room
import androidx.room.withTransaction
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.healthband.analysis.AnomalyStatus
import com.example.healthband.analysis.EpisodeProgress
import com.example.healthband.ble.BleFailure
import com.example.healthband.data.MeasurementSource
import com.example.healthband.data.SimulatedMeasurementSource
import com.example.healthband.history.HealthDatabase
import com.example.healthband.history.HistoryRepository
import com.example.healthband.history.SessionHistory
import com.example.healthband.model.Measurement
import com.example.healthband.ui.HealthViewModel
import com.example.healthband.ui.ReadingStatus
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Integra las fuentes, el monitor, el detector y Room sin periférico físico. */
@RunWith(AndroidJUnit4::class)
class AcquisitionTest {
    @Test
    fun simulatorPersistsSustainedEpisodeUsingCalibratedHistory() = runBlocking {
        withTestMonitor { viewModel, history, elapsed, _ ->
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
            viewModel.uiState.first { !it.isRunning && !it.historyBusy }
            val summary = history.sessions().first().first()
            assertFalse(summary.declaredRest)
            val episode = history.episodes(summary.id).first().single()
            assertEquals(105, episode.progress.peakBpm)
            assertTrue(episode.progress.durationMs >= 15_000)
        }
    }

    @Test
    fun interruptedTransportExpiresAndCanReconnectWithFreshParser() = runBlocking {
        withTestMonitor { viewModel, history, elapsed, _ ->
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
            viewModel.uiState.first { it.persistedCount == 1 }
            assertEquals(2, history.sessions().first().size)
            second.close()
            viewModel.uiState.first { it.status == ReadingStatus.DISCONNECTED }
        }
    }

    /** Una transacción retenida no debe ocultar lecturas que el parser ya aceptó. */
    @Test
    fun roomWriteLockDoesNotDelayLiveReading() = runBlocking {
        withTestMonitor { monitor, _, _, database ->
            val input = Channel<String>(4)
            withContext(Dispatchers.Main) {
                monitor.startSession(isBle = false, declaredRest = false) {
                    object : MeasurementSource {
                        override fun chunks() = flow { for (chunk in input) emit(chunk) }
                    }
                }
            }
            input.send("HB1,SEQ=000001,BPM=075,IBI=0800,Q=1\n")
            monitor.uiState.first { it.persistedCount == 1 }
            coroutineScope {
                val locked = CompletableDeferred<Unit>()
                val release = CompletableDeferred<Unit>()
                launch {
                    database.withTransaction {
                        locked.complete(Unit)
                        release.await()
                    }
                }
                locked.await()
                try {
                    input.send("HB1,SEQ=000002,BPM=080,IBI=0750,Q=1\n")
                    val reading = withTimeoutOrNull(1_000) {
                        monitor.uiState.first { it.measurement?.bpm == 80 }
                    }
                    assertNotNull("Room bloqueó una lectura en vivo", reading)
                } finally {
                    release.complete(Unit)
                    input.close()
                }
            }
        }
    }

    /** Un fallo confirmado por el escritor no altera la lectura ni el estado de BLE. */
    @Test
    fun storageFailureKeepsBleReadingsAndCommittedPrefix() = runBlocking {
        withTestMonitor(historyFactory = { repository ->
            object : SessionHistory by repository {
                override suspend fun record(
                    id: Long, measurement: Measurement, startsSegment: Boolean, episode: EpisodeProgress?
                ) {
                    throw IOException("Fallo de escritura inyectado")
                }
            }
        }) { monitor, history, _, _ ->
            val input = Channel<String>(4)
            val closed = CompletableDeferred<Unit>()
            startInput(monitor, input, closed, isBle = true)
            input.send(frame(1, 75))
            monitor.uiState.first { it.persistedCount == 1 }
            input.send(frame(2, 80))
            monitor.uiState.first { it.storageError != null }
            input.send(frame(3, 85))
            val state = monitor.uiState.first { it.measurement?.bpm == 85 }
            assertEquals(ReadingStatus.VALID, state.status)
            assertEquals(3, state.receivedCount)
            assertEquals(1, state.persistedCount)
            assertEquals(0, state.errorCount)
            assertFalse(closed.isCompleted)
            assertEquals(1L, history.sessions().first().single().validCount)
        }
    }

    /** La fuente se cierra al detenerse y la sesión siguiente conserva únicamente sus propias muestras. */
    @Test
    fun stoppingDuringWriteAllowsOneImmediateRestartWithSeparateRoomSessions() = runBlocking {
        val inWrite = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        withTestMonitor(historyFactory = { repository ->
            object : SessionHistory by repository {
                override suspend fun record(
                    id: Long, measurement: Measurement, startsSegment: Boolean, episode: EpisodeProgress?
                ) {
                    inWrite.complete(Unit)
                    release.await()
                    repository.record(id, measurement, startsSegment, episode)
                }
            }
        }) { monitor, history, _, _ ->
            val oldInput = Channel<String>(4)
            val oldClosed = CompletableDeferred<Unit>()
            startInput(monitor, oldInput, oldClosed)
            oldInput.send(frame(1, 70))
            monitor.uiState.first { it.persistedCount == 1 }
            oldInput.send(frame(2, 72))
            inWrite.await()
            try {
                withContext(Dispatchers.Main) { monitor.stopSession() }
                oldClosed.await()
                assertNull(monitor.uiState.value.measurement)

                val nextInput = Channel<String>(4)
                val nextClosed = CompletableDeferred<Unit>()
                startInput(monitor, nextInput, nextClosed, isBle = true)
                startInput(monitor, Channel(4), CompletableDeferred())
                assertEquals(0, monitor.uiState.value.receivedCount)
                nextInput.send(frame(1, 91))
                release.complete(Unit)
                val next = monitor.uiState.first { it.persistedCount == 1 }
                assertEquals(91, next.measurement?.bpm)
                assertEquals(listOf(91), next.recentBpm)
                val sessions = history.sessions().first()
                assertEquals(2, sessions.size)
                assertEquals(listOf(false, true), sessions.map { it.simulated })
                assertEquals(listOf(91), history.samples(sessions[0].id, 0).first().map { it.bpm })
                assertEquals(listOf(70, 72), history.samples(sessions[1].id, 0).first().map { it.bpm })
                withContext(Dispatchers.Main) { monitor.stopSession() }
                nextClosed.await()
            } finally {
                release.complete(Unit)
            }
        }
    }

    /** Al llenar la cola se conserva un prefijo de datos sin pausar el dashboard. */
    @Test
    fun queueOverflowKeepsLiveReadingsAndStoresOnlyBoundedPrefix() = runBlocking {
        val firstWrite = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        withTestMonitor(historyFactory = { repository ->
            object : SessionHistory by repository {
                override suspend fun recordFirst(
                    simulated: Boolean, declaredRest: Boolean, measurement: Measurement, episode: EpisodeProgress?
                ): Long {
                    firstWrite.complete(Unit)
                    release.await()
                    return repository.recordFirst(simulated, declaredRest, measurement, episode)
                }
            }
        }) { monitor, history, _, _ ->
            val input = Channel<String>(64)
            startInput(monitor, input, CompletableDeferred())
            input.send(frame(1, 75))
            firstWrite.await()
            try {
                for (seq in 2..50) input.send(frame(seq, 75))
                val state = monitor.uiState.first { it.receivedCount == 50 }
                assertTrue(state.storageError.orEmpty().contains("saturó"))
                assertEquals(0, state.persistedCount)
                assertEquals(ReadingStatus.VALID, state.status)
            } finally {
                release.complete(Unit)
            }
            input.close()
            monitor.uiState.first { !it.isRunning && !it.historyBusy }
            assertEquals(33L, history.sessions().first().single().validCount)
        }
    }

    /** Cancelar el ámbito propietario detiene tanto la fuente como la escritura pendiente. */
    @Test
    fun ownerCancellationReleasesSourceAndDiscardsUncommittedWork() = runBlocking {
        val inWrite = CompletableDeferred<Unit>()
        val writeClosed = CompletableDeferred<Unit>()
        withTestMonitor(historyFactory = { repository ->
            object : SessionHistory by repository {
                override suspend fun recordFirst(
                    simulated: Boolean, declaredRest: Boolean, measurement: Measurement, episode: EpisodeProgress?
                ): Long {
                    inWrite.complete(Unit)
                    try {
                        kotlinx.coroutines.awaitCancellation()
                    } finally {
                        writeClosed.complete(Unit)
                    }
                }
            }
        }) { monitor, history, _, _ ->
            val input = Channel<String>(4)
            val sourceClosed = CompletableDeferred<Unit>()
            startInput(monitor, input, sourceClosed)
            input.send(frame(1, 75))
            inWrite.await()
            withContext(Dispatchers.Main) { monitor.viewModelScope.cancel() }
            sourceClosed.await()
            writeClosed.await()
            assertTrue(history.sessions().first().isEmpty())
            assertNull(monitor.uiState.value.storageError)
        }
    }

    private suspend fun startInput(
        monitor: HealthViewModel,
        input: Channel<String>,
        closed: CompletableDeferred<Unit>,
        isBle: Boolean = false
    ) = withContext(Dispatchers.Main) {
        monitor.startSession(isBle, declaredRest = false) { ready ->
            object : MeasurementSource {
                override fun chunks() = flow {
                    if (isBle) ready()
                    try {
                        for (chunk in input) emit(chunk)
                    } finally {
                        closed.complete(Unit)
                    }
                }
            }
        }
    }

    private fun frame(sequence: Int, bpm: Int) =
        "HB1,SEQ=${sequence.toString().padStart(6, '0')},BPM=${bpm.toString().padStart(3, '0')},IBI=0800,Q=1\n"

    private suspend fun withTestMonitor(
        historyFactory: (HistoryRepository) -> SessionHistory = { it },
        block: suspend (HealthViewModel, HistoryRepository, AtomicLong, HealthDatabase) -> Unit
    ) {
        val application = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application
        val database = Room.inMemoryDatabaseBuilder(application, HealthDatabase::class.java).build()
        val repository = HistoryRepository(database)
        val elapsed = AtomicLong(0)
        val monitor = HealthViewModel(application, 4_000, historyFactory(repository), elapsed::get)
        try {
            withTimeout(12_000) { block(monitor, repository, elapsed, database) }
        } finally {
            withContext(Dispatchers.Main) { monitor.stopSession() }
            monitor.viewModelScope.coroutineContext[Job]?.children?.toList()?.joinAll()
            database.close()
        }
    }
}
