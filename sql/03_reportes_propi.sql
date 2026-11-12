/* =====================================================================
   PropiDB - REQ 007: Reportes (procedimientos almacenados)
   ---------------------------------------------------------------------
   Procedimientos de este archivo:
     1. dbo.usp_Reporte_Clientes     Clientes resumido
     2. dbo.usp_Reporte_Facturas     Facturas por rango de fechas
     3. dbo.usp_Reporte_Auditoria    Pistas de auditoría
     4. dbo.usp_Reporte_Seguridad    Configuración de seguridad

   Todos cumplen con:
   - Manejo de errores con TRY/CATCH (los errores se vuelven a lanzar
     con THROW para que la aplicación los reciba).
   - Manejo de transacciones: BEGIN / COMMIT / ROLLBACK.
   - Documentación técnica en el encabezado de cada procedimiento.
   - Consultas optimizadas: filtros por rango de fechas sin funciones
     sobre la columna (así pueden usar índices) y OPTION (RECOMPILE)
     en las consultas con parámetros opcionales.

   Nivel de aislamiento elegido: SNAPSHOT (reportes de datos)
   ---------------------------------------------------------------------
   Por qué SNAPSHOT:
   - Un reporte lee muchas filas durante varios segundos. Con SNAPSHOT ve
     una "foto" de la base tomada al empezar, así que los números siempre
     son consistentes entre sí (por ejemplo, el subtotal de una factura
     siempre coincide con su detalle, aunque alguien la esté modificando).
   - Los reportes no bloquean a quienes digitan facturas, y los digitadores
     no hacen esperar a los reportes. Es lo más importante en un sistema
     de facturación en uso.
   Por qué no los otros niveles:
   - READ UNCOMMITTED: podría mostrar datos de transacciones que luego se
     cancelan (lecturas sucias). Inaceptable en facturación.
   - READ COMMITTED (por defecto): los reportes esperan a las escrituras
     y, en un reporte largo, pueden mezclar datos de antes y de después.
   - REPEATABLE READ y SERIALIZABLE: retienen bloqueos y frenan a los
     digitadores. Son excesivos para solo leer.
   Costo de SNAPSHOT: usa espacio extra en tempdb (versiones de filas).
   Es aceptable para el volumen de este sistema.
   El reporte de seguridad lee solo vistas del catálogo del sistema, que
   no se versionan, por eso usa READ COMMITTED.

   Índices que se sugieren para el REQ 009 (los crea quien mide el
   rendimiento):
     Cliente(fecha_registro) INCLUDE (estado, ...)  -> usp_Reporte_Clientes
     Factura(fecha) INCLUDE (codigo_cliente, ...)   -> usp_Reporte_Facturas
     Bitacora_Auditoria(fec_registro) INCLUDE (cod_usuario)
                                                    -> usp_Reporte_Auditoria

   Pasos para instalarlo:
     1. Ejecutar este archivo completo.
     2. Volver a ejecutar permisos_roles.sql (toma los nombres
        usp_Reporte_* y asigna los permisos a cada rol).
     3. Ejecutar la PARTE 2 de pruebas que está al final.
   ===================================================================== */
USE PropiDB;
GO

/* Permite el nivel SNAPSHOT en la base (si hay transacciones abiertas en
   otras ventanas de SSMS, cierren esas ventanas y vuelvan a correrlo). */
IF (SELECT snapshot_isolation_state FROM sys.databases WHERE name = N'PropiDB') = 0
    ALTER DATABASE PropiDB SET ALLOW_SNAPSHOT_ISOLATION ON;
GO

/* =====================================================================
   1. usp_Reporte_Clientes
   ---------------------------------------------------------------------
   Propósito : Lista resumida de clientes registrados en un rango de fechas.
   Parámetros: @fecha_desde  DATE      Fecha de registro inicial (obligatoria)
               @fecha_hasta  DATE      Fecha de registro final, incluida (obligatoria)
               @estado       CHAR(1)   'A' activos, 'I' inactivos, 'T' todos
                                       (por defecto 'T')
   Salida    : nombre, numero_identificacion, actividad_economica, correo,
               telefono. La identificación, el correo y el teléfono se
               muestran descifrados.
   Seguridad : WITH EXECUTE AS OWNER, porque descifrar usa la llave
               simétrica y el certificado, a los que el rol de consulta no
               tiene acceso directo.
   Aislamiento: SNAPSHOT.
   Errores propios:
               50050 fechas vacías | 50051 fecha desde mayor que hasta |
               50052 estado inválido
   Ejemplo   : EXEC dbo.usp_Reporte_Clientes '2025-01-01', '2026-12-31', 'A';
   Historial : 1.0  2026-11-07  Daniela Tames  Creación
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Clientes
    @fecha_desde DATE,
    @fecha_hasta DATE,
    @estado      CHAR(1) = 'T'
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;   -- vuelve al nivel anterior al terminar el procedimiento

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50050, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50051, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        SET @estado = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@estado)), ''), 'T'));
        IF @estado NOT IN ('A', 'I', 'T')
            THROW 50052, N'El estado debe ser A (activo), I (inactivo) o T (todos).', 1;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        SELECT c.nombre,
               CONVERT(VARCHAR(50),  DECRYPTBYKEY(c.numero_identificacion)) AS numero_identificacion,
               ae.descripcion                                               AS actividad_economica,
               CONVERT(VARCHAR(150), DECRYPTBYKEY(c.correo))                AS correo,
               CONVERT(VARCHAR(20),  DECRYPTBYKEY(c.telefono))              AS telefono
        FROM dbo.Cliente c
        JOIN dbo.Actividad_Economica ae
          ON ae.codigo_actividad_economica = c.codigo_actividad_economica
        WHERE c.fecha_registro >= @fecha_desde
          AND c.fecha_registro <  DATEADD(DAY, 1, @fecha_hasta)   -- incluye todo el día "hasta"
          AND (@estado = 'T' OR c.estado = @estado)
        ORDER BY c.nombre
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes')
            CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   2. usp_Reporte_Facturas
   ---------------------------------------------------------------------
   Propósito : Facturas emitidas en un rango de fechas, con los datos
               del cliente.
   Parámetros: @fecha_desde  DATE   Fecha inicial de la factura (obligatoria)
               @fecha_hasta  DATE   Fecha final, incluida (obligatoria)
   Salida    : nombre_cliente, numero_identificacion (descifrada),
               actividad_economica, num_factura, fecha, subtotal,
               total_impuestos, total_factura.
   Seguridad : WITH EXECUTE AS OWNER (descifra la identificación).
   Aislamiento: SNAPSHOT.
   Errores propios:
               50053 fechas vacías | 50054 fecha desde mayor que hasta
   Ejemplo   : EXEC dbo.usp_Reporte_Facturas '2026-01-01', '2026-06-30';
   Historial : 1.0  2026-11-07  Daniela Tames  Creación
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Facturas
    @fecha_desde DATE,
    @fecha_hasta DATE
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50053, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50054, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;

        BEGIN TRANSACTION;

        SELECT c.nombre                                                     AS nombre_cliente,
               CONVERT(VARCHAR(50), DECRYPTBYKEY(c.numero_identificacion))  AS numero_identificacion,
               ae.descripcion                                               AS actividad_economica,
               f.num_factura,
               f.fecha,
               f.subtotal,
               f.total_impuestos,
               f.monto_total                                                AS total_factura
        FROM dbo.Factura f
        JOIN dbo.Cliente c
          ON c.codigo_cliente = f.codigo_cliente
        JOIN dbo.Actividad_Economica ae
          ON ae.codigo_actividad_economica = c.codigo_actividad_economica
        WHERE f.fecha >= @fecha_desde
          AND f.fecha <  DATEADD(DAY, 1, @fecha_hasta)
        ORDER BY f.fecha, f.num_factura;

        COMMIT TRANSACTION;
        CLOSE SYMMETRIC KEY sk_propi_clientes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'sk_propi_clientes')
            CLOSE SYMMETRIC KEY sk_propi_clientes;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   3. usp_Reporte_Auditoria
   ---------------------------------------------------------------------
   Propósito : Pistas de auditoría registradas por los triggers en un
               rango de fechas, para un usuario o para todos.
   Parámetros: @fecha_desde  DATE          Fecha de registro inicial (obligatoria)
               @fecha_hasta  DATE          Fecha de registro final, incluida (obligatoria)
               @usuario      VARCHAR(128)  Usuario específico; NULL o vacío = todos
   Salida    : fecha_registro, accion (Inserción / Borrado / Modificación),
               nombre_usuario, tabla_afectada, llave_registro,
               datos_afectados (inserciones y borrados),
               datos_antes y datos_despues (solo modificaciones).
   Seguridad : WITH EXECUTE AS OWNER (la bitácora no se lee directo).
   Aislamiento: SNAPSHOT.
   Notas     : Los datos sensibles de Cliente aparecen cifrados en la
               bitácora a propósito (la auditoría no los expone).
   Errores propios:
               50055 fechas vacías | 50056 fecha desde mayor que hasta
   Ejemplo   : EXEC dbo.usp_Reporte_Auditoria '2026-11-01', '2026-11-30', NULL;
   Historial : 1.0  2026-11-07  Daniela Tames  Creación
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Auditoria
    @fecha_desde DATE,
    @fecha_hasta DATE,
    @usuario     VARCHAR(128) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SNAPSHOT;

    BEGIN TRY
        IF @fecha_desde IS NULL OR @fecha_hasta IS NULL
            THROW 50055, N'Las fechas desde y hasta son obligatorias.', 1;
        IF @fecha_desde > @fecha_hasta
            THROW 50056, N'La fecha desde no puede ser mayor que la fecha hasta.', 1;

        SET @usuario = NULLIF(LTRIM(RTRIM(@usuario)), '');

        BEGIN TRANSACTION;

        SELECT b.fec_registro                                       AS fecha_registro,
               CASE b.ind_accion WHEN 'I' THEN N'Inserción'
                                 WHEN 'D' THEN N'Borrado'
                                 WHEN 'U' THEN N'Modificación' END  AS accion,
               RTRIM(b.cod_usuario)                                 AS nombre_usuario,
               b.cod_tabla                                          AS tabla_afectada,
               b.cod_llave                                          AS llave_registro,
               CASE WHEN b.ind_accion <> 'U' THEN b.des_datos END   AS datos_afectados,
               CASE WHEN b.ind_accion = 'U' AND ISJSON(b.des_datos) = 1
                    THEN JSON_QUERY(b.des_datos, '$.antes') END     AS datos_antes,
               CASE WHEN b.ind_accion = 'U' AND ISJSON(b.des_datos) = 1
                    THEN JSON_QUERY(b.des_datos, '$.despues') END   AS datos_despues
        FROM dbo.Bitacora_Auditoria b
        WHERE b.fec_registro >= @fecha_desde
          AND b.fec_registro <  DATEADD(DAY, 1, @fecha_hasta)
          AND (@usuario IS NULL OR b.cod_usuario = @usuario)   -- CHAR ignora los espacios al final
        ORDER BY b.fec_registro
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   4. usp_Reporte_Seguridad
   ---------------------------------------------------------------------
   Propósito : Muestra qué puede hacer cada usuario de la base de datos
               sobre cada objeto, según los roles a los que pertenece.
   Parámetros: @usuario  SYSNAME  Usuario específico; NULL o vacío = todos
   Salida    : nombre_usuario, rol, nombre_objeto,
               tipo_objeto (Tabla / Vista / Procedimiento / Función),
               tipo_permiso (Selección / Inserción / Borrado /
               Modificación / Execute), estado (GRANT o DENY).
   Notas     : Los permisos dados a nivel de esquema (dbo) se expanden a
               cada objeto del esquema. Un DENY prevalece sobre cualquier
               GRANT del mismo usuario.
   Seguridad : WITH EXECUTE AS OWNER, porque el sistema solo muestra los
               permisos que el usuario que consulta puede ver.
   Aislamiento: READ COMMITTED (solo lee vistas del catálogo del sistema).
   Errores propios: ninguno (valida el usuario si se indica uno).
               50057 usuario no existe en la base de datos
   Ejemplo   : EXEC dbo.usp_Reporte_Seguridad @usuario = 'usr_digitador';
   Historial : 1.0  2026-11-07  Daniela Tames  Creación
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Reporte_Seguridad
    @usuario SYSNAME = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

    BEGIN TRY
        SET @usuario = NULLIF(LTRIM(RTRIM(@usuario)), '');

        IF @usuario IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @usuario AND type IN ('S', 'U'))
            THROW 50057, N'El usuario indicado no existe en la base de datos.', 1;

        BEGIN TRANSACTION;

        SELECT u.name AS nombre_usuario,
               r.name AS rol,
               o.name AS nombre_objeto,
               CASE o.type WHEN 'U'  THEN N'Tabla'
                           WHEN 'V'  THEN N'Vista'
                           WHEN 'P'  THEN N'Procedimiento'
                           WHEN 'FN' THEN N'Función'
                           ELSE o.type_desc END AS tipo_objeto,
               CASE dp.permission_name WHEN 'SELECT'  THEN N'Selección'
                                       WHEN 'INSERT'  THEN N'Inserción'
                                       WHEN 'DELETE'  THEN N'Borrado'
                                       WHEN 'UPDATE'  THEN N'Modificación'
                                       WHEN 'EXECUTE' THEN N'Execute'
                                       ELSE dp.permission_name END AS tipo_permiso,
               dp.state_desc AS estado
        FROM sys.database_principals u
        JOIN sys.database_role_members rm
          ON rm.member_principal_id = u.principal_id
        JOIN sys.database_principals r
          ON r.principal_id = rm.role_principal_id
        JOIN sys.database_permissions dp
          ON dp.grantee_principal_id = r.principal_id
         AND dp.class IN (1, 3)                       -- 1 = objeto, 3 = esquema
        JOIN sys.objects o
          ON (dp.class = 1 AND o.object_id = dp.major_id AND dp.minor_id = 0)
          OR (dp.class = 3 AND o.schema_id = dp.major_id)
        WHERE u.type IN ('S', 'U')
          AND r.type = 'R'
          AND o.is_ms_shipped = 0
          AND dp.permission_name IN ('SELECT', 'INSERT', 'DELETE', 'UPDATE', 'EXECUTE')
          AND (   (dp.permission_name IN ('SELECT', 'INSERT', 'DELETE', 'UPDATE') AND o.type IN ('U', 'V'))
               OR (dp.permission_name = 'EXECUTE' AND o.type IN ('P', 'FN')))
          AND (@usuario IS NULL OR u.name = @usuario)
        ORDER BY u.name, r.name, o.name, dp.permission_name
        OPTION (RECOMPILE);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   PARTE 2: PRUEBAS
   Ejecutar DESPUÉS de volver a correr permisos_roles.sql.
   ===================================================================== */

/* El nivel SNAPSHOT debe estar activo (debe decir ON) */
SELECT name, snapshot_isolation_state_desc FROM sys.databases WHERE name = N'PropiDB';

/* Funcionamiento de los 4 reportes */
EXEC dbo.usp_Reporte_Clientes   @fecha_desde = '2024-01-01', @fecha_hasta = '2026-12-31', @estado = 'T';
EXEC dbo.usp_Reporte_Clientes   @fecha_desde = '2024-01-01', @fecha_hasta = '2026-12-31', @estado = 'I';
EXEC dbo.usp_Reporte_Facturas   @fecha_desde = '2025-01-01', @fecha_hasta = '2026-12-31';
EXEC dbo.usp_Reporte_Auditoria  @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @usuario = NULL;
EXEC dbo.usp_Reporte_Seguridad  @usuario = NULL;
EXEC dbo.usp_Reporte_Seguridad  @usuario = 'usr_digitador';

/* Manejo de errores: debe imprimir OK */
BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-12-31', @fecha_hasta = '2026-01-01', @estado = 'T';
    PRINT N'FALLO: no detectó fechas invertidas';
END TRY
BEGIN CATCH
    PRINT N'OK validación de fechas -> ' + ERROR_MESSAGE();
END CATCH

BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @estado = 'X';
    PRINT N'FALLO: no detectó el estado inválido';
END TRY
BEGIN CATCH
    PRINT N'OK validación de estado -> ' + ERROR_MESSAGE();
END CATCH

/* Permisos por rol: debe imprimir OK en las 4 pruebas */
EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    EXEC dbo.usp_Reporte_Clientes @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31', @estado = 'T';
    PRINT N'OK consulta ejecuta el reporte de clientes';
END TRY
BEGIN CATCH
    PRINT N'FALLO consulta/clientes: ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_consulta';
BEGIN TRY
    EXEC dbo.usp_Reporte_Auditoria @fecha_desde = '2026-01-01', @fecha_hasta = '2026-12-31';
    PRINT N'FALLO: consulta pudo ver la auditoría';
END TRY
BEGIN CATCH
    PRINT N'OK consulta sin acceso a la auditoría -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_digitador';
BEGIN TRY
    EXEC dbo.usp_Reporte_Seguridad;
    PRINT N'FALLO: el digitador pudo ver la seguridad';
END TRY
BEGIN CATCH
    PRINT N'OK digitador sin acceso al reporte de seguridad -> ' + ERROR_MESSAGE();
END CATCH
REVERT;

EXECUTE AS USER = N'usr_admin';
BEGIN TRY
    EXEC dbo.usp_Reporte_Seguridad @usuario = 'usr_consulta';
    PRINT N'OK administrador ejecuta el reporte de seguridad';
END TRY
BEGIN CATCH
    PRINT N'FALLO admin/seguridad: ' + ERROR_MESSAGE();
END CATCH
REVERT;
GO
