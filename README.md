# 🛒 TiendaUamDB - Sistema Centralizado de Base de Datos

![SQL Server](https://img.shields.io/badge/SQL_Server-2022-CC2927?style=for-the-badge&logo=microsoft-sql-server&logoColor=white)
![T-SQL](https://img.shields.io/badge/T--SQL-Procedural-0078D4?style=for-the-badge&logo=microsoft&logoColor=white)
![UAM](https://img.shields.io/badge/Universidad_Americana-Grupo_6-003366?style=for-the-badge)

Este repositorio contiene el script maestro de implementación para **TiendaUamDB**, un ecosistema de base de datos relacional diseñado para la gestión integral de una tienda. El proyecto abarca desde la definición de la lógica de negocio (vistas, funciones y procedimientos almacenados) hasta la implementación de alta disponibilidad, monitoreo de errores, envío de correos automatizados, auditoría transaccional y control de seguridad por roles.

---

## 📑 Tabla de Contenidos

1. [Arquitectura del Proyecto](#-arquitectura-del-proyecto)
2. [Módulos y Responsabilidades](#-módulos-y-responsabilidades)
3. [Lógica de Negocio (Programmability)](#-lógica-de-negocio-programmability)
4. [Automatización y Jobs](#-automatización-y-jobs)
5. [Seguridad y Control de Acceso](#-seguridad-y-control-de-acceso)
6. [Implementación y Pruebas](#-implementación-y-pruebas)

---

## 🏗 Arquitectura del Proyecto

El script `ScriptCompleto_Grupo6.sql` está diseñado bajo un enfoque modular. Se recomienda su ejecución secuencial en un entorno SQL Server con el servicio de **SQL Server Agent** habilitado para el correcto funcionamiento de los trabajos automatizados.

### 👥 Módulos y Responsabilidades (Grupo 6)

| Sección | Responsable | Enfoque Técnico |
| :--- | :--- | :--- |
| **1. Mantenimiento y Monitoreo** | Diedereich | Optimización de índices, actualización de estadísticas e implementación de Extended Events para captura de errores T-SQL. |
| **2. Lógica de Negocio y Automatización** | Steven | Creación de Vistas, Funciones escalares/tabla, Procedimientos Almacenados transaccionales y SQL Server Agent Jobs. |
| **3. Database Mail** | Gabriela Guerrero | Configuración de perfiles SMTP y envío de alertas automatizadas por bajo stock. |
| **4. Auditoría y Seguridad** | Dereck & Davis | Triggers DML para logs centralizados (`AuditoriaLog`) y RBAC (Role-Based Access Control) con Logins/Users. |

---

## ⚙ Lógica de Negocio (Programmability)

El sistema abstrae la complejidad de las consultas mediante los siguientes objetos:

### Vistas Estratégicas
* `vw_VentasDetalladas`: Reporte granular uniendo clientes, empleados, productos y finanzas.
* `vw_ResumenVentasPorCliente`: KPI de clientes (cantidad de ventas, monto total y ticket promedio).
* `vw_ProductosBajoStock`: Filtro de inventario crítico (Stock <= 100).

### Procedimientos Almacenados (Transaccionales)
Los procedimientos incluyen manejo de errores (`TRY/CATCH`) y validación de reglas de negocio antes de aplicar un `COMMIT`:
* `sp_RegistrarVenta`: Registra el maestro y detalle de una venta, descontando stock automáticamente.
* `sp_AgregarDetalleVenta`: Añade ítems a una venta existente.
* `sp_ReporteVentasDiarias`: Genera el cierre de caja de una fecha específica.
* `sp_ActualizarStock`: Permite ingresos limpios al inventario de forma segura.

---

## 🤖 Automatización y Jobs

El ecosistema utiliza **SQL Server Agent** para garantizar la autonomía de la base de datos sin intervención manual:

1.  **Cierre Diario (`TiendaUam_ReporteVentasDiarias`)**: Se ejecuta todos los días a las 23:00 hrs para consolidar ventas.
2.  **Alerta de Inventario (`TiendaUam_AlertaBajoStock`)**: Se dispara diariamente a las 08:00 hrs. Enlaza con **Database Mail** para enviar un correo al administrador si existen productos por debajo del umbral mínimo.
3.  **Mantenimiento Profundo (`TiendaUam_Mantenimiento_TiendaUam`)**: Programado para las 02:00 hrs (ventana de baja carga). Reorganiza índices fragmentados, actualiza estadísticas y ejecuta un `DBCC CHECKDB`.

---

## 🛡 Seguridad y Control de Acceso

Se implementó un modelo de seguridad por principio de menor privilegio (RBAC). El sistema cuenta con auditoría DML estricta que captura el usuario de red, fecha y detalles exactos del cambio (ej. "Precio: $25 -> $22.50").

### Matriz de Roles

| Rol en BD | Descripción de Permisos |
| :--- | :--- |
| `rol_admin_tienda` | Acceso DML completo (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) en todas las tablas principales. |
| `rol_ventas` | `INSERT` en Ventas/Detalles. `SELECT` a catálogo de productos y vistas de clientes. |
| `rol_bodega` | `SELECT` y `UPDATE` limitado exclusivamente a la tabla Producto y Categorías para gestión de stock. |
| `rol_rrhh` | `SELECT`, `INSERT`, `UPDATE` únicamente en la tabla de Empleados y Ciudades. |
| `rol_auditor` | Permisos estrictos de solo lectura (`SELECT`) limitados a las vistas estratégicas y financieras. |

---

## 🚀 Implementación y Pruebas

Para desplegar este ecosistema en un servidor local o de pruebas:

1.  Asegúrese de tener creada la base de datos `TiendaUamDB`.
2.  Abra el script `ScriptCompleto_Grupo6.sql` en SQL Server Management Studio (SSMS).
3.  **Importante:** Verifique que **SQL Server Agent** esté iniciado en los servicios de Windows.
4.  Ejecute el script. Toda la sección de configuración de `Database Mail` requiere permisos de `sysadmin`.
5.  Al final del script encontrará el bloque bloque `SECCION DE PRUEBAS / VERIFICACION`. Esta sección puede ser ejecutada por bloques para validar:
    * Triggers de auditoría (Insertando y borrando productos de prueba).
    * Simulación de permisos mediante `EXECUTE AS USER = 'usr_bodega_tienda';`.
    * Ejecución manual de los Jobs mediante `sp_start_job`.

> **Nota para el despliegue del correo:** En la sección 3 (Database Mail), actualice las credenciales y el servidor SMTP según la infraestructura real antes de enviar a producción. La configuración por defecto utiliza un entorno de pruebas SMTP.