import { useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { ArrowRight, CheckCircle2, Leaf } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { signupCustomer } from "@/lib/customerOnboardingApi";

export default function Signup() {
  const [searchParams] = useSearchParams();
  const plan = searchParams.get("plan") || "starter";

  const [form, setForm] = useState({
    company_name: "",
    contact_name: "",
    contact_email: "",
    portal_password: "",
    city: "",
    country: "IT",
  });

  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  function update(key: string, value: string) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    try {
      setLoading(true);
      setError(null);
      const res = await signupCustomer({
        ...form,
        assigned_release_version: "0.1.12",
        subscription_plan: plan,
      });
      setResult(res);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore durante la registrazione");
    } finally {
      setLoading(false);
    }
  }

  const resultCustomer = result?.customer;

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b border-border/50 bg-card/80 backdrop-blur-sm">
        <div className="container mx-auto px-4 py-4 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary rounded-xl flex items-center justify-center">
              <Leaf className="w-6 h-6 text-primary-foreground" />
            </div>
            <span className="text-xl font-bold">GreenBrain</span>
          </Link>
          <Button variant="ghost" size="sm" asChild>
            <Link to="/login">Hai già un account? Accedi</Link>
          </Button>
        </div>
      </header>

      <div className="flex-1 flex items-center justify-center py-12 px-4">
        {result ? (
          <Card className="w-full max-w-md p-8 text-center">
            <div className="w-14 h-14 bg-primary/10 rounded-2xl flex items-center justify-center mx-auto mb-6">
              <CheckCircle2 className="w-8 h-8 text-primary" />
            </div>
            <h2 className="text-2xl font-bold mb-2">Account creato</h2>
            <p className="text-muted-foreground text-sm mb-6">
              Il tuo account GreenBrain è pronto. Accedi con le credenziali scelte per entrare
              nella tua area cliente e salvare il metodo di pagamento per avviare l&apos;attivazione.
            </p>
            <Separator className="mb-6" />
            <div className="text-left space-y-3 text-sm mb-8">
              {resultCustomer?.company_name && (
                <div className="flex justify-between items-center">
                  <span className="text-muted-foreground">Azienda</span>
                  <span className="font-medium">{resultCustomer.company_name}</span>
                </div>
              )}
              {resultCustomer?.tenant_code && (
                <div className="flex justify-between items-center">
                  <span className="text-muted-foreground">Tenant</span>
                  <span className="font-mono text-xs bg-muted px-2 py-0.5 rounded">
                    {resultCustomer.tenant_code}
                  </span>
                </div>
              )}
              {(resultCustomer?.portal_user_email || resultCustomer?.contact_email) && (
                <div className="flex justify-between items-center">
                  <span className="text-muted-foreground">Email accesso</span>
                  <span className="font-medium">
                    {resultCustomer?.portal_user_email ?? resultCustomer?.contact_email}
                  </span>
                </div>
              )}
            </div>
            <Button className="w-full" size="lg" asChild>
              <Link to="/login">
                Vai al login <ArrowRight className="w-4 h-4 ml-2" />
              </Link>
            </Button>
          </Card>
        ) : (
          <Card className="w-full max-w-md p-8">
            <div className="mb-8">
              <div className="flex items-center justify-between mb-2">
                <h1 className="text-2xl font-bold">Crea account aziendale</h1>
                <Badge variant="secondary" className="capitalize">{plan}</Badge>
              </div>
              <p className="text-muted-foreground text-sm">
                Dopo la registrazione potrai accedere alla tua area cliente,
                salvare il metodo di pagamento e avviare il processo di attivazione GreenBrain.
              </p>
            </div>

            <form onSubmit={submit} className="space-y-5">
              <div className="space-y-2">
                <Label htmlFor="company_name">Nome azienda</Label>
                <Input
                  id="company_name"
                  placeholder="Garden Center Rossi S.r.l."
                  value={form.company_name}
                  onChange={(e) => update("company_name", e.target.value)}
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="contact_name">Nome referente</Label>
                <Input
                  id="contact_name"
                  placeholder="Mario Rossi"
                  value={form.contact_name}
                  onChange={(e) => update("contact_name", e.target.value)}
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="contact_email">Email di accesso</Label>
                <Input
                  id="contact_email"
                  type="email"
                  placeholder="mario.rossi@azienda.it"
                  value={form.contact_email}
                  onChange={(e) => update("contact_email", e.target.value)}
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="portal_password">Password portale</Label>
                <Input
                  id="portal_password"
                  type="password"
                  placeholder="Almeno 8 caratteri"
                  value={form.portal_password}
                  onChange={(e) => update("portal_password", e.target.value)}
                  required
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="city">Città</Label>
                  <Input
                    id="city"
                    placeholder="Milano"
                    value={form.city}
                    onChange={(e) => update("city", e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="country">Paese</Label>
                  <Input
                    id="country"
                    placeholder="IT"
                    value={form.country}
                    onChange={(e) => update("country", e.target.value)}
                  />
                </div>
              </div>

              {error && (
                <p className="text-sm text-destructive bg-destructive/10 px-4 py-3 rounded-lg">
                  {error}
                </p>
              )}

              <Button type="submit" className="w-full" size="lg" disabled={loading}>
                {loading ? "Creazione account..." : (
                  <>Crea account <ArrowRight className="w-4 h-4 ml-2" /></>
                )}
              </Button>
            </form>

            <p className="text-xs text-center text-muted-foreground mt-6">
              Hai già un account?{" "}
              <Link to="/login" className="underline hover:text-foreground">
                Accedi
              </Link>
            </p>
          </Card>
        )}
      </div>
    </div>
  );
}
