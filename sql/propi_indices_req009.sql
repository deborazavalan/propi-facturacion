USE PropiDB;
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_BitacoraAuditoria_fec_registro' AND object_id = OBJECT_ID(N'dbo.Bitacora_Auditoria'))
    DROP INDEX IX_BitacoraAuditoria_fec_registro ON dbo.Bitacora_Auditoria;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CIX_BitacoraAuditoria_fec_registro' AND object_id = OBJECT_ID(N'dbo.Bitacora_Auditoria'))
    DROP INDEX CIX_BitacoraAuditoria_fec_registro ON dbo.Bitacora_Auditoria;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Cliente_fecha_registro' AND object_id = OBJECT_ID(N'dbo.Cliente'))
    DROP INDEX IX_Cliente_fecha_registro ON dbo.Cliente;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Factura_fecha' AND object_id = OBJECT_ID(N'dbo.Factura'))
    DROP INDEX IX_Factura_fecha ON dbo.Factura;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Factura_codigo_cliente' AND object_id = OBJECT_ID(N'dbo.Factura'))
    DROP INDEX IX_Factura_codigo_cliente ON dbo.Factura;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Nota_num_factura' AND object_id = OBJECT_ID(N'dbo.Nota_Credito_Debito'))
    DROP INDEX IX_Nota_num_factura ON dbo.Nota_Credito_Debito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Nota_fecha' AND object_id = OBJECT_ID(N'dbo.Nota_Credito_Debito'))
    DROP INDEX IX_Nota_fecha ON dbo.Nota_Credito_Debito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Producto_estado_descripcion' AND object_id = OBJECT_ID(N'dbo.Producto_Servicio'))
    DROP INDEX IX_Producto_estado_descripcion ON dbo.Producto_Servicio;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Cliente_nombre' AND object_id = OBJECT_ID(N'dbo.Cliente'))
    DROP INDEX IX_Cliente_nombre ON dbo.Cliente;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Canton_provincia' AND object_id = OBJECT_ID(N'dbo.Canton'))
    DROP INDEX IX_Canton_provincia ON dbo.Canton;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Distrito_canton' AND object_id = OBJECT_ID(N'dbo.Distrito'))
    DROP INDEX IX_Distrito_canton ON dbo.Distrito;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Barrio_distrito' AND object_id = OBJECT_ID(N'dbo.Barrio'))
    DROP INDEX IX_Barrio_distrito ON dbo.Barrio;
GO

IF OBJECT_ID('tempdb..#carga_req009') IS NOT NULL DROP PROCEDURE #carga_req009;
GO
CREATE PROCEDURE #carga_req009
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @fac_mid   INT = (SELECT num_factura FROM dbo.Factura ORDER BY num_factura OFFSET 700 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @nota_mid  INT = (SELECT numero_nota FROM dbo.Nota_Credito_Debito ORDER BY numero_nota OFFSET 300 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @prod_mid  INT = (SELECT codigo_producto FROM dbo.Producto_Servicio ORDER BY codigo_producto OFFSET 600 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @cli_mid   INT = (SELECT codigo_cliente FROM dbo.Cliente ORDER BY codigo_cliente OFFSET 600 ROWS FETCH NEXT 1 ROWS ONLY);
    DECLARE @fac_txt   VARCHAR(100) = CONVERT(VARCHAR(20), @fac_mid);
    DECLARE @nom_txt   VARCHAR(100) = (SELECT LEFT(nombre, 5) FROM dbo.Cliente WHERE codigo_cliente = @cli_mid);
    DECLARE @prod_txt  VARCHAR(100) = (SELECT LEFT(descripcion, 5) FROM dbo.Producto_Servicio WHERE codigo_producto = @prod_mid);
    DECLARE @prov      INT = (SELECT TOP 1 codigo_provincia FROM dbo.Canton ORDER BY codigo_canton);
    DECLARE @canton    INT = (SELECT TOP 1 codigo_canton FROM dbo.Distrito ORDER BY codigo_distrito);
    DECLARE @distrito  INT = (SELECT TOP 1 codigo_distrito FROM dbo.Barrio ORDER BY codigo_barrio);
    DECLARE @sel_d DATE = DATEADD(DAY, -60,  CAST(GETDATE() AS DATE));
    DECLARE @sel_h DATE = DATEADD(DAY, -30,  CAST(GETDATE() AS DATE));
    DECLARE @amp_d DATE = DATEADD(DAY, -730, CAST(GETDATE() AS DATE));
    DECLARE @amp_h DATE = CAST(GETDATE() AS DATE);

    PRINT N'## C01 usp_Factura_Obtener (por llave primaria)';
    EXEC dbo.usp_Factura_Obtener @num_factura = @fac_mid;
    PRINT N'## C02 usp_Factura_Listar (por número de factura)';
    EXEC dbo.usp_Factura_Listar @texto = @fac_txt;
    PRINT N'## C03 usp_Factura_Listar (por nombre de cliente)';
    EXEC dbo.usp_Factura_Listar @texto = @nom_txt;
    PRINT N'## C04 usp_Factura_Listar (sin filtro, las 500 más recientes)';
    EXEC dbo.usp_Factura_Listar @texto = NULL;
    PRINT N'## C05 usp_Nota_Obtener (por llave primaria)';
    EXEC dbo.usp_Nota_Obtener @numero_nota = @nota_mid;
    PRINT N'## C06 usp_Nota_Listar (por número de factura)';
    EXEC dbo.usp_Nota_Listar @texto = @fac_txt, @tipo = NULL;
    PRINT N'## C07 usp_Nota_Listar (solo notas de crédito, las más recientes)';
    EXEC dbo.usp_Nota_Listar @texto = NULL, @tipo = 'C';
    PRINT N'## C08 usp_Producto_Obtener (por llave primaria)';
    EXEC dbo.usp_Producto_Obtener @codigo_producto = @prod_mid;
    PRINT N'## C09 usp_Producto_Listar (activos, ordenados por descripción)';
    EXEC dbo.usp_Producto_Listar @texto = NULL, @estado = 'A';
    PRINT N'## C10 usp_Producto_Listar (búsqueda por texto)';
    EXEC dbo.usp_Producto_Listar @texto = @prod_txt, @estado = NULL;
    PRINT N'## C11 usp_Cliente_Obtener (por llave primaria)';
    EXEC dbo.usp_Cliente_Obtener @codigo_cliente = @cli_mid;
    PRINT N'## C12 usp_Cliente_Listar (sin filtro, ordenado por nombre)';
    EXEC dbo.usp_Cliente_Listar @texto = NULL, @estado = NULL;
    PRINT N'## C13 usp_Catalogo_Listar cantón (por provincia)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'canton', @padre = @prov;
    PRINT N'## C14 usp_Catalogo_Listar distrito (por cantón)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'distrito', @padre = @canton;
    PRINT N'## C15 usp_Catalogo_Listar barrio (por distrito)';
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'barrio', @padre = @distrito;
    PRINT N'## C16 usp_Reporte_Clientes (rango selectivo)';
    EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @estado = 'T';
    PRINT N'## C17 usp_Reporte_Facturas (rango selectivo)';
    EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @sel_d, @fecha_hasta = @sel_h;
    PRINT N'## C18 usp_Reporte_Auditoria (rango selectivo)';
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @sel_d, @fecha_hasta = @sel_h, @usuario = NULL;
    PRINT N'## C19 usp_Reporte_Auditoria (rango amplio)';
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @usuario = NULL;
    PRINT N'## C21 usp_Reporte_Clientes (rango amplio)';
    EXEC dbo.usp_Reporte_Clientes  @fecha_desde = @amp_d, @fecha_hasta = @amp_h, @estado = 'T';
    PRINT N'## C22 usp_Reporte_Facturas (rango amplio)';
    EXEC dbo.usp_Reporte_Facturas  @fecha_desde = @amp_d, @fecha_hasta = @amp_h;
    PRINT N'## C20 usp_Reporte_Seguridad (lee el catálogo del sistema, no tablas del negocio)';
    EXEC dbo.usp_Reporte_Seguridad @usuario = NULL;
END
GO

SET NOCOUNT ON;
CHECKPOINT;
DBCC DROPCLEANBUFFERS;
DBCC FREEPROCCACHE;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
PRINT N'>>> ANTES (1)';
EXEC #carga_req009;
PRINT N'>>> ANTES (2)';
EXEC #carga_req009;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SELECT N'ANTES' AS momento, OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       ps.last_elapsed_time / 1000.0 AS ms_ultima_ejecucion,
       ps.last_logical_reads AS lecturas_logicas, ps.last_worker_time / 1000.0 AS ms_cpu
  FROM sys.dm_exec_procedure_stats ps
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento;
GO

CREATE CLUSTERED INDEX CIX_BitacoraAuditoria_fec_registro
    ON dbo.Bitacora_Auditoria (fec_registro);

CREATE NONCLUSTERED INDEX IX_Cliente_fecha_registro
    ON dbo.Cliente (fecha_registro)
    INCLUDE (estado, nombre, codigo_actividad_economica);

CREATE NONCLUSTERED INDEX IX_Factura_fecha
    ON dbo.Factura (fecha)
    INCLUDE (codigo_cliente, subtotal, total_impuestos, monto_total);

CREATE NONCLUSTERED INDEX IX_Factura_codigo_cliente
    ON dbo.Factura (codigo_cliente)
    INCLUDE (fecha, codigo_moneda, subtotal, total_impuestos, monto_total);

CREATE NONCLUSTERED INDEX IX_Nota_num_factura
    ON dbo.Nota_Credito_Debito (num_factura)
    INCLUDE (fecha, tipo, monto);

CREATE NONCLUSTERED INDEX IX_Nota_fecha
    ON dbo.Nota_Credito_Debito (fecha DESC)
    INCLUDE (num_factura, tipo, monto);

CREATE NONCLUSTERED INDEX IX_Producto_estado_descripcion
    ON dbo.Producto_Servicio (estado, descripcion)
    INCLUDE (codigo_CABYS, codigo_unidad_medida, precio, codigo_tipo_impuesto);

CREATE NONCLUSTERED INDEX IX_Cliente_nombre
    ON dbo.Cliente (nombre)
    INCLUDE (estado);

CREATE NONCLUSTERED INDEX IX_Canton_provincia   ON dbo.Canton   (codigo_provincia) INCLUDE (nombre);
CREATE NONCLUSTERED INDEX IX_Distrito_canton    ON dbo.Distrito (codigo_canton)    INCLUDE (nombre);
CREATE NONCLUSTERED INDEX IX_Barrio_distrito    ON dbo.Barrio   (codigo_distrito)  INCLUDE (nombre);
GO

UPDATE STATISTICS dbo.Bitacora_Auditoria WITH FULLSCAN;
UPDATE STATISTICS dbo.Factura WITH FULLSCAN;
UPDATE STATISTICS dbo.Nota_Credito_Debito WITH FULLSCAN;
UPDATE STATISTICS dbo.Producto_Servicio WITH FULLSCAN;
UPDATE STATISTICS dbo.Cliente WITH FULLSCAN;
GO

SET NOCOUNT ON;
CHECKPOINT;
DBCC DROPCLEANBUFFERS;
DBCC FREEPROCCACHE;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
PRINT N'>>> DESPUÉS (1)';
EXEC #carga_req009;
PRINT N'>>> DESPUÉS (2)';
EXEC #carga_req009;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

SELECT N'DESPUÉS' AS momento, OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       ps.last_elapsed_time / 1000.0 AS ms_ultima_ejecucion,
       ps.last_logical_reads AS lecturas_logicas, ps.last_worker_time / 1000.0 AS ms_cpu
  FROM sys.dm_exec_procedure_stats ps
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento;
GO

;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT OBJECT_NAME(ps.object_id, ps.database_id) AS procedimiento,
       x.n.value('@PhysicalOp', 'varchar(40)')                                   AS operador,
       x.n.value('(IndexScan/Object/@Table)[1]', 'sysname')                      AS tabla,
       ISNULL(x.n.value('(IndexScan/Object/@Index)[1]', 'sysname'), N'(heap)')   AS indice
  FROM sys.dm_exec_procedure_stats ps
 CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp
 CROSS APPLY qp.query_plan.nodes('//RelOp[IndexScan]') x(n)
 WHERE ps.database_id = DB_ID() AND OBJECT_NAME(ps.object_id, ps.database_id) LIKE N'usp[_]%'
 ORDER BY procedimiento, tabla;
GO
