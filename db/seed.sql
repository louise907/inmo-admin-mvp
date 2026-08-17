-- ==============================================================================
-- DATOS DE PRUEBA -- solo para desarrollo, nunca correr en producción.
-- Crea un propietario, un inquilino, dos propiedades (una ocupada con
-- contrato activo, otra disponible) para poder ver el dashboard con datos.
-- ==============================================================================
WITH propietario AS (
    INSERT INTO personas (nombre_completo, telefono, correo)
    VALUES ('Propietario de Prueba', '5500000001', 'propietario.prueba@example.com')
    RETURNING id
), inquilino AS (
    INSERT INTO personas (nombre_completo, telefono, correo)
    VALUES ('Inquilino de Prueba', '5500000002', 'inquilino.prueba@example.com')
    RETURNING id
), propiedad_ocupada AS (
    INSERT INTO propiedades (propietario_id, identificador, direccion, precio_renta, estatus)
    SELECT id, 'PRUEBA-01', 'Calle Falsa 123, CDMX', 12000, 'ocupada' FROM propietario
    RETURNING id
), propiedad_disponible AS (
    INSERT INTO propiedades (propietario_id, identificador, direccion, precio_renta, estatus)
    SELECT id, 'PRUEBA-02', 'Av. Siempre Viva 456, CDMX', 9500, 'disponible' FROM propietario
    RETURNING id
)
INSERT INTO contratos (propiedad_id, inquilino_id, identificador, fecha_inicio, fecha_fin, monto_renta, dia_pago)
SELECT propiedad_ocupada.id, inquilino.id, 'PRUEBA-01-A', '2026-01-01', '2027-01-01', 12000, 5
FROM propiedad_ocupada, inquilino;
