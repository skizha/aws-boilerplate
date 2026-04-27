export default function Home() {
  return (
    <main className="flex flex-1 items-center justify-center bg-slate-950 px-6 py-20 text-white">
      <section className="max-w-3xl rounded-3xl border border-white/10 bg-white/5 p-10 shadow-2xl shadow-cyan-950/40">
        <p className="mb-4 text-sm font-semibold uppercase tracking-[0.35em] text-cyan-300">
          Dev Environment
        </p>
        <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">
          Travel Marketplace web is ready for EKS.
        </h1>
        <p className="mt-6 text-lg leading-8 text-slate-300">
          This Next.js application is built as a standalone Node.js container,
          published to Amazon ECR, and exposed in the dev cluster through the
          AWS Load Balancer Controller.
        </p>
        <div className="mt-10 grid gap-4 text-sm text-slate-300 sm:grid-cols-3">
          <div className="rounded-2xl border border-white/10 bg-slate-900/80 p-4">
            <span className="block font-semibold text-white">Runtime</span>
            Next.js SSR on port 3000
          </div>
          <div className="rounded-2xl border border-white/10 bg-slate-900/80 p-4">
            <span className="block font-semibold text-white">Platform</span>
            Amazon EKS dev cluster
          </div>
          <div className="rounded-2xl border border-white/10 bg-slate-900/80 p-4">
            <span className="block font-semibold text-white">Ingress</span>
            Internet-facing AWS ALB
          </div>
        </div>
      </section>
    </main>
  );
}
