
/* ==========================================================================
   SISTEMA DE AUDITORÍA (Registro y evidencia de eventos)
   ========================================================================== */

-- 1. Crear Tabla Centralizada de Logs
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
    PRINT 'Tabla [AuditoriaLog] creada con éxito.';
END
GO

-- 2. Trigger de Auditoría para la tabla Productos
CREATE TRIGGER trg_Auditar_Productos
ON Productos
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
        SELECT 'Productos', @Accion, ID,
               CONCAT('Producto Añadido: ', Nombre, ' | Precio Inicial: $', Precio, ' | Stock: ', Stock)
        FROM inserted;
    END

    -- Actualizaciones (Registra solo si hay cambios reales en los datos)
    IF @Accion = 'UPDATE'
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Productos', @Accion, i.ID,
               CONCAT('Modificación - Nombre: [', d.Nombre, ' -> ', i.Nombre, 
                      '] | Precio: [$', d.Precio, ' -> $', i.Precio, 
                      '] | Stock: [', d.Stock, ' -> ', i.Stock, ']')
        FROM inserted i
        INNER JOIN deleted d ON i.ID = d.ID
        WHERE i.Precio <> d.Precio OR i.Stock <> d.Stock OR i.Nombre <> d.Nombre;
    END

    -- Eliminaciones
    IF @Accion = 'DELETE'
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Productos', @Accion, ID,
               CONCAT('Producto Eliminado: ', Nombre, ' | Último Precio registrado: $', Precio)
        FROM deleted;
    END
END;
GO

-- 3. Trigger de Auditoría para la tabla Ventas
CREATE TRIGGER trg_Auditar_Ventas
ON Ventas
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Registrar nuevas ventas
    IF EXISTS(SELECT * FROM inserted)
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Ventas', 'INSERT', i.ID,
               CONCAT('Venta Registrada - ProductoID: ', i.ProductoID, ' | Cantidad: ', i.Cantidad)
        FROM inserted i;
    END

    -- Registrar ventas eliminadas (incluyendo eliminaciones en cascada)
    IF EXISTS(SELECT * FROM deleted)
    BEGIN
        INSERT INTO AuditoriaLog (NombreTabla, Accion, RegistroID, Detalles)
        SELECT 'Ventas', 'DELETE', d.ID,
               CONCAT('Venta Removida - ProductoID: ', d.ProductoID, ' | Cantidad original: ', d.Cantidad)
        FROM deleted d;
    END
END;
GO

USE GestionComercial_DB;
GO

/* ==========================================================================
   PRUEBAS DE AUDITORÍA PARA DOCUMENTACIÓN
   ========================================================================== */

-- PRUEBA 1: Inserción de un nuevo producto (Dispara trg_Auditar_Productos - INSERT)
PRINT '--- Ejecutando Prueba 1: INSERT en Productos ---';
INSERT INTO Productos (Nombre, Precio, Stock) 
VALUES ('Mouse Inalámbrico HP', 25.00, 100);
GO

-- PRUEBA 2: Actualización de datos sensibles (Dispara trg_Auditar_Productos - UPDATE)
-- Modificaremos el precio y el stock del producto que acabamos de crear
PRINT '--- Ejecutando Prueba 2: UPDATE en Productos ---';
UPDATE Productos 
SET Precio = 22.50, Stock = 85 
WHERE Nombre = 'Mouse Inalámbrico HP';
GO

-- PRUEBA 3: Inserción de una nueva venta (Dispara trg_Auditar_Ventas - INSERT)
-- Venderemos 2 unidades del producto con ID 1 ('Laptop Dell XPS')
PRINT '--- Ejecutando Prueba 3: INSERT en Ventas ---';
INSERT INTO Ventas (ProductoID, Cantidad) 
VALUES (1, 2);
GO

-- PRUEBA 4: Eliminación de una venta directa (Dispara trg_Auditar_Ventas - DELETE)
-- Eliminaremos la venta que acabamos de registrar (asumiendo que es la Venta ID 1)
PRINT '--- Ejecutando Prueba 4: DELETE directo en Ventas ---';
DELETE FROM Ventas 
WHERE ID = 1;
GO

-- PRUEBA 5: Eliminación en cascada (Dispara ambos triggers)
-- A. Primero creamos una venta atada al 'Monitor ASUS 27"' (ProductoID 2)
INSERT INTO Ventas (ProductoID, Cantidad) VALUES (2, 5);

-- B. Luego eliminamos el producto. 
-- Esto debe borrar el producto Y borrar la venta automáticamente por el CASCADE.
PRINT '--- Ejecutando Prueba 5: DELETE en cascada ---';
DELETE FROM Productos 
WHERE ID = 2;
GO

/* ==========================================================================
   CONSULTA DE RESULTADOS
   ========================================================================== */
PRINT '--- Consultando Bitácora de Auditoría ---';
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