package com.example.healthband.history

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
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
        SELECT s.id, s.startedAtMs, s.endedAtMs, s.simulated,
            COUNT(m.id) AS validCount, AVG(m.bpm) AS averageBpm,
            MIN(m.bpm) AS minBpm, MAX(m.bpm) AS maxBpm
        FROM sessions s LEFT JOIN samples m ON s.id = m.sessionId
        GROUP BY s.id ORDER BY s.id DESC
    """)
    fun sessions(): Flow<List<SessionSummary>>

    @Query("SELECT * FROM samples WHERE sessionId = :id ORDER BY id DESC LIMIT :limit OFFSET :offset")
    fun samples(id: Long, limit: Int, offset: Long): Flow<List<SampleEntity>>

    @Query("DELETE FROM sessions WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("DELETE FROM sessions")
    suspend fun deleteAll()
}
