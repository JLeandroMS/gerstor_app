# Documentación histórica: modo privado

Solo corresponde a «Archivos guardados en la app». Para el explorador del teléfono consultar README.md.

# Mis archivos — Flutter + SQLite, Android

Proyecto académico de un gestor de archivos local. Sin cuentas, Firebase, APIs ni conexión para las operaciones locales. Interfaz en español.

## 1. Preparar en Windows

1. Extraer el ZIP completo en una carpeta nueva, por ejemplo `C:\Users\steve\develop\gestor_archivos_sqlite`. No mezclar con un proyecto anterior.
2. Abrir esa carpeta en VS Code y abrir Terminal > Nueva terminal.
3. Ejecutar `flutter doctor`. Deben estar disponibles Flutter y Android toolchain. Si solicita licencias, ejecutar `flutter doctor --android-licenses` y aceptarlas.
4. Ejecutar ` .\preparar.bat ` (sin los espacios exteriores).
5. Este script genera la carpeta `android/` y el wrapper de Gradle con la plantilla de tu Flutter instalado; conserva el código incluido y descarga dependencias. Se requiere internet en la PC para esta preparación y la primera compilación. No se incluyen binarios ni APK precompilado.
6. Ejecutar `flutter analyze` y `flutter test`. Los tests de escritorio usan SQLite FFI. Si en Windows falta una DLL de SQLite, revisar la configuración de sqflite_common_ffi; eso no impide ejecutar SQLite nativo en Android.

Requiere Dart >=3.7 (incluido en Flutter moderno). No elegir Chrome ni Windows: la aplicación está dirigida a Android. Las dependencias directas están fijadas; conservar el `pubspec.lock` que genere `flutter pub get` en la entrega.

## 2. Preparar el teléfono

1. Ajustes > Acerca del teléfono > tocar 7 veces Número de compilación. En algunas marcas está dentro de Información de software o se llama Versión del sistema. Puede pedir PIN.
2. Buscar Opciones de desarrollador en Ajustes y activar Depuración USB.
3. Conectar con cable USB **de datos**, desbloquear y elegir Transferencia de archivos si aparece el menú USB.
4. Aceptar en el teléfono “¿Permitir depuración USB?” para esta computadora.
5. En algunas marcas hay un ajuste adicional “Instalar vía USB”; activarlo solo si el teléfono lo solicita para esta instalación.
6. En la terminal ejecutar `flutter devices`. Copiar el ID de la fila que indica Android.
7. Ejecutar `flutter run -d ID_DEL_TELEFONO`, sustituyendo ese texto por el ID real. No escribir los signos < >.
8. Esperar a que compile, instale y abra “Mis archivos”. Mantener el teléfono desbloqueado durante la instalación. Si pide permiso de instalación por USB, aceptarlo.

No necesitás instalar SQLite en el teléfono ni crear la base a mano: sqflite la crea al primer inicio. No necesita root ni permiso de acceso a todos los archivos.

## 3. Si no aparece el teléfono

- `unauthorized`: desbloquear el teléfono y aceptar la ventana de depuración.
- Sin dispositivo: probar otro cable de datos/puerto; revisar Depuración USB y controlador USB de la marca en Windows.
- `flutter devices` solo muestra Chrome o Windows: todavía no se detecta el Android.
- Se construyó un APK pero no apareció la app: `flutter build apk` solo construye. Ejecutar `flutter run -d ID` para instalar y abrir.
- Gradle o JDK: ejecutar `flutter doctor -v` y revisar el error concreto. La plantilla se genera con tu Flutter para evitar copiar versiones antiguas de Gradle. No editar versiones ni saltarse validaciones a ciegas.
- Error al abrir un PDF u otro archivo: instalar un visor compatible en el teléfono.

## 4. Usar la aplicación

- **Carpeta**: crea una carpeta en la ubicación actual.
- **Importar**: selecciona uno o varios archivos. Se guardan copias internas. Si hay un nombre repetido se agrega `(1)`, `(2)`, etc.
- **Seleccionar varios**: tocar el icono de lista con marcas en la barra superior, seleccionar elementos con las casillas o con pulsación larga, y utilizar los iconos para copiar, mover o crear un ZIP. Tocar Atrás para salir de la selección.
- **Copiar/mover varios**: elegir los elementos, tocar Copiar o Mover, abrir la carpeta de destino y tocar **Pegar**. El movimiento del lote es una sola transacción SQLite: si existe un conflicto no se mueve ninguno.
- **Comprimir ZIP**: seleccionar uno o varios elementos, pulsar el icono ZIP y asignar el nombre. También existe la opción **Comprimir en ZIP** en el menú de cada elemento. Conserva subcarpetas.
- **Extraer ZIP**: en el menú de un archivo `.zip`, tocar **Extraer ZIP aquí**. Se crea una carpeta nueva con el nombre del ZIP y se recuperan los archivos y subcarpetas. No admite archivos cifrados, enlaces ni rutas inseguras; se limita a 1000 entradas y 1 GB descomprimido.
- Tocar una carpeta para entrar o un archivo para abrir con un visor externo.
- Menú de tres puntos: renombrar, copiar, mover, compartir, detalles y eliminar.
- Para pegar en la raíz usar Atrás hasta `/Mis archivos`.
- Búsqueda global por nombre. Limpiar la búsqueda para volver a la carpeta actual y poder pegar.
- Filtros por tipo; “documentos” agrupa los archivos que no son imágenes, videos ni audio.
- Ordenar por nombre, fecha más reciente o tamaño descendente. Carpetas siempre primero.
- Compartir / sacar copia: entrega una copia a las aplicaciones disponibles de Android. El destino determina si necesita internet.

## Alcance y cuidado de datos

Es un gestor de archivos **importados al espacio privado de la aplicación**, no un explorador de todo el sistema Android. Las carpetas son lógicas en SQLite y los bytes se almacenan con identificadores internos. Renombrar o mover actualiza la organización sin cambiar el archivo original externo. No hay papelera ni edición del contenido. Los cambios hechos por un visor externo sobre una copia no se sincronizan con el gestor.

Desinstalar o borrar datos de la app elimina sus archivos internos. Compartir permite sacar copias antes. Elegir archivos de un proveedor de nube puede requerir internet; para demostrar funcionamiento offline, elegir archivos locales en Descargas y usar modo avión.

La app no solicita permiso de almacenamiento amplio; el selector de Android da acceso a los archivos elegidos. El manifiesto de la plantilla desactiva backup de la aplicación.

## Estructura

- `lib/main.dart`: interfaz, navegación, búsqueda, filtros y manejo de acciones asíncronas.
- `lib/entry.dart`: modelo tipado y presentación de tamaños.
- `lib/file_repository.dart`: SQLite, validaciones, operaciones en disco y consultas parametrizadas.
- `test/repository_test.dart`: pruebas de contenido, persistencia, copias recursivas, ciclos, duplicados y eliminación.
- `docs/PRUEBAS_MANUALES.md`: lista de verificación y evidencias.
- `docs/BASE_DE_DATOS.md`: explicación del modelo para exponer.

## Crear un APK para entregar

Después de preparar el proyecto:

```powershell
flutter build apk --release
```

Resultado: `build\app\outputs\flutter-apk\app-release.apk`.
Podés copiarlo al teléfono y abrirlo. Android puede pedir autorizar “Instalar aplicaciones desconocidas” para la aplicación con la que abriste el APK. Esto no se necesita para la instalación por `flutter run`. La firma de la plantilla es para demostración local; publicar en una tienda requiere configurar una firma propia.

## Validación y límites de esta entrega

Revisiones realizadas: los cuatro archivos Dart pasaron el análisis sintáctico de `dart format`; el esquema SQL se ejecutó con SQLite y se verificaron la restricción de nombres duplicados en la raíz y la eliminación en cascada. Esto no sustituye una compilación Flutter ni las pruebas en el dispositivo.

Se incluye código fuente y un generador de la estructura Android compatible con el Flutter local. No se ha compilado ni ejecutado en un Android en el entorno de elaboración; no hay Flutter ni Android SDK disponibles allí. Las pruebas Dart incluidas deben ejecutarse con `flutter test` en la computadora del estudiante. Revisar la lista manual antes de presentar. Si Android termina el proceso durante una copia recursiva, puede quedar una carpeta parcialmente copiada; los errores capturados durante la copia sí revierten esa copia. La limpieza de archivos huérfanos se reintenta al arrancar.

Documentación de referencia:
- https://docs.flutter.dev/platform-integration/android/setup
- https://developer.android.com/studio/run/device
- https://pub.dev/packages/sqflite/versions/2.4.2
- https://pub.dev/packages/file_picker/versions/10.3.10
- https://pub.dev/packages/open_filex/versions/4.7.0
- https://pub.dev/packages/share_plus/versions/10.1.4
