import { LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface KpiCardProps {
  title: string;
  value: string | number;
  change?: string;
  changeType?: "positive" | "negative" | "neutral";
  icon: LucideIcon;
  variant?: "default" | "compact";
}

export function KpiCard({
  title,
  value,
  change,
  changeType = "neutral",
  icon: Icon,
  variant = "default",
}: KpiCardProps) {
  const compact = variant === "compact";

  return (
    <Card className={cn("animate-fade-in", compact ? "p-4" : "p-6")}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className={cn("font-medium text-muted-foreground", compact ? "text-xs" : "text-sm")}>{title}</p>

          <p className={cn("font-bold mt-1 tabular-nums", compact ? "text-2xl" : "text-3xl")}>{value}</p>

          {change && (
            <p
              className={cn(
                compact ? "text-xs mt-1" : "text-sm mt-1",
                changeType === "positive" && "text-primary",
                changeType === "negative" && "text-destructive",
                changeType === "neutral" && "text-muted-foreground",
              )}
            >
              {change}
            </p>
          )}
        </div>

        <div
          className={cn(
            "rounded-lg flex items-center justify-center shrink-0",
            compact ? "w-10 h-10 bg-primary/10" : "w-12 h-12 bg-primary/10",
          )}
        >
          <Icon className={cn(compact ? "w-5 h-5 text-primary" : "w-6 h-6 text-primary")} />
        </div>
      </div>
    </Card>
  );
}
