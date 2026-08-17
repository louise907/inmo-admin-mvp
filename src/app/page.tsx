"use client";

import { useAuth } from "@/lib/auth-context";
import { supabase } from "@/lib/supabase";
import { LoginForm } from "@/components/LoginForm";
import { PropertiesList } from "@/components/PropertiesList";

export default function Home() {
  const { session, loading } = useAuth();

  if (loading) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Cargando...</p>
      </div>
    );
  }

  if (!session) {
    return <LoginForm />;
  }

  return (
    <div className="flex-1 bg-zinc-50 dark:bg-black">
      <header className="flex items-center justify-between border-b border-zinc-200 bg-white px-6 py-4 dark:border-zinc-800 dark:bg-zinc-950">
        <div>
          <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
            Propiedades
          </h1>
          <p className="text-sm text-zinc-500 dark:text-zinc-400">
            {session.user.email}
          </p>
        </div>
        <button
          onClick={() => supabase.auth.signOut()}
          className="rounded-md border border-zinc-300 px-3 py-1.5 text-sm text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-900"
        >
          Cerrar sesión
        </button>
      </header>

      <main className="p-6">
        <PropertiesList />
      </main>
    </div>
  );
}
