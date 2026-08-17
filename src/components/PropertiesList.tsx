"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Propiedad = {
  id: string;
  identificador: string;
  direccion: string | null;
  precio_renta: number;
  estatus: "disponible" | "ocupada" | "pausada" | "inactiva";
  propietario: { nombre_completo: string } | null;
};

const ESTATUS_LABEL: Record<Propiedad["estatus"], string> = {
  disponible: "Disponible",
  ocupada: "Ocupada",
  pausada: "Pausada",
  inactiva: "Inactiva",
};

const ESTATUS_BADGE: Record<Propiedad["estatus"], string> = {
  disponible:
    "bg-blue-50 text-blue-700 dark:bg-blue-950 dark:text-blue-300",
  ocupada:
    "bg-green-50 text-green-700 dark:bg-green-950 dark:text-green-300",
  pausada:
    "bg-amber-50 text-amber-700 dark:bg-amber-950 dark:text-amber-300",
  inactiva: "bg-zinc-100 text-zinc-500 dark:bg-zinc-900 dark:text-zinc-400",
};

const PESOS = new Intl.NumberFormat("es-MX", {
  style: "currency",
  currency: "MXN",
  maximumFractionDigits: 0,
});

export function PropertiesList() {
  const [propiedades, setPropiedades] = useState<Propiedad[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    supabase
      .from("propiedades")
      .select(
        "id, identificador, direccion, precio_renta, estatus, propietario:personas(nombre_completo)"
      )
      .order("estatus")
      .order("identificador")
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          setError(error.message);
          return;
        }
        // Supabase-js tipa la relación como arreglo aunque sea a-uno; se
        // normaliza aquí para que el componente reciba un objeto o null.
        const normalizado = (data ?? []).map((p) => ({
          ...p,
          propietario: Array.isArray(p.propietario)
            ? (p.propietario[0] ?? null)
            : p.propietario,
        })) as Propiedad[];
        setPropiedades(normalizado);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  if (error) {
    return (
      <p className="text-sm text-red-600 dark:text-red-400">
        No se pudieron cargar las propiedades: {error}
      </p>
    );
  }

  if (!propiedades) {
    return (
      <p className="text-sm text-zinc-500 dark:text-zinc-400">Cargando...</p>
    );
  }

  if (propiedades.length === 0) {
    return (
      <p className="text-sm text-zinc-500 dark:text-zinc-400">
        No hay propiedades registradas todavía.
      </p>
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-zinc-200 dark:border-zinc-800">
      <table className="w-full text-left text-sm">
        <thead className="bg-zinc-50 text-zinc-500 dark:bg-zinc-900 dark:text-zinc-400">
          <tr>
            <th className="px-4 py-3 font-medium">Identificador</th>
            <th className="px-4 py-3 font-medium">Dirección</th>
            <th className="px-4 py-3 font-medium">Propietario</th>
            <th className="px-4 py-3 font-medium">Renta</th>
            <th className="px-4 py-3 font-medium">Estatus</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
          {propiedades.map((p) => (
            <tr key={p.id}>
              <td className="px-4 py-3 font-medium text-zinc-900 dark:text-zinc-100">
                {p.identificador}
              </td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">
                {p.direccion ?? "—"}
              </td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">
                {p.propietario?.nombre_completo ?? "—"}
              </td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">
                {PESOS.format(p.precio_renta)}
              </td>
              <td className="px-4 py-3">
                <span
                  className={`rounded-full px-2.5 py-1 text-xs font-medium ${ESTATUS_BADGE[p.estatus]}`}
                >
                  {ESTATUS_LABEL[p.estatus]}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
