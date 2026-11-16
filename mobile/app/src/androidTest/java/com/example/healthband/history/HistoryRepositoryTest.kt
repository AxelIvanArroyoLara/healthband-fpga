package com.example.healthband.history

import android.content.Context
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.healthband.analysis.AnomalyConfig
import com.example.healthband.analysis.EpisodeContext
import com.example.healthband.analysis.EpisodeProgress
import com.example.healthband.model.Measurement
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Comprueba reapertura de SQLite, estadísticas e integridad referencial en Android. */
@RunWith(AndroidJUnit4::class)
class HistoryRepositoryTest {
    @Test
    fun sessionSurvivesReopeningAndDeletionCascades() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-${UUID.randomUUID()}.db"
        try {
            val sessionId = withDatabase(context, name) { database ->
                val repository = HistoryRepository(database)
                val id = repository.begin(true, 100)
                repository.record(id, Measurement(1, 60, 1_000, true, 200), startsSegment = true)
                repository.record(id, Measurement(2, 200, 300, false, 300), startsSegment = false)
                repository.record(id, Measurement(3, 80, 750, true, 400), startsSegment = true)
                repository.finish(id, 500)
                id
            }
            withDatabase(context, name) { database ->
                val repository = HistoryRepository(database)
                val summary = repository.sessions().first().single()
                assertEquals(100L, summary.startedAtMs)
                assertEquals(500L, summary.endedAtMs)
                assertEquals(2L, summary.validCount)
                assertEquals(70.0, requireNotNull(summary.averageBpm), 0.0)
                assertEquals(60, summary.minBpm)
                assertEquals(80, summary.maxBpm)
                assertEquals(listOf(60, 80), repository.samples(sessionId, 0).first().map { it.bpm })
                assertTrue(database.historyDao().samples(sessionId, 10, 0).first().all { it.quality == 1 })
                repository.delete(sessionId)
                assertTrue(repository.samples(sessionId, 0).first().isEmpty())
                repository.begin(false, 600)
                repository.begin(false, 700)
                repository.deleteAll()
                assertTrue(repository.sessions().first().isEmpty())
            }
        } finally {
            context.deleteDatabase(name)
        }
        Unit
    }

    @Test
    fun baselineExcludesOtherSourcesAndEpisodesAndPreservesAnnotations() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val database = Room.inMemoryDatabaseBuilder(context, HealthDatabase::class.java).build()
        try {
            val repository = HistoryRepository(database)
            val config = AnomalyConfig(minimumSessionSamples = 2)
            val measure = Measurement(1, 70, 880, true, 200)
            suspend fun restSession(simulated: Boolean): Long {
                val id = repository.begin(simulated, 100, declaredRest = true)
                repeat(2) { repository.record(id, measure, startsSegment = it == 0) }
                repository.finish(id, 300)
                return id
            }
            val episodeSession = restSession(true)
            restSession(true)
            restSession(false)
            assertNull(repository.baseline(true, config))
            restSession(true)
            assertEquals(70.0, requireNotNull(repository.baseline(true, config)).bpm, 0.0)

            val episode = EpisodeProgress(400, 200, 15_000, 110, 70.0)
            repository.record(episodeSession, measure, false, episode)
            repository.setEpisodeContext(episodeSession, 400, EpisodeContext.ACTIVITY)
            repository.record(episodeSession, measure, false, episode.copy(durationMs = 16_000))
            assertNull(repository.baseline(true, config))
            val saved = repository.episodes(episodeSession).first().single()
            assertEquals(16_000L, saved.progress.durationMs)
            assertEquals(EpisodeContext.ACTIVITY, saved.context)
            repository.delete(episodeSession)
            assertTrue(repository.episodes(episodeSession).first().isEmpty())
        } finally {
            database.close()
        }
        Unit
    }

    private suspend fun <T> withDatabase(
        context: Context,
        name: String,
        block: suspend (HealthDatabase) -> T
    ): T {
        val database = Room.databaseBuilder(context, HealthDatabase::class.java, name).build()
        return try {
            block(database)
        } finally {
            database.close()
        }
    }
}
