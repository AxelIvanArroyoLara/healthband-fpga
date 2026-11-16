package com.example.healthband.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.healthband.analysis.EpisodeContext
import com.example.healthband.history.HealthDatabase
import com.example.healthband.history.HistoryEpisode
import com.example.healthband.history.HistoryRepository
import com.example.healthband.history.HistorySample
import com.example.healthband.history.SessionSummary
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Selecciona páginas de una sesión y gestiona las acciones sobre el historial. */
@OptIn(ExperimentalCoroutinesApi::class)
class HistoryViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = HistoryRepository(HealthDatabase.get(application))
    private val selection = MutableStateFlow<HistoryPage?>(null)
    val selectedPage = selection.asStateFlow()
    private val failure = MutableStateFlow<String?>(null)
    val error = failure.asStateFlow()

    val sessions = repository.sessions()
        .catch { failure.value = "No se pudo leer el historial" }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList<SessionSummary>())

    val details = selection.flatMapLatest { page ->
        if (page == null) flowOf(null) else repository.samples(page.sessionId, page.offset)
            .map { HistoryDetail(page, it) }
            .catch { failure.value = "No se pudieron leer las muestras de la sesión" }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val episodes = selection.map { it?.sessionId }.distinctUntilChanged().flatMapLatest { id ->
        if (id == null) flowOf(null) else repository.episodes(id)
            .map { HistoryEpisodes(id, it) }
            .catch { failure.value = "No se pudieron leer los episodios de la sesión" }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** Guarda el contexto seleccionado por el usuario para un episodio. */
    fun annotate(sessionId: Long, episode: Long, context: EpisodeContext) {
        viewModelScope.launch {
            try {
                repository.setEpisodeContext(sessionId, episode, context)
                failure.value = null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                failure.value = "No se pudo guardar el contexto"
            }
        }
    }

    fun select(id: Long) {
        selection.value = HistoryPage(id, 0)
    }

    fun closeDetails() {
        selection.value = null
    }

    fun changePage(offset: Long) {
        selection.value = selection.value?.copy(offset = offset.coerceAtLeast(0))
    }

    /** Elimina una sesión o todo el historial después de la confirmación de la interfaz. */
    fun delete(id: Long?) {
        viewModelScope.launch {
            try {
                if (id == null) repository.deleteAll() else repository.delete(id)
                if (id == null || selection.value?.sessionId == id) closeDetails()
                failure.value = null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                failure.value = "No se pudo eliminar el historial"
            }
        }
    }
}

/** Posición de una página de muestras, ordenadas desde el final de la sesión. */
data class HistoryPage(val sessionId: Long, val offset: Long)

/** Muestras que pertenecen a la página solicitada. */
data class HistoryDetail(val page: HistoryPage, val samples: List<HistorySample>)


/** Episodios correspondientes a la sesión consultada. */
data class HistoryEpisodes(val sessionId: Long, val episodes: List<HistoryEpisode>)
