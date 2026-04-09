import { useEffect, useMemo, useState } from "react";
import { Calendar as CalendarIcon } from "lucide-react";
import { format, parse, isValid } from "date-fns";
import { it } from "date-fns/locale";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import { cn } from "@/lib/utils";

function parseISODate(s: string): Date | null {
  const d = parse(s, "yyyy-MM-dd", new Date());
  return isValid(d) ? d : null;
}

function toISODate(d: Date) {
  return format(d, "yyyy-MM-dd");
}

export function DateField({
  value,
  onChange,
  className,
}: {
  value: string;
  onChange: (nextISO: string) => void;
  className?: string;
}) {
  const [text, setText] = useState(value);

  useEffect(() => {
    setText(value);
  }, [value]);

  const selectedDate = useMemo(() => parseISODate(value), [value]);

  const commit = () => {
    const d = parseISODate(text);
    if (d) onChange(toISODate(d));
    else setText(value); // rollback se invalida
  };

  return (
    <div className={cn("flex items-center gap-1", className)}>
      <Input
        value={text}
        onChange={(e) => setText(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            commit();
          }
        }}
        className="h-9 w-[150px]"
      />

      <Popover>
        <PopoverTrigger asChild>
          <Button variant="outline" size="icon" className="h-9 w-9">
            <CalendarIcon className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0" align="start">
          <Calendar
            mode="single"
            selected={selectedDate ?? undefined}
            onSelect={(d) => {
              if (!d) return;
              onChange(toISODate(d));
            }}
            locale={it}
            className={cn("p-3 pointer-events-auto")}
          />
        </PopoverContent>
      </Popover>
    </div>
  );
}
