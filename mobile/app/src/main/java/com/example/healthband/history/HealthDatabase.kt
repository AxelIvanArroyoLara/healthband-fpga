package com.example.healthband.history

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/** Mantiene una única base privada por proceso de la aplicación. */
@Database(entities = [SessionEntity::class, SampleEntity::class], version = 1)
abstract class HealthDatabase : RoomDatabase() {
    abstract fun historyDao(): HistoryDao

    companion object {
        @Volatile private var instance: HealthDatabase? = null

        fun get(context: Context): HealthDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(
                context.applicationContext, HealthDatabase::class.java, "healthband.db"
            ).build().also { instance = it }
        }
    }
}
