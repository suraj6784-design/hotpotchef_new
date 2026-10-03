// Canonical marketplace roles. JWT `user_metadata.role` and public.users.role
// historically diverged (`Delivery Partner`, `Food Lover`, `Delivery`, …).

export type AppRole = "customer" | "chef" | "driver" | "admin"

export function parseAppRole(raw: unknown): AppRole {
  const s = String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")

  switch (s) {
    case "chef":
    case "cook":
    case "kitchen":
      return "chef"
    case "driver":
    case "delivery":
    case "delivery partner":
    case "deliverypartner":
      return "driver"
    case "admin":
    case "ops":
    case "platform":
    case "platform admin":
    case "platformadmin":
      return "admin"
    case "customer":
    case "food lover":
    case "foodlover":
    case "diner":
      return "customer"
    default:
      return "customer"
  }
}

export function canonicalAppRoleLabel(role: AppRole): "Customer" | "Chef" | "Driver" | "Admin" {
  switch (role) {
    case "chef":
      return "Chef"
    case "driver":
      return "Driver"
    case "admin":
      return "Admin"
    case "customer":
      return "Customer"
  }
}
