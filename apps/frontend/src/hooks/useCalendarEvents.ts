import { useEffect, useState } from 'react';
import { apiGet } from '@/lib/apiClient';

export interface CalendarEvent {
  id: string;
  date: string;
  name: string;
  impact_level: 'low' | 'medium' | 'high';
}

export function useCalendarEvents(year: number, month: number) {
  const [events, setEvents] = useState<CalendarEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchEvents() {
      setLoading(true);
      
      const startDate = `${year}-${String(month + 1).padStart(2, '0')}-01`;
      const endDate = new Date(year, month + 1, 0).toISOString().split('T')[0];

      try {
        const resp = await apiGet('/api/v1/planner/calendar-events', {
          date_from: startDate,
          date_to: endDate,
        });
        setEvents(((resp?.items) as CalendarEvent[]) || []);
      } catch (err: any) {
        console.log('Errore fetch eventi:', err.message);
        setEvents([]);
      }
      
      setLoading(false);
    }

    fetchEvents();
  }, [year, month]);

  // Helper: restituisce i giorni con eventi
  const eventDays = events.map(e => new Date(e.date).getDate());

  return { events, eventDays, loading };
}
