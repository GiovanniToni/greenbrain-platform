export type PlanCode = "starter" | "pro" | "advanced";

export const PLAN_META: Record<
  PlanCode,
  { label: string; price: number; tagline: string; features: string[]; highlighted?: boolean }
> = {
  starter: {
    label: "Starter",
    price: 99,
    tagline:
      "Ideale per Garden Center che vogliono analizzare i dati storici, monitorare le performance e pianificare l'assortimento.",
    features: [
      "Dati storici di vendita",
      "Dashboard analytics",
      "Assortment Planner",
      "Area cliente riservata",
      "Onboarding guidato incluso",
      "Aggiornamenti e supporto tecnico",
      "Attivazione abbonamento dal portale",
    ],
  },
  pro: {
    label: "Pro",
    price: 149,
    highlighted: true,
    tagline:
      "Per chi vuole anche previsioni della domanda e un processo di riordino strutturato e automatizzato.",
    features: [
      "Tutto di Starter",
      "Forecast domanda per prodotto",
      "Processo di riordino automatizzato",
    ],
  },
  advanced: {
    label: "Advanced",
    price: 199,
    tagline:
      "La soluzione completa con gestione avanzata dei fornitori.",
    features: [
      "Tutto di Pro",
      "Area fornitori",
    ],
  },
};

export const PLAN_CODES = Object.keys(PLAN_META) as PlanCode[];

export function planDisplayName(code: string | null | undefined): string {
  if (!code) return "—";
  const meta = PLAN_META[code as PlanCode];
  return meta ? `GreenBrain ${meta.label}` : code.charAt(0).toUpperCase() + code.slice(1);
}

export function planDisplayPrice(code: string | null | undefined): string | null {
  if (!code) return null;
  const meta = PLAN_META[code as PlanCode];
  return meta ? `€${meta.price}/mese` : null;
}
