import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  chefPayoutBreakdown,
  chefTakeHomeAfterDriverStipend,
  FREE_DELIVERY_DRIVER_PAYOUT,
  freeDeliveryDriverStipend,
  orderUsesDeliveryPartner,
  roundMoney,
} from './payout.ts'

Deno.test('free delivery above ₹199 pays the existing ₹20 chef-funded stipend', () => {
  assertEquals(FREE_DELIVERY_DRIVER_PAYOUT >= 15 && FREE_DELIVERY_DRIVER_PAYOUT <= 20, true)
  assertEquals(FREE_DELIVERY_DRIVER_PAYOUT, 20)
  assertEquals(
    freeDeliveryDriverStipend({ foodTotal: 220, deliveryFee: 0, partnerDelivery: true }),
    20,
  )
  assertEquals(
    freeDeliveryDriverStipend({ foodTotal: 199, deliveryFee: 0, partnerDelivery: true }),
    20,
  )
  assertEquals(
    freeDeliveryDriverStipend({ foodTotal: 198.99, deliveryFee: 0, partnerDelivery: true }),
    0,
  )
  assertEquals(
    freeDeliveryDriverStipend({ foodTotal: 220, deliveryFee: 30, partnerDelivery: true }),
    0,
  )
  assertEquals(
    freeDeliveryDriverStipend({ foodTotal: 220, deliveryFee: 0, partnerDelivery: false }),
    0,
  )
})

Deno.test('chef take-home drops by that stipend and paid delivery does not', () => {
  const gross = chefPayoutBreakdown(220, 20)
  const net = chefTakeHomeAfterDriverStipend(gross.chefPayout, FREE_DELIVERY_DRIVER_PAYOUT)
  assertEquals(net, roundMoney(gross.chefPayout - 20))
  assertEquals(gross.margin, roundMoney(240 - gross.chefPayout))

  const paid = chefPayoutBreakdown(151, 20)
  assertEquals(paid.chefPayout, 145.35)
  assertEquals(
    chefTakeHomeAfterDriverStipend(paid.chefPayout, 0),
    paid.chefPayout,
  )
})

Deno.test('partner vs chef-self matches the driver card rule', () => {
  assertEquals(orderUsesDeliveryPartner('Delivery Partner'), true)
  assertEquals(orderUsesDeliveryPartner('Chef-Self'), false)
  assertEquals(orderUsesDeliveryPartner('Customer Pickup'), false)
  assertEquals(
    orderUsesDeliveryPartner('', [{ selected_service_type: 'Chef-Self' }]),
    false,
  )
})
