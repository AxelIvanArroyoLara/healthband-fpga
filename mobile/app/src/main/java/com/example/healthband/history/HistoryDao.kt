package com.example.healthband.history

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

/** Ejecuta las escrituras y agrega las estadísticas en SQLite. */
@Dao
interface HistoryDao {
    @Insert
    suspend fun insertSession(session: SessionEntity): Long

    @Insert
    suspend fun insertSample(sample: SampleEntity)

    @Query("UPDATE sessions SET endedAtMs = MAX(endedAtMs, :endedAtMs) WHERE id = :id")
    suspend fun updateEnd(id: Long, endedAtMs: Long)

    @Query("""
        SELECT s.id, s.startedAtMs, s.endedAtMs, s.simulated, s.declaredRest,
            COUNT(m.id) AS validCount, AVG(m.bpm) AS averageBpm,
            MIN(m.bpm) AS minBpm, MAX(m.bpm) AS maxBpm
        FROM sessions s LEFT JOIN samples m ON s.id = m.sessionId
        GROUP BY s.id ORDER BY s.id DESC
    """)
    fun sessions(): Flow<List<SessionSummary>>

    @Query("SELECT * FROM samples WHERE sessionId = :id ORDER BY id DESC LIMIT :limit OFFSET :offset")
    fun samples(id: Long, limit: Int, offset: Long): Flow<List<SampleEntity>>

    @Query("""
        SELECT s.id FROM sessions s
        WHERE s.declaredRest = 1 AND s.simulated = :simulated
            AND NOT EXISTS (SELECT 1 FROM episodes e WHERE e.sessionId = s.id)
            AND (SELECT COUNT(*) FROM samples m WHERE m.sessionId = s.id) >= :minimumSamples
        ORDER BY s.id DESC LIMIT 12
    """)
    suspend fun baselineSessionIds(simulated: Boolean, minimumSamples: Int): List<Long>

    @Query("SELECT bpm FROM samples WHERE sessionId = :id ORDER BY id DESC LIMIT :limit")
    suspend fun baselineSamples(id: Long, limit: Int): List<Int>

    @Upsert(entity = EpisodeEntity::class)
    suspend fun upsertEpisode(episode: EpisodeUpdate)

    @Query("SELECT * FROM episodes WHERE sessionId = :id ORDER BY startedElapsedMs DESC")
    fun episodes(id: Long): Flow<List<EpisodeEntity>>

    @Query("UPDATE episodes SET context = :context WHERE sessionId = :id AND startedElapsedMs = :episode")
    suspend fun setEpisodeContext(id: Long, episode: Long, context: String)

    @Query("DELETE FROM sessions WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM sessions")
    suspend fun deleteAll()
}
