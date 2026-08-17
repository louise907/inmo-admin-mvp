# Administrador de Rentas — MVP

App web para la administración de propiedades en renta (contratos, inquilinos, avales, pagos, gastos y conciliación mensual con propietarios).

MVP independiente, enfocado en resolver la operación actual con ~30 propiedades. No confundir con CasaLogin/SIGI (producto más grande, en desarrollo por separado) — este proyecto está pensado para eventualmente integrarse como su módulo de administración de arrendamientos.

## Stack

- Next.js (export estático) + Tailwind + shadcn/ui
- Supabase (Postgres + Auth + Storage) como backend
- Hosting: GitHub Pages

## Seguridad

Este repositorio es público. Toda la seguridad de acceso a datos vive en las políticas de Row Level Security (RLS) de Supabase — no hay backend propio que la respalde, ya que GitHub Pages solo sirve contenido estático. Nunca se debe comitear una `service_role key` ni ninguna credencial real; solo la `anon key` pública viaja en el bundle del cliente, protegida por RLS.

## Base de datos

El esquema vive en [`db/schema.sql`](db/schema.sql).
