import { useState } from "react";
import { signupCustomer } from "@/lib/customerOnboardingApi";

export default function Signup() {
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

  async function submit() {
    try {
      setLoading(true);
      setError(null);

      const res = await signupCustomer({
        ...form,
        assigned_release_version: "0.1.12",
      });

      setResult(res);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore signup");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ maxWidth: 600, margin: "40px auto", fontFamily: "sans-serif" }}>
      <h2>Customer Signup</h2>

      <input placeholder="Company" onChange={(e) => update("company_name", e.target.value)} />
      <br /><br />

      <input placeholder="Nome contatto" onChange={(e) => update("contact_name", e.target.value)} />
      <br /><br />

      <input placeholder="Email" onChange={(e) => update("contact_email", e.target.value)} />
      <br /><br />

      <input
        type="password"
        placeholder="Password portale"
        onChange={(e) => update("portal_password", e.target.value)}
      />
      <br /><br />

      <input placeholder="Città" onChange={(e) => update("city", e.target.value)} />
      <br /><br />

      <button onClick={submit} disabled={loading}>
        {loading ? "Creazione..." : "Crea cliente"}
      </button>

      {error && <p style={{ color: "red" }}>{error}</p>}

      {result && (
        <pre style={{ marginTop: 20 }}>
          {JSON.stringify(result, null, 2)}
        </pre>
      )}
    </div>
  );
}
