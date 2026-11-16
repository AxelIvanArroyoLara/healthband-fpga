
package com.example.healthband

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import com.example.healthband.ui.HealthScreen

/**
 * Actividad principal de HealthBand.
 *
 * Es el punto de entrada de la aplicación Android.
 * Su única responsabilidad inicial es configurar Compose
 * y presentar la pantalla principal.
 */
class MainActivity : ComponentActivity() {

    /**
     * Inicializa la actividad y su contenido visual.
     *
     * @param savedInstanceState Estado anterior de la actividad,
     * si Android dispone de uno.
     */
    override fun onCreate(savedInstanceState: Bundle?) {

        super.onCreate(savedInstanceState)

        // Define el contenido de la actividad mediante Compose.
        setContent {

            // Aplica los estilos de Material Design 3.
            MaterialTheme {

                Surface {

                    // Muestra la pantalla principal de HealthBand.
                    HealthScreen()
                }
            }
        }
    }
}
