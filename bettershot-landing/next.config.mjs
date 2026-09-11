/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  async redirects() {
    return [
      { source: "/image-processing", destination: "/screenshots", permanent: true },
      { source: "/download", destination: "/#download", permanent: true },
    ]
  },
  images: {
    unoptimized: true,
  },
}

export default nextConfig
