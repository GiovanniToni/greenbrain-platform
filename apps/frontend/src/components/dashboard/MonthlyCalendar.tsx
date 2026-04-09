import { useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useCalendarEvents } from "@/hooks/useCalendarEvents";

const days = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"];

interface MonthlyCalendarProps {
  onSelectDate?: (date: Date) => void;
  variant?: "default" | "compact";
}

export function MonthlyCalendar({ onSelectDate, variant = "default" }: MonthlyCalendarProps) {
  const compact = variant === "compact";

  const today = new Date();
  const [viewDate, setViewDate] = useState(new Date(today.getFullYear(), today.getMonth(), 1));
  const [selectedDay, setSelectedDay] = useState<number | null>(null);

  const year = viewDate.getFullYear();
  const month = viewDate.getMonth();

  const { eventDays } = useCalendarEvents(year, month);

  const firstDayOfMonth = new Date(year, month, 1).getDay(); // 0=Dom
  const daysInMonth = new Date(year, month + 1, 0).getDate();

  // Offset per iniziare da Lunedì
  const offset = firstDayOfMonth === 0 ? 6 : firstDayOfMonth - 1;

  const calendarDays: (number | null)[] = useMemo(() => {
    const arr: (number | null)[] = [];
    for (let i = 0; i < offset; i++) arr.push(null);
    for (let i = 1; i <= daysInMonth; i++) arr.push(i);

    // ✅ completiamo fino a multiplo di 7 per avere righe complete (35 o 42)
    while (arr.length % 7 !== 0) arr.push(null);

    return arr;
  }, [offset, daysInMonth]);

  // ✅ quante righe? (5 o 6)
  const rowsCount = Math.ceil(calendarDays.length / 7); // 5 o 6

  // ✅ se 6 righe, celle più basse per stare nella card h-[260px]
  const cellClass = useMemo(() => {
    if (!compact) return "h-10"; // default un po' più grande (ma non usato nella prima riga)
    return rowsCount >= 6 ? "h-7" : "h-8"; // 6 righe -> più compatto
  }, [compact, rowsCount]);

  const monthName = viewDate.toLocaleDateString("it-IT", { month: "long", year: "numeric" });

  const isToday = (day: number) =>
    day === today.getDate() && month === today.getMonth() && year === today.getFullYear();

  const hasEvent = (day: number) => eventDays.includes(day);

  const handlePrevMonth = () => {
    setViewDate(new Date(year, month - 1, 1));
    setSelectedDay(null);
  };

  const handleNextMonth = () => {
    setViewDate(new Date(year, month + 1, 1));
    setSelectedDay(null);
  };

  const handleDayClick = (day: number) => {
    setSelectedDay(day);
    onSelectDate?.(new Date(year, month, day));
  };

  return (
    <Card
      className={cn(
        "animate-fade-in flex flex-col",
        compact ? "p-4 h-[260px] lg:h-[260px]" : "p-6",
        "overflow-hidden", // ✅ garantisce che niente sfori
      )}
    >
      {/* Header */}
      <div className={cn("flex items-center justify-between", compact ? "mb-2" : "mb-4")}>
        <h3 className={cn("font-medium text-muted-foreground capitalize", compact ? "text-xs" : "text-sm")}>
          {monthName}
        </h3>
        <div className="flex gap-1">
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={handlePrevMonth}>
            <ChevronLeft className="w-4 h-4" />
          </Button>
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={handleNextMonth}>
            <ChevronRight className="w-4 h-4" />
          </Button>
        </div>
      </div>

      {/* Giorni della settimana */}
      <div className={cn("grid grid-cols-7 gap-1", compact ? "mb-1" : "mb-2")}>
        {days.map((d) => (
          <div
            key={d}
            className={cn(
              "text-center font-medium text-muted-foreground",
              compact ? "text-[10px] py-0.5" : "text-xs py-1",
            )}
          >
            {d}
          </div>
        ))}
      </div>

      {/* Griglia giorni (sempre dentro) */}
      <div className="grid grid-cols-7 gap-1 flex-1 min-h-0">
        {calendarDays.map((day, index) => (
          <button
            key={index}
            type="button"
            disabled={day === null}
            onClick={() => day && handleDayClick(day)}
            className={cn(
              "w-full flex items-center justify-center rounded-md text-sm leading-none transition-colors relative",
              cellClass,
              compact ? "text-xs" : "text-sm",
              day === null && "invisible",
              day !== null && isToday(day) && "bg-primary text-primary-foreground font-bold",
              day !== null && !isToday(day) && selectedDay === day && "bg-accent text-accent-foreground",
              day !== null && !isToday(day) && selectedDay !== day && "hover:bg-muted",
            )}
          >
            {day}
            {day !== null && hasEvent(day) && !isToday(day) && (
              <span className="absolute bottom-1 w-1.5 h-1.5 bg-destructive rounded-full" />
            )}
          </button>
        ))}
      </div>
    </Card>
  );
}
