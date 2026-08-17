import type { NextConfig } from "next";

// GitHub Pages solo sirve contenido estático: sin servidor, sin API routes,
// sin optimización de imágenes en vivo. basePath/assetPrefix apuntan al
// nombre del repo porque el sitio se publica en
// https://<usuario>.github.io/inmo-admin-mvp/, no en la raíz del dominio.
const repoName = "inmo-admin-mvp";

const nextConfig: NextConfig = {
  output: "export",
  basePath: `/${repoName}`,
  assetPrefix: `/${repoName}/`,
  images: {
    unoptimized: true,
  },
  trailingSlash: true,
};

export default nextConfig;
