/* =====================================================================
   PropiDB - REQ 004 y REQ 008: Permisos por rol con GRANT, REVOKE, DENY
   ---------------------------------------------------------------------
   Modelo de seguridad (mínimo privilegio):
   - rol_administrador : acceso total (tablas y procedimientos).
   - rol_digitador     : SOLO ejecuta procedimientos de clientes, facturas,
                         notas y catálogos. No toca las tablas directo.
   - rol_consulta      : SOLO ejecuta los reportes permitidos.
   - Nadie (ni el administrador) puede insertar, modificar ni borrar las
     bitácoras de forma directa. Se llenan solo con triggers y procedimientos.

   Por qué los usuarios no necesitan permisos sobre las tablas:
   los procedimientos y las tablas pertenecen a dbo, así que SQL Server
   aplica el "encadenamiento de propiedad" y no revisa permisos de tabla
   cuando se llega a ellas desde un procedimiento.

   Nombres que deben usar los procedimientos que faltan (los patrones de
   abajo los toman automáticamente al volver a correr este script):
     usp_Factura_*  usp_FacturaDetalle_*  usp_Nota_*  usp_Producto_*
     usp_Reporte_Clientes  usp_Reporte_Facturas
     usp_Reporte_Auditoria  usp_Reporte_Seguridad

   El script se puede ejecutar varias veces: primero reinicia los permisos
   de los 3 roles y luego los vuelve a aplicar.
   ===================================================================== */
USE PropiDB;
GO
SET NOCOUNT ON;

/* ---------------------------------------------------------------------
   0. REINICIO (REVOKE): deja los 3 roles sin permisos propios
   --------------------------------------------------------------------- */
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql += N'REVOKE EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_administrador, rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.procedures;

SELECT @sql += N'REVOKE SELECT, INSERT, UPDATE, DELETE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_administrador, rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.tables;

EXEC sys.sp_executesql @sql;

REVOKE SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo
    FROM rol_administrador, rol_digitador, rol_consulta;
GO

/* ---------------------------------------------------------------------
   1. ADMINISTRADOR (GRANT): acceso total a toda la información
   --------------------------------------------------------------------- */
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO rol_administrador;
GRANT VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes  TO rol_administrador;
GRANT CONTROL         ON CERTIFICATE::cert_propi_clientes  TO rol_administrador;
GRANT VIEW DEFINITION TO rol_administrador;   -- ver la configuración de seguridad (reporte)
GO

/* ---------------------------------------------------------------------
   2. DIGITADOR y CONSULTA (DENY): nada de acceso directo a las tablas
   --------------------------------------------------------------------- */
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO rol_digitador, rol_consulta;
GO

/* ---------------------------------------------------------------------
   3. BITÁCORAS (DENY): solo escriben los triggers y los procedimientos
   --------------------------------------------------------------------- */
DENY INSERT, UPDATE, DELETE ON dbo.Bitacora_Auditoria TO rol_administrador, rol_digitador, rol_consulta;
DENY INSERT, UPDATE, DELETE ON dbo.Bitacora_Acceso    TO rol_administrador, rol_digitador, rol_consulta;
GO

/* ---------------------------------------------------------------------
   4. PROCEDIMIENTOS (GRANT EXECUTE) según un mapa rol -> patrón de nombre
      incluir = patrón LIKE que se permite, excluir = patrón que se omite
   --------------------------------------------------------------------- */
DECLARE @mapa_grant TABLE (rol SYSNAME, incluir NVARCHAR(100), excluir NVARCHAR(100) NULL);

INSERT INTO @mapa_grant (rol, incluir, excluir) VALUES
  /* Todos los roles: sesión y bitácora de accesos (login) */
  (N'rol_digitador', N'usp[_]Sesion[_]%',          NULL),
  (N'rol_digitador', N'usp[_]BitacoraAcceso[_]%',  NULL),
  (N'rol_consulta',  N'usp[_]Sesion[_]%',          NULL),
  (N'rol_consulta',  N'usp[_]BitacoraAcceso[_]%',  NULL),
  /* Digitador: clientes, facturas, detalle, notas (sin eliminar) y catálogos */
  (N'rol_digitador', N'usp[_]Catalogo[_]%',        NULL),
  (N'rol_digitador', N'usp[_]Cliente[_]%',         N'%[_]Eliminar'),
  (N'rol_digitador', N'usp[_]Factura%',            N'%[_]Eliminar'),
  (N'rol_digitador', N'usp[_]Nota%',               N'%[_]Eliminar'),
  /* Digitador: solo consultar productos e impuestos (para llenar facturas) */
  (N'rol_digitador', N'usp[_]Producto[_]Listar',     NULL),
  (N'rol_digitador', N'usp[_]Producto[_]Obtener',    NULL),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Listar',  NULL),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Obtener', NULL),
  /* Consulta: reportería (Clientes y Facturas) */
  (N'rol_consulta',  N'usp[_]Reporte[_]Clientes',  NULL),
  (N'rol_consulta',  N'usp[_]Reporte[_]Facturas',  NULL);
  /* Si el profesor quiere que Consulta vea los 4 reportes, agregue aquí
     las filas de usp_Reporte_Auditoria y usp_Reporte_Seguridad y quite
     su DENY de la sección 5. */

DECLARE @sql NVARCHAR(MAX) = N'';   -- (en este bloque hay que declararla de nuevo: el GO anterior la borró)
SELECT @sql += N'GRANT EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(p.schema_id)) + N'.' + QUOTENAME(p.name)
             + N' TO ' + QUOTENAME(m.rol) + N';' + CHAR(10)
FROM sys.procedures p
JOIN @mapa_grant m
  ON p.name LIKE m.incluir
 AND (m.excluir IS NULL OR p.name NOT LIKE m.excluir);

EXEC sys.sp_executesql @sql;

/* Los procedimientos de validación son internos: se llaman desde otros
   procedimientos y no necesitan permiso directo (REVOKE) */
SET @sql = N'';
SELECT @sql += N'REVOKE EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name)
             + N' FROM rol_digitador, rol_consulta;' + CHAR(10)
FROM sys.procedures
WHERE name LIKE N'%[_]Validar';
EXEC sys.sp_executesql @sql;
GO

/* ---------------------------------------------------------------------
   5. PROCEDIMIENTOS (DENY EXECUTE): prohibiciones explícitas
      El DENY siempre gana sobre cualquier GRANT.
   --------------------------------------------------------------------- */
DECLARE @mapa_deny TABLE (rol SYSNAME, patron NVARCHAR(100));

INSERT INTO @mapa_deny (rol, patron) VALUES
  /* Nadie salvo el administrador elimina registros */
  (N'rol_digitador', N'%[_]Eliminar'),
  (N'rol_consulta',  N'%[_]Eliminar'),
  /* Consulta es solo lectura: no inserta ni actualiza */
  (N'rol_consulta',  N'%[_]Insertar'),
  (N'rol_consulta',  N'%[_]Actualizar'),
  /* Los catálogos de impuestos y productos los mantiene solo el administrador */
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Insertar'),
  (N'rol_digitador', N'usp[_]TipoImpuesto[_]Actualizar'),
  (N'rol_digitador', N'usp[_]Producto[_]Insertar'),
  (N'rol_digitador', N'usp[_]Producto[_]Actualizar'),
  /* Auditoría y seguridad son reportes sensibles: solo administrador */
  (N'rol_digitador', N'usp[_]Reporte[_]Auditoria'),
  (N'rol_digitador', N'usp[_]Reporte[_]Seguridad'),
  (N'rol_consulta',  N'usp[_]Reporte[_]Auditoria'),
  (N'rol_consulta',  N'usp[_]Reporte[_]Seguridad');

DECLARE @sql2 NVARCHAR(MAX) = N'';
SELECT @sql2 += N'DENY EXECUTE ON ' + QUOTENAME(SCHEMA_NAME(p.schema_id)) + N'.' + QUOTENAME(p.name)
              + N' TO ' + QUOTENAME(d.rol) + N';' + CHAR(10)
FROM sys.procedures p
JOIN @mapa_deny d ON p.name LIKE d.patron;

EXEC sys.sp_executesql @sql2;
GO

/* ---------------------------------------------------------------------
   6. CLAVE Y CERTIFICADO (REVOKE): el digitador y consulta no deben
      tener CONTROL sobre el certificado.
      Esto solo se aplica cuando todos los procedimientos que abren la
      llave simétrica ya usan WITH EXECUTE AS OWNER. Si falta alguno,
      el script avisa y NO quita el permiso, para no romper la aplicación.
   --------------------------------------------------------------------- */
IF EXISTS (SELECT 1
           FROM sys.procedures p
           JOIN sys.sql_modules m ON m.object_id = p.object_id
           WHERE m.definition LIKE N'%OPEN SYMMETRIC KEY%'
             AND m.execute_as_principal_id IS NULL)
BEGIN
    PRINT N'ADVERTENCIA: estos procedimientos abren la llave pero no usan WITH EXECUTE AS OWNER.';
    PRINT N'Agregue esa línea entre la lista de parámetros y el AS, y vuelva a correr este script:';
    SELECT p.name AS procedimiento_sin_execute_as_owner
    FROM sys.procedures p
    JOIN sys.sql_modules m ON m.object_id = p.object_id
    WHERE m.definition LIKE N'%OPEN SYMMETRIC KEY%'
      AND m.execute_as_principal_id IS NULL;
END
ELSE
BEGIN
    REVOKE VIEW DEFINITION ON SYMMETRIC KEY::sk_propi_clientes FROM rol_digitador, rol_consulta;
    REVOKE CONTROL         ON CERTIFICATE::cert_propi_clientes FROM rol_digitador, rol_consulta;
    PRINT N'Permisos sobre la llave y el certificado quitados a digitador y consulta.';
END
GO

/* =====================================================================
   PRUEBAS (cada una debe imprimir OK)
   ===================================================================== */

/* 1. El digitador NO puede leer tablas directo */
EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    SELECT TOP (1) * FROM dbo.Cliente;
    PRINT N'FALLO 1: el digitador pudo leer la tabla Cliente';
END TRY
BEGIN CATCH
    PRINT N'OK 1: digitador sin SELECT directo -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

/* 2. El digitador SÍ puede usar un procedimiento permitido */
EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Catalogo_Listar @catalogo = 'tipo_identificacion';
    PRINT N'OK 2: digitador ejecuta usp_Catalogo_Listar';
END TRY
BEGIN CATCH
    PRINT N'FALLO 2: ' + ERROR_MESSAGE();
END CATCH
REVERT;

/* 3. El digitador NO puede eliminar clientes (id 0, para no borrar nada real) */
EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Cliente_Eliminar @codigo_cliente = 0;
    PRINT N'FALLO 3: el digitador pudo ejecutar usp_Cliente_Eliminar';
END TRY
BEGIN CATCH
    PRINT N'OK 3: digitador sin EXECUTE en Eliminar -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

/* 4. Consulta NO puede escribir */
EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion) VALUES ('X', 'X');
    PRINT N'FALLO 4: consulta pudo insertar';
END TRY
BEGIN CATCH
    PRINT N'OK 4: consulta sin INSERT -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

/* 5. El administrador SÍ escribe, y el trigger igual registra en la bitácora
      (comprueba que el encadenamiento de propiedad funciona con el DENY) */
EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    INSERT INTO dbo.Unidad_Medida (codigo_unidad_medida, descripcion) VALUES ('PRM', 'Prueba permisos');
    DELETE FROM dbo.Unidad_Medida WHERE codigo_unidad_medida = 'PRM';
    PRINT N'OK 5: administrador escribe y el trigger registró en la bitácora';
END TRY
BEGIN CATCH
    PRINT N'FALLO 5: ' + ERROR_MESSAGE();
END CATCH
REVERT;

/* 6. Ni el administrador puede borrar la bitácora */
EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    DELETE FROM dbo.Bitacora_Auditoria;
    PRINT N'FALLO 6: el administrador pudo borrar la bitácora';
END TRY
BEGIN CATCH
    PRINT N'OK 6: bitácora protegida incluso para el administrador -> ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO

/* =====================================================================
   REPORTE DE PERMISOS (úsenlo en la defensa; sirve de base para el
   Reporte de Configuración de Seguridad del REQ 007)
   ===================================================================== */
SELECT r.name AS rol,
       dp.class_desc AS tipo_objeto,
       CASE dp.class
            WHEN 0  THEN DB_NAME()
            WHEN 1  THEN OBJECT_NAME(dp.major_id)
            WHEN 3  THEN SCHEMA_NAME(dp.major_id)
            WHEN 24 THEN (SELECT k.name FROM sys.symmetric_keys k WHERE k.symmetric_key_id = dp.major_id)
            WHEN 25 THEN (SELECT c.name FROM sys.certificates c   WHERE c.certificate_id  = dp.major_id)
            ELSE CONVERT(NVARCHAR(128), dp.major_id)
       END AS objeto,
       dp.permission_name AS permiso,
       dp.state_desc AS estado
FROM sys.database_permissions dp
JOIN sys.database_principals r ON r.principal_id = dp.grantee_principal_id
WHERE r.name IN (N'rol_administrador', N'rol_digitador', N'rol_consulta')
ORDER BY r.name, dp.state_desc, dp.class_desc, objeto, dp.permission_name;
GO
