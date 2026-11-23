/* =====================================================================
   PropiDB - REQ 014, paso 5a: CONMUTACIÓN DE REGRESO, parte en SJ
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERSJ   (la primaria actual)

   Qué hace:
   1. Escribe una fila de prueba con la hora exacta (desde aquí se mide
      el RTO).
   2. Cierra las conexiones a PropiDB y hace el respaldo de la cola del
      registro con NORECOVERY. PropiDB queda en RESTORING aquí.
   3. Vuelve a habilitar la copia y restauración del trasvase, para que
      SJ siga siendo la secundaria cuando PT vuelva a ser la primaria.

   Inmediatamente después, corran replicacion_5b_regreso_en_pt.sql en
   SQLSERVERPT.
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
IF DATABASEPROPERTYEX(N'PropiDB', 'Status') <> 'ONLINE'
   OR DATABASEPROPERTYEX(N'PropiDB', 'Updateability') <> 'READ_WRITE'
BEGIN
    RAISERROR(N'PropiDB no está ONLINE con escritura aquí. No se hizo nada.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------- 1. Fila de prueba ---------- */
INSERT PropiDB.dbo.Prueba_REQ014 (momento, instancia, nota)
VALUES (SYSDATETIME(), @@SERVERNAME, N'Último cambio en SJ antes de regresar a PT');
SELECT * FROM PropiDB.dbo.Prueba_REQ014;
GO

/* ---------- 2. Cerrar conexiones y respaldar la cola con NORECOVERY ---------- */
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
ALTER DATABASE PropiDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
BACKUP LOG PropiDB
    TO DISK = N'C:\SQLBackups\PropiDB_tail_sj.trn'
    WITH NORECOVERY, INIT, FORMAT, CHECKSUM;
GO

/* ---------- 3. SJ vuelve a ser secundaria del trasvase ---------- */
EXEC msdb.dbo.sp_update_job @job_name = N'LSCopy_PropiDB',    @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = N'LSRestore_PropiDB', @enabled = 1;
GO

/* Verificación: debe decir RESTORING */
SELECT name, state_desc FROM sys.databases WHERE name = N'PropiDB';
PRINT N'Listo. Ahora corran replicacion_5b_regreso_en_pt.sql en SQLSERVERPT.';
GO

SET NOEXEC OFF;
GO
