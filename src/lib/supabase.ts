import { createClient } from "@supabase/supabase-js";

// Este archivo corre en el navegador (export estático, sin servidor propio).
// La anon key está diseñada para ser pública: la seguridad real vive en las
// políticas RLS de la base de datos (ver db/schema.sql), no aquí.
// Nunca agregar la service_role key en este proyecto.
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    "Faltan NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY. Copia .env.example a .env.local y complétalas."
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
