# OmniStudio

OmniStudio es una suite de productividad y entretenimiento creada para combinar IA, creación de contenido, comunicación en tiempo real y herramientas colaborativas dentro de una misma experiencia digital.

El proyecto se encuentra en desarrollo activo y su planificación se gestiona en el board de GitHub: https://github.com/orgs/Omnistudio-oficial/projects/1

## Estado actual del proyecto

El repositorio refleja la evolución del producto en tres niveles principales:

- Desarrollo de la aplicación Android nativa con Kotlin y Jetpack Compose
- Prototipo y evolución de la app Flutter para experiencias multiplataforma
- Integración de infraestructura cloud con Firebase, Supabase, IA y servicios multimedia

Actualmente el proyecto está en una fase de consolidación funcional, con foco en:

- autenticación y usuarios
- mensajería en tiempo real
- almacenamiento multimedia
- servicios de IA y automatización
- experiencia móvil moderna
- integración de mapas, audio y video

## Roadmap y cronograma

### Fase 1 - Base del producto (Completada)
- infraestructura del repositorio
- configuración inicial de Gradle y Android
- estructura modular de la app
- integraciones base con Firebase y servicios externos

### Fase 2 - Core app y UX (En progreso)
- autenticación con Firebase y Google Sign-In
- chat en tiempo real
- flujo de mensajes y multimedia
- gestión de datos con Room y servicios cloud

### Fase 3 - IA y productividad (En desarrollo)
- asistentes y generación de contenido
- traducción y reconocimiento de idioma
- editor/documentos y funciones de productividad
- flujo de video, audio y contenido creativo

### Fase 4 - Multiplataforma y release (Próximo)
- estabilización de Flutter app
- pruebas de integración y QA
- despliegue y validación de producción
- preparación de release y documentación final

## Visión del producto

La intención del proyecto es ofrecer una suite todo-en-uno con:

- editor y gestión de documentos
- generación musical y edición de audio
- mensajería instantánea y realtime
- asistentes con IA para ayuda, traducción y generación de contenido
- multimedia, cámara, video y medios compartidos
- experiencias móviles modernas y colaborativas

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
- arquitectura para app móvil complementaria

### Infraestructura y servicios
- Firebase Analytics, Crashlytics y Authentication
- Supabase para almacenamiento y chat multimedia
- OpenRouteService para rutas y geocodificación
- Gemini AI y servicios de IA

## Estructura del repositorio

```text
.
├── app/                  # Aplicación Android principal (Kotlin)
│   ├── src/
│   ├── build.gradle.kts
│   └── proguard-rules.pro
├── flutter_app/          # Aplicación Flutter complementaria
│   ├── lib/
│   ├── android/
│   ├── ios/
│   ├── pubspec.yaml
│   └── README.md
├── docs/                 # Documentación técnica y guías
├── public/               # Recursos públicos del proyecto
├── scripts/              # Scripts auxiliares
├── supabase/             # Configuración de Supabase
├── .env.example          # Variables de entorno de ejemplo
├── build.gradle.kts      # Configuración raíz de Gradle
├── settings.gradle.kts   # Configuración del proyecto Gradle
├── gradle.properties     # Propiedades del sistema de compilación
├── metadata.json         # Metadatos del proyecto
├── database.rules.json   # Reglas de Firebase Realtime Database
├── .gitignore
├── README.md
└── LICENSE               # si se agrega más adelante
```

## Funcionalidades principales

- autenticación y seguridad con Firebase
- chat en tiempo real con mensajes y multimedia
- integración con IA generativa
- captura de cámara, video y efectos visuales
- traducción local y reconocimiento de idioma
- geolocalización y mapas
- persistencia de datos con Firebase y Room
- notificaciones y eventos de sistema
- soporte para almacenamiento de medios con Supabase

## Requisitos

Antes de compilar el proyecto necesitas:

- Android Studio
- JDK 11 o superior
- Android SDK
- proyecto de Firebase configurado
- claves de API para Google, Gemini, Supabase, OpenRouteService y otros servicios

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

El proyecto usa el plugin de secretos para leer estas variables durante la compilación y ejecución.

## Ejecución

### Android

```bash
./gradlew assembleDebug
```

O abre el proyecto desde Android Studio y ejecuta la app en un emulador o dispositivo físico.

### Flutter

```bash
cd flutter_app
flutter pub get
flutter run
```

## Documentación y seguimiento

El proyecto cuenta con documentación técnica en `docs/` y seguimiento de tareas y avances en el GitHub Project:

- Project board: https://github.com/orgs/Omnistudio-oficial/projects/1
- Documentación técnica: `docs/`
- Guías de integración de Supabase, chat y media

## Notas importantes

- no subir claves ni secretos al repositorio
- usar variables de entorno o secretos del entorno de compilación
- mantener sincronizado el README con el estado real del board del proyecto
- priorizar QA, validación funcional y estabilidad antes de release final

## Licencia

Este repositorio no tiene una licencia explícita definida aún en la raíz. Si se va a publicar o distribuir públicamente, se recomienda añadir una licencia adecuada al proyecto.

## Contacto

Para más información sobre el estado del proyecto, cambios en desarrollo o próximas entregas, revisar el repositorio y el board oficial del proyecto en GitHub.
