/* =====================================================================
   PropiDB - REQ 014, paso 2: activar el trasvase de registros en la PRIMARIA
   ---------------------------------------------------------------------
   EJECUTAR CONECTADA A:  localhost\SQLSERVERPT   (la primaria)
   Requisito: haber corrido replicacion_1_primaria.sql con éxito.

   Qué hace:
   1. Saca un respaldo completo nuevo de PropiDB en C:\SQLBackups\LogShip
      (con ese respaldo se inicializa la secundaria en el paso 3).
   2. Configura PropiDB como base primaria del trasvase de registros.
   3. Crea la tarea del Agent LSBackup_PropiDB, que respalda el registro
      de transacciones cada 10 segundos.
   4. Registra a SQLSERVERSJ como secundaria.
   5. Espera 30 segundos y muestra que ya se están generando respaldos.

   Después de correr este script, corran replicacion_3_secundaria.sql
   en SQLSERVERSJ dentro de los siguientes 30 minutos.
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
IF DB_ID(N'PropiDB') IS NULL
   OR CONVERT(NVARCHAR(20), DATABASEPROPERTYEX(N'PropiDB', 'Recovery')) <> N'FULL'
BEGIN
    RAISERROR(N'PropiDB no existe o no está en FULL. Corran primero replicacion_1_primaria.sql.', 16, 1);
    SET NOEXEC ON;
END
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = N'PropiDB')
BEGIN
    RAISERROR(N'El trasvase ya está configurado para PropiDB en esta instancia. No se cambió nada.', 16, 1);
    SET NOEXEC ON;
END
GO

/* ---------- 1. Respaldo completo inicial ---------- */
BACKUP DATABASE PropiDB
    TO DISK = N'C:\SQLBackups\LogShip\PropiDB_ls_full.bak'
    WITH INIT, FORMAT, CHECKSUM, STATS = 25;
GO

/* ---------- 2 a 4. Configuración de la primaria ---------- */
DECLARE @ret            INT,
        @backup_job_id  UNIQUEIDENTIFIER,
        @primary_id     UNIQUEIDENTIFIER,
        @sched_uid      UNIQUEIDENTIFIER,
        @sched_id       INT,
        @secundaria     NVARCHAR(128) = LEFT(@@SERVERNAME, CHARINDEX(N'\', @@SERVERNAME)) + N'SQLSERVERSJ',
        @hoy            INT = CONVERT(INT, CONVERT(CHAR(8), GETDATE(), 112));

EXEC @ret = master.dbo.sp_add_log_shipping_primary_database
     @database                 = N'PropiDB',
     @backup_directory         = N'C:\SQLBackups\LogShip',
     @backup_share             = N'C:\SQLBackups\LogShip',   -- misma laptop: ruta local
     @backup_job_name          = N'LSBackup_PropiDB',
     @backup_retention_period  = 60,     -- minutos que se guardan los .trn
     @backup_compression       = 2,      -- usa la configuración del servidor
     @backup_threshold         = 5,      -- alerta si pasan 5 min sin respaldo
     @threshold_alert_enabled  = 1,
     @history_retention_period = 1440,
     @backup_job_id            = @backup_job_id OUTPUT,
     @primary_id               = @primary_id OUTPUT,
     @overwrite                = 1;

IF @@ERROR <> 0 OR @ret <> 0
BEGIN
    RAISERROR(N'Falló sp_add_log_shipping_primary_database. Revisen la pestaña Messages.', 16, 1);
    RETURN;
END

/* Horario: todos los días, cada 10 segundos (el mínimo del Agent) */
EXEC msdb.dbo.sp_add_schedule
     @schedule_name          = N'LSBackupSchedule_PropiDB',
     @enabled                = 1,
     @freq_type              = 4,     -- diario
     @freq_interval          = 1,
     @freq_subday_type       = 2,     -- en segundos
     @freq_subday_interval   = 10,
     @freq_recurrence_factor = 0,
     @active_start_date      = @hoy,
     @active_end_date        = 99991231,
     @active_start_time      = 0,
     @active_end_time        = 235959,
     @schedule_uid           = @sched_uid OUTPUT,
     @schedule_id            = @sched_id OUTPUT;

EXEC msdb.dbo.sp_attach_schedule @job_id = @backup_job_id, @schedule_id = @sched_id;
EXEC msdb.dbo.sp_update_job      @job_id = @backup_job_id, @enabled = 1;

EXEC master.dbo.sp_add_log_shipping_primary_secondary
     @primary_database   = N'PropiDB',
     @secondary_server   = @secundaria,
     @secondary_database = N'PropiDB',
     @overwrite          = 1;

PRINT N'Trasvase configurado. Secundaria registrada: ' + @secundaria;
GO

/* =====================================================================
   VERIFICACIÓN (espera 30 s para que corran unos respaldos de registro)
   ===================================================================== */
WAITFOR DELAY '00:00:30';

/* 1. La tarea debe existir y estar habilitada (enabled = 1) */
SELECT j.name AS tarea, j.enabled
FROM msdb.dbo.sysjobs j
WHERE j.name = N'LSBackup_PropiDB';

/* 2. Debe mostrar un último respaldo de hace pocos segundos */
SELECT primary_database,
       last_backup_file,
       last_backup_date,
       DATEDIFF(SECOND, last_backup_date, GETDATE()) AS segundos_desde_ultimo
FROM msdb.dbo.log_shipping_monitor_primary
WHERE primary_database = N'PropiDB';

/* 3. Secundaria registrada */
SELECT secondary_server, secondary_database
FROM msdb.dbo.log_shipping_primary_secondaries;
GO

SET NOEXEC OFF;
GO
