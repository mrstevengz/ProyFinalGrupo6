USE TiendaUamDB
GO



/* ==========================================================================
   SECCION 1: DIEDEREICH (Mantenimiento y Extended Events)
   ========================================================================== */

/* Actualización de estadísticas */
EXEC sp_updatestats;
GO

/* Consulta de verificación: estadísticas actualizadas */
SELECT 
    OBJECT_NAME(s.object_id) AS Tabla,
    s.name AS Estadistica,
    STATS_DATE(s.object_id, s.stats_id) AS FechaUltimaActualizacion
FROM sys.stats s
WHERE OBJECT_NAME(s.object_id) IN ('Categorias', 'Ciudades', 'Cliente', 'Empleados', 'Producto', 'Ventas', 'DetalleVentas')
ORDER BY Tabla, Estadistica;
GO

/* 5.2 Reorganización de índices */
ALTER INDEX ALL ON Categorias REORGANIZE;
ALTER INDEX ALL ON Ciudades REORGANIZE;
ALTER INDEX ALL ON Cliente REORGANIZE;
ALTER INDEX ALL ON Empleados REORGANIZE;
ALTER INDEX ALL ON Producto REORGANIZE;
ALTER INDEX ALL ON Ventas REORGANIZE;
ALTER INDEX ALL ON DetalleVentas REORGANIZE;
GO

/* Consulta de verificación: fragmentación de índices */
SELECT 
    OBJECT_NAME(ips.object_id) AS Tabla,
    i.name AS Indice,
    ips.index_type_desc AS TipoIndice,
    ips.avg_fragmentation_in_percent AS FragmentacionPorcentaje
FROM sys.dm_db_index_physical_stats(DB_ID('TiendaUamDB'), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE OBJECT_NAME(ips.object_id) IN ('Categorias', 'Ciudades', 'Cliente', 'Empleados', 'Producto', 'Ventas', 'DetalleVentas')
ORDER BY FragmentacionPorcentaje DESC;
GO

/* Verificación de integridad de la base de datos */
DBCC CHECKDB('TiendaUamDB');
GO

/* ==========================================================================
   EXTENDED EVENTS (MONITOREO DE ERRORES)
   ========================================================================== */

USE master;
GO

/* Eliminar la sesión si ya existe para evitar errores */
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = 'XE_TiendaUam_Errores')
    DROP EVENT SESSION XE_TiendaUam_Errores ON SERVER;
GO

/* Crear sesión para capturar errores de T-SQL en TiendaUamDB */
CREATE EVENT SESSION XE_TiendaUam_Errores ON SERVER 
ADD EVENT sqlserver.error_reported
(
    ACTION 
    (
        sqlserver.sql_text,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.database_name
    )
    /* Filtramos únicamente los errores que ocurran dentro de nuestra BD */
    WHERE (sqlserver.database_name = N'TiendaUamDB')
)
ADD TARGET package0.ring_buffer;
GO


--FINAL SECCION DIEDEREICH

/* ==========================================================================
   SECCION 2: STEVEN (Vistas, Funciones, Procedimientos y Agent Jobs)
   ========================================================================== */

-- VISTAS DE LA EMPRESA

USE TiendaUamDB;
GO

CREATE VIEW dbo.vw_VentasDetalladas
AS
SELECT
	v.VentaID,
	v.FechaVenta,
	c.ClienteID,
	(c.Nombres + ' ' + c.Apellidos) as Cliente,
	e.EmpleadoID,
	(e.Nombres + ' ' + e.Apellidos) as Empleado,
	p.ProductoID,
	p.Nombre as Producto,
	cat.Nombre as Categoria,
	dv.Cantidad,
	dv.PrecioUnitario,
	dv.Subtotal PERSISTED

FROM Ventas v
INNER JOIN Cliente c ON c.ClienteID = v.ClienteID
INNER JOIN Empleados e ON e.EmpleadoID = v.EmpleadoID
INNER JOIN DetalleVentas dv on dv.VentaID = v.VentaID
INNER JOIN Producto p on p.ProductoID = dv.ProductoID
INNER JOIN Categorias cat ON cat.CategoriaID =p.CategoriaID
GO

CREATE VIEW dbo.vw_ResumenVentasPorCliente
AS
SELECT
	c.ClienteID,
	(c.Nombres + ' ' + c.Apellidos) as Cliente,
	ci.Nombre as Ciudad,
	COUNT(v.VentaID) as CantidadVentas,
	ISNULL(SUM(v.Total),0) as MontoTotal,
	ISNULL(AVG(v.Total), 0) as TicketPromedio
FROM Cliente c
INNER JOIN Ciudades ci ON ci.CiudadID = c.CiudadID
LEFT JOIN Ventas v ON v.ClienteID = c.ClienteID
GROUP BY c.ClienteID, c.Nombres,c.Apellidos, ci.Nombre
GO

CREATE VIEW dbo.vw_ProductosBajoStock
AS
SELECT
	p.ProductoID,
	p.Nombre as Producto,
	cat.Nombre as Categoria,
	p.Stock,
	p.PrecioUnitario
FROM Producto p
INNER JOIN Categorias cat ON cat.CategoriaID = p.CategoriaID
WHERE p.Activo = 1 AND p.Stock <= 100 --Umbral
GO

--FUNCIONES DE LA EMPRESA

CREATE FUNCTION dbo.fn_TotalVenta(
@VentaID INT
)
RETURNS DECIMAL(12,2)
AS
BEGIN
	DECLARE @Total DECIMAL(12,2)
	SELECT @Total = ISNULL(SUM(Subtotal),0)
	FROM DetalleVentas
	WHERE VentaID = @VentaID

	RETURN @Total
END
GO

CREATE FUNCTION dbo.fn_CalcularDescuento(@Monto DECIMAL(12,2))
RETURNS DECIMAL(12,2)
AS
BEGIN
	Declare @Descuento DECIMAL(12,2)

	SET @Descuento =
	CASE
		WHEN @Monto >= 500 THEN @Monto * 0.10
		WHEN @Monto >= 200 THEN @Monto * 0.05
	END

	RETURN @Descuento
END
GO

CREATE FUNCTION dbo.fn_VentasPorRango
(
	@FechaInicio DATETIME,
	@FechaFin DATETIME
)
RETURNS TABLE
AS
RETURN
(
	SELECT
		v.VentaID,
		v.FechaVenta,
		(c.Nombres + ' ' + c.Apellidos) AS Cliente,
		(e.Nombres + ' ' + e.Apellidos) AS Empleado,
		v.Total
	FROM Ventas v
	INNER JOIN Cliente c ON c.ClienteID = v.ClienteID
	INNER JOIN Empleados e ON e.EmpleadoID = v.EmpleadoID
	WHERE v.FechaVenta >= @FechaInicio
	AND v.FechaVenta < DATEADD(DAY, 1, @FechaFin)
)
GO

--PROCEDIMIENTOS ALMACENADOS

CREATE PROCEDURE dbo.sp_RegistrarVenta
	@ClienteID INT,
	@EmpleadoID INT,
	@ProductoID INT,
	@Cantidad INT,
	@VentaID INT OUTPUT
AS
BEGIN
	SET NOCOUNT ON

	BEGIN TRY
	--Validacion de entrada
	IF @Cantidad <= 0
		THROW 50001, 'La cantidad debe ser mayor a cero', 1

		DECLARE @StockActual INT, @Precio DECIMAL(12,2)

		SELECT @StockActual= Stock, @Precio = PrecioUnitario
		FROM Producto
		WHERE ProductoID = @ProductoID AND Activo = 1

		IF @StockActual IS NULL
			THROW 50002, 'El producto no existe o esta inactivo', 1

		IF @StockActual < @Cantidad
			THROW 50003, 'Stock insuficiente para realizar la venta', 1


		BEGIN TRANSACTION

			--Cabecera de la venta
			INSERT INTO Ventas(ClienteID, EmpleadoID, Total)
			VALUES(@ClienteID, @EmpleadoID, 0)
			
			SET @VentaID = SCOPE_IDENTITY()

			--Linea de detalle
			INSERT INTO DetalleVentas(VentaID, ProductoID, Cantidad, PrecioUnitario)
			VALUES(@VentaID, @ProductoID, @Cantidad, @Precio)

			--Descontar del stock
			UPDATE Producto
			SET Stock = Stock - @Cantidad
			WHERE ProductoID = @ProductoID

			--Recalcular total
			UPDATE Ventas
			SET Total = dbo.fn_TotalVenta(@VentaID) --Se usa la funcion
			WHERE VentaID = @VentaID

		COMMIT TRANSACTION
		PRINT 'Venta registrada correctamente. VentaID = ' + CAST(@VentaID AS NVARCHAR(10))

	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION
		THROW
	END CATCH
END
GO

--Procedimiento 2
CREATE PROCEDURE dbo.sp_AgregarDetalleVenta
	@VentaID INT,
	@ProductoID INT,
	@Cantidad INT
AS
BEGIN
	SET NOCOUNT ON

	BEGIN TRY
		IF NOT EXISTS(SELECT 1 FROM Ventas WHERE VentaID = @VentaID)
			THROW 50010, 'La venta no existe', 1

		DECLARE @StockActual INT, @Precio DECIMAL(12,2)

		SELECT @StockActual = Stock, @Precio = PrecioUnitario
		FROM Producto
		WHERE ProductoID = @ProductoID AND Activo = 1

		IF @StockActual IS NULL
			THROW 50011, 'El producto no existe o esta inactivo', 1;

		IF @StockActual < @Cantidad
			THROW 50012, 'Stock insuficiente', 1;


		BEGIN TRANSACTION

			INSERT INTO DetalleVentas (VentaID, ProductoID, Cantidad, PrecioUnitario)
			VALUES (@VentaID, @ProductoID, @Cantidad, @Precio)

			UPDATE Producto
			SET Stock = Stock - @Cantidad
			WHERE ProductoID = @ProductoID

			UPDATE Ventas
			SET Total = dbo.fn_TotalVenta(@VentaID)
			WHERE VentaID = @VentaID
		COMMIT TRANSACTION
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0
			ROLLBACK TRANSACTION
		THROW
	END CATCH
END
GO

--Procedimiento 3

CREATE PROCEDURE sp_ReporteVentasDiarias @Fecha DATE = NULL
AS
BEGIN
	SET NOCOUNT ON

	IF @Fecha IS NULL
		SET @Fecha = CAST(GETDATE() AS DATE)

	--Resumen de las ventas
	SELECT 
		@Fecha AS Fecha,
		COUNT(*) AS CantidadVentas,
		ISNULL(SUM(Total), 0) as MontoTotal
	FROM Ventas
	WHERE CAST(FechaVenta as DATE) = @Fecha

	--Ventas detalladas del dia
	SELECT *
	FROM dbo.vw_VentasDetalladas
	WHERE CAST(FechaVenta as DATE) = @Fecha
	ORDER BY VentaID
END
GO

--PROCEDIMIENTO 4

CREATE PROCEDURE sp_ActualizarStock @ProductoID INT, @Cantidad INT
AS
BEGIN
	SET NOCOUNT ON

	IF @Cantidad <= 0
		THROW 50020, 'La cantidad a ingresar debe ser positiva', 1;

	IF NOT EXISTS(SELECT 1 FROM Producto WHERE ProductoID = @ProductoID)
		THROW 50021, 'El producto no existe', 1;

	UPDATE Producto
	SET Stock = Stock + @Cantidad
	WHERE ProductoID = @ProductoID

	PRINT 'Stock actualizado'
END
GO

--SQL SERVER AGENT JOBS

--JOB 1

USE msdb
GO

EXEC msdb.dbo.sp_add_job
	@job_name = 'TiendaUam_ReporteVentasDiarias',
	@enabled = 1,
	@description= 'Genera el reporte del dia de forma automatica'
GO

EXEC msdb.dbo.sp_add_jobstep
	@job_name ='TiendaUam_ReporteVentasDiarias',
	@step_name = 'Ejecutar cierre de ventas',
	@subsystem = 'TSQL',
	@database_name = 'TiendaUamDB',
	@command = N'EXEC dbo.sp_ReporteVentasDiarias;',
	@on_success_action = 1,
	@retry_attempts = 1,
	@retry_interval = 1
GO

EXEC msdb.dbo.sp_add_schedule
	@schedule_name = 'Horario_Diario_11-00',
	@freq_type = 4,
	@freq_interval = 1,
	@active_start_time = 230000
GO

EXEC msdb.dbo.sp_attach_schedule
	@job_name = 'TiendaUam_ReporteVentasDiarias',
	@schedule_name = 'Horario_Diario_11-00'
GO

EXEC msdb.dbo.sp_add_jobserver
	@job_name= 'TiendaUam_ReporteVentasDiarias'
GO

--JOB 2

USE msdb
GO

EXEC msdb.dbo.sp_add_job
	@job_name = 'TiendaUam_AlertaBajoStock',
	@enabled = 1,
	@description = 'Notifica por correo los productos con stock critico.'
GO

EXEC msdb.dbo.sp_add_jobstep
	@job_name ='TiendaUam_AlertaBajoStock',
	@step_name = 'Revisar stock y notificar',
	@subsystem = 'TSQL',
	@database_name = 'TiendaUamDB',
	--DE MOMENTO NO ESTA ACTIVO EL DATABASE MAIL, PENDIENTE A LA CREACION DEL PERFIL. DESCOMENTARIAR CUANDO SE CORRA EL DATABASE MAIL
	@command = N'
	DECLARE @cuenta INT;
	SELECT @cuenta = COUNT(*) FROM dbo.vw_ProductosBajoStock

	IF @cuenta > 0
	BEGIN 
		DECLARE @cuerpo NVARCHAR(MAX)
		SELECT @cuerpo = 
			STRING_AGG(
				CONCAT(Producto, '' ('', Categoria, '') - Stock: ''Stock),
				CHAR(13) + CHAR(10)
			)
		FROM dbo.vw_ProductosBajoStock
		
		/*EXEC msdb.dbo.sp_send_dbmail
			@profile_name = ''PerfilTiendaUam'',
			@recipients = ''ggpaiz@uamv.edu.ni'',
			@subject = ''ALERTA: Productos con stock critico'',
			@body = @cuerpo;*/
	END',
	@retry_attempts = 1,
	@retry_interval = 1
GO

EXEC msdb.dbo.sp_add_schedule
	@schedule_name = 'Horario_Diario_0800',
	@freq_type = 4,
	@freq_interval = 1,
	@active_start_time = 080000
GO

EXEC msdb.dbo.sp_attach_schedule
	@job_name = 'TiendaUam_AlertaBajoStock',
	@schedule_name = 'Horario_Diario_0800'
GO

EXEC msdb.dbo.sp_add_jobserver
	@job_name= 'TiendaUam_AlertaBajoStock'
GO

--JOB 3

USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'TiendaUam_Mantenimiento_TiendaUam')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'TiendaUam_Mantenimiento_TiendaUam';
END;
GO

/* Crear Job */
EXEC msdb.dbo.sp_add_job 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam',
    @enabled = 1,
    @description = 'Job para ejecutar mantenimiento automático diario de la base de datos TiendaUamDB.';
GO

/* Paso 1: Actualizar estadísticas */
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam',
    @step_name = 'Actualizar estadísticas TiendaUamDB',
    @subsystem = 'TSQL',
    @database_name = 'TiendaUamDB',
    @command = 'EXEC sp_updatestats;';
GO

/* Paso 2: Reorganizar índices */
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam',
    @step_name = 'Reorganizar índices TiendaUamDB',
    @subsystem = 'TSQL',
    @database_name = 'TiendaUamDB',
    @command = '
        ALTER INDEX ALL ON Categorias REORGANIZE;
        ALTER INDEX ALL ON Ciudades REORGANIZE;
        ALTER INDEX ALL ON Cliente REORGANIZE;
        ALTER INDEX ALL ON Empleados REORGANIZE;
        ALTER INDEX ALL ON Producto REORGANIZE;
        ALTER INDEX ALL ON Ventas REORGANIZE;
        ALTER INDEX ALL ON DetalleVentas REORGANIZE;
    ';
GO

/* Paso 3: Verificar integridad */
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam',
    @step_name = 'Verificar integridad TiendaUamDB',
    @subsystem = 'TSQL',
    @database_name = 'TiendaUamDB',
    @command = 'DBCC CHECKDB(''TiendaUamDB'');';
GO

/* Crear horario diario (ej: a las 2:00 AM, horario de baja carga) */
IF EXISTS (SELECT * FROM msdb.dbo.sysschedules WHERE name = 'Horario_Diario_TiendaUam-0200')
BEGIN
    EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'Horario_Diario_TiendaUam';
END;
GO

EXEC msdb.dbo.sp_add_schedule 
    @schedule_name = 'Horario_Diario_TiendaUam-0200',
    @freq_type = 4, -- Diario
    @freq_interval = 1,
    @active_start_time = 020000; -- 2:00:00 AM
GO

EXEC msdb.dbo.sp_attach_schedule 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam',
    @schedule_name = 'Horario_Diario_TiendaUam-0200';
GO

EXEC msdb.dbo.sp_add_jobserver 
    @job_name = 'TiendaUam_Mantenimiento_TiendaUam';
GO


-- (Las pruebas de evidencia de esta seccion se movieron a la
--  SECCION DE PRUEBAS / VERIFICACION al final del script.)

--FINAL SECCION STEVEN

/* ==========================================================================
   CONFIGURACIÓN DE DATABASE MAIL - TIENDA UAM
   Inicio de la sección: Gabriela Michelle Guerero Paiz
   ========================================================================== */

USE master;
GO
/* --------------------------------------------------------------------------
   Paso 1: Habilitar las opciones avanzadas y el componente Database Mail
-------------------------------------------------------------------------- */

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE;
GO

/* --------------------------------------------------------------------------
   Paso 2: Crear la cuenta de correo (Account)
   Nota: Modificar el correo, display_name y credenciales según el servidor
-------------------------------------------------------------------------- */

USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_account WHERE name = 'CuentaNotificacionesUam')
BEGIN
	EXEC sysmail_delete_account_sp @account_name = 'CuentaNotificacionesUam';
END
GO

EXEC sysmail_add_account_sp
	@account_name = 'CuentaNotificacionesUam',
	@description = 'Cuenta de correo donde se envian las notificaciondes de TiendaUamDB',
	@email_address = 'ggpaiz@uamv.edu.ni',
	@display_name = 'Notificaciones Tienda UAM',
	@mailserver_name = 'smtp.gmail.com',
	@port = 587,
	@enable_ssl = 1,
	@username = 'ggpaiz@uamv.edu.ni',
	@password = 'mary pfga yltt vchl';
GO

/* --------------------------------------------------------------------------
   Paso 3: Crear el perfil de Database Mail (Profile)
-------------------------------------------------------------------------- */

IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profile WHERE name = 'PerfilTiendaUam')
BEGIN
	EXEC sysmail_delete_profile_sp @profile_name = 'PerfilTiendaUam';
END
GO

EXEC sysmail_add_profile_sp
	@profile_name = 'PerfilTiendaUam',
	@description = 'Perfil para la base de datos TiendaUamDB';
GO

/* --------------------------------------------------------------------------
   Paso 4: Asociar la cuenta al perfil
-------------------------------------------------------------------------- */

EXEC sysmail_add_profileaccount_sp
	@profile_name = 'PerfilTiendaUam',
	@account_name = 'CuentaNotificacionesUam',
	@sequence_number = 1;
GO

/* --------------------------------------------------------------------------
   Paso 5: Conceder permisos de uso del perfil al rol publico
-------------------------------------------------------------------------- */

EXEC sysmail_add_principalprofile_sp
	@profile_name = 'PerfilTiendaUam',
	@principal_name = 'public',
	@is_default = 1;
GO


/* (Las evidencias de funcionamiento de Database Mail se movieron a la
   SECCION DE PRUEBAS / VERIFICACION al final del script.) */

--Actualizacion del JOB 2 creado anteriormente para que funcione con el Database Mail configurado

EXEC sp_update_jobstep 
    @job_name = 'TiendaUam_AlertaBajoStock', 
    @step_id = 1, 
    @command = N'
	DECLARE @cuenta INT;
	SELECT @cuenta = COUNT(*) FROM TiendaUamDB.dbo.vw_ProductosBajoStock;

	IF @cuenta > 0
	BEGIN 
		DECLARE @cuerpo NVARCHAR(MAX);
		SELECT @cuerpo = 
			STRING_AGG(
				CONCAT(Producto, '' ('', Categoria, '') - Stock: '', Stock),
				CHAR(13) + CHAR(10)
			)
		FROM TiendaUamDB.dbo.vw_ProductosBajoStock;
		
		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = ''PerfilTiendaUam'',
			@recipients = ''ggpaiz@uamv.edu.ni'', -- Actualizado para tu presentacion
			@subject = ''ALERTA: Productos con stock critico'',
			@body = @cuerpo;
	END';
GO

/* ==========================================================================
   Fin de la sección de : Gabriela Guerrero
   ========================================================================== */

/* ==========================================================================
   SECCION 4: AUDITORIA (Dereck) - CONFIGURACION
   ========================================================================== */

USE TiendaUamDB;
GO

/* --------------------------------------------------------------------------
   1. Tabla Centralizada de Logs
-------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.AuditoriaLog', 'U') IS NULL
BEGIN
    CREATE TABLE AuditoriaLog (
        LogID           INT IDENTITY(1,1) PRIMARY KEY,
        NombreTabla     NVARCHAR(50)  NOT NULL,
        Accion          NVARCHAR(20)  NOT NULL,
        UsuarioBD       NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
        FechaHora       DATETIME      NOT NULL DEFAULT GETDATE(),
        RegistroID      INT           NOT NULL,
        Detalles        NVARCHAR(MAX) NULL
    );
    PRINT 'Tabla [AuditoriaLog] creada con exito.';
END
GO

/* --------------------------------------------------------------------------
   2. Trigger de Auditoria para la tabla Producto
-------------------------------------------------------------------------- */
CREATE TRIGGER trg_Auditar_Producto
ON Producto
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Accion NVARCHAR(20);

    IF EXISTS(SELECT * FROM inserted) AND EXISTS(SELECT * FROM deleted)
        SET @Accion = 'UPDATE';
    ELSE IF EXISTS(SELECT * FROM inserted)
        SET @Accion = 'INSERT';
    ELSE IF EXISTS(SELECT * FROM deleted)
        SET @Accion = 'DELETE';

    -- Inserciones
    IF @Accion = 'INSERT'
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Producto', @Accion, ProductoID,
               CONCAT('Producto Anadido: ', Nombre, ' | Precio Inicial: $', PrecioUnitario, ' | Stock: ', Stock)
        FROM inserted;
    END

    -- Actualizaciones (Registra solo si hay cambios reales en los datos)
    IF @Accion = 'UPDATE'
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Producto', @Accion, i.ProductoID,
               CONCAT('Modificacion - Nombre: [', d.Nombre, ' -> ', i.Nombre,
                      '] | Precio: [$', d.PrecioUnitario, ' -> $', i.PrecioUnitario,
                      '] | Stock: [', d.Stock, ' -> ', i.Stock, ']')
        FROM inserted i
        INNER JOIN deleted d ON i.ProductoID = d.ProductoID
        WHERE i.PrecioUnitario <> d.PrecioUnitario OR i.Stock <> d.Stock OR i.Nombre <> d.Nombre;
    END

    -- Eliminaciones
    IF @Accion = 'DELETE'
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Producto', @Accion, ProductoID,
               CONCAT('Producto Eliminado: ', Nombre, ' | Ultimo Precio registrado: $', PrecioUnitario)
        FROM deleted;
    END
END;
GO

/* --------------------------------------------------------------------------
   3. Trigger de Auditoria para la tabla DetalleVentas
   (equivale al detalle de producto vendido: tiene ProductoID y Cantidad)
-------------------------------------------------------------------------- */
CREATE TRIGGER trg_Auditar_DetalleVentas
ON DetalleVentas
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Registrar nuevas lineas de venta
    IF EXISTS(SELECT * FROM inserted)
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'DetalleVentas', 'INSERT', i.DetalleID,
               CONCAT('Detalle Registrado - VentaID: ', i.VentaID, ' | ProductoID: ', i.ProductoID, ' | Cantidad: ', i.Cantidad)
        FROM inserted i;
    END

    -- Registrar lineas eliminadas
    IF EXISTS(SELECT * FROM deleted)
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'DetalleVentas', 'DELETE', d.DetalleID,
               CONCAT('Detalle Removido - VentaID: ', d.VentaID, ' | ProductoID: ', d.ProductoID, ' | Cantidad original: ', d.Cantidad)
        FROM deleted d;
    END
END;
GO

/* SECCION DE SEGURIDAD - DAVIS 
	EJECUTAR DESPUES DE CREAR VIEWS
*/

/* 1. ELIMINAR OBJETOS SI YA EXISTEN
   Esto permite volver a ejecutar el script sin tantos errores.*/

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'usr_admin_tienda')
    DROP USER usr_admin_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'usr_ventas_tienda')
    DROP USER usr_ventas_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'usr_bodega_tienda')
    DROP USER usr_bodega_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'usr_rrhh_tienda')
    DROP USER usr_rrhh_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'usr_auditor_tienda')
    DROP USER usr_auditor_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_admin_tienda')
    DROP ROLE rol_admin_tienda;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_ventas')
    DROP ROLE rol_ventas;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_bodega')
    DROP ROLE rol_bodega;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_rrhh')
    DROP ROLE rol_rrhh;
GO

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_auditor')
    DROP ROLE rol_auditor;
GO

USE master;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'login_admin_tienda')
    DROP LOGIN login_admin_tienda;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'login_ventas_tienda')
    DROP LOGIN login_ventas_tienda;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'login_bodega_tienda')
    DROP LOGIN login_bodega_tienda;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'login_rrhh_tienda')
    DROP LOGIN login_rrhh_tienda;
GO

IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'login_auditor_tienda')
    DROP LOGIN login_auditor_tienda;
GO

/* 2. CREACION DE LOGINS
   Los logins permiten entrar al servidor SQL Server. */

CREATE LOGIN login_admin_tienda
WITH PASSWORD = 'AdminUAM2026*';
GO

CREATE LOGIN login_ventas_tienda
WITH PASSWORD = 'VentasUAM2026*';
GO

CREATE LOGIN login_bodega_tienda
WITH PASSWORD = 'BodegaUAM2026*';
GO

CREATE LOGIN login_rrhh_tienda
WITH PASSWORD = 'RRHHUAM2026*';
GO

CREATE LOGIN login_auditor_tienda
WITH PASSWORD = 'AuditorUAM2026*';
GO

/* 3. CREACION DE USUARIOS EN LA BASE DE DATOS
   Cada usuario se relaciona con un login. */

USE TiendaUamDB;
GO

CREATE USER usr_admin_tienda FOR LOGIN login_admin_tienda;
GO

CREATE USER usr_ventas_tienda FOR LOGIN login_ventas_tienda;
GO

CREATE USER usr_bodega_tienda FOR LOGIN login_bodega_tienda;
GO

CREATE USER usr_rrhh_tienda FOR LOGIN login_rrhh_tienda;
GO

CREATE USER usr_auditor_tienda FOR LOGIN login_auditor_tienda;
GO

/* 4. CREACION DE ROLES
   Los roles sirven para agrupar permisos. */

CREATE ROLE rol_admin_tienda;
GO

CREATE ROLE rol_ventas;
GO

CREATE ROLE rol_bodega;
GO

CREATE ROLE rol_rrhh;
GO

CREATE ROLE rol_auditor;
GO

/* 5. ASIGNAR USUARIOS A ROLES */

ALTER ROLE rol_admin_tienda ADD MEMBER usr_admin_tienda;
GO

ALTER ROLE rol_ventas ADD MEMBER usr_ventas_tienda;
GO

ALTER ROLE rol_bodega ADD MEMBER usr_bodega_tienda;
GO

ALTER ROLE rol_rrhh ADD MEMBER usr_rrhh_tienda;
GO

ALTER ROLE rol_auditor ADD MEMBER usr_auditor_tienda;
GO

/* 7. ASIGNACION DE PERMISOS
   Se otorgan permisos segun el tipo de usuario. */

/* Rol administrador:
   Puede consultar, insertar, actualizar y eliminar datos principales. */

GRANT SELECT, INSERT, UPDATE, DELETE ON Categorias TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON Ciudades TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON Cliente TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON Empleados TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON Producto TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON Ventas TO rol_admin_tienda;
GRANT SELECT, INSERT, UPDATE, DELETE ON DetalleVentas TO rol_admin_tienda;
GO

/* Rol ventas:
   Puede consultar clientes mediante una vista,
   consultar productos y registrar ventas.
*/

GRANT SELECT ON vw_VentasDetalladas TO rol_ventas;
GRANT SELECT ON Producto TO rol_ventas;
GRANT SELECT ON Categorias TO rol_ventas;
GRANT SELECT ON vw_ResumenVentasPorCliente TO rol_ventas;

GRANT INSERT ON Ventas TO rol_ventas;
GRANT INSERT ON DetalleVentas TO rol_ventas;
GRANT UPDATE ON Ventas TO rol_ventas;
GO

/* Rol bodega:
   Puede consultar productos y actualizar el stock.
*/

GRANT SELECT ON Producto TO rol_bodega;
GRANT SELECT ON Categorias TO rol_bodega;
GRANT UPDATE ON Producto TO rol_bodega;
GO

/* Rol recursos humanos:
   Puede consultar y actualizar informacion de empleados.
*/

GRANT SELECT, INSERT, UPDATE ON Empleados TO rol_rrhh;
GRANT SELECT ON Ciudades TO rol_rrhh;
GO

/* Rol auditor:
   Solo puede consultar informacion mediante vistas.
*/

GRANT SELECT ON vw_ProductosBajoStock TO rol_auditor;
GRANT SELECT ON vw_ResumenVentasPorCliente TO rol_auditor;
GRANT SELECT ON vw_VentasDetalladas TO rol_auditor;
GO


/* ============================================================
   FIN DEL SCRIPT DE SEGURIDAD
   ============================================================ */


/* ==========================================================================
   SECCION DE PRUEBAS / VERIFICACION
   Ejecutar al final, no incluir al crear la base de datos
   ========================================================================== */

/* ---- PRUEBAS SECCION 1: DIEDEREICH ---- 
	ESTAN EN SU SECCION PARA VERIFICAR INMEDIATAMENTE LOS CAMBIOS
*/

/* ---- Pruebas de la SECCION 2: STEVEN ---- */

--DEMOSTRACIONES DE EVIDENCIA

USE TiendaUamDB;
GO

-- Probar VISTAS
SELECT TOP 10 * FROM dbo.vw_VentasDetalladas;
SELECT * FROM dbo.vw_ResumenVentasPorCliente ORDER BY MontoTotal DESC;
SELECT * FROM dbo.vw_ProductosBajoStock;
GO

-- Probar FUNCIONES
SELECT dbo.fn_TotalVenta(1)            AS TotalVenta1;
SELECT dbo.fn_CalcularDescuento(550)   AS Descuento_550;  -- 10%
SELECT dbo.fn_CalcularDescuento(250)   AS Descuento_250;  -- 5%
SELECT * FROM dbo.fn_VentasPorRango('2025-06-01', '2025-06-05');
GO

-- Probar PROCEDIMIENTOS
DECLARE @NuevaVenta INT;
EXEC dbo.sp_RegistrarVenta
     @ClienteID = 1, @EmpleadoID = 2,
     @ProductoID = 1, @Cantidad = 3,
     @VentaID = @NuevaVenta OUTPUT;

EXEC dbo.sp_AgregarDetalleVenta
     @VentaID = @NuevaVenta, @ProductoID = 2, @Cantidad = 2;

SELECT * FROM dbo.vw_VentasDetalladas WHERE VentaID = @NuevaVenta;
GO

EXEC dbo.sp_ActualizarStock @ProductoID = 3, @Cantidad = 50;
EXEC dbo.sp_ReporteVentasDiarias @Fecha = '2025-06-01';
GO

-- Probar JOBS manualmente (evidencia de ejecucion)
EXEC msdb.dbo.sp_start_job @job_name = 'TiendaUam_ReporteVentasDiarias';
EXEC msdb.dbo.sp_start_job @job_name = 'TiendaUam_AlertaBajoStock';
EXEC msdb.dbo.sp_start_job @job_name = 'TiendaUam_Mantenimiento_TiendaUam';
GO

-- Consultar historial de ejecucion de los jobs (evidencia)
SELECT j.name AS Job,
       h.run_date, h.run_time,
       CASE h.run_status
            WHEN 0 THEN 'Fallido' WHEN 1 THEN 'Exitoso'
            WHEN 2 THEN 'Reintento' WHEN 3 THEN 'Cancelado'
       END AS Estado,
       h.message
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory h ON h.job_id = j.job_id
WHERE j.name LIKE 'TiendaUam_%'
ORDER BY h.run_date DESC, h.run_time DESC;
GO

/* ---- Pruebas de la SECCION 3: GABRIELA (Database Mail) ---- */

/* ==========================================================================
   EVIDENCIAS DE FUNCIONAMIENTO (DEMOSTRACIÓN)
   ========================================================================== */

/* 1. Enviar un correo de prueba manual */
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'PerfilTiendaUam',
    @recipients = 'ggpaiz@uamv.edu.ni',
    @subject = 'Prueba de Configuración - Tienda UAM',
    @body = 'Este es un mensaje automático de prueba generado desde SQL Server. El componente Database Mail ha sido configurado exitosamente para el proyecto.';
GO

/* 2. Consultar el registro de correos para verificar el estado de los envíos */
-- Mostrar los correos que salieron sin problemas
SELECT mailitem_id, recipients, subject, send_request_date, sent_status 
FROM msdb.dbo.sysmail_allitems
WHERE sent_status = 'sent';
GO

-- Mostrar el registro de errores (muy util si algo falla en la presentacion)
SELECT * FROM msdb.dbo.sysmail_event_log
ORDER BY log_date DESC;
GO

/* ==========================================================================
   SECCION 4: AUDITORIA - PRUEBAS
   ========================================================================== */

USE TiendaUamDB;
GO

-- PRUEBA 1: Insercion de un nuevo producto (Dispara trg_Auditar_Producto - INSERT)
-- Nota: Producto requiere CategoriaID (FK). Se usa la categoria 1 (Bebidas).
PRINT '--- Ejecutando Prueba 1: INSERT en Producto ---';
INSERT INTO Producto (Nombre, CategoriaID, PrecioUnitario, Stock)
VALUES ('Mouse Inalambrico HP', 1, 25.00, 100);
GO

-- PRUEBA 2: Actualizacion de datos sensibles (Dispara trg_Auditar_Producto - UPDATE)
-- Modificaremos el precio y el stock del producto que acabamos de crear
PRINT '--- Ejecutando Prueba 2: UPDATE en Producto ---';
UPDATE Producto
SET PrecioUnitario = 22.50, Stock = 85
WHERE Nombre = 'Mouse Inalambrico HP';
GO

-- PRUEBA 3: Insercion de una nueva linea de venta (Dispara trg_Auditar_DetalleVentas - INSERT)
-- Agregamos 2 unidades del producto ID 1 ('Coca-Cola 1.5L') a la venta ID 1.
PRINT '--- Ejecutando Prueba 3: INSERT en DetalleVentas ---';
INSERT INTO DetalleVentas (VentaID, ProductoID, Cantidad, PrecioUnitario)
VALUES (1, 1, 2, 45.00);
GO

-- PRUEBA 4: Eliminacion de una linea de venta (Dispara trg_Auditar_DetalleVentas - DELETE)
-- Eliminamos la linea de detalle que acabamos de registrar en la Prueba 3.
PRINT '--- Ejecutando Prueba 4: DELETE en DetalleVentas ---';
DELETE FROM DetalleVentas
WHERE VentaID = 1 AND ProductoID = 1 AND Cantidad = 2;
GO

-- PRUEBA 5: Eliminacion de producto con su detalle asociado (Dispara ambos triggers)
-- Nota: TiendaUamDB NO define ON DELETE CASCADE, por lo que primero se elimina la
-- linea de detalle (dispara trg_Auditar_DetalleVentas) y luego el producto
-- (dispara trg_Auditar_Producto). Usamos el producto creado en la Prueba 1.
PRINT '--- Ejecutando Prueba 5: DELETE de producto y su detalle ---';
DECLARE @ProdPrueba INT = (SELECT ProductoID FROM Producto WHERE Nombre = 'Mouse Inalambrico HP');

-- A. Creamos una linea de venta atada a ese producto
INSERT INTO DetalleVentas (VentaID, ProductoID, Cantidad, PrecioUnitario)
VALUES (1, @ProdPrueba, 5, 22.50);

-- B. Eliminamos primero el detalle y luego el producto
DELETE FROM DetalleVentas WHERE ProductoID = @ProdPrueba;
DELETE FROM Producto      WHERE ProductoID = @ProdPrueba;
GO

/* ==========================================================================
   CONSULTA DE RESULTADOS
   ========================================================================== */
PRINT '--- Consultando Bitacora de Auditoria ---';
SELECT
    LogID,
    NombreTabla,
    Accion,
    UsuarioBD,
    FORMAT(FechaHora, 'yyyy-MM-dd HH:mm:ss') AS FechaHora,
    RegistroID,
    Detalles
FROM AuditoriaLog
ORDER BY LogID ASC;
GO

--PRUEBAS DE SEGURIDAD

/* 8. CONSULTAS DE VERIFICACION
   Estas consultas sirven como evidencia para capturas. */

/* Ver usuarios creados */

SELECT
    name AS Usuario,
    type_desc AS Tipo
FROM sys.database_principals
WHERE name LIKE 'usr_%';
GO

/* Ver roles creados */

SELECT
    name AS Rol,
    type_desc AS Tipo
FROM sys.database_principals
WHERE name LIKE 'rol_%';
GO

/* Ver usuarios asignados a roles */

SELECT
    r.name AS Rol,
    u.name AS Usuario
FROM sys.database_role_members rm
INNER JOIN sys.database_principals r
    ON rm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals u
    ON rm.member_principal_id = u.principal_id
WHERE r.name LIKE 'rol_%';
GO

/* Ver permisos asignados */

SELECT
    usuario.name AS Rol,
    permiso.permission_name AS Permiso,
    permiso.state_desc AS Estado,
    OBJECT_NAME(permiso.major_id) AS Objeto
FROM sys.database_permissions permiso
INNER JOIN sys.database_principals usuario
    ON permiso.grantee_principal_id = usuario.principal_id
WHERE usuario.name LIKE 'rol_%';
GO

/* 9. PRUEBAS BASICAS DE FUNCIONAMIENTO
   Estas pruebas muestran que cada usuario tiene permisos diferentes. */

/* Prueba con usuario de ventas */

EXECUTE AS USER = 'usr_ventas_tienda';
GO

SELECT USER_NAME() AS Usuario_Actual;
GO

SELECT * FROM vw_VentasDetalladas;
GO

SELECT * FROM Producto;
GO

SELECT * FROM vw_ResumenVentasPorCliente;
GO

REVERT;
GO

/* Prueba con usuario de bodega */

EXECUTE AS USER = 'usr_bodega_tienda';
GO

SELECT USER_NAME() AS Usuario_Actual;
GO

SELECT * FROM Producto;
GO

UPDATE Producto
SET Stock = Stock + 5
WHERE ProductoID = 1;
GO

SELECT * FROM Producto WHERE ProductoID = 1;
GO

REVERT;
GO

/* Prueba con usuario de recursos humanos */

EXECUTE AS USER = 'usr_rrhh_tienda';
GO

SELECT USER_NAME() AS Usuario_Actual;
GO

SELECT * FROM Empleados;
GO

REVERT;
GO

/* Prueba con usuario auditor */

EXECUTE AS USER = 'usr_auditor_tienda';
GO

SELECT USER_NAME() AS Usuario_Actual;
GO

SELECT * FROM vw_VentasDetalladas;
GO

SELECT * FROM vw_ResumenVentasPorCliente;
GO

SELECT * FROM vw_ProductosBajoStock;
GO

REVERT;
GO

/* Prueba con usuario administrador */

EXECUTE AS USER = 'usr_admin_tienda';
GO

SELECT USER_NAME() AS Usuario_Actual;
GO

SELECT * FROM Cliente;
GO

SELECT * FROM Empleados;
GO

SELECT * FROM Ventas;
GO

REVERT;
GO
