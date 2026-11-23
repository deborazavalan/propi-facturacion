/* =====================================================================
   PropiDB - REQ 014, paso 4b: CONMUTACIÓN, parte en la secundaria
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERSJ   (la nueva primaria)
   Requisito: haber corrido replicacion_4a_conmutacion_primaria.sql.

   Qué hace:
   1. Detiene las tareas de copia y restauración del trasvase.
   2. Las corre una última vez a mano para aplicar los registros pendientes.
   2b. Cierra las conexiones que haya a PropiDB (evita el error de acceso exclusivo).
   3. Aplica la cola del registro (C:\SQLBackups\PropiDB_tail.trn) con
      RECOVERY: PropiDB queda ONLINE y con escritura en esta instancia.
   4. Protege la llave maestra con la llave de ESTE servidor, para que los
      procedimientos descifren sin contraseña igual que en la primaria.
   5. Verifica: fila de prueba, cantidades, descifrado y RTO medido.

   Después, la aplicación se apunta a localhost\SQLSERVERSJ.
   ===================================================================== */
SET NOEXEC OFF;
GO
USE master;
GO
PRINT N'Instancia actual: ' + @@SERVERNAME;
IF @@SERVERNAME NOT LIKE N'%\SQLSERVERSJ'
BEGIN
    RAISERROR(N'Este script va en SQLSERVERSJ. Están conectadas a otra instancia; no se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO
IF DATABASEPROPERTYEX(N'PropiDB', 'IsInStandBy') <> 1
   AND DATABASEPROPERTYEX(N'PropiDB', 'Status') <> 'RESTORING'
BEGIN
    RAISERROR(N'PropiDB no está en standby aquí. ¿Ya se hizo la conmutación? No se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE PROCEDURE #esperar_tarea @tarea SYSNAME AS
BEGIN
    WAITFOR DELAY '00:00:03';
    WHILE EXISTS (SELECT 1
                  FROM msdb.dbo.sysjobactivity a
                  JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
                  WHERE j.name = @tarea
                    AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
                    AND a.start_execution_date IS NOT NULL
                    AND a.stop_execution_date IS NULL)
        WAITFOR DELAY '00:00:02';
END
GO

/* ---------- 1. Detener copia y restauración automáticas ---------- */
EXEC msdb.dbo.sp_update_job @job_name = N'LSCopy_PropiDB',    @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = N'LSRestore_PropiDB', @enabled = 0;
EXEC #esperar_tarea N'LSCopy_PropiDB';
EXEC #esperar_tarea N'LSRestore_PropiDB';
GO

/* ---------- 2. Última pasada manual: copiar y aplicar lo pendiente ---------- */
EXEC msdb.dbo.sp_start_job @job_name = N'LSCopy_PropiDB';
EXEC #esperar_tarea N'LSCopy_PropiDB';
EXEC msdb.dbo.sp_start_job @job_name = N'LSRestore_PropiDB';
EXEC #esperar_tarea N'LSRestore_PropiDB';
GO

/* ---------- 2b. Cerrar conexiones a PropiDB ----------
   La secundaria en STANDBY acepta lectores. Si una pestaña de SSMS (o la
   aplicación) está conectada, RESTORE LOG falla con "Exclusive access could
   not be obtained". Aquí se cierran todas las conexiones antes de restaurar. */
DECLARE @k NVARCHAR(MAX) = N'';
SELECT @k += N'KILL ' + CONVERT(NVARCHAR(10), s.session_id) + N'; '
FROM sys.dm_exec_sessions s
WHERE s.session_id <> @@SPID
  AND (s.database_id = DB_ID(N'PropiDB')
       OR s.session_id IN (SELECT request_session_id FROM sys.dm_tran_locks
                           WHERE resource_database_id = DB_ID(N'PropiDB')));
PRINT N'Conexiones cerradas: ' + @k;
EXEC (@k);
GO

/* ---------- 3. Cola del registro y puesta en línea ---------- */
RESTORE LOG PropiDB
    FROM DISK = N'C:\SQLBackups\PropiDB_tail.trn'
    WITH RECOVERY;
GO
ALTER DATABASE PropiDB SET MULTI_USER;
GO

/* ---------- 4. Llave maestra protegida por el servidor nuevo ---------- */
USE PropiDB;
GO
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
GO

/* =====================================================================
   VERIFICACIÓN
   ===================================================================== */

/* 1. Debe estar ONLINE, con escritura y en FULL */
SELECT name, state_desc, is_read_only, is_in_standby, user_access_desc, recovery_model_desc
FROM sys.databases WHERE name = N'PropiDB';

/* 2. La fila de prueba escrita en la primaria debe estar aquí (RPO = 0)
      y rto_segundos es el tiempo total de la conmutación */
SELECT id, momento, instancia AS escrita_en, nota,
       @@SERVERNAME AS ahora_en,
       DATEDIFF(SECOND, momento, SYSDATETIME()) AS rto_segundos
FROM dbo.Prueba_REQ014;

/* 3. Mismas cantidades que antes */
SELECT (SELECT COUNT(*) FROM dbo.Cliente)            AS clientes,
       (SELECT COUNT(*) FROM dbo.Factura)            AS facturas,
       (SELECT COUNT(*) FROM dbo.Bitacora_Auditoria) AS filas_auditoria;

/* 4. Descifrado SIN escribir la contraseña de la llave maestra */
OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (3) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
GO
USE master;
GO

SET NOEXEC OFF;
GO
