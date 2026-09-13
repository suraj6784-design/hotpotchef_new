// Shared order-status parser for edge functions.
// Canonical form is snake_case. Accepts Title Case from the chef app
// ("Ready for Pickup") and snake_case from the driver app
// (`ready_for_pickup`) during the transition.

export type OrderStatusKind =
  | "pending_chef_approval"
  | "confirmed"
  | "preparing"
  | "ready_for_pickup"
  | "driver_assigned"
  | "accepted"
  | "picked_up"
  | "out_for_delivery"
  | "delivered"
  | "cancelled"
  | "completed"
  | "unknown"

function normalize(raw: unknown): string {
  return String(raw ?? "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]/g, "")
}

export function parseOrderStatus(raw: unknown): OrderStatusKind {
  const s = normalize(raw)
  if (!s) return "unknown"

  switch (s) {
    case "pendingchefapproval":
    case "pending":
      return "pending_chef_approval"
    case "confirmed":
      return "confirmed"
    case "preparing":
      return "preparing"
    case "readyforpickup":
    case "ready":
      return "ready_for_pickup"
    case "driverassigned":
      return "driver_assigned"
    case "accepted":
      return "accepted"
    case "pickedup":
    case "picked":
      return "picked_up"
    case "outfordelivery":
    case "out":
      return "out_for_delivery"
    case "delivered":
      return "delivered"
    case "cancelled":
    case "canceled":
    case "rejected":
      return "cancelled"
    case "completed":
      return "completed"
    default:
      return "unknown"
  }
}

export function isReadyForPickup(raw: unknown): boolean {
  return parseOrderStatus(raw) === "ready_for_pickup"
}

export function isOutForDelivery(raw: unknown): boolean {
  return parseOrderStatus(raw) === "out_for_delivery"
}
