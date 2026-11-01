# Ejecutor Python local de OmniStudio

## Diseño

- La pantalla Flutter carga un HTML local mediante `webview_flutter`.
- El HTML crea un Web Worker y carga Pyodide `0.29.5` desde jsDelivr.
- El código que escribe la persona se ejecuta dentro del Worker, en el dispositivo. No se envía a AI Agent Ultimate, Firebase ni Supabase.
- El runtime se descarga la primera vez; por eso se necesita Internet para la inicialización. La ejecución posterior usa el runtime cargado en memoria mientras la pantalla siga abierta.
- El Worker bloquea las APIs habituales de red después de descargar Pyodide y solo permite una lista pequeña de módulos estándar de Python.

## Límites actuales

- Máximo 12.000 caracteres de código.
- Máximo 5 segundos por ejecución; al agotarse el tiempo se termina el Worker y se reinicia.
- Salida limitada a 12.000 caracteres.
- Sin acceso a archivos nativos, credenciales de la aplicación ni APIs de Firebase/Supabase.
- Módulos permitidos: math, statistics, random, datetime, json, re, collections, itertools, functools, decimal, fractions, string, textwrap y csv.

## Consideraciones de seguridad

Este ejecutor está diseñado para aprendizaje y scripts pequeños. El Worker es un aislamiento del navegador, no un sandbox reforzado para ejecutar código hostil. El límite de tiempo no equivale a un límite duro de memoria: un programa que consuma memoria excesiva todavía podría afectar el proceso WebView o la aplicación. No se debe usar para ejecutar código no confiable de terceros ni scripts que necesiten permisos elevados.

El runtime de Pyodide se obtiene de jsDelivr. El código del usuario se mantiene local, pero la descarga inicial del runtime sí genera una solicitud HTTPS al CDN. No se descargan paquetes adicionales desde el código del usuario.


## Integración con Sara AI

- Si la respuesta más reciente de Sara contiene un bloque Markdown etiquetado como `python` o `py`, la persona puede escribir una orden explícita como "Sara, ejecuta ese código" o "corre ese script".
- La aplicación reconoce la orden solo si el mensaje contiene una intención explícita de ejecutar y la respuesta inmediatamente anterior de Sara incluye un bloque Python de hasta 12.000 caracteres.
- La orden abre el ejecutor local y, cuando Pyodide termina de inicializarse, ejecuta ese bloque una sola vez sin requerir un botón adicional.
- No se ejecuta código por el simple hecho de que Sara lo genere o responda. Sin orden explícita y código en la respuesta inmediatamente anterior, el chat sigue su flujo normal.
- La extracción y el traspaso del bloque se realizan dentro de Flutter. El código no se envía una segunda vez a AI Agent Ultimate, Firebase ni Supabase.
- El ejecutor mantiene sus límites: 5 segundos por ejecución, 12.000 caracteres de entrada/salida y sin límite duro de memoria. No es un sandbox reforzado para código hostil.

## Verificación manual pendiente

1. Abrir AI Assistant > Ejecutor Python local.
2. Esperar el estado "Python listo".
3. Ejecutar el ejemplo inicial y verificar las raíces cuadradas y el total.
4. Probar `import os` y confirmar que la importación se bloquea.
5. Probar `while True: pass` y confirmar que el Worker se detiene al llegar a 5 segundos.
6. Desactivar Internet antes de abrir la pantalla por primera vez y confirmar que se muestra un error de inicialización claro.
7. Repetir en Android e iOS.

La incorporación al repositorio y la aprobación de CI no sustituyen estas pruebas en dispositivos reales.
