import React from "react";
import { Card } from "@/components/ui/card";
import { FutureWindowRow } from "@/hooks/useAnalyticsFutureWindowsKpi";

type Tot = { qty: number; imp: number };

function fmtInt(n: number) {
  return Number(n || 0).toLocaleString("it-IT", { maximumFractionDigits: 0 });
}

function fmtMoney(n: number) {
  return "€ " + Number(n || 0).toLocaleString("it-IT", { maximumFractionDigits: 2 });
}

function daysBetweenInclusive(fromISO: string, toISO: string): number {
  const a = new Date(fromISO + "T00:00:00");
  const b = new Date(toISO + "T00:00:00");
  const ms = b.getTime() - a.getTime();
  const days = Math.floor(ms / 86400000) + 1;
  return Math.max(1, days);
}

function GroupDivider() {
  return (
    <div className="hidden lg:flex items-stretch px-2">
      <div className="w-px bg-border/60" />
    </div>
  );
}

function GroupCaption({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">{children}</span>
      <div className="h-px flex-1 bg-border/60" />
    </div>
  );
}

function MiniKpiCard({ label, qty, imp, highlight }: { label: string; qty: number; imp: number; highlight?: boolean }) {
  return (
    <div
      className={[
        "flex-1 min-w-[120px] rounded-lg border px-3 py-2",
        "bg-muted/30",
        "flex flex-col justify-between",
        highlight ? "border-primary/30 bg-primary/10" : "border-border",
      ].join(" ")}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">{label}</span>
      </div>

      <div className="mt-1 flex items-baseline justify-between gap-3">
        <div className="flex flex-col leading-tight">
          <span className="text-base font-semibold tabular-nums">{fmtInt(qty)}</span>
          <span className="text-[11px] text-muted-foreground tabular-nums">{fmtMoney(imp)}</span>
        </div>
      </div>
    </div>
  );
}

function MiniValueCard({
  label,
  value,
  hint,
  emphasis,
}: {
  label: string;
  value: string;
  hint?: string;
  emphasis?: boolean;
}) {
  return (
    <div
      className={[
        "flex-1 min-w-[160px] rounded-lg border px-3 py-2",
        "bg-muted/30 border-border",
        "flex flex-col justify-between",
        emphasis ? "bg-primary/10 border-primary/30" : "",
      ].join(" ")}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">{label}</span>
      </div>

      <div className="mt-1 flex items-baseline justify-between gap-3">
        <span className="text-base font-semibold tabular-nums">{value}</span>
      </div>

      {hint ? <span className="text-[10px] text-muted-foreground mt-0.5">{hint}</span> : null}
    </div>
  );
}

function FutureWindowMiniCard({ row }: { row: FutureWindowRow }) {
  return (
    <div className="flex-1 min-w-[140px] rounded-lg border bg-muted/30 border-border px-3 py-2 flex flex-col justify-between">
      <span className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
        {row.window_days}gg
      </span>

      <div className="mt-1 grid grid-cols-3 gap-2 text-[10px] text-muted-foreground tabular-nums">
        <div className="flex flex-col">
          <span className="uppercase tracking-wide opacity-80">Min</span>
          <span className="text-foreground/80 font-medium">{fmtInt(row.min_qty)}</span>
        </div>
        <div className="flex flex-col">
          <span className="uppercase tracking-wide opacity-80">Max</span>
          <span className="text-foreground/80 font-medium">{fmtInt(row.max_qty)}</span>
        </div>
        <div className="flex flex-col">
          <span className="uppercase tracking-wide opacity-80">Media</span>
          <span className="text-foreground font-semibold">{fmtInt(row.avg_qty)}</span>
        </div>
      </div>
    </div>
  );
}

function FutureWindowsGroup({ rows, loading }: { rows: FutureWindowRow[]; loading?: boolean }) {
  if (loading) {
    return (
      <div className="flex-1 min-w-[240px] rounded-lg border bg-muted/20 border-border px-3 py-2">
        <div className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">…</div>
        <div className="mt-1 text-[11px] text-muted-foreground">Caricamento vendite attese…</div>
      </div>
    );
  }

  if (!rows || rows.length === 0) {
    return (
      <div className="flex-1 min-w-[240px] rounded-lg border bg-muted/20 border-border px-3 py-2">
        <div className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">n/d</div>
        <div className="mt-1 text-[11px] text-muted-foreground">Nessuna statistica disponibile.</div>
      </div>
    );
  }

  const ordered = [...rows].sort((a, b) => a.window_days - b.window_days);

  return (
    <div className="flex flex-wrap items-stretch gap-2 w-full">
      {ordered.map((r) => (
        <FutureWindowMiniCard key={r.window_days} row={r} />
      ))}
    </div>
  );
}

export function AnalyticsOperationalKpis({
  rolling,
  selectedRange,
  stockQty,
  reorderQty,
  futureRows,
  futureLoading,
  dateFrom,
  dateTo,
}: {
  rolling: { d7: Tot; d10: Tot; d30: Tot; d60: Tot; d90: Tot } | null; // ✅ d60
  selectedRange: Tot;
  stockQty: number | null;
  reorderQty: number | null;
  futureRows: FutureWindowRow[];
  futureLoading?: boolean;
  dateFrom: string;
  dateTo: string;
  loading?: boolean; // lasciato per compat ma non usato qui
}) {
  const rangeDays = daysBetweenInclusive(dateFrom, dateTo);
  const rangeLabel = `${rangeDays} giorni`;

  return (
    <Card className="p-3">
      {/* Content row (responsive) */}
      <div className="flex flex-col gap-3 lg:flex-row lg:items-stretch lg:gap-0">
        {/* GROUP 1: Vendite */}
        <div className="flex-1 min-w-0 lg:pr-3 space-y-2">
          <GroupCaption>Vendite</GroupCaption>
          <div className="flex flex-wrap items-stretch gap-2">
            <MiniKpiCard label="7gg" qty={rolling?.d7?.qty ?? 0} imp={rolling?.d7?.imp ?? 0} />
            <MiniKpiCard label="10gg" qty={rolling?.d10?.qty ?? 0} imp={rolling?.d10?.imp ?? 0} />
            <MiniKpiCard label="30gg" qty={rolling?.d30?.qty ?? 0} imp={rolling?.d30?.imp ?? 0} />
            <MiniKpiCard label="60gg" qty={rolling?.d60?.qty ?? 0} imp={rolling?.d60?.imp ?? 0} /> {/* ✅ NEW */}
            <MiniKpiCard label="90gg" qty={rolling?.d90?.qty ?? 0} imp={rolling?.d90?.imp ?? 0} />
            <MiniKpiCard label={rangeLabel} qty={selectedRange.qty} imp={selectedRange.imp} highlight />
          </div>
        </div>

        <GroupDivider />

        {/* GROUP 2: Giacenza */}
        <div className="flex-1 min-w-0 lg:px-3 space-y-2">
          <GroupCaption>Giacenza</GroupCaption>
          <div className="flex flex-wrap items-stretch gap-2">
            <MiniValueCard
              label="Giacenza attuale"
              value={stockQty == null ? "-" : fmtInt(stockQty)}
              hint={stockQty == null ? "non disponibile per questa vista" : "qty disponibili"}
            />
          </div>
        </div>

        <GroupDivider />

        {/* GROUP 3: Vendite attese */}
        <div className="flex-[1.3] min-w-0 lg:px-3 space-y-2">
          <GroupCaption>Vendite attese</GroupCaption>
          <FutureWindowsGroup rows={futureRows || []} loading={futureLoading} />
        </div>

        <GroupDivider />

        {/* GROUP 4: Da fare */}
        <div className="flex-1 min-w-0 lg:pl-3 space-y-2">
          <GroupCaption>Da fare</GroupCaption>
          <div className="flex flex-wrap items-stretch gap-2">
            <MiniValueCard
              label="Da riordinare"
              value={reorderQty == null ? "-" : fmtInt(reorderQty)}
              hint={reorderQty == null ? "non disponibile per questa vista" : "qty suggerita"}
              emphasis
            />
          </div>
        </div>
      </div>
    </Card>
  );
}
