/* =====================================================================
   PropiDB - REQ 014, paso 4a: CONMUTACIÓN, parte en la primaria
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERPT   (la primaria actual)

   Qué hace:
   1. Escribe una fila de prueba en dbo.Prueba_REQ014 con la hora exacta
      (sirve para probar que no se pierde nada y para medir el RTO).
   2. Detiene la tarea de respaldo del trasvase.
   3. Saca a todos de PropiDB y hace el respaldo de la cola del registro
      (tail-log) con NORECOVERY. PropiDB queda en RESTORING en esta
      instancia: ya nadie puede escribir aquí.

   Inmediatamente después, corran replicacion_4b_conmutacion_secundaria.sql
   en SQLSERVERSJ. El RTO se cuenta desde este script.
   ===================================================================== */
SET NOEXEC OFF;
GO
USE master;
GO
PRINT N'Instancia actual: ' + @@SERVERNAME;
IF @@SERVERNAME NOT LIKE N'%\SQLSERVERPT'
BEGIN
    RAISERROR(N'Este script va en SQLSERVERPT. Están conectadas a otra instancia; no se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO
IF DATABASEPROPERTYEX(N'PropiDB', 'Status') <> 'ONLINE'
BEGIN
    RAISERROR(N'PropiDB no está ONLINE aquí. ¿Ya se hizo la conmutación? No se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO

/* Procedimiento temporal: espera a que una tarea del Agent termine */
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

/* ---------- 1. Fila de prueba ---------- */
USE PropiDB;
GO
IF OBJECT_ID(N'dbo.Prueba_REQ014') IS NULL
    CREATE TABLE dbo.Prueba_REQ014 (
        id        INT IDENTITY(1,1) PRIMARY KEY,
        momento   DATETIME2(3)  NOT NULL,
        instancia NVARCHAR(128) NOT NULL,
        nota      NVARCHAR(200) NOT NULL
    );
GO
INSERT dbo.Prueba_REQ014 (momento, instancia, nota)
VALUES (SYSDATETIME(), @@SERVERNAME, N'Último cambio en la primaria antes de la conmutación');
SELECT * FROM dbo.Prueba_REQ014;
GO
USE master;
GO

/* ---------- 2. Detener el respaldo automático ---------- */
EXEC msdb.dbo.sp_update_job @job_name = N'LSBackup_PropiDB', @enabled = 0;
EXEC #esperar_tarea N'LSBackup_PropiDB';
GO

/* ---------- 3. Cola del registro con NORECOVERY ---------- */
ALTER DATABASE PropiDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
BACKUP LOG PropiDB
    TO DISK = N'C:\SQLBackups\PropiDB_tail.trn'
    WITH NORECOVERY, INIT, FORMAT, CHECKSUM;
GO

/* Verificación: debe decir RESTORING */
SELECT name, state_desc FROM sys.databases WHERE name = N'PropiDB';
PRINT N'Listo. Ahora corran replicacion_4b_conmutacion_secundaria.sql en SQLSERVERSJ.';
GO

SET NOEXEC OFF;
GO
