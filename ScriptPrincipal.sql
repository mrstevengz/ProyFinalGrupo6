USE TiendaUamDB
GO

--SECCION DIEDEREICH

/* 5.1 Actualización de estadísticas */
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

/* 5.3 Verificación de integridad de la base de datos */
DBCC CHECKDB('TiendaUamDB');
GO

/* ==========================================================================
   6. EXTENDED EVENTS (MONITOREO DE ERRORES)
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

/* Iniciar la sesión */
ALTER EVENT SESSION XE_TiendaUam_Errores ON SERVER STATE = START;
GO

/* Prueba para generar un error capturable en TiendaUamDB */
USE TiendaUamDB;
GO

BEGIN TRY
    -- Intentamos insertar un cliente violando la restricción UNIQUE de Cédula
    INSERT INTO Cliente (Nombres, Apellidos, Cedula, CiudadID) 
    VALUES ('Prueba', 'Error', '001-150201-1000A', 1);
END TRY
BEGIN CATCH
    PRINT 'Error forzado capturado por Extended Events.';
END CATCH;
GO

/* Consulta de verificación: Leer eventos capturados desde el ring_buffer */
WITH Eventos AS
(
    SELECT CAST(t.target_data AS XML) AS TargetData
    FROM sys.dm_xe_session_targets t
    INNER JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name = 'XE_TiendaUam_Errores' AND t.target_name = 'ring_buffer'
)
SELECT 
    Evento.value('@name', 'VARCHAR(100)') AS NombreEvento,
    Evento.value('(data[@name="error_number"]/value)[1]', 'INT') AS NumeroError,
    Evento.value('(data[@name="message"]/value)[1]', 'NVARCHAR(MAX)') AS MensajeError,
    Evento.value('(action[@name="database_name"]/value)[1]', 'SYSNAME') AS BaseDeDatos,
    Evento.value('(action[@name="username"]/value)[1]', 'SYSNAME') AS Usuario,
    Evento.value('(action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') AS ConsultaSQL
FROM Eventos
CROSS APPLY TargetData.nodes('//RingBufferTarget/event') AS X(Evento)
ORDER BY NumeroError DESC;
GO

--FINAL SECCION DIEDEREICH


--Seccion Steven

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
	--DE MOMENTO NO ESTA ACTIVO EL DATABASE MAIL, PENDIENTE A LA CREACION DEL PERFIL
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
			@recipients = ''bodega@tiendauam.com'',
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

--FINAL SECCION STEVEN

--FINAL SCRIPT



/* ==========================================================================
   CONFIGURACIÓN DE DATABASE MAIL - TIENDA UAM
   Sección: Gabriela Guerrero
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