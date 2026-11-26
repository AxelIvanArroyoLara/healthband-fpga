# APK Android

Ambos APK se compilaron con el código móvil del commit
`ee7bd39e671b1bfaeec35bf9fd1d3707d88a3b97`. Los reportes de cobertura
posteriores corresponden a la misma app con pruebas adicionales.

| Archivo | Uso |
| --- | --- |
| `app-debug.apk` | Firmado con certificado de desarrollo e instalable en un teléfono con Android API 24 o posterior |
| `app-release-unsigned.apk` | Release optimizado. Requiere firma antes de poder instalarse |

Verifica las sumas con `shasum -a 256 -c SHA256SUMS.txt` desde esta carpeta
y ejecuta `adb install -r app-debug.apk` con el teléfono autorizado.
Consulta [instalación, ADB y recompilación](../README.md) y los
[reportes](../evidence/README.md).
