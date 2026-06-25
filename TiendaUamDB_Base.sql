/* ==========================================================================
   TiendaUamDB - Script Base con Mantenimiento y Extended Events
   Universidad Americana (UAM)
   Propósito: Base de datos funcional con estrategias de administración, 
   monitoreo de errores y automatización de mantenimiento.
   ========================================================================== */

USE master;
GO

IF DB_ID('TiendaUamDB') IS NOT NULL
BEGIN
    ALTER DATABASE TiendaUamDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TiendaUamDB;
END
GO

CREATE DATABASE TiendaUamDB;
GO

USE TiendaUamDB;
GO

/* ==========================================================================
   1. TABLAS CATÁLOGO
   ========================================================================== */

CREATE TABLE Categorias (
    CategoriaID     INT IDENTITY(1,1) PRIMARY KEY,
    Nombre          NVARCHAR(60)  NOT NULL,
    Descripcion     NVARCHAR(200) NULL,
    Activo          BIT           NOT NULL DEFAULT 1
);
GO

CREATE TABLE Ciudades (
    CiudadID        INT IDENTITY(1,1) PRIMARY KEY,
    Nombre          NVARCHAR(80)  NOT NULL,
    Departamento    NVARCHAR(80)  NOT NULL,
    Pais            NVARCHAR(60)  NOT NULL DEFAULT 'Nicaragua'
);
GO

/* ==========================================================================
   2. TABLAS PRINCIPALES
   ========================================================================== */

CREATE TABLE Cliente (
    ClienteID       INT IDENTITY(1,1) PRIMARY KEY,
    Nombres         NVARCHAR(80)  NOT NULL,
    Apellidos       NVARCHAR(80)  NOT NULL,
    Cedula          NVARCHAR(20)  NOT NULL UNIQUE,
    Telefono        NVARCHAR(20)  NULL,
    Email           NVARCHAR(120) NULL,
    CiudadID        INT           NOT NULL,
    FechaRegistro   DATETIME      NOT NULL DEFAULT GETDATE(),
    CONSTRAINT FK_Cliente_Ciudad FOREIGN KEY (CiudadID)
        REFERENCES Ciudades(CiudadID)
);
GO

CREATE TABLE Empleados (
    EmpleadoID      INT IDENTITY(1,1) PRIMARY KEY,
    Nombres         NVARCHAR(80)  NOT NULL,
    Apellidos       NVARCHAR(80)  NOT NULL,
    Cedula          NVARCHAR(20)  NOT NULL UNIQUE,
    Cargo           NVARCHAR(60)  NOT NULL,
    Salario         DECIMAL(12,2) NOT NULL CHECK (Salario >= 0),
    CiudadID        INT           NOT NULL,
    FechaContratacion DATE        NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Activo          BIT           NOT NULL DEFAULT 1,
    CONSTRAINT FK_Empleado_Ciudad FOREIGN KEY (CiudadID)
        REFERENCES Ciudades(CiudadID)
);
GO

CREATE TABLE Producto (
    ProductoID      INT IDENTITY(1,1) PRIMARY KEY,
    Nombre          NVARCHAR(120) NOT NULL,
    CategoriaID     INT           NOT NULL,
    PrecioUnitario  DECIMAL(12,2) NOT NULL CHECK (PrecioUnitario >= 0),
    Stock           INT           NOT NULL DEFAULT 0 CHECK (Stock >= 0),
    Activo          BIT           NOT NULL DEFAULT 1,
    CONSTRAINT FK_Producto_Categoria FOREIGN KEY (CategoriaID)
        REFERENCES Categorias(CategoriaID)
);
GO

CREATE TABLE Ventas (
    VentaID         INT IDENTITY(1,1) PRIMARY KEY,
    ClienteID       INT           NOT NULL,
    EmpleadoID      INT           NOT NULL,
    FechaVenta      DATETIME      NOT NULL DEFAULT GETDATE(),
    Total           DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (Total >= 0),
    CONSTRAINT FK_Venta_Cliente  FOREIGN KEY (ClienteID)
        REFERENCES Cliente(ClienteID),
    CONSTRAINT FK_Venta_Empleado FOREIGN KEY (EmpleadoID)
        REFERENCES Empleados(EmpleadoID)
);
GO

CREATE TABLE DetalleVentas (
    DetalleID       INT IDENTITY(1,1) PRIMARY KEY,
    VentaID         INT           NOT NULL,
    ProductoID      INT           NOT NULL,
    Cantidad        INT           NOT NULL CHECK (Cantidad > 0),
    PrecioUnitario  DECIMAL(12,2) NOT NULL CHECK (PrecioUnitario >= 0),
    Subtotal        AS (Cantidad * PrecioUnitario) PERSISTED,
    CONSTRAINT FK_Detalle_Venta    FOREIGN KEY (VentaID)
        REFERENCES Ventas(VentaID),
    CONSTRAINT FK_Detalle_Producto FOREIGN KEY (ProductoID)
        REFERENCES Producto(ProductoID)
);
GO

/* ==========================================================================
   3. INSERCIONES
   ========================================================================== */

-- Categorías
INSERT INTO Categorias (Nombre, Descripcion) VALUES
('Bebidas',      'Bebidas frias y calientes'),
('Snacks',       'Galletas, frituras y dulces'),
('Limpieza',     'Productos de aseo del hogar'),
('Higiene',      'Cuidado e higiene personal'),
('Abarrotes',    'Granos basicos y enlatados');
GO

-- Ciudades
INSERT INTO Ciudades (Nombre, Departamento, Pais) VALUES
('Managua',     'Managua',     'Nicaragua'),
('Leon',        'Leon',        'Nicaragua'),
('Granada',     'Granada',     'Nicaragua'),
('Masaya',      'Masaya',      'Nicaragua'),
('Esteli',      'Esteli',      'Nicaragua');
GO

-- Cliente
INSERT INTO Cliente (Nombres, Apellidos, Cedula, Telefono, Email, CiudadID) VALUES
('Steven',   'Martinez',  '001-150201-1000A', '8888-1001', 'steven@correo.com',   1),
('Gabriela', 'Guerrero',  '001-220302-1001B', '8888-1002', 'gabriela@correo.com', 2),
('Carlos',   'Lopez',     '001-130403-1002C', '8888-1003', 'carlos@correo.com',   3),
('Maria',    'Gomez',     '001-100504-1003D', '8888-1004', 'maria@correo.com',    4),
('Luis',     'Hernandez', '001-080605-1004E', '8888-1005', 'luis@correo.com',     5);
GO

-- Empleados
INSERT INTO Empleados (Nombres, Apellidos, Cedula, Cargo, Salario, CiudadID) VALUES
('Pedro',   'Ramirez',  '001-010180-2000A', 'Administrador', 25000.00, 1),
('Ana',     'Torres',   '001-020281-2001B', 'Cajero',        12000.00, 1),
('Jose',    'Mendoza',  '001-030382-2002C', 'Vendedor',      11000.00, 2),
('Laura',   'Castro',   '001-040483-2003D', 'Vendedor',      11000.00, 3),
('Roberto', 'Flores',   '001-050584-2004E', 'Bodeguero',     10000.00, 4);
GO

-- Producto
INSERT INTO Producto (Nombre, CategoriaID, PrecioUnitario, Stock) VALUES
('Coca-Cola 1.5L',         1, 45.00, 120),
('Galletas Oreo',          2, 22.50, 200),
('Cloro 1L',               3, 30.00,  80),
('Jabon de tocador',       4, 18.00, 150),
('Arroz 1lb',              5, 16.00, 300);
GO

-- Ventas (cabecera)
INSERT INTO Ventas (ClienteID, EmpleadoID, FechaVenta, Total) VALUES
(1, 2, '2025-06-01T10:15:00', 0),
(2, 3, '2025-06-02T11:30:00', 0),
(3, 4, '2025-06-03T09:45:00', 0),
(4, 2, '2025-06-04T14:20:00', 0),
(5, 3, '2025-06-05T16:05:00', 0);
GO

-- DetalleVentas
INSERT INTO DetalleVentas (VentaID, ProductoID, Cantidad, PrecioUnitario) VALUES
(1, 1, 2, 45.00),
(1, 2, 3, 22.50),
(2, 3, 1, 30.00),
(2, 5, 5, 16.00),
(3, 4, 4, 18.00),
(4, 1, 1, 45.00),
(4, 2, 2, 22.50),
(5, 5, 10, 16.00);
GO

-- Recalcular el Total de cada venta
UPDATE v
SET v.Total = d.SumaTotal
FROM Ventas v
INNER JOIN (
    SELECT VentaID, SUM(Subtotal) AS SumaTotal
    FROM DetalleVentas
    GROUP BY VentaID
) d ON d.VentaID = v.VentaID;
GO

/* ==========================================================================
   4. VERIFICACIÓN RÁPIDA
   ========================================================================== */
SELECT 'Categorias' AS Tabla, COUNT(*) AS Registros FROM Categorias
UNION ALL SELECT 'Ciudades',      COUNT(*) FROM Ciudades
UNION ALL SELECT 'Cliente',       COUNT(*) FROM Cliente
UNION ALL SELECT 'Empleados',     COUNT(*) FROM Empleados
UNION ALL SELECT 'Producto',      COUNT(*) FROM Producto
UNION ALL SELECT 'Ventas',        COUNT(*) FROM Ventas
UNION ALL SELECT 'DetalleVentas', COUNT(*) FROM DetalleVentas;
GO

/* ==========================================================================
   5. PLAN DE MANTENIMIENTO MANUAL
   ========================================================================== */

USE TiendaUamDB;
GO

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

/* ==========================================================================
   7. SQL SERVER AGENT JOB (AUTOMATIZACIÓN DEL MANTENIMIENTO)
   ========================================================================== */

USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'JOB_Mantenimiento_TiendaUam')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = 'JOB_Mantenimiento_TiendaUam';
END;
GO

/* Crear Job */
EXEC msdb.dbo.sp_add_job 
    @job_name = 'JOB_Mantenimiento_TiendaUam',
    @enabled = 1,
    @description = 'Job para ejecutar mantenimiento automático diario de la base de datos TiendaUamDB.';
GO

/* Paso 1: Actualizar estadísticas */
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = 'JOB_Mantenimiento_TiendaUam',
    @step_name = 'Actualizar estadísticas TiendaUamDB',
    @subsystem = 'TSQL',
    @database_name = 'TiendaUamDB',
    @command = 'EXEC sp_updatestats;';
GO

/* Paso 2: Reorganizar índices */
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = 'JOB_Mantenimiento_TiendaUam',
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
    @job_name = 'JOB_Mantenimiento_TiendaUam',
    @step_name = 'Verificar integridad TiendaUamDB',
    @subsystem = 'TSQL',
    @database_name = 'TiendaUamDB',
    @command = 'DBCC CHECKDB(''TiendaUamDB'');';
GO

/* Crear horario diario (ej: a las 2:00 AM, horario de baja carga) */
IF EXISTS (SELECT * FROM msdb.dbo.sysschedules WHERE name = 'Horario_Diario_TiendaUam')
BEGIN
    EXEC msdb.dbo.sp_delete_schedule @schedule_name = 'Horario_Diario_TiendaUam';
END;
GO

EXEC msdb.dbo.sp_add_schedule 
    @schedule_name = 'Horario_Diario_TiendaUam',
    @freq_type = 4, -- Diario
    @freq_interval = 1,
    @active_start_time = 020000; -- 2:00:00 AM
GO

EXEC msdb.dbo.sp_attach_schedule 
    @job_name = 'JOB_Mantenimiento_TiendaUam',
    @schedule_name = 'Horario_Diario_TiendaUam';
GO

EXEC msdb.dbo.sp_add_jobserver 
    @job_name = 'JOB_Mantenimiento_TiendaUam';
GO

/* Ejecutar Job manualmente por primera vez para comprobar funcionalidad */
EXEC msdb.dbo.sp_start_job @job_name = 'JOB_Mantenimiento_TiendaUam';
GO

/* ==========================================================================
   FIN DEL SCRIPT
   ========================================================================== */