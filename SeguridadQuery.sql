/* 1. ELIMINAR OBJETOS SI YA EXISTEN
   Esto permite volver a ejecutar el script sin tantos errores.*/

IF OBJECT_ID('vw_Clientes_Consulta', 'V') IS NOT NULL
    DROP VIEW vw_Clientes_Consulta;
GO

IF OBJECT_ID('vw_Empleados_Consulta', 'V') IS NOT NULL
    DROP VIEW vw_Empleados_Consulta;
GO

IF OBJECT_ID('vw_Ventas_Resumen', 'V') IS NOT NULL
    DROP VIEW vw_Ventas_Resumen;
GO

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

/* 6. CREACION DE VISTAS PARA CONSULTAS SEGURAS
   Estas vistas muestran solo la informacion necesaria. */

CREATE VIEW vw_Clientes_Consulta
AS
SELECT
    ClienteID,
    Nombres,
    Apellidos,
    CONCAT('***', RIGHT(Cedula, 4)) AS Cedula_Parcial,
    Telefono,
    Email,
    CiudadID,
    FechaRegistro
FROM Cliente;
GO

CREATE VIEW vw_Empleados_Consulta
AS
SELECT
    EmpleadoID,
    Nombres,
    Apellidos,
    Cargo,
    CiudadID,
    FechaContratacion,
    Activo
FROM Empleados;
GO

CREATE VIEW vw_Ventas_Resumen
AS
SELECT
    v.VentaID,
    v.FechaVenta,
    c.Nombres + ' ' + c.Apellidos AS Cliente,
    e.Nombres + ' ' + e.Apellidos AS Empleado,
    v.Total
FROM Ventas v
INNER JOIN Cliente c
    ON v.ClienteID = c.ClienteID
INNER JOIN Empleados e
    ON v.EmpleadoID = e.EmpleadoID;
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

GRANT SELECT ON vw_Clientes_Consulta TO rol_ventas;
GRANT SELECT ON Producto TO rol_ventas;
GRANT SELECT ON Categorias TO rol_ventas;
GRANT SELECT ON vw_Ventas_Resumen TO rol_ventas;

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
GRANT SELECT ON vw_Empleados_Consulta TO rol_rrhh;
GO

/* Rol auditor:
   Solo puede consultar informacion mediante vistas.
*/

GRANT SELECT ON vw_Clientes_Consulta TO rol_auditor;
GRANT SELECT ON vw_Empleados_Consulta TO rol_auditor;
GRANT SELECT ON vw_Ventas_Resumen TO rol_auditor;
GO

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

SELECT * FROM vw_Clientes_Consulta;
GO

SELECT * FROM Producto;
GO

SELECT * FROM vw_Ventas_Resumen;
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

SELECT * FROM vw_Clientes_Consulta;
GO

SELECT * FROM vw_Empleados_Consulta;
GO

SELECT * FROM vw_Ventas_Resumen;
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

/* ============================================================
   FIN DEL SCRIPT DE SEGURIDAD
   ============================================================ */