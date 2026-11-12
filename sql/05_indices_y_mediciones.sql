/* =====================================================================
   PropiDB - REQ 009: índices y medición antes / después
   Persona B (Débora Zavala)
   ---------------------------------------------------------------------
   Qué hace:
     PASO 0  quita los 3 índices (si existen) para partir del estado "antes".
     PASO 1  mide los reportes SIN índices.
     PASO 2  crea los 3 índices.
     PASO 3  repite exactamente las mismas pruebas CON índices.
     PASO 4  muestra si SQL Server usó los índices.
     PASO 5  (opcional) los borra para repetir la medición.

   Requisitos: haber corrido el script principal, triggers_auditoria,
   dataset_propi y reportes_propi (los reportes deben existir).

   Cómo usarlo (importante):
     * Ejecute CADA PASO por separado: seleccione el bloque y F5.
     * Antes de los pasos 1 y 3: Consulta > Opciones de consulta > Resultados >
       Cuadrícula > "Descartar resultados después de la ejecución". Así no se
       dibujan miles de filas y solo se ven los mensajes.
     * Los números salen en la pestaña "Mensajes":
         - "logical reads" (lecturas lógicas): cuántas páginas leyó cada tabla.
           Es la medida principal; casi no cambia entre corridas.
         - "CPU time" y "elapsed time" (ms): dependen de la máquina; si quiere
           estabilidad, corra la prueba 3 veces y anote la mediana.
     * Anote los valores en el cuadro de la sección 9 del documento.
     * Cada prueba tiene un rótulo ">>> ANTES | ..." o ">>> DESPUÉS | ..." para
       ubicar sus números. Las pruebas A miden solo el filtro por fecha; las
       pruebas B son el procedimiento completo, con descifrado y ORDER BY.
     * Con el plan de ejecución real (Ctrl+M) se puede capturar la imagen que
       muestra "Table Scan / Clustered Index Scan" antes e "Index Seek" después.

   Nota sobre los resultados: con ~1,000 a 1,500 filas por tabla el ahorro en
   lecturas es real pero pequeño en términos absolutos (las tablas ocupan pocas
   páginas). La mejora se nota más en los rangos selectivos (pruebas "selectivo")
   y crece al aumentar el volumen. En el rango amplio SQL Server puede seguir
   leyendo casi todo, y eso es esperable.
   ===================================================================== */
USE PropiDB;
GO

/* ---------------------------- PASO 0: estado "antes" ---------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Cliente_fecha_registro' AND object_id = OBJECT_ID(N'dbo.Cliente'))
    DROP INDEX IX_Cliente_fecha_registro ON dbo.Cliente;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Factura_fecha' AND object_id = OBJECT_ID(N'dbo.Factura'))
    DROP INDEX IX_Factura_fecha ON dbo.Factura;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BitacoraAuditoria_fec_registro' AND object_id = OBJECT_ID(N'dbo.Bitacora_Auditoria'))
    DROP INDEX IX_BitacoraAuditoria_fec_registro ON dbo.Bitacora_Auditoria;
GO

/* ---------------------------- PASO 1: medición ANTES ---------------------------- */

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- cada prueba parte de la memoria vacía (si no hay permiso, el error se ignora y se sigue)
CHECKPOINT;
DBCC DROPCLEANBUFFERS;

-- rangos de prueba: uno que trae pocas filas (30 días) y otro que trae casi todo (2 años)
DECLARE @sel_d DATE = DATEADD(DAY, -60,  CAST(GETDATE() AS DATE));
DECLARE @sel_h DATE = DATEADD(DAY, -30,  CAST(GETDATE() AS DATE));
DECLARE @amp_d DATE = DATEADD(DAY, -730, CAST(GETDATE() AS DATE));
DECLARE @amp_h DATE = CAST(GETDATE() AS DATE);

-------------------------------------------------------------------------
-- A) La consulta de cada reporte, sin descifrar (mide solo el índice)
-------------------------------------------------------------------------
PRINT N'>>> ANTES | A1 Clientes | selectivo';
SELECT COUNT_BIG(*) AS filas, MAX(nombre) AS n, MAX(codigo_actividad_economica) AS a, MIN(estado) AS e
  FROM dbo.Cliente
 WHERE fecha_registro >= @sel_d AND fecha_registro < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> ANTES | A2 Clientes | amplio';
SELECT COUNT_BIG(*) AS filas, MAX(nombre) AS n, MAX(codigo_actividad_economica) AS a, MIN(estado) AS e
  FROM dbo.Cliente
 WHERE fecha_registro >= @amp_d AND fecha_registro < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

PRINT N'>>> ANTES | A3 Facturas | selectivo';
SELECT COUNT_BIG(*) AS filas, SUM(subtotal) AS s, SUM(total_impuestos) AS i, SUM(monto_total) AS t, MAX(codigo_cliente) AS c
  FROM dbo.Factura
 WHERE fecha >= @sel_d AND fecha < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> ANTES | A4 Facturas | amplio';
SELECT COUNT_BIG(*) AS filas, SUM(subtotal) AS s, SUM(total_impuestos) AS i, SUM(monto_total) AS t, MAX(codigo_cliente) AS c
  FROM dbo.Factura
 WHERE fecha >= @amp_d AND fecha < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

PRINT N'>>> ANTES | A5 Auditoría | selectivo';
SELECT COUNT_BIG(*) AS filas, MAX(cod_usuario) AS u, MAX(ind_accion) AS a, MAX(cod_tabla) AS t, MAX(cod_llave) AS l
  FROM dbo.Bitacora_Auditoria
 WHERE fec_registro >= @sel_d AND fec_registro < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> ANTES | A6 Auditoría | amplio';
SELECT COUNT_BIG(*) AS filas, MAX(cod_usuario) AS u, MAX(ind_accion) AS a, MAX(cod_tabla) AS t, MAX(cod_llave) AS l
  FROM dbo.Bitacora_Auditoria
 WHERE fec_registro >= @amp_d AND fec_registro < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

-------------------------------------------------------------------------
-- B) Los procedimientos completos (incluyen el descifrado y el ORDER BY)
-------------------------------------------------------------------------
PRINT N'>>> ANTES | B1 usp_Reporte_Clientes | selectivo';
EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @estado = 'T';
PRINT N'>>> ANTES | B2 usp_Reporte_Clientes | amplio';
EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @estado = 'T';
PRINT N'>>> ANTES | B3 usp_Reporte_Facturas | selectivo';
EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @sel_d, @fecha_hasta = @sel_h;
PRINT N'>>> ANTES | B4 usp_Reporte_Facturas | amplio';
EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @amp_d, @fecha_hasta = @amp_h;
PRINT N'>>> ANTES | B5 usp_Reporte_Auditoria | selectivo';
EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @usuario = NULL;
PRINT N'>>> ANTES | B6 usp_Reporte_Auditoria | amplio';
EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @usuario = NULL;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ---------------------------- PASO 2: crear los índices ---------------------------- */
/* Cada índice tiene como llave la columna por la que filtra el reporte (rango de fechas)
   y en INCLUDE las columnas que el reporte lee, para no volver a la tabla (índice "cubriente").
   Los datos cifrados de Cliente no se incluyen: son pesados y solo se leen para las filas que salen. */

-- usp_Reporte_Clientes: WHERE fecha_registro BETWEEN ... AND estado ...
CREATE NONCLUSTERED INDEX IX_Cliente_fecha_registro
    ON dbo.Cliente (fecha_registro)
    INCLUDE (estado, nombre, codigo_actividad_economica);

-- usp_Reporte_Facturas: WHERE fecha BETWEEN ... y JOIN con Cliente por codigo_cliente
CREATE NONCLUSTERED INDEX IX_Factura_fecha
    ON dbo.Factura (fecha)
    INCLUDE (codigo_cliente, subtotal, total_impuestos, monto_total);

-- usp_Reporte_Auditoria: WHERE fec_registro BETWEEN ... AND cod_usuario = ...
CREATE NONCLUSTERED INDEX IX_BitacoraAuditoria_fec_registro
    ON dbo.Bitacora_Auditoria (fec_registro)
    INCLUDE (cod_usuario, ind_accion, cod_tabla, cod_llave);
GO

/* ---------------------------- PASO 3: medición DESPUÉS ---------------------------- */

SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- cada prueba parte de la memoria vacía (si no hay permiso, el error se ignora y se sigue)
CHECKPOINT;
DBCC DROPCLEANBUFFERS;

-- rangos de prueba: uno que trae pocas filas (30 días) y otro que trae casi todo (2 años)
DECLARE @sel_d DATE = DATEADD(DAY, -60,  CAST(GETDATE() AS DATE));
DECLARE @sel_h DATE = DATEADD(DAY, -30,  CAST(GETDATE() AS DATE));
DECLARE @amp_d DATE = DATEADD(DAY, -730, CAST(GETDATE() AS DATE));
DECLARE @amp_h DATE = CAST(GETDATE() AS DATE);

-------------------------------------------------------------------------
-- A) La consulta de cada reporte, sin descifrar (mide solo el índice)
-------------------------------------------------------------------------
PRINT N'>>> DESPUÉS | A1 Clientes | selectivo';
SELECT COUNT_BIG(*) AS filas, MAX(nombre) AS n, MAX(codigo_actividad_economica) AS a, MIN(estado) AS e
  FROM dbo.Cliente
 WHERE fecha_registro >= @sel_d AND fecha_registro < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> DESPUÉS | A2 Clientes | amplio';
SELECT COUNT_BIG(*) AS filas, MAX(nombre) AS n, MAX(codigo_actividad_economica) AS a, MIN(estado) AS e
  FROM dbo.Cliente
 WHERE fecha_registro >= @amp_d AND fecha_registro < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

PRINT N'>>> DESPUÉS | A3 Facturas | selectivo';
SELECT COUNT_BIG(*) AS filas, SUM(subtotal) AS s, SUM(total_impuestos) AS i, SUM(monto_total) AS t, MAX(codigo_cliente) AS c
  FROM dbo.Factura
 WHERE fecha >= @sel_d AND fecha < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> DESPUÉS | A4 Facturas | amplio';
SELECT COUNT_BIG(*) AS filas, SUM(subtotal) AS s, SUM(total_impuestos) AS i, SUM(monto_total) AS t, MAX(codigo_cliente) AS c
  FROM dbo.Factura
 WHERE fecha >= @amp_d AND fecha < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

PRINT N'>>> DESPUÉS | A5 Auditoría | selectivo';
SELECT COUNT_BIG(*) AS filas, MAX(cod_usuario) AS u, MAX(ind_accion) AS a, MAX(cod_tabla) AS t, MAX(cod_llave) AS l
  FROM dbo.Bitacora_Auditoria
 WHERE fec_registro >= @sel_d AND fec_registro < DATEADD(DAY, 1, @sel_h) OPTION (RECOMPILE);

PRINT N'>>> DESPUÉS | A6 Auditoría | amplio';
SELECT COUNT_BIG(*) AS filas, MAX(cod_usuario) AS u, MAX(ind_accion) AS a, MAX(cod_tabla) AS t, MAX(cod_llave) AS l
  FROM dbo.Bitacora_Auditoria
 WHERE fec_registro >= @amp_d AND fec_registro < DATEADD(DAY, 1, @amp_h) OPTION (RECOMPILE);

-------------------------------------------------------------------------
-- B) Los procedimientos completos (incluyen el descifrado y el ORDER BY)
-------------------------------------------------------------------------
PRINT N'>>> DESPUÉS | B1 usp_Reporte_Clientes | selectivo';
EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @estado = 'T';
PRINT N'>>> DESPUÉS | B2 usp_Reporte_Clientes | amplio';
EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @estado = 'T';
PRINT N'>>> DESPUÉS | B3 usp_Reporte_Facturas | selectivo';
EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @sel_d, @fecha_hasta = @sel_h;
PRINT N'>>> DESPUÉS | B4 usp_Reporte_Facturas | amplio';
EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @amp_d, @fecha_hasta = @amp_h;
PRINT N'>>> DESPUÉS | B5 usp_Reporte_Auditoria | selectivo';
EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @usuario = NULL;
PRINT N'>>> DESPUÉS | B6 usp_Reporte_Auditoria | amplio';
EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @usuario = NULL;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* ---------------------------- PASO 4: ¿SQL Server usó los índices? ---------------------------- */
/* seeks = búsquedas por el índice; scans = recorridos completos; lookups = idas a la tabla. */
SELECT OBJECT_NAME(i.object_id) AS tabla, i.name AS indice,
       ISNULL(s.user_seeks, 0) AS seeks, ISNULL(s.user_scans, 0) AS scans, ISNULL(s.user_lookups, 0) AS lookups
  FROM sys.indexes i
  LEFT JOIN sys.dm_db_index_usage_stats s
         ON s.object_id = i.object_id AND s.index_id = i.index_id AND s.database_id = DB_ID()
 WHERE i.name IN (N'IX_Cliente_fecha_registro', N'IX_Factura_fecha', N'IX_BitacoraAuditoria_fec_registro');

/* Tamaño de cada índice (para el documento) */
SELECT OBJECT_NAME(ps.object_id) AS tabla, i.name AS indice,
       SUM(ps.used_page_count) AS paginas, SUM(ps.used_page_count) * 8 AS kilobytes
  FROM sys.dm_db_partition_stats ps
  JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
 WHERE i.name IN (N'IX_Cliente_fecha_registro', N'IX_Factura_fecha', N'IX_BitacoraAuditoria_fec_registro')
 GROUP BY ps.object_id, i.name;
GO

/* ---------------------------- PASO 5 (opcional): repetir la medición ----------------------------
   Para volver al "antes", ejecute de nuevo el PASO 0. Los índices finales del proyecto son los del PASO 2.
*/
