import { Calendar, Gift } from "lucide-react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { useCalendarEvents } from "@/hooks/useCalendarEvents";

const impactIcons: Record<string, typeof Gift> = {
  high: Gift,
  medium: Calendar,
  low: Calendar,
};

type Props = {
  variant?: "default" | "compact";
};

export function EventsCard({ variant = "default" }: Props) {
  const compact = variant === "compact";
  const today = new Date();
  const { events, loading } = useCalendarEvents(today.getFullYear(), today.getMonth());

  const displayEvents =
    events.length > 0
      ? events
      : [
          { id: "1", date: "2024-02-14", name: "San Valentino", impact_level: "high" as const },
          { id: "2", date: "2024-03-08", name: "Festa della Donna", impact_level: "high" as const },
          { id: "3", date: "2024-03-21", name: "Inizio Primavera", impact_level: "medium" as const },
          { id: "4", date: "2024-05-12", name: "Festa della Mamma", impact_level: "high" as const },
        ];

  const formatDate = (dateStr: string) => {
    const d = new Date(dateStr);
    return d.toLocaleDateString("it-IT", { day: "numeric", month: "short" });
  };

  return (
    <Card
      className={cn(
        "animate-fade-in flex flex-col overflow-hidden", // ✅ niente sfora
        compact ? "p-4 h-[260px] lg:h-[260px]" : "p-6",
      )}
    >
      <div className="flex items-center justify-between">
        <h3 className={cn("font-medium text-muted-foreground", compact ? "text-xs" : "text-sm")}>
          {loading ? "Caricamento..." : "Prossimi Eventi"}
        </h3>
      </div>

      {/* ✅ lista scrollabile per mantenere altezza fissa */}
      <div className={cn("mt-3 space-y-2 overflow-y-auto pr-1", compact ? "max-h-[190px]" : "max-h-[320px]")}>
        {displayEvents.slice(0, 10).map((event) => {
          const Icon = impactIcons[(event as any).impact_level] || Calendar;
          const impact = (event as any).impact_level as string | undefined;

          return (
            <div
              key={event.id}
              className={cn(
                "flex items-center gap-3 rounded-lg hover:bg-muted/50 transition-colors",
                compact ? "p-2" : "p-2",
              )}
            >
              <div
                className={cn(
                  "bg-secondary rounded-lg flex items-center justify-center shrink-0",
                  compact ? "w-9 h-9" : "w-10 h-10",
                )}
              >
                <Icon
                  className={cn(impact === "high" ? "text-primary" : "text-accent", compact ? "w-4 h-4" : "w-5 h-5")}
                />
              </div>

              <div className="min-w-0">
                <p className={cn("font-medium truncate", compact ? "text-xs" : "text-sm")}>{event.name}</p>
                <p className={cn("text-muted-foreground", compact ? "text-[10px]" : "text-xs")}>
                  {formatDate(event.date)}
                </p>
              </div>
            </div>
          );
        })}
      </div>
    </Card>
  );
}
