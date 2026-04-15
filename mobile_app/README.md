# PAE Mobile (Flutter)

Cliente movil para la aplicacion PAE (gestion de rutas, pedidos y recogidas).

## Objetivo de stack

- Backend: Python + FastAPI (API REST + WebSocket)
- Frontend movil: Flutter + Dart

Toda la logica de app se mantiene en Dart. No hace falta escribir Java, Kotlin, C++ o Swift para el flujo funcional.

## Estado actual

Este directorio ya incluye:

- Estructura base de Flutter en `lib/`
- Login y sesion persistente
- Pantalla central para crear/asignar pedidos
- Pantalla repartidor para responder recogidas, actualizar estado y enviar ubicacion
- Integracion REST y WebSocket con el backend existente

## Primer arranque

1. Instalar Flutter SDK
2. Desde este directorio, generar wrappers de plataforma (Android/iOS):
   - `flutter create .`
3. Instalar dependencias:
   - `flutter pub get`
4. Ejecutar en emulador/dispositivo:
   - `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000`

Notas:

- En Android Emulator, `10.0.2.2` apunta al localhost del host.
- En iOS Simulator suele funcionar `http://localhost:8000`.

## Credenciales demo

- Central: `central` / `central123`
- Repartidor: `driver1` / `driver123`
- Repartidor: `driver2` / `driver123`
