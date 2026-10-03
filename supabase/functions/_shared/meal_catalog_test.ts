import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { filterSellableMeals, isAvailableStatus } from "./meal_catalog.ts"

Deno.test("only Available inventory rows pass", () => {
  assertEquals(isAvailableStatus("Available"), true)
  assertEquals(isAvailableStatus("Archived"), false)
  assertEquals(isAvailableStatus("Closed"), false)
  const rows = filterSellableMeals([
    { id: "1", status: "Available", customer_name: "" },
    { id: "2", status: "Archived", customer_name: "" },
    { id: "3", status: "Closed", customer_name: "" },
    { id: "4", status: "Paused", customer_name: "" },
    { id: "5", status: "cancelled", customer_name: "" },
    { id: "6", status: "Available", customer_name: "diner@example.com" },
  ])
  assertEquals(rows.map((r) => r.id), ["1"])
})
