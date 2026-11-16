package com.example.healthband.history

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/** Registro local de un periodo de monitoreo y su último cierre confirmado. */
@Entity(tableName = "sessions")
data class SessionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val startedAtMs: Long,
    val endedAtMs: Long,
    val simulated: Boolean
)

/** Lectura con calidad válida. Una interrupción inicia un segmento nuevo de la gráfica. */
@Entity(
    tableName = "samples",
    foreignKeys = [ForeignKey(
        entity = SessionEntity::class,
        parentColumns = ["id"],
        childColumns = ["sessionId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index(value = ["sessionId", "id"])]
)
data class SampleEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sessionId: Long,
    val bpm: Int,
    val ibiMs: Int,
    val quality: Int,
    val receivedAtMs: Long,
    val startsSegment: Boolean
)
