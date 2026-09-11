/** @type {import('next').NextConfig} */
const nextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  async redirects() {
    return [{ source: "/image-processing", destination: "/screenshots", permanent: true }]
  },
  images: {
    unoptimized: true,
  },
}

export default nextConfig
