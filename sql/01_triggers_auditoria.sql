/* =====================================================================
   PropiDB - REQ 005: Triggers de auditoría para TODAS las tablas
   ---------------------------------------------------------------------
   Qué hace:
   - Recorre todas las tablas del esquema dbo que tengan llave primaria.
   - Crea 3 triggers por tabla: trg_<Tabla>_Insert, _Update y _Delete.
   - Cada trigger escribe en dbo.Bitacora_Auditoria (I / U / D).
   - Usa CREATE OR ALTER, así que se puede ejecutar varias veces y
     reemplaza los triggers que ya existían (Cliente y Factura).
   - Excluye solo Bitacora_Auditoria (si no, el trigger se llamaría
     a sí mismo sin fin).

   Requiere SQL Server 2017 o superior (usa STRING_AGG).
   ===================================================================== */
USE PropiDB;
GO
SET NOCOUNT ON;

/* 1. Llaves primarias de todas las tablas (incluye llaves compuestas) */
IF OBJECT_ID('tempdb..#pk') IS NOT NULL DROP TABLE #pk;

SELECT t.name AS tabla, c.name AS columna, ic.key_ordinal AS orden
INTO #pk
FROM sys.tables t
JOIN sys.indexes i        ON i.object_id = t.object_id AND i.is_primary_key = 1
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE SCHEMA_NAME(t.schema_id) = N'dbo';

/* Aviso: tablas sin llave primaria (no se les puede crear trigger) */
SELECT t.name AS tabla_sin_pk_no_se_crea_trigger
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND t.name <> N'Bitacora_Auditoria'
  AND NOT EXISTS (SELECT 1 FROM #pk p WHERE p.tabla = t.name);

/* 2. Plantillas de los triggers */
DECLARE @tpl_i NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER INSERT
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''I'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_I},
           (SELECT * FROM inserted x WHERE {ON_X_I}
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i;
END';

DECLARE @tpl_d NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER DELETE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''D'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_D},
           (SELECT * FROM deleted x WHERE {ON_X_D}
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END';

DECLARE @tpl_u NVARCHAR(MAX) = N'
CREATE OR ALTER TRIGGER dbo.{TRG} ON dbo.{TQ}
AFTER UPDATE
AS
BEGIN
    IF @@ROWCOUNT = 0 RETURN;
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Auditoria
        (fec_registro, cod_guid, ind_accion, cod_usuario, cod_sesion_usuario,
         cod_tabla, cod_llave, des_datos)
    SELECT GETDATE(),
           CONVERT(VARCHAR(255), NEWID()),
           ''U'',
           ORIGINAL_LOGIN(),
           COALESCE(CONVERT(INT, SESSION_CONTEXT(N''id_sesion'')), @@SPID),
           ''{T}'',
           {KEY_I},
           (SELECT JSON_QUERY((SELECT * FROM deleted y WHERE {ON_Y_I}
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS antes,
                   JSON_QUERY((SELECT * FROM inserted x WHERE {ON_X_I}
                               FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS despues
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted i
    JOIN deleted d ON {ON_D_I};
END';

/* 3. Generar y ejecutar los triggers tabla por tabla */
DECLARE @tabla SYSNAME,
        @sql   NVARCHAR(MAX),
        @key_i NVARCHAR(MAX), @key_d  NVARCHAR(MAX),
        @on_x_i NVARCHAR(MAX), @on_y_i NVARCHAR(MAX),
        @on_x_d NVARCHAR(MAX), @on_d_i NVARCHAR(MAX);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT tabla
    FROM #pk
    WHERE tabla <> N'Bitacora_Auditoria'
    ORDER BY tabla;

OPEN cur;
FETCH NEXT FROM cur INTO @tabla;

WHILE @@FETCH_STATUS = 0
BEGIN
    SELECT
        /* cod_llave, por ejemplo: CONCAT('num_factura=', i.[num_factura], ', numero_linea=', i.[numero_linea]) */
        @key_i = N'CONCAT(' + (STRING_AGG(CONVERT(NVARCHAR(MAX),
                    N'''' + CASE WHEN orden > 1 THEN N', ' ELSE N'' END + columna
                    + N'='', i.' + QUOTENAME(columna)), N', ')
                    WITHIN GROUP (ORDER BY orden)) + N')',
        @key_d = N'CONCAT(' + (STRING_AGG(CONVERT(NVARCHAR(MAX),
                    N'''' + CASE WHEN orden > 1 THEN N', ' ELSE N'' END + columna
                    + N'='', d.' + QUOTENAME(columna)), N', ')
                    WITHIN GROUP (ORDER BY orden)) + N')',
        /* condiciones de unión por llave primaria */
        @on_x_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'x.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND '),
        @on_y_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'y.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND '),
        @on_x_d = STRING_AGG(CONVERT(NVARCHAR(MAX), N'x.' + QUOTENAME(columna) + N' = d.' + QUOTENAME(columna)), N' AND '),
        @on_d_i = STRING_AGG(CONVERT(NVARCHAR(MAX), N'd.' + QUOTENAME(columna) + N' = i.' + QUOTENAME(columna)), N' AND ')
    FROM #pk
    WHERE tabla = @tabla;

    /* INSERT */
    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_i,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Insert')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_I}', @key_i),
                N'{ON_X_I}', @on_x_i);
    EXEC sys.sp_executesql @sql;

    /* DELETE */
    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_d,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Delete')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_D}', @key_d),
                N'{ON_X_D}', @on_x_d);
    EXEC sys.sp_executesql @sql;

    /* UPDATE */
    SET @sql = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tpl_u,
                N'{TRG}',  QUOTENAME(N'trg_' + @tabla + N'_Update')),
                N'{TQ}',   QUOTENAME(@tabla)),
                N'{T}',    @tabla),
                N'{KEY_I}', @key_i),
                N'{ON_X_I}', @on_x_i),
                N'{ON_Y_I}', @on_y_i);
    SET @sql = REPLACE(@sql, N'{ON_D_I}', @on_d_i);
    EXEC sys.sp_executesql @sql;

    PRINT N'Triggers creados para: ' + @tabla;
    FETCH NEXT FROM cur INTO @tabla;
END

CLOSE cur;
DEALLOCATE cur;
DROP TABLE #pk;
GO

/* =====================================================================
   VERIFICACIÓN
   ===================================================================== */

/* 1. Triggers por tabla (cada una debe tener 3) */
SELECT OBJECT_NAME(parent_id) AS tabla,
       COUNT(*)               AS cantidad_triggers,
       STRING_AGG(name, N', ') AS triggers
FROM sys.triggers
WHERE parent_class = 1
GROUP BY parent_id
ORDER BY tabla;

/* 2. Tablas que NO tienen exactamente 3 triggers (debe dar 0 filas;
      Bitacora_Auditoria queda excluida a propósito) */
SELECT t.name AS tabla_incompleta
FROM sys.tables t
WHERE SCHEMA_NAME(t.schema_id) = N'dbo'
  AND t.name <> N'Bitacora_Auditoria'
  AND (SELECT COUNT(*) FROM sys.triggers tr WHERE tr.parent_id = t.object_id) <> 3;
GO

/* 3. Prueba rápida con una tabla de catálogo: insertar, modificar, borrar */
EXEC sp_set_session_context N'id_sesion', 1001;

INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion)
VALUES ('TRG', 'Prueba de trigger');

UPDATE dbo.Unidad_Medida
SET descripcion = 'Prueba de trigger modificada'
WHERE codigo_unidad_medida = 'TRG';

DELETE FROM dbo.Unidad_Medida
WHERE codigo_unidad_medida = 'TRG';

SELECT TOP (3) fec_registro, ind_accion, RTRIM(cod_usuario) AS cod_usuario,
       cod_sesion_usuario, cod_tabla, cod_llave, des_datos
FROM dbo.Bitacora_Auditoria
WHERE cod_tabla = 'Unidad_Medida'
ORDER BY fec_registro DESC;
GO
