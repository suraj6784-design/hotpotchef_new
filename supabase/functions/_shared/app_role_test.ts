import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { canonicalAppRoleLabel, parseAppRole } from "./app_role.ts"

Deno.test("maps JWT/DB aliases onto Chef Customer Driver Admin", () => {
  assertEquals(parseAppRole("Delivery Partner"), "driver")
  assertEquals(parseAppRole("delivery_partner"), "driver")
  assertEquals(parseAppRole("Delivery"), "driver")
  assertEquals(parseAppRole("Food Lover"), "customer")
  assertEquals(parseAppRole("Chef"), "chef")
  assertEquals(canonicalAppRoleLabel(parseAppRole("Food Lover")), "Customer")
  assertEquals(canonicalAppRoleLabel(parseAppRole("Delivery Partner")), "Driver")
})
