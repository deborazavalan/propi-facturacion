/* =====================================================================
   PropiDB - REQ 014, paso 3: preparar la SECUNDARIA
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERSJ   (la secundaria)
   Requisito: haber corrido replicacion_2_primaria_trasvase.sql en
   SQLSERVERPT hace menos de 30 minutos.

   Qué hace:
   1. Restaura PropiDB desde C:\SQLBackups\LogShip\PropiDB_ls_full.bak en
      modo STANDBY (solo lectura, sigue aceptando registros).
   2. Crea la tarea LSCopy_PropiDB (copia los .trn cada 10 s) y la tarea
      LSRestore_PropiDB (los aplica cada 10 s).
   3. Crea los 3 logins con el MISMO SID que en la primaria, para que los
      usuarios de la base funcionen aquí sin ajustes al conmutar.
   4. Espera 45 segundos y verifica copia, restauración, datos y descifrado.

   Si PropiDB ya existe en esta instancia, el script se detiene.
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
IF DB_ID(N'PropiDB') IS NOT NULL
BEGIN
    RAISERROR(N'PropiDB ya existe en esta instancia. El script se detiene para no sobrescribirla.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------- 1. Restaurar en STANDBY ---------- */
DECLARE @d NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultDataPath'));
DECLARE @l NVARCHAR(260) = CONVERT(NVARCHAR(260), SERVERPROPERTY('InstanceDefaultLogPath'));
DECLARE @sql NVARCHAR(MAX) =
    N'RESTORE DATABASE PropiDB FROM DISK = N''C:\SQLBackups\LogShip\PropiDB_ls_full.bak'' '
  + N'WITH MOVE N''PropiDB''     TO N''' + @d + N'PropiDB.mdf'', '
  + N'     MOVE N''PropiDB_log'' TO N''' + @l + N'PropiDB_log.ldf'', '
  + N'STANDBY = N''C:\SQLBackups\LogShipCopy\PropiDB_standby.tuf'', STATS = 25;';
EXEC sys.sp_executesql @sql;
GO

/* ---------- 2. Configuración de la secundaria ---------- */
DECLARE @ret             INT,
        @copy_job_id     UNIQUEIDENTIFIER,
        @restore_job_id  UNIQUEIDENTIFIER,
        @secondary_id    UNIQUEIDENTIFIER,
        @sched_uid       UNIQUEIDENTIFIER,
        @copy_sched_id   INT,
        @rest_sched_id   INT,
        @primaria        NVARCHAR(128) = LEFT(@@SERVERNAME, CHARINDEX(N'\', @@SERVERNAME)) + N'SQLSERVERPT',
        @hoy             INT = CONVERT(INT, CONVERT(CHAR(8), GETDATE(), 112));

EXEC @ret = master.dbo.sp_add_log_shipping_secondary_primary
     @primary_server               = @primaria,
     @primary_database             = N'PropiDB',
     @backup_source_directory      = N'C:\SQLBackups\LogShip',
     @backup_destination_directory = N'C:\SQLBackups\LogShipCopy',
     @copy_job_name                = N'LSCopy_PropiDB',
     @restore_job_name             = N'LSRestore_PropiDB',
     @file_retention_period        = 60,
     @overwrite                    = 1,
     @copy_job_id                  = @copy_job_id OUTPUT,
     @restore_job_id               = @restore_job_id OUTPUT,
     @secondary_id                 = @secondary_id OUTPUT;

IF @@ERROR <> 0 OR @ret <> 0
BEGIN
    RAISERROR(N'Falló sp_add_log_shipping_secondary_primary. Revisen la pestaña Messages.', 16, 1);
    RETURN;
END

/* Horario de copia: cada 10 s */
EXEC msdb.dbo.sp_add_schedule
     @schedule_name = N'LSCopySchedule_PropiDB', @enabled = 1,
     @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 2, @freq_subday_interval = 10,
     @freq_recurrence_factor = 0,
     @active_start_date = @hoy, @active_end_date = 99991231,
     @active_start_time = 0, @active_end_time = 235959,
     @schedule_uid = @sched_uid OUTPUT, @schedule_id = @copy_sched_id OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @copy_job_id, @schedule_id = @copy_sched_id;

/* Horario de restauración: cada 10 s */
EXEC msdb.dbo.sp_add_schedule
     @schedule_name = N'LSRestoreSchedule_PropiDB', @enabled = 1,
     @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 2, @freq_subday_interval = 10,
     @freq_recurrence_factor = 0,
     @active_start_date = @hoy, @active_end_date = 99991231,
     @active_start_time = 0, @active_end_time = 235959,
     @schedule_uid = @sched_uid OUTPUT, @schedule_id = @rest_sched_id OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @restore_job_id, @schedule_id = @rest_sched_id;

EXEC @ret = master.dbo.sp_add_log_shipping_secondary_database
     @secondary_database       = N'PropiDB',
     @primary_server           = @primaria,
     @primary_database         = N'PropiDB',
     @restore_delay            = 0,
     @restore_mode             = 1,   -- STANDBY: solo lectura entre restauraciones
     @disconnect_users         = 1,   -- saca a quien esté leyendo cuando toca restaurar
     @restore_threshold        = 5,   -- alerta si pasan 5 min sin restaurar
     @threshold_alert_enabled  = 1,
     @history_retention_period = 1440,
     @overwrite                = 1;

IF @@ERROR <> 0 OR @ret <> 0
BEGIN
    RAISERROR(N'Falló sp_add_log_shipping_secondary_database. Revisen la pestaña Messages.', 16, 1);
    RETURN;
END

EXEC msdb.dbo.sp_update_job @job_id = @copy_job_id,    @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_id = @restore_job_id, @enabled = 1;

PRINT N'Secundaria configurada. Primaria: ' + @primaria;
GO

/* ---------- 3. Logins con el mismo SID que los usuarios de la base ---------- */
DECLARE @s NVARCHAR(MAX) = N'';
SELECT @s += N'IF SUSER_ID(N''' + dp.name + N''') IS NULL CREATE LOGIN ' + QUOTENAME(dp.name)
           + N' WITH PASSWORD = N'''
           + CASE dp.name WHEN N'usr_admin'     THEN N'Adm!n_Propi2026'
                          WHEN N'usr_digitador' THEN N'D!gita_Propi2026'
                          ELSE N'C0nsulta_Propi2026!' END
           + N''', SID = ' + CONVERT(NVARCHAR(200), dp.sid, 1)
           + N', DEFAULT_DATABASE = PropiDB, CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;' + NCHAR(10)
FROM PropiDB.sys.database_principals dp
WHERE dp.name IN (N'usr_admin', N'usr_digitador', N'usr_consulta');
EXEC sys.sp_executesql @s;
GO

/* =====================================================================
   VERIFICACIÓN (espera 45 s para que corran copia y restauración)
   ===================================================================== */
WAITFOR DELAY '00:00:45';

/* 1. Las dos tareas deben existir y estar habilitadas */
SELECT name AS tarea, enabled
FROM msdb.dbo.sysjobs
WHERE name IN (N'LSCopy_PropiDB', N'LSRestore_PropiDB');

/* 2. Último archivo copiado y restaurado, hace pocos segundos */
SELECT secondary_database,
       last_copied_file,   last_copied_date,
       last_restored_file, last_restored_date,
       DATEDIFF(SECOND, last_restored_date, GETDATE()) AS segundos_desde_ultima_restauracion,
       last_restored_latency AS latencia_min
FROM msdb.dbo.log_shipping_monitor_secondary
WHERE secondary_database = N'PropiDB';

/* 3. La base debe verse en STANDBY / solo lectura */
SELECT name, state_desc, is_in_standby, is_read_only
FROM sys.databases WHERE name = N'PropiDB';

/* 4. Logins enlazados (las 3 filas deben tener login) */
SELECT dp.name AS usuario, sp.name AS login
FROM PropiDB.sys.database_principals dp
LEFT JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE dp.name IN (N'usr_admin', N'usr_digitador', N'usr_consulta');

/* 5. Mismas cantidades que en la primaria */
SELECT (SELECT COUNT(*) FROM PropiDB.dbo.Cliente)            AS clientes,
       (SELECT COUNT(*) FROM PropiDB.dbo.Factura)            AS facturas,
       (SELECT COUNT(*) FROM PropiDB.dbo.Bitacora_Auditoria) AS filas_auditoria;
GO

/* 6. Descifrado en la secundaria. Aquí la llave maestra se abre con su
      contraseña porque esta instancia tiene otra llave de servidor. Si
      justo coincide con una restauración puede salir "session killed":
      vuelvan a ejecutar solo este bloque. */
USE PropiDB;
GO
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Propi_MasterKey_2026!';
OPEN SYMMETRIC KEY sk_propi_clientes DECRYPTION BY CERTIFICATE cert_propi_clientes;
SELECT TOP (3) codigo_cliente, nombre,
       CONVERT(VARCHAR(50),  DECRYPTBYKEY(numero_identificacion)) AS numero_identificacion,
       CONVERT(VARCHAR(150), DECRYPTBYKEY(correo))                AS correo,
       CONVERT(VARCHAR(20),  DECRYPTBYKEY(telefono))              AS telefono
FROM dbo.Cliente
ORDER BY codigo_cliente DESC;
CLOSE SYMMETRIC KEY sk_propi_clientes;
CLOSE MASTER KEY;
GO
USE master;
GO

SET NOEXEC OFF;
GO
