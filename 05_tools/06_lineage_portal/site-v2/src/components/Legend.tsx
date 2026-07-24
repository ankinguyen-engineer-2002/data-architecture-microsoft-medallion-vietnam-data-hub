export function Legend({ showDirection = true }: { showDirection?: boolean }) {
  return (
    <div className="pointer-events-none absolute bottom-6 left-6 z-10 flex flex-col gap-1.5 rounded-lg border border-ink-800 bg-ink-950/80 px-3.5 py-3 backdrop-blur">
      <div className="font-mono text-[9.5px] uppercase tracking-[0.18em] text-ink-500">
        Layer
      </div>
      <Row color="var(--color-bronze)" label="Bronze" desc="Source" />
      <Row color="var(--color-silver)" label="Silver" desc="Curated" />
      <Row color="var(--color-gold)" label="Gold" desc="Serving" />
      <Row color="var(--color-semantic)" label="Semantic" desc="Model" />
      {showDirection && (
        <div className="mt-1.5 border-t border-ink-800 pt-1.5">
          <div className="font-mono text-[9.5px] uppercase tracking-[0.18em] text-ink-500">
            Direction
          </div>
          <Row color="var(--color-bronze)" label="Upstream" desc="← sources" thin />
          <Row color="var(--color-silver)" label="Downstream" desc="consumers →" thin />
        </div>
      )}
    </div>
  );
}

function Row({
  color,
  label,
  desc,
  thin,
}: {
  color: string;
  label: string;
  desc: string;
  thin?: boolean;
}) {
  return (
    <div className="flex items-center gap-2 text-[11px]">
      {thin ? (
        <span className="block h-[1.5px] w-4" style={{ background: color }} />
      ) : (
        <span className="h-1.5 w-1.5 rounded-full" style={{ background: color }} />
      )}
      <span className="text-ink-200">{label}</span>
      <span className="text-ink-500">{desc}</span>
    </div>
  );
}
