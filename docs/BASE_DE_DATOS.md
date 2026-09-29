# SQLite del explorador del teléfono

Base `device_files.db`, tabla `device_entries`:

| Columna | Tipo | Uso |
|---|---|---|
| path | TEXT PRIMARY KEY | Ruta absoluta real |
| parent | TEXT NOT NULL | Carpeta contenedora; índice device_parent |
| name | TEXT NOT NULL | Nombre visible |
| is_folder | INTEGER NOT NULL | 1 carpeta, 0 archivo |
| size | INTEGER NOT NULL | Bytes del archivo; 0 en carpetas |
| modified | TEXT NOT NULL | Fecha ISO 8601 |

El sistema de archivos es la fuente de verdad. La tabla es un índice persistente de metadatos, no almacena contenido ni concede permisos. Al entrar en una carpeta se lee el disco y se actualizan sus filas en una transacción. Si falla la lectura, no se interpreta la carpeta como vacía ni se limpia su índice. Las subcarpetas se actualizan al visitarlas. Renombrar/mover/eliminar invalida metadatos del subárbol anterior.

`files.db` y `entries` del modo privado se mantienen intactos. Ver MODO_PRIVADO_ANTERIOR.md para ese modo.
