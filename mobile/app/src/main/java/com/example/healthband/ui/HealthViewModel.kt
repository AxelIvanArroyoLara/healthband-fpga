
package com.example.healthband.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.healthband.data.MeasurementRepository
import com.example.healthband.data.SimulatedMeasurementSource
import com.example.healthband.model.Measurement
import com.example.healthband.protocol.ParseResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Representa toda la información necesaria para mostrar la pantalla.
 *
 * @property isRunning Indica si el simulador está activo.
 * @property measurement Última medición aceptada.
 * @property status Estado descriptivo de la simulación.
 * @property receivedCount Número de mediciones aceptadas.
 * @property errorCount Número de tramas rechazadas.
 * @property lastError Descripción del último error detectado.
 */
data class HealthUiState(
    val isRunning: Boolean = false,
    val measurement: Measurement? = null,
    val status: String = "Simulador detenido",
    val receivedCount: Int = 0,
    val errorCount: Int = 0,
    val lastError: String? = null
)

/**
 * ViewModel principal de HealthBand.
 *
 * Coordina el repositorio de mediciones y publica un estado
 * observable para la interfaz Jetpack Compose.
 *
 * La pantalla no necesita conocer el origen de los datos
 * ni interactuar directamente con el parser.
 */
class HealthViewModel : ViewModel() {

    // Repositorio configurado inicialmente con datos simulados.
    private val repository = MeasurementRepository(
        source = SimulatedMeasurementSource()
    )

    // Estado interno modificable exclusivamente desde el ViewModel.
    private val _uiState = MutableStateFlow(HealthUiState())

    // Estado de solo lectura expuesto a la interfaz.
    val uiState: StateFlow<HealthUiState> = _uiState.asStateFlow()

    // Trabajo asíncrono utilizado para controlar la simulación.
    private var simulationJob: Job? = null

    /**
     * Inicia una sesión de simulación.
     *
     * No crea una segunda sesión si ya existe una activa.
     */
    fun startSimulation() {

        if (simulationJob?.isActive == true) {
            return
        }

        // Una nueva sesión comienza con estado y contadores limpios.
        _uiState.value = HealthUiState(
            isRunning = true,
            status = "Esperando mediciones..."
        )

        simulationJob = viewModelScope.launch {

            try {

                repository.measurements().collect { result ->

                    when (result) {

                        is ParseResult.Success -> {
                            handleMeasurement(result.measurement)
                        }

                        is ParseResult.Error -> {
                            handleError(result.reason)
                        }
                    }
                }

            } catch (exception: CancellationException) {

                // La cancelación normal no debe presentarse como error.
                throw exception

            } catch (exception: Exception) {

                // Un fallo inesperado detiene y limpia la lectura.
                _uiState.update {
                    it.copy(
                        measurement = null,
                        status = "Error del simulador",
                        lastError = exception.message
                    )
                }

            } finally {

                // Garantiza que el estado refleje el fin del trabajo.
                _uiState.update {
                    it.copy(isRunning = false)
                }
            }
        }
    }

    /**
     * Actualiza el estado con una medición aceptada.
     *
     * Las mediciones inválidas no se muestran como BPM actuales.
     */
    private fun handleMeasurement(measurement: Measurement) {

        _uiState.update { current ->

            current.copy(
                measurement = measurement,
                status = if (measurement.isValid) {
                    "Simulación activa"
                } else {
                    "Sin señal válida"
                },
                receivedCount = current.receivedCount + 1,
                lastError = null
            )
        }
    }

    /**
     * Registra un error sin interrumpir toda la simulación.
     *
     * @param reason Motivo por el que se rechazó la trama.
     */
    private fun handleError(reason: String) {

        _uiState.update { current ->

            current.copy(
                errorCount = current.errorCount + 1,
                lastError = reason
            )
        }
    }

    /**
     * Detiene la simulación y descarta la medición actual.
     */
    fun stopSimulation() {

        simulationJob?.cancel()
        simulationJob = null

        _uiState.update {
            it.copy(
                isRunning = false,
                measurement = null,
                status = "Simulador detenido",
                lastError = null
            )
        }
    }

    /**
     * Libera el trabajo activo al destruirse el ViewModel.
     */
    override fun onCleared() {

        simulationJob?.cancel()

        super.onCleared()
    }
}
