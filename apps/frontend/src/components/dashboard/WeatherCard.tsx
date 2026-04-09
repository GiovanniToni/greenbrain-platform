import { Cloud, Sun, CloudRain } from "lucide-react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const mockWeather = {
  today: { temp: 22, condition: "sunny", icon: Sun },
  forecast: [
    { day: "Dom", temp: 20, icon: Cloud },
    { day: "Lun", temp: 18, icon: CloudRain },
    { day: "Mar", temp: 21, icon: Sun },
    { day: "Mer", temp: 23, icon: Sun },
  ],
};

type Props = { variant?: "default" | "compact" };

export function WeatherCard({ variant = "default" }: Props) {
  const compact = variant === "compact";
  const TodayIcon = mockWeather.today.icon;

  return (
    <Card
      className={cn("animate-fade-in flex flex-col overflow-hidden", compact ? "p-4 h-[260px] lg:h-[260px]" : "p-6")}
    >
      <h3 className={cn("font-medium text-muted-foreground", compact ? "text-xs mb-3" : "text-sm mb-4")}>
        Meteo Locale
      </h3>

      <div className={cn("flex items-center gap-4", compact ? "mb-3" : "mb-4")}>
        <div
          className={cn(
            "bg-primary/10 rounded-xl flex items-center justify-center",
            compact ? "w-14 h-14" : "w-16 h-16",
          )}
        >
          <TodayIcon className={cn("text-primary", compact ? "w-8 h-8" : "w-10 h-10")} />
        </div>

        <div className="min-w-0">
          <p className={cn("font-bold leading-none tabular-nums", compact ? "text-[40px]" : "text-4xl")}>
            {mockWeather.today.temp}°
          </p>
          <p className={cn("text-muted-foreground", compact ? "text-xs mt-1" : "text-sm")}>Oggi, Soleggiato</p>
        </div>
      </div>

      <div className={cn("grid grid-cols-4 gap-2 border-t border-border mt-auto", compact ? "pt-3" : "pt-4")}>
        {mockWeather.forecast.map((day) => {
          const DayIcon = day.icon;
          return (
            <div key={day.day} className="text-center">
              <p className={cn("text-muted-foreground", compact ? "text-[10px]" : "text-xs")}>{day.day}</p>
              <DayIcon className={cn("mx-auto my-1 text-muted-foreground", compact ? "w-4 h-4" : "w-5 h-5")} />
              <p className={cn("font-medium", compact ? "text-xs" : "text-sm")}>{day.temp}°</p>
            </div>
          );
        })}
      </div>
    </Card>
  );
}
