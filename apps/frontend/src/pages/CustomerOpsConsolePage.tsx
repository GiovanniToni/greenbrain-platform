import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Users, LayoutDashboard, Terminal, RefreshCw, UserPlus } from "lucide-react";
import { Card } from "@/components/ui/card";
import { createAdminUser, listCustomers, type CustomerOpsItem } from "@/lib/customerOpsApi";
import { PasswordInput } from "@/components/PasswordInput";

function computeKpis(items: CustomerOpsItem[]) {
  return {
    total: items.length,
    active: items.filter((x) => x.subscription_status === "active").length,
    slotPending: items.filter((x) => x.onboarding_status === "slot_requested").length,
    dataValidation: items.filter((x) => x.onboarding_status === "data_validation_pending").length,
    deliveryPending: items.filter(
      (x) =>
        Boolean(x.assigned_release_version) &&
        (!x.delivery_status || x.delivery_status === "pending" || x.delivery_status === "prepared"),
    ).length,
    noPayment: items.filter((x) => !x.payment_method_saved).length,
  };
}

type Kpis = ReturnType<typeof computeKpis>;

export default function CustomerOpsConsolePage() {
  const [kpis, setKpis] = useState<Kpis | null>(null);
  const [loadingKpis, setLoadingKpis] = useState(true);
  const [adminForm, setAdminForm] = useState({ email: "", full_name: "", password: "" });
  const [adminCreating, setAdminCreating] = useState(false);
  const [adminMessage, setAdminMessage] = useState<string | null>(null);
  const [adminError, setAdminError] = useState<string | null>(null);

  async function submitAdminUser(e: React.FormEvent) {
    e.preventDefault();
    setAdminCreating(true);
    setAdminMessage(null);
    setAdminError(null);

    try {
      const user = await createAdminUser({
        email: adminForm.email,
        full_name: adminForm.full_name || undefined,
        password: adminForm.password,
      });
      setAdminMessage(`Admin creato: ${user.email}`);
      setAdminForm({ email: "", full_name: "", password: "" });
    } catch (err) {
      setAdminError(err instanceof Error ? err.message : "Errore creazione admin");
    } finally {
      setAdminCreating(false);
    }
  }

  useEffect(() => {
    setLoadingKpis(true);
    listCustomers(200)
      .then((data) => setKpis(computeKpis(data.items || [])))
      .catch(() => setKpis(null))
      .finally(() => setLoadingKpis(false));
  }, []);

  const kpiItems: { label: string; value: number; color: string; alert?: boolean }[] = kpis
    ? [
        { label: "Clienti totali",        value: kpis.total,         color: "#374151" },
        { label: "Abbonamenti attivi",     value: kpis.active,        color: "#16a34a" },
        { label: "Slot da confermare",     value: kpis.slotPending,   color: "#d97706", alert: kpis.slotPending > 0 },
        { label: "Validazione pendente",   value: kpis.dataValidation,color: "#7c3aed", alert: kpis.dataValidation > 0 },
        { label: "Delivery pendenti",      value: kpis.deliveryPending,color: "#0369a1",alert: kpis.deliveryPending > 0 },
        { label: "Senza pagamento",        value: kpis.noPayment,     color: "#b91c1c", alert: kpis.noPayment > 0 },
      ]
    : [];

  return (
    <div className="max-w-6xl mx-auto">
      <div className="mb-8 rounded-2xl border bg-white p-6 shadow-sm">
        <div className="flex items-start justify-between gap-6 flex-wrap">
          <div className="flex items-start gap-4">
            <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center shrink-0">
              <Terminal className="w-6 h-6 text-primary" />
            </div>
            <div>
              <h1 className="text-3xl font-bold leading-tight">Console operativa GreenBrain</h1>
              <p className="text-muted-foreground text-sm mt-2 max-w-2xl">
                Centro di controllo interno per clienti, onboarding, pagamenti, slot setup, delivery e accesso alla piattaforma.
              </p>
            </div>
          </div>

          <div className="text-xs text-muted-foreground bg-muted/40 border rounded-full px-3 py-1">
            Area team interno
          </div>
        </div>
      </div>

      {/* live KPI strip */}
      <div className="mb-8 rounded-2xl border bg-white p-5 shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">KPI operativi in tempo reale</span>
          {loadingKpis && <RefreshCw className="w-4 h-4 animate-spin text-muted-foreground" />}
        </div>
        {loadingKpis && !kpis ? (
          <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="bg-muted/30 border border-dashed rounded-xl p-4 h-20 animate-pulse" />
            ))}
          </div>
        ) : kpis ? (
          <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
            {kpiItems.map(({ label, value, color, alert }) => (
              <div
                key={label}
                className="border rounded-xl p-4 text-center"
                style={{ background: alert && value > 0 ? `${color}10` : "#fafafa", borderColor: alert && value > 0 ? `${color}40` : undefined }}
              >
                <div style={{ fontSize: 30, fontWeight: 850, color, lineHeight: 1 }}>{value}</div>
                <div className="text-xs text-muted-foreground mt-2 leading-tight">{label}</div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">Dati non disponibili.</p>
        )}
      </div>

      {/* main entry cards */}
      <div className="grid lg:grid-cols-2 gap-5">
        <Link to="/customers">
          <Card className="p-7 hover:border-primary/50 hover:shadow-md transition-all cursor-pointer h-full group border-primary/20">
            <div className="flex items-start justify-between gap-4 mb-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center group-hover:bg-primary/20 transition-colors">
                  <Users className="w-6 h-6 text-primary" />
                </div>
                <div>
                  <h2 className="font-semibold text-xl leading-tight">Gestisci clienti</h2>
                  {kpis && <p className="text-xs text-muted-foreground mt-1">{kpis.total} clienti · {kpis.active} attivi</p>}
                </div>
              </div>
              <span className="text-xs px-2 py-1 rounded-full bg-primary/10 text-primary border border-primary/20">Ops</span>
            </div>
            <p className="text-sm text-muted-foreground leading-relaxed">
              Vista operativa per onboarding, slot setup, pagamento, abbonamento, delivery, download e disdette.
            </p>
            {kpis && (kpis.slotPending > 0 || kpis.dataValidation > 0 || kpis.deliveryPending > 0 || kpis.noPayment > 0) && (
              <div className="flex gap-2 mt-4 flex-wrap">
                {kpis.slotPending > 0 && <span className="text-xs px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200">{kpis.slotPending} slot</span>}
                {kpis.dataValidation > 0 && <span className="text-xs px-2 py-0.5 rounded-full bg-violet-50 text-violet-700 border border-violet-200">{kpis.dataValidation} validazioni</span>}
                {kpis.deliveryPending > 0 && <span className="text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">{kpis.deliveryPending} delivery</span>}
                {kpis.noPayment > 0 && <span className="text-xs px-2 py-0.5 rounded-full bg-red-50 text-red-700 border border-red-200">{kpis.noPayment} senza pagamento</span>}
              </div>
            )}
          </Card>
        </Link>

        <Link to="/dashboard">
          <Card className="p-7 hover:border-primary/50 hover:shadow-md transition-all cursor-pointer h-full">
            <div className="flex items-start justify-between gap-4 mb-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center">
                  <LayoutDashboard className="w-6 h-6 text-primary" />
                </div>
                <div>
                  <h2 className="font-semibold text-xl leading-tight">Piattaforma</h2>
                  <p className="text-xs text-muted-foreground mt-1">Dashboard cliente / operativa</p>
                </div>
              </div>
              <span className="text-xs px-2 py-1 rounded-full bg-muted text-muted-foreground border">App</span>
            </div>
            <p className="text-sm text-muted-foreground leading-relaxed">
              Accedi alla dashboard GreenBrain: forecast, analytics, pianificazione, riordino e fornitori.
            </p>
          </Card>
        </Link>
      </div>

      <div className="mt-8 rounded-2xl border bg-white p-6 shadow-sm">
        <div className="flex items-start gap-4 mb-5">
          <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center shrink-0">
            <UserPlus className="w-6 h-6 text-primary" />
          </div>
          <div>
            <h2 className="font-semibold text-xl leading-tight">Crea admin GreenBrain</h2>
            <p className="text-sm text-muted-foreground mt-1">
              Crea un nuovo utente interno con accesso alla console Ops e alla piattaforma dev.
            </p>
          </div>
        </div>

        <form onSubmit={submitAdminUser} className="grid md:grid-cols-4 gap-3 items-end">
          <div>
            <label className="text-xs font-medium text-muted-foreground">Nome</label>
            <input
              className="w-full mt-1 border rounded-lg px-3 py-2 text-sm"
              value={adminForm.full_name}
              onChange={(e) => setAdminForm((f) => ({ ...f, full_name: e.target.value }))}
              placeholder="Irene"
            />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Email</label>
            <input
              className="w-full mt-1 border rounded-lg px-3 py-2 text-sm"
              type="email"
              value={adminForm.email}
              onChange={(e) => setAdminForm((f) => ({ ...f, email: e.target.value }))}
              placeholder="nome@greenbrain.it"
              required
            />
          </div>
          <div>
            <label className="text-xs font-medium text-muted-foreground">Password temporanea</label>
            <PasswordInput
              className="w-full mt-1 border rounded-lg px-3 py-2 text-sm"
              value={adminForm.password}
              onChange={(e) => setAdminForm((f) => ({ ...f, password: e.target.value }))}
              placeholder="Minimo 8 caratteri"
              required
            />
          </div>
          <button
            type="submit"
            disabled={adminCreating}
            className="rounded-lg bg-primary text-primary-foreground px-4 py-2 text-sm font-semibold disabled:opacity-50"
          >
            {adminCreating ? "Creazione..." : "Crea admin"}
          </button>
        </form>

        {adminMessage && <p className="text-sm text-green-700 mt-3">{adminMessage}</p>}
        {adminError && <p className="text-sm text-red-700 mt-3">{adminError}</p>}
      </div>

      <div className="mt-8 rounded-xl border bg-muted/30 p-4 text-xs text-muted-foreground">
        Quest&apos;area è riservata al team interno GreenBrain. Non condividere l&apos;accesso con i clienti.
      </div>
    </div>
  );
}
