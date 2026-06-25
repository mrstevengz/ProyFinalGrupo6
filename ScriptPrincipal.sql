USE TiendaUamDB
GO

-- VISTAS DE LA EMPRESA

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

