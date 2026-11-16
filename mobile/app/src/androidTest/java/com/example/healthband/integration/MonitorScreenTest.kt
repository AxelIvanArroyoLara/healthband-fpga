package com.example.healthband.integration

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import com.example.healthband.MainActivity
import com.example.healthband.history.HealthDatabase
import com.example.healthband.history.HistoryRepository
import com.example.healthband.ui.HealthViewModel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Comprueba el simulador y la conservación del monitor al recrear la actividad. */
class MonitorScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun runningSimulationSurvivesRecreationAndAppearsInHistory() {
        val history = HistoryRepository(HealthDatabase.get(compose.activity))
        val previousIds = runBlocking { history.sessions().first().map { it.id }.toSet() }
        try {
            compose.onNodeWithText("Iniciar simulación").performScrollTo().performClick()
            awaitText("Medición válida")

            compose.activityRule.scenario.recreate()
            awaitText("Medición válida")
            compose.onNodeWithText("Detener simulación").performScrollTo().performClick()
            awaitText("Simulador detenido")
            compose.onNodeWithText("--").assertExists()

            compose.onNodeWithText("Historial").performClick()
            awaitText("Simulador")
            val newSessions = runBlocking { history.sessions().first().filter { it.id !in previousIds } }
            assertTrue(newSessions.single().validCount > 0)
        } finally {
            compose.activityRule.scenario.onActivity { activity ->
                ViewModelProvider(activity)[HealthViewModel::class.java].stopSession()
            }
            runBlocking {
                // Elimina únicamente los registros generados durante esta prueba del emulador.
                history.sessions().first().filter { it.id !in previousIds }.forEach { history.delete(it.id) }
            }
        }
    }

    private fun awaitText(text: String) {
        compose.waitUntil(timeoutMillis = 8_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
