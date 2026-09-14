// release-chef-payout: release an on-hold Route transfer after delivery.
// Skipped checkout paths (no Route account / mock / too-small) return skipped
// instead of throwing "No Razorpay Transfer ID".

import {
  basicAuthHeader,
  hasRazorpayKeys,
  isSkippedTransferStatus,
  RAZORPAY_API_BASE,
  razorpayErrorMessage,
  readRazorpayKeys,
} from "../_shared/razorpay_route.mjs"
import { isDeliveredLike } from "../_shared/order_status.ts"

export interface ReleaseRecord {
  id?: string
  status?: string
  transfer_status?: string
  razorpay_transfer_id?: string | null
  order_id?: string | null
}

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>

export interface ReleaseDeps {
  getRazorpayKeys?: () => { keyId: string; keySecret: string }
  fetchImpl?: FetchLike
  markReleased: (mealId: string, transferId: string) => Promise<void>
}

export interface ReleaseResult {
  status: number
  body: Record<string, unknown>
}

function jsonResult(body: Record<string, unknown>, status = 200): ReleaseResult {
  return { status, body }
}

export function firstTransferIdFromOrder(order: unknown): string | null {
  if (!order || typeof order !== "object") return null
  const transfers = (order as { transfers?: unknown }).transfers
  if (!Array.isArray(transfers)) return null
  for (const row of transfers) {
    if (row && typeof row === "object" && (row as { id?: unknown }).id) {
      const id = String((row as { id: unknown }).id)
      if (id.startsWith("trf_")) return id
    }
  }
  return null
}

export async function fetchTransferIdForOrder(
  orderId: string,
  keys: { keyId: string; keySecret: string },
  fetchImpl: FetchLike,
): Promise<string | null> {
  const url = `${RAZORPAY_API_BASE}/v1/orders/${encodeURIComponent(orderId)}?expand[]=transfers`
  const response = await fetchImpl(url, {
    method: "GET",
    headers: {
      Authorization: basicAuthHeader(keys.keyId, keys.keySecret),
    },
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(razorpayErrorMessage(data, "Failed to load Razorpay order transfers"))
  }
  return firstTransferIdFromOrder(data)
}

export async function releaseHeldTransfer(
  transferId: string,
  keys: { keyId: string; keySecret: string },
  fetchImpl: FetchLike,
): Promise<Record<string, unknown>> {
  const response = await fetchImpl(`${RAZORPAY_API_BASE}/v1/transfers/${encodeURIComponent(transferId)}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: basicAuthHeader(keys.keyId, keys.keySecret),
    },
    body: JSON.stringify({ on_hold: 0 }),
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(razorpayErrorMessage(data, "Failed to release transfer hold on Razorpay"))
  }
  return data as Record<string, unknown>
}

export async function handleReleaseChefPayout(
  payload: { record?: ReleaseRecord; table?: string },
  deps: ReleaseDeps,
): Promise<ReleaseResult> {
  const record = payload.record
  // Catalog meal status churn (Available/Paused/Archived) must not release.
  // Orders use delivered / completed (Title Case or snake_case).
  if (!record || !isDeliveredLike(record.status)) {
    return jsonResult({ skipped: true, reason: "not_delivered" })
  }
  if (record.transfer_status === "released") {
    return jsonResult({ skipped: true, reason: "already_released" })
  }
  if (isSkippedTransferStatus(record.transfer_status)) {
    return jsonResult({ skipped: true, reason: record.transfer_status })
  }

  const keys = (deps.getRazorpayKeys ?? readRazorpayKeys)()
  if (!hasRazorpayKeys(keys)) {
    return jsonResult({ error: "Payment gateway configuration missing" }, 400)
  }

  const fetchImpl = deps.fetchImpl ?? globalThis.fetch
  let transferId = record.razorpay_transfer_id ? String(record.razorpay_transfer_id) : ""

  try {
    if (!transferId && record.order_id) {
      transferId = await fetchTransferIdForOrder(String(record.order_id), keys, fetchImpl) ?? ""
    }
    if (!transferId) {
      return jsonResult({ skipped: true, reason: "no_transfer_id" })
    }

    const rzpResult = await releaseHeldTransfer(transferId, keys, fetchImpl)
    if (record.id) {
      await deps.markReleased(String(record.id), transferId)
    }
    return jsonResult({ success: true, transfer_id: transferId, rzpResult })
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to release chef payout"
    return jsonResult({ error: message }, 400)
  }
}
