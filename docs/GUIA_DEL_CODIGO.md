# Arquitectura por responsabilidades e inyección

Esta edición reorganiza el explorador principal. Mantiene las bases device_files.db y files.db, el esquema y las funciones de la app. El modo privado anterior se conserva en legacy y no se presenta como una refactorización SOLID completa de ese módulo.

## Mapa de carpetas

| Carpeta / archivo dentro de lib | Responsabilidad |
|---|---|
| main.dart | Iniciar Flutter y montar la aplicación con dependencias recibidas |
| app/composition_root.dart | Elegir implementaciones concretas y conectarlas por constructor |
| domain/models/device_entry.dart | Datos inmutables de un archivo/carpeta |
| domain/contracts/file_browser.dart | Casos de uso del explorador |
| domain/contracts/file_storage.dart | Contrato para operar sobre el disco |
| domain/contracts/metadata_store.dart | Contrato de persistencia de metadatos |
| domain/contracts/storage_access.dart | Contrato de permisos y raíces |
| domain/contracts/file_actions.dart | Contrato para abrir y compartir |
| core/file_name_validator.dart | Regla común para nombres válidos |
| data/local_file_storage.dart | Implementación con File y Directory; sin SQL |
| data/sqlite_metadata_store.dart | Implementación de metadatos en SQLite; sin operaciones físicas |
| platform/android_storage_access.dart | MethodChannel y comprobación de Android |
| platform/plugin_file_actions.dart | Adaptador open_filex, share_plus y cross_file |
| application/indexed_file_browser.dart | Coordina almacenamiento y metadatos mediante contratos |
| application/browser_controller.dart | Estado de carga, navegación, búsqueda y acciones |
| presentation/device_page.dart | Widgets, diálogos y ciclo de vida de la pantalla |
| legacy/private_files_page.dart | Pantalla privada anterior, recibe la fábrica del repositorio |
| legacy/file_repository.dart | Repositorio privado anterior: jerarquía lógica, archivos y ZIP |
| entry.dart | Modelo privado y formato de tamaños |

Los archivos lib/device_page.dart y lib/file_repository.dart son exportaciones de compatibilidad, no implementaciones duplicadas. lib/device_repository.dart fue sustituido por las clases especializadas.

## Flujo de arranque

1. main crea AppDependencies.production fuera de la pantalla.
2. La composición construye LocalFileStorage y SqliteMetadataStore.
3. IndexedFileBrowser recibe ambos por constructor usando FileStorage y MetadataStore.
4. BrowserController recibe FileBrowser, StorageAccess y FileActions.
5. DevicePage recibe el controlador. No crea servicios ni importa plugins o SQLite.
6. initialize comprueba permiso y raíces mediante StorageAccess.
7. FileBrowser.list lee el disco y después actualiza metadatos.
8. El controlador notifica a sus oyentes; la pantalla reconstruye widgets.

## Cómo se aplica SOLID

| Principio | Evidencia concreta |
|---|---|
| S: responsabilidad única | Widgets, coordinación, disco, SQL y plataforma tienen clases diferentes. |
| O: extensión | Se puede introducir otra implementación de MetadataStore o FileStorage y cambiar solo la composición. |
| L: sustitución | Las implementaciones y los dobles de pruebas cumplen los mismos contratos; las pruebas verifican casos observables, no prueban universalmente todo el principio. |
| I: interfaces pequeñas | Los permisos no dependen de SQL; compartir no obliga a implementar operaciones de disco; cada servicio tiene su contrato. |
| D: inversión | Controlador y coordinador reciben interfaces. No importan data ni platform. Solo composition_root conoce las implementaciones. |

No se necesita un paquete de inyección: se utiliza inyección manual por constructor. Recibir una dependencia concreta por constructor es inyección; recibir un contrato permite además invertir la dependencia respecto de sus implementaciones.

BrowserController depende de ChangeNotifier de Flutter para notificar estado: no es un dominio completamente independiente del framework. El dominio (modelos y contratos) no importa Flutter ni SQLite. El módulo legacy conserva decisiones anteriores; no debe afirmarse que todo el código cumple SOLID de forma absoluta.

## Ejemplo: renombrar

DevicePage muestra el diálogo. Al confirmar llama controller.rename. El controlador serializa la acción y llama al contrato FileBrowser. IndexedFileBrowser delega el cambio físico en FileStorage; LocalFileStorage valida y usa rename. Solo después invalida los metadatos anteriores mediante MetadataStore. El controlador vuelve a listar y notifica a la pantalla.

La UI conoce la intención; LocalFileStorage conoce File/Directory; SqliteMetadataStore conoce tablas y transacciones. IndexedFileBrowser define el orden entre esas dos operaciones.

## SQLite

SqliteMetadataStore recibe una función para abrir una conexión. La apertura es perezosa y la conexión se reutiliza durante el proceso. close permite liberar la conexión explícitamente en pruebas; la app no la cierra durante una tarea en vuelo.

createSchema mantiene device_entries con path como clave primaria, parent, name, is_folder, size y modified. replaceDirectory sustituye los registros de una carpeta dentro de una transacción. invalidate elimina rutas obsoletas del índice, nunca archivos físicos.

La lista se lee del almacenamiento. SQLite es un índice persistente de las carpetas visitadas, no un escaneo global ni la fuente de búsqueda. La transacción SQL no engloba las operaciones del sistema de archivos.

## Métodos del controlador

| Método | Función |
|---|---|
| initialize | Comprobar permiso, actualizar raíces y leer carpeta |
| requestAccess | Solicitar autorización y volver a comprobar |
| navigate / up | Navegar conservando ubicación si falla la lectura |
| setQuery / visible | Filtrar nombres de la carpeta sin consultar disco ni SQL |
| stage / clearClipboard | Preparar o cancelar copiar/mover |
| createFolder / rename / delete / paste | Coordinar acción y refrescar |
| open / share | Delegar integración externa en FileActions |
| _run | Evitar acciones simultáneas desde la UI y comunicar errores |
| _mutate | Refrescar el listado después de una operación física |

entries y roots se exponen como listas de solo lectura para evitar mutación accidental desde la vista. busy, location y otros estados tienen getters; se modifican mediante métodos del controlador. Tras dispose se suprimen notificaciones tardías.

## Paquetes

Flutter construye widgets; Dart es el lenguaje. sqflite accede a SQLite. path maneja rutas. dart:io viene incluido y opera sobre archivos. open_filex abre archivos; share_plus y cross_file permiten compartir. path_provider, file_picker, mime y archive se conservan para el módulo privado. flutter_test y sqflite_common_ffi se usan en pruebas.

## Pruebas incluidas

- device_repository_test.dart: disco temporal real y SQLite FFI; creación, lectura, copia, movimiento, borrado, colisiones y límites de rutas.
- indexed_file_browser_test.dart: un fallo físico no borra metadatos; reemplazos por interfaces sin tocar Android.
- browser_controller_test.dart: permiso revocado, fallo de navegación, concurrencia de carga, búsqueda local y adaptador de apertura.
- repository_test.dart: regresión del módulo privado anterior.

Ejecutar flutter analyze y flutter test en un equipo con Flutter. Las pruebas fueron actualizadas pero no ejecutadas en el entorno de elaboración, que no dispone de Dart/Flutter/Android SDK. Se comprobaron imports locales, límites entre capas, SQL y contenido del ZIP. Verificar permisos y operaciones en un teléfono antes de presentar.

## Límites conservados

No hay papelera, búsqueda global, sincronización en la nube ni acceso a datos privados protegidos de otras apps. Mover entre volúmenes puede fallar; copiar y luego eliminar requiere intervención del usuario. Los cambios concurrentes de otras apps no están bloqueados. SQLite y disco no forman una sola transacción. El índice puede quedar desactualizado si falla una escritura y se reconstruye al visitar la carpeta.

## Para exponer

Abrir main.dart, luego composition_root.dart para mostrar la conexión de dependencias. Comparar FileStorage con LocalFileStorage y MetadataStore con SqliteMetadataStore. Mostrar IndexedFileBrowser.rename, BrowserController.rename y el diálogo en DevicePage. Finalmente, enseñar un fake en browser_controller_test.dart: reemplaza servicios sin usar Android ni SQLite y conserva el mismo contrato.

## Pantalla de inicio y acceso rápido (versión 2.2)

La pantalla inicial ahora es HomePage, en presentation/home_page.dart. Muestra capacidad y accesos a Descargas, Cámara (DCIM), Imágenes (Pictures), Documentos, Música y Videos (Movies). Son accesos a carpetas, no búsquedas globales de todos los archivos de esos tipos. Si una carpeta no existe o no se puede leer, se deshabilita sin crearla automáticamente.

Se mantiene la separación de responsabilidades:

| Archivo | Función |
|---|---|
| domain/models/storage_overview.dart | Volúmenes, rutas rápidas y cálculo de porcentaje |
| domain/contracts/storage_dashboard.dart | Contrato para consultar el resumen |
| platform/android_storage_dashboard.dart | Adaptador del nuevo método nativo dashboard |
| application/home_controller.dart | Permiso, carga, errores y actualización del inicio |
| presentation/home_page.dart | Tarjetas de capacidad, accesos y navegación |
| application/browser_controller.dart, openLocation | Comprueba y lee el destino antes de abrir el explorador |
| android_template/MainActivity.kt, storageDashboard | Consulta StatFs y directorios públicos estándar |

Flujo: main → composición → HomePage → HomeController → StorageDashboard → Kotlin. Al tocar una carpeta: BrowserController.openLocation comprueba acceso, configura raíces y lee/indexa el destino; solo si termina correctamente se abre DevicePage. El botón de casa vuelve al inicio. Al regresar se actualiza la capacidad. También se puede tirar hacia abajo o tocar Actualizar.

La capacidad procede de StatFs: usado = totalBytes - freeBytes; porcentaje = usado / totalBytes × 100. availableBytes es el espacio libre disponible para las aplicaciones, que puede ser menor que freeBytes por reservas del sistema. El total corresponde al sistema de archivos, no necesariamente a la capacidad comercial anunciada. No se calcula recorriendo carpetas ni leyendo SQLite. Cada volumen se muestra por separado para no sumar capacidades duplicadas o incompatibles. Si no se puede consultar un volumen, muestra capacidad no disponible.

Los métodos roots y dashboard usan la misma función storageRoots. El contrato StorageAccess no crece con las estadísticas: StorageDashboard es una interfaz independiente. Los controladores se construyen por inyección en composition_root.

Pruebas añadidas: home_controller_test.dart verifica porcentaje, tamaño grande, capacidad desconocida, denegación/revocación de permiso, error y reintento con servicios simulados. Deben ejecutarse en el equipo con Flutter.

Fuentes de las APIs nativas:
- https://developer.android.com/reference/android/os/StatFs
- https://developer.android.com/reference/android/os/Environment


## Ajuste 2.2.1

HomePage ahora muestra el título Acceso rápido y primero las tarjetas de rutas. Debajo muestra Almacenamiento y la barra de cada volumen. Se eliminaron los saludos y las explicaciones de la pantalla, y el acceso privado se trasladó al menú superior. AndroidStorageDashboard traduce MissingPluginException a NativeUpdateRequired; nunca inventa estadísticas. actualizar.bat prepara Kotlin y recompila para actualizar la implementación instalada. Consultar LEEME_ACTUALIZACION.md.
