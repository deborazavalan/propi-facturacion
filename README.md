# Propi Facturación

Aplicación web (Node.js + Express) que se conecta a SQL Server con el usuario de cada persona.

## 1. Base de datos (en SSMS, cada archivo completo con Ctrl+A y F5, en este orden)
1. `sql/00_script_completo.sql` (borra y recrea PropiDB)
2. `sql/01_triggers_auditoria.sql`
3. `sql/02_dataset_propi.sql`
4. `sql/03_reportes_propi.sql`
5. `sql/06_crud_facturacion.sql` (productos, notas, facturas y detalle; el primer bloque ya viene en el 00, se puede volver a correr)
6. `sql/04_permisos_roles.sql` (siempre después del 06; luego correr de nuevo la PARTE 2 de pruebas del archivo 03)
7. `sql/05_indices_y_mediciones.sql` (por pasos, ver el encabezado)
8. `sql/07_indices_procedimientos_crud.sql` (REQ 009 parte 2: índices clustered y nonclustered para los procedimientos del CRUD; se corre después del 05, por pasos)

`sql/propi_script_completo_anexo.sql` junta todo lo anterior en un solo archivo, sin encabezados, para el anexo del documento.

## 2. Aplicación
1. Copiar `.env.example` como `.env` y ajustar servidor, instancia y base (`DB_NAME=PropiDB`).
2. `npm.cmd install` (solo la primera vez)
3. `npm.cmd start` y abrir http://localhost:3000

Usuarios de prueba: `usr_admin`, `usr_digitador`, `usr_consulta` (contraseñas definidas en el script principal).

## Réplica (REQ 014)

Los scripts de trasvase de registros están en `sql/replicacion/` (1 a 3 para configurar; 4a/4b/5a/5b para la conmutación) y el informe en `docs/REQ014_replicacion.pdf`. Para que la aplicación use la base secundaria después de una conmutación, cambie `DB_INSTANCE` en `.env` (SQLSERVERPT es la primaria y SQLSERVERSJ la secundaria) y reinicie el servidor.
