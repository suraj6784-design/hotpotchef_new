import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"
import { isOutForDelivery, isReadyForPickup, parseOrderStatus } from "./order_status.ts"

Deno.test("parses chef Title Case and driver snake_case to the same kind", () => {
  assertEquals(parseOrderStatus("Ready for Pickup"), "ready_for_pickup")
  assertEquals(parseOrderStatus("ready_for_pickup"), "ready_for_pickup")
  assertEquals(parseOrderStatus("Out for Delivery"), "out_for_delivery")
  assertEquals(parseOrderStatus("out_for_delivery"), "out_for_delivery")
})

Deno.test("push helpers accept both wire forms", () => {
  assertEquals(isReadyForPickup("Ready for Pickup"), true)
  assertEquals(isReadyForPickup("ready_for_pickup"), true)
  assertEquals(isOutForDelivery("Out for Delivery"), true)
  assertEquals(isOutForDelivery("out_for_delivery"), true)
  assertEquals(isOutForDelivery("Preparing"), false)
})
