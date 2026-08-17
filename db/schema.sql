-- ==============================================================================
-- ADMINISTRADOR DE RENTAS - MVP
-- Single-tenant (una sola inmobiliaria), pensado para Supabase
-- Convenciones alineadas con schema.sql de CasaLogin/SIGI (español, snake_case,
-- UUID, TIMESTAMPTZ, enums estatus_*_enum) para facilitar una futura fusión
-- como módulo de arrendamientos, sin traer su complejidad multi-tenant.
-- ==============================================================================

-- LIMPIEZA (solo en desarrollo)
DROP VIEW IF EXISTS actividad_reciente CASCADE;
DROP VIEW IF EXISTS pagos_estatus CASCADE;
DROP TABLE IF EXISTS resumenes_mensuales CASCADE;
DROP TABLE IF EXISTS documentos CASCADE;
DROP TABLE IF EXISTS gastos CASCADE;
DROP TABLE IF EXISTS pagos CASCADE;
DROP TABLE IF EXISTS contratos CASCADE;
DROP TABLE IF EXISTS propiedades CASCADE;
DROP TABLE IF EXISTS personas CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;

DROP TYPE IF EXISTS rol_usuario_enum CASCADE;
DROP TYPE IF EXISTS estatus_propiedad_enum CASCADE;
DROP TYPE IF EXISTS estatus_contrato_enum CASCADE;
DROP TYPE IF EXISTS entidad_documento_enum CASCADE;

-- ==============================================================================
-- 1. EXTENSIONES Y TIPOS
-- ==============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE rol_usuario_enum AS ENUM ('admin', 'operador');
CREATE TYPE estatus_propiedad_enum AS ENUM ('disponible', 'ocupada', 'pausada', 'inactiva');
CREATE TYPE estatus_contrato_enum AS ENUM ('activo', 'finalizado', 'cancelado');
CREATE TYPE entidad_documento_enum AS ENUM ('persona', 'propiedad', 'contrato', 'gasto');

-- ==============================================================================
-- 2. USUARIOS (staff interno, auth de Supabase)
-- Sin tabla de roles/permisos JSONB como en SIGI: al ser single-tenant basta
-- un enum simple. Si esto se fusiona a SIGI más adelante, se reemplaza por
-- inmobiliaria_id + rol_id (FK a roles).
-- ==============================================================================
CREATE TABLE usuarios (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nombre_completo VARCHAR(150) NOT NULL,
    correo VARCHAR(150) NOT NULL,
    rol rol_usuario_enum NOT NULL DEFAULT 'operador',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 3. PERSONAS (identidad centralizada)
-- Reemplaza los datos duplicados de dueño/inquilino/aval que vivían sueltos
-- dentro de cada Excel. Una misma persona puede ser propietario en una
-- propiedad e inquilino/aval en otra, o repetirse como inquilino en contratos
-- distintos, sin reescribir sus datos cada vez.
-- ==============================================================================
CREATE TABLE personas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre_completo VARCHAR(150) NOT NULL,
    telefono VARCHAR(15) NOT NULL,
    telefono_2 VARCHAR(15),
    correo VARCHAR(150),
    numero_ine VARCHAR(20),
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_personas_nombre ON personas(nombre_completo);
CREATE INDEX idx_personas_ine ON personas(numero_ine);

-- ==============================================================================
-- 4. PROPIEDADES
-- Nota: NO se guarda "fecha_en_que_se_desocupa" aquí (existía duplicada junto
-- a "fin de contrato" en el Excel original). Se calcula a partir del contrato
-- activo — ver vista más abajo si se necesita expuesta directamente.
-- ==============================================================================
CREATE TABLE propiedades (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    propietario_id UUID NOT NULL REFERENCES personas(id),
    identificador VARCHAR(50) UNIQUE NOT NULL, -- ej. "PRUEBA-EJEMPLO"
    direccion TEXT,
    precio_renta NUMERIC(14,2) NOT NULL DEFAULT 0,
    estatus estatus_propiedad_enum NOT NULL DEFAULT 'disponible',
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_propiedades_propietario ON propiedades(propietario_id);
CREATE INDEX idx_propiedades_estatus ON propiedades(estatus);

-- ==============================================================================
-- 5. CONTRATOS
-- ==============================================================================
CREATE TABLE contratos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    propiedad_id UUID NOT NULL REFERENCES propiedades(id) ON DELETE CASCADE,
    inquilino_id UUID NOT NULL REFERENCES personas(id),
    aval_id UUID REFERENCES personas(id),
    identificador VARCHAR(50) UNIQUE NOT NULL, -- ej. "PEJAA0126"
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    monto_renta NUMERIC(14,2) NOT NULL,
    dia_pago SMALLINT NOT NULL DEFAULT 1 CHECK (dia_pago BETWEEN 1 AND 28),
    comision_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 10,
    interes_moratorio_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 10,
    estatus estatus_contrato_enum NOT NULL DEFAULT 'activo',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (fecha_fin > fecha_inicio)
);

CREATE INDEX idx_contratos_propiedad ON contratos(propiedad_id);
CREATE INDEX idx_contratos_inquilino ON contratos(inquilino_id);
CREATE INDEX idx_contratos_estatus ON contratos(estatus);

-- ==============================================================================
-- 6. PAGOS
-- El estatus (pagado/vencido/próximo) NO se guarda como columna: se deriva
-- en la vista pagos_estatus a partir de fecha_pago y fecha_vencimiento, para
-- no arrastrar un campo que se pueda desincronizar de la realidad.
-- ==============================================================================
CREATE TABLE pagos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    contrato_id UUID NOT NULL REFERENCES contratos(id) ON DELETE CASCADE,
    fecha_vencimiento DATE NOT NULL,
    fecha_pago DATE,
    monto_renta NUMERIC(14,2) NOT NULL,
    monto_pagado NUMERIC(14,2) NOT NULL DEFAULT 0,
    interes NUMERIC(14,2) NOT NULL DEFAULT 0,
    interes_perdonado BOOLEAN NOT NULL DEFAULT false,
    motivo_perdon TEXT,
    comision_monto NUMERIC(14,2) NOT NULL DEFAULT 0,
    comision_cobrada NUMERIC(14,2) NOT NULL DEFAULT 0,
    notas TEXT, -- para dejar constancia de negociaciones/excepciones puntuales
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(contrato_id, fecha_vencimiento)
);

CREATE INDEX idx_pagos_contrato ON pagos(contrato_id);
CREATE INDEX idx_pagos_fecha_vencimiento ON pagos(fecha_vencimiento);

-- ==============================================================================
-- 7. GASTOS
-- A diferencia del original, SIEMPRE lleva fecha — soluciona el hueco de no
-- poder atribuir automáticamente un gasto a su mes en el resumen financiero.
-- ==============================================================================
CREATE TABLE gastos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    propiedad_id UUID NOT NULL REFERENCES propiedades(id) ON DELETE CASCADE,
    descripcion TEXT NOT NULL,
    monto NUMERIC(14,2) NOT NULL,
    fecha DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_gastos_propiedad ON gastos(propiedad_id);
CREATE INDEX idx_gastos_fecha ON gastos(fecha);

-- ==============================================================================
-- 8. DOCUMENTOS
-- Tabla genérica para todo lo que antes vivía como archivos sueltos en
-- carpetas (INE, contrato escaneado, recibos, notas generales). El archivo
-- físico vive en Supabase Storage (bucket privado); aquí solo la referencia.
-- ==============================================================================
CREATE TABLE documentos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entidad_tipo entidad_documento_enum NOT NULL,
    entidad_id UUID NOT NULL,
    tipo_documento VARCHAR(50) NOT NULL, -- 'ine', 'contrato_firmado', 'recibo', 'general', etc.
    storage_path TEXT NOT NULL,          -- ruta dentro del bucket de Supabase Storage
    nombre_original VARCHAR(255),
    subido_por UUID REFERENCES usuarios(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_documentos_entidad ON documentos(entidad_tipo, entidad_id);

-- ==============================================================================
-- 9. RESUMENES MENSUALES
-- ingresos_total / gastos_total / comision_generada se recalculan con la
-- función recalcular_resumen_mensual() a partir de pagos y gastos reales —
-- nunca se capturan a mano, para no perder consistencia con los datos base.
-- pagado_a_propietario y notas sí son campos manuales (decisión operativa).
-- ==============================================================================
CREATE TABLE resumenes_mensuales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    propiedad_id UUID NOT NULL REFERENCES propiedades(id) ON DELETE CASCADE,
    anio SMALLINT NOT NULL,
    mes SMALLINT NOT NULL CHECK (mes BETWEEN 1 AND 12),
    ingresos_total NUMERIC(14,2) NOT NULL DEFAULT 0,
    gastos_total NUMERIC(14,2) NOT NULL DEFAULT 0,
    comision_generada NUMERIC(14,2) NOT NULL DEFAULT 0,
    monto_pagado_a_propietario NUMERIC(14,2) NOT NULL DEFAULT 0,
    pagado_a_propietario BOOLEAN NOT NULL DEFAULT false,
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(propiedad_id, anio, mes)
);

CREATE INDEX idx_resumenes_propiedad ON resumenes_mensuales(propiedad_id);

-- ==============================================================================
-- 10. FUNCIONES Y TRIGGERS
-- ==============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_usuarios_updated_at BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_personas_updated_at BEFORE UPDATE ON personas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_propiedades_updated_at BEFORE UPDATE ON propiedades
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_contratos_updated_at BEFORE UPDATE ON contratos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_pagos_updated_at BEFORE UPDATE ON pagos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_resumenes_updated_at BEFORE UPDATE ON resumenes_mensuales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Genera automáticamente el calendario de pagos mensual al crear un contrato
-- (antes se armaba a mano fila por fila en el Excel), cobrando siempre en
-- contrato.dia_pago -- NO en el día de fecha_inicio.
--
-- Si fecha_inicio no coincide con dia_pago, el primer pago se genera
-- PRORRATEADO por días (sobre base de mes de 30 días) cubriendo desde
-- fecha_inicio hasta el día antes del primer cobro "normal", y queda
-- marcado en notas para que se note que fue calculado, no negociado.
--
-- Esto es solo el valor por defecto: en la práctica todo es negociable, así
-- que cualquier fila (monto_renta, notas, etc.) se puede editar a mano
-- después sin que nada la vuelva a sobreescribir -- este trigger corre una
-- sola vez, al crear el contrato.
CREATE OR REPLACE FUNCTION generar_calendario_pagos()
RETURNS TRIGGER AS $$
DECLARE
    primer_cobro_normal DATE;
    dias_prorrateo INTEGER;
    monto_prorrateado NUMERIC(14,2);
    fecha_cursor DATE;
BEGIN
    primer_cobro_normal := make_date(
        EXTRACT(YEAR FROM NEW.fecha_inicio)::INT,
        EXTRACT(MONTH FROM NEW.fecha_inicio)::INT,
        NEW.dia_pago
    );
    IF primer_cobro_normal < NEW.fecha_inicio THEN
        primer_cobro_normal := primer_cobro_normal + INTERVAL '1 month';
    END IF;

    dias_prorrateo := primer_cobro_normal - NEW.fecha_inicio;
    IF dias_prorrateo > 0 THEN
        monto_prorrateado := ROUND(NEW.monto_renta * dias_prorrateo / 30.0, 2);
        INSERT INTO pagos (contrato_id, fecha_vencimiento, monto_renta, comision_monto, notas)
        VALUES (
            NEW.id,
            NEW.fecha_inicio,
            monto_prorrateado,
            ROUND(monto_prorrateado * NEW.comision_porcentaje / 100, 2),
            format('Pago prorrateado (%s días, base mes de 30) -- calculado automáticamente, revisar/ajustar si se negoció otro monto', dias_prorrateo)
        );
    END IF;

    fecha_cursor := primer_cobro_normal;
    WHILE fecha_cursor <= NEW.fecha_fin LOOP
        INSERT INTO pagos (contrato_id, fecha_vencimiento, monto_renta, comision_monto)
        VALUES (
            NEW.id,
            fecha_cursor,
            NEW.monto_renta,
            ROUND(NEW.monto_renta * NEW.comision_porcentaje / 100, 2)
        );
        fecha_cursor := fecha_cursor + INTERVAL '1 month';
    END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generar_calendario_pagos AFTER INSERT ON contratos
    FOR EACH ROW EXECUTE FUNCTION generar_calendario_pagos();

-- Aplica el interés moratorio (10% mensual, definido por contrato) a los
-- pagos vencidos que aún no se han pagado ni perdonado. El interés se suma
-- también a comision_monto porque el interés que se cobra es ganancia de la
-- inmobiliaria, no del propietario (confirmado con la usuaria). Pensado para
-- correr diario vía pg_cron o una Edge Function programada.
CREATE OR REPLACE FUNCTION aplicar_intereses_moratorios()
RETURNS INTEGER AS $$
DECLARE
    v_afectados INTEGER;
BEGIN
    WITH actualizados AS (
        UPDATE pagos pa
        SET interes = ROUND(pa.monto_renta * c.interes_moratorio_porcentaje / 100, 2),
            comision_monto = pa.comision_monto + ROUND(pa.monto_renta * c.interes_moratorio_porcentaje / 100, 2)
        FROM contratos c
        WHERE c.id = pa.contrato_id
          AND pa.fecha_vencimiento < CURRENT_DATE
          AND pa.fecha_pago IS NULL
          AND pa.interes = 0
          AND pa.interes_perdonado = false
        RETURNING pa.id
    )
    SELECT COUNT(*) INTO v_afectados FROM actualizados;
    RETURN v_afectados;
END;
$$ LANGUAGE plpgsql;

-- Perdona el interés moratorio de un pago puntual, dejando registrado el
-- motivo (auditoría) y revirtiendo el monto que se le había sumado a la
-- comisión de la inmobiliaria.
CREATE OR REPLACE FUNCTION perdonar_interes(p_pago_id UUID, p_motivo TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE pagos
    SET comision_monto = comision_monto - interes,
        interes = 0,
        interes_perdonado = true,
        motivo_perdon = p_motivo
    WHERE id = p_pago_id;
END;
$$ LANGUAGE plpgsql;

-- Recalcula (o crea) el resumen mensual de una propiedad a partir de pagos y
-- gastos reales. Se llama manualmente o vía cron/edge function los últimos
-- días de cada mes, replicando el proceso descrito en la nota de Obsidian.
CREATE OR REPLACE FUNCTION recalcular_resumen_mensual(p_propiedad_id UUID, p_anio SMALLINT, p_mes SMALLINT)
RETURNS VOID AS $$
DECLARE
    v_ingresos NUMERIC(14,2);
    v_gastos NUMERIC(14,2);
    v_comision NUMERIC(14,2);
BEGIN
    SELECT COALESCE(SUM(pa.monto_pagado), 0), COALESCE(SUM(pa.comision_cobrada), 0)
    INTO v_ingresos, v_comision
    FROM pagos pa
    JOIN contratos c ON c.id = pa.contrato_id
    WHERE c.propiedad_id = p_propiedad_id
      AND EXTRACT(YEAR FROM pa.fecha_vencimiento) = p_anio
      AND EXTRACT(MONTH FROM pa.fecha_vencimiento) = p_mes;

    SELECT COALESCE(SUM(g.monto), 0) INTO v_gastos
    FROM gastos g
    WHERE g.propiedad_id = p_propiedad_id
      AND EXTRACT(YEAR FROM g.fecha) = p_anio
      AND EXTRACT(MONTH FROM g.fecha) = p_mes;

    INSERT INTO resumenes_mensuales (propiedad_id, anio, mes, ingresos_total, gastos_total, comision_generada)
    VALUES (p_propiedad_id, p_anio, p_mes, v_ingresos, v_gastos, v_comision)
    ON CONFLICT (propiedad_id, anio, mes)
    DO UPDATE SET
        ingresos_total = EXCLUDED.ingresos_total,
        gastos_total = EXCLUDED.gastos_total,
        comision_generada = EXCLUDED.comision_generada,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- 11. VISTAS
-- ==============================================================================

-- Estatus de cada pago derivado, no almacenado.
CREATE VIEW pagos_estatus AS
SELECT
    pa.*,
    CASE
        WHEN pa.fecha_pago IS NOT NULL THEN 'pagado'
        WHEN pa.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
        ELSE 'proximo'
    END AS estatus
FROM pagos pa;

-- Fecha de desocupación derivada del contrato activo (reemplaza el campo
-- duplicado que existía en el Excel original a nivel propiedad).
CREATE VIEW propiedades_detalle AS
SELECT
    p.*,
    c.fecha_fin AS fecha_desocupacion_estimada,
    c.id AS contrato_activo_id
FROM propiedades p
LEFT JOIN contratos c ON c.propiedad_id = p.id AND c.estatus = 'activo';

-- Feed de actividad reciente para el dashboard.
CREATE VIEW actividad_reciente AS
SELECT 'pago' AS tipo, pa.id, c.propiedad_id, pa.fecha_pago AS fecha, pa.created_at
FROM pagos pa JOIN contratos c ON c.id = pa.contrato_id
WHERE pa.fecha_pago IS NOT NULL
UNION ALL
SELECT 'gasto', g.id, g.propiedad_id, g.fecha, g.created_at
FROM gastos g
UNION ALL
SELECT 'documento', d.id, NULL, d.created_at::date, d.created_at
FROM documentos d
UNION ALL
SELECT 'contrato', ct.id, ct.propiedad_id, ct.fecha_inicio, ct.created_at
FROM contratos ct
ORDER BY created_at DESC;

-- ==============================================================================
-- 12. ROW LEVEL SECURITY
-- Single-tenant: cualquier usuario autenticado que exista en "usuarios" tiene
-- acceso. No hay aislamiento por inmobiliaria_id (no aplica en este MVP).
-- Como el repo es público y todo query sale del navegador con la anon key,
-- ESTA es la única barrera de seguridad real — no confiar en el frontend.
-- ==============================================================================
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE personas ENABLE ROW LEVEL SECURITY;
ALTER TABLE propiedades ENABLE ROW LEVEL SECURITY;
ALTER TABLE contratos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE gastos ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE resumenes_mensuales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "staff_autenticado" ON usuarios
    FOR ALL USING (auth.uid() = id);

CREATE POLICY "staff_autenticado" ON personas
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON propiedades
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON contratos
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON pagos
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON gastos
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON documentos
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

CREATE POLICY "staff_autenticado" ON resumenes_mensuales
    FOR ALL USING (EXISTS (SELECT 1 FROM usuarios u WHERE u.id = auth.uid()));

-- NOTA: además de esto, en el dashboard de Supabase hay que:
--   1. Crear el bucket de Storage (privado) para documentos.
--   2. Agregar políticas equivalentes sobre storage.objects (mismo criterio:
--      solo usuarios presentes en la tabla "usuarios" pueden leer/escribir).
--   3. Nunca generar URLs públicas para el bucket — solo signed URLs de
--      corta duración desde el cliente autenticado.

-- ==============================================================================
-- 13. PERMISOS DE ROL (GRANT)
-- RLS por sí solo no basta: sin GRANT, Postgres niega el acceso a la tabla
-- antes de evaluar las políticas ("permission denied for table ..."). Solo
-- se otorga a "authenticated" -- no hay acceso anónimo en este MVP, toda
-- operación exige sesión (ver políticas arriba).
-- ==============================================================================
GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON
    usuarios, personas, propiedades, contratos, pagos, gastos, documentos, resumenes_mensuales
TO authenticated;

GRANT SELECT ON pagos_estatus, actividad_reciente TO authenticated;
