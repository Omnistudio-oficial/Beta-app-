# OmniStudio

OmniStudio es una app multiplataforma de productividad y entretenimiento que combina IA, creación de contenido, comunicación en tiempo real y herramientas de trabajo colaborativo en un mismo ecosistema.

El repositorio incluye una aplicación Android nativa desarrollada en Kotlin y una aplicación Flutter complementaria, además de servicios, configuraciones y documentación para potenciar la experiencia completa del producto.

## Descripción general

La solución está orientada a ofrecer una suite todo-en-uno con:

- Editor y gestión de documentos
- Herramientas de creación musical y edición de audio
- Mensajería y chat en tiempo real
- Integración con IA para asistentes, traducción y generación de contenido
- Funcionalidad multimedia con cámara, audio, video y almacenamiento
- Autenticación con Firebase y experiencia de usuario moderna

## Stack tecnológico

### Android / Kotlin
- Jetpack Compose
- Kotlin + coroutines
- Room
- Firebase
- Firestore / Realtime Database / Cloud Messaging
- ML Kit para identificación y traducción de idiomas
- MediaPipe para visión computacional
- WebRTC para comunicación en tiempo real
- MapLibre + OpenStreetMap
- Retrofit + OkHttp + Moshi

### Flutter
- Flutter SDK
- Dart
- Estructura modular para frontend de app móvil

### Infraestructura y servicios
- Firebase Analytics, Crashlytics y Authentication
- Supabase para almacenamiento multimedia y chat
- OpenRouteService para rutas y geocodificación
- Gemini AI y servicios de IA asociados

## Estructura del repositorio

```text
.
├── app/                  # Aplicación Android principal (Kotlin)
│   ├── src/
│   ├── build.gradle.kts
│   └── proguard-rules.pro
├── flutter_app/          # Aplicación Flutter
│   ├── lib/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── README.md
├── docs/                 # Documentación técnica y guías
├── public/               # Recursos públicos del proyecto
├── scripts/              # Scripts auxiliares
├── supabase/             # Configuración relacionada con Supabase
├── .env.example          # Variables de entorno de ejemplo
├── build.gradle.kts      # Configuración raíz de Gradle
├── settings.gradle.kts   # Configuración del proyecto Gradle
├── gradle.properties     # Propiedades del sistema de compilación
├── metadata.json         # Metadatos del proyecto
├── database.rules.json   # Reglas de Firebase Realtime Database
├── .gitignore
└── README.md
```

## Funcionalidades principales

- Autenticación y seguridad con Firebase
- Chat en tiempo real con mensajes y multimedia
- Integración con IA generativa
- Cámara, video y efectos visuales
- Traducción local y reconocimiento de idioma
- Geolocalización y mapas
- Gestión persistent de datos con Room y Firebase
- Notificaciones y eventos del sistema
- Soporte para almacenamiento de medios con Supabase

## Requisitos

Antes de compilar el proyecto necesitas:

- Android Studio
- JDK 11+
- Android SDK con nivel de API compatible
- Firebase project configurado
- Claves de API para los servicios integrados

## Configuración de entorno

Copia el archivo `.env.example` como `.env` y completa los valores necesarios:

```env
GEMINI_API_KEY=tu_clave
MAPS_API_KEY=tu_clave
OPENROUTESERVICE_API_KEY=tu_clave
GIPHY_API_KEY=tu_clave
KLIPY_API_KEY=tu_clave
SUPABASE_PROJECT_URL=https://tu-proyecto.supabase.co
SUPABASE_PUBLISHABLE_KEY=tu_key_publica
```

El proyecto usa el plugin de secretos para leer estas variables en la compilación y en tiempo de ejecución.

## Ejecución

### Android

```bash
./gradlew assembleDebug
```

O abre el proyecto en Android Studio y ejecuta la app en un emulador o dispositivo físico.

### Flutter

```bash
cd flutter_app
flutter pub get
flutter run
```

## Documentación

El directorio `docs/` contiene guías útiles sobre integración con:

- Groq Workspace connectors
- Carga de media en chat con Supabase
- Notificaciones de chat
- Eliminación de media en Supabase

## Notas importantes

- La configuración de Firebase y claves sensibles no debe subirse al repositorio.
- Usa variables de entorno o secretos del entorno de compilación para no exponer datos privados.
- El proyecto está preparado para desarrollo moderno con Compose, servicios cloud y capacidades de IA.

## Licencia

Este repositorio no incluye un archivo de licencia explícito en la raíz. Si necesitas definir una licencia para publicación o distribución, es recomendable añadir una según el uso del proyecto.

## Contacto

Para más información sobre el proyecto o su evolución, consulta el repositorio de GitHub y la documentación interna incluida en `docs/`.
