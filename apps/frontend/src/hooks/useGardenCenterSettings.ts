import { useEffect, useState } from 'react';
import { apiGet, apiPost } from '@/lib/apiClient';

export interface GardenCenterSettings {
  city: string;
  lat: number | null;
  lon: number | null;
}

const defaultSettings: GardenCenterSettings = {
  city: '',
  lat: null,
  lon: null,
};

export function useGardenCenterSettings() {
  const [settings, setSettings] = useState<GardenCenterSettings>(defaultSettings);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    apiGet('/api/v1/settings/garden-center')
      .then((data) => {
        setSettings({
          city: data.city || '',
          lat: data.lat != null ? Number(data.lat) : null,
          lon: data.lon != null ? Number(data.lon) : null,
        });
      })
      .catch((err) => console.log('Errore fetch settings:', err.message))
      .finally(() => setLoading(false));
  }, []);

  const saveSettings = async (newSettings: GardenCenterSettings) => {
    setSaving(true);
    try {
      await apiPost('/api/v1/settings/garden-center', newSettings);
      setSettings(newSettings);
      setSaving(false);
      return { error: null };
    } catch (err: any) {
      console.log('Errore salvataggio settings:', err.message);
      setSaving(false);
      return { error: err.message ?? 'Errore salvataggio' };
    }
  };

  return { settings, loading, saving, saveSettings };
}
