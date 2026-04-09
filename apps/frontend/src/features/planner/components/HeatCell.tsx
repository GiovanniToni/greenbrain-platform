import { HeatCell as HeatCellType, HeatMetric, HeatRange } from "../types";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

type Props = {
  cell?: HeatCellType;
  metric: HeatMetric;
  isCurrent?: boolean;
  isNext?: boolean;
  range?: HeatRange;
  showRange?: boolean;
};

function formatValue(cell: HeatCellType | undefined, metric: HeatMetric): string {
  if (!cell) return "–";

  switch (metric) {
    case "avg_qty":
      return Math.round(cell.avg_qty).toLocaleString("it-IT");

    case "avg_rev": {
      const val = cell.avg_rev;
      if (val >= 100) return `€${Math.round(val).toLocaleString("it-IT")}`;
      return `€${val.toLocaleString("it-IT", {
        minimumFractionDigits: 0,
        maximumFractionDigits: 2,
      })}`;
    }

    case "share_rev":
      return `${Math.round(cell.share_rev * 100)}%`;

    case "stock_target": {
      const v = cell.stock_target;
      if (v == null) return "–";
      return Math.round(v).toLocaleString("it-IT");
    }

    case "space_m2": {
      const v = cell.space_m2;
      if (v == null) return "–";
      return `${v.toLocaleString("it-IT", {
        minimumFractionDigits: 1,
        maximumFractionDigits: 1,
      })}`;
    }

    default:
      return "–";
  }
}

function getHeatClass(colorScore: number | null | undefined): string {
  if (colorScore == null || !Number.isFinite(colorScore)) return "bg-muted/30";
  const bucket = Math.min(9, Math.max(0, Math.floor(colorScore * 10)));
  return `heat-${bucket}`;
}

function formatRangeNum(val: number | null): string {
  if (val == null) return "–";
  return Math.round(val).toLocaleString("it-IT");
}

export function HeatCell({ cell, metric, isCurrent, isNext, range, showRange }: Props) {
  const heatClass = getHeatClass(cell?.color_score);
  const borderClass = cn(
    isNext && "ring-2 ring-primary ring-inset",
    isCurrent && !isNext && "ring-1 ring-primary/60 ring-inset",
  );

  const content = (
    <div
      className={cn(
        "h-7 min-w-[38px] flex items-center justify-center text-xs tabular-nums px-1 select-none",
        heatClass,
        borderClass,
      )}
    >
      {formatValue(cell, metric)}
    </div>
  );

  if (!cell) return content;

  return (
    <Tooltip delayDuration={150}>
      <TooltipTrigger asChild>{content}</TooltipTrigger>
      <TooltipContent side="top" className="text-xs space-y-0.5">
        <div>Qty: {Math.round(cell.avg_qty).toLocaleString("it-IT")}</div>
        <div>Rev: €{cell.avg_rev.toLocaleString("it-IT", { maximumFractionDigits: 2 })}</div>
        <div>Share: {(cell.share_rev * 100).toFixed(1)}%</div>

        {cell.sigma_qty != null && <div>σ Qty: {Number(cell.sigma_qty).toFixed(2)}</div>}

        {cell.stock_target != null && (
          <div className="pt-1 border-t border-border">
            Stock target: {Math.round(cell.stock_target).toLocaleString("it-IT")}
          </div>
        )}

        {cell.space_m2 != null && (
          <div>
            Space:{" "}
            {cell.space_m2.toLocaleString("it-IT", {
              minimumFractionDigits: 1,
              maximumFractionDigits: 1,
            })}{" "}
            m²
          </div>
        )}

        {showRange && range && (
          <>
            <div className="border-t border-border mt-1 pt-1">
              Qty range: {formatRangeNum(range.min_qty)} – {formatRangeNum(range.max_qty)}
            </div>
            <div>
              Rev range: €{formatRangeNum(range.min_rev)} – €{formatRangeNum(range.max_rev)}
            </div>
          </>
        )}
      </TooltipContent>
    </Tooltip>
  );
}
