import type { CustomerOpsItem } from "@/lib/customerOpsApi";

// LATEST_RELEASE must be kept manually aligned to the highest semver folder in:
// /opt/greenbrain-platform/releases/customer-local/
// The frontend cannot read the filesystem at runtime; this value must be
// updated whenever a new customer release folder is added.
// Current on-disk folders: 0.1.0 0.1.1 0.1.3–0.1.12  →  latest = 0.1.12
export const LATEST_RELEASE = "0.1.12";

const PRE_OPERATOR_STATUSES = new Set(["draft", "signup_started", "checkout_started"]);

export function customerHealth(
  item: CustomerOpsItem,
): { label: string; color: string; bg: string } {
  if ((item.subscription_status || "").toLowerCase() === "active") {
    return { label: "Ready", color: "#166534", bg: "#dcfce7" };
  }
  if (PRE_OPERATOR_STATUSES.has((item.onboarding_status || "").toLowerCase())) {
    return { label: "Blocked", color: "#991b1b", bg: "#fee2e2" };
  }
  if (!item.payment_method_saved) {
    return { label: "Blocked", color: "#991b1b", bg: "#fee2e2" };
  }
  return { label: "In onboarding", color: "#92400e", bg: "#fef3c7" };
}
