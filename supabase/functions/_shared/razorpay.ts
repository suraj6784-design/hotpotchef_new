export function razorpayAuthHeader() {
  const keyId = Deno.env.get('RAZORPAY_KEY_ID') ?? ''
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET') ?? ''
  if (!keyId || !keySecret) {
    throw new Error('Razorpay is not configured')
  }
  return { keyId, keySecret, header: `Basic ${btoa(`${keyId}:${keySecret}`)}` }
}

export async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message))
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

export async function verifyCheckoutSignature(
  orderId: string,
  paymentId: string,
  signature: string,
): Promise<boolean> {
  const { keySecret } = razorpayAuthHeader()
  const expected = await hmacSha256Hex(`${orderId}|${paymentId}`, keySecret)
  return expected === signature
}

export async function fetchPayment(paymentId: string) {
  const { header } = razorpayAuthHeader()
  const res = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}`, {
    headers: { Authorization: header },
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error(data?.error?.description || 'Could not fetch Razorpay payment')
  }
  return data
}

export async function refundPayment(paymentId: string, amountPaise?: number) {
  const { header } = razorpayAuthHeader()
  const body: Record<string, unknown> = { speed: 'normal' }
  if (amountPaise && amountPaise > 0) body.amount = amountPaise

  const res = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/refund`, {
    method: 'POST',
    headers: {
      Authorization: header,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const data = await res.json()
  if (!res.ok) {
    const description = String(data?.error?.description || '')
    if (/already refunded|fully refunded/i.test(description)) {
      return { id: 'already_refunded', status: 'processed', already: true }
    }
    throw new Error(description || 'Razorpay refund failed')
  }
  return data
}

export async function createRazorpayOrder(amountPaise: number, receipt: string, notes: Record<string, string>) {
  const { header } = razorpayAuthHeader()
  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      Authorization: header,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: amountPaise,
      currency: 'INR',
      receipt,
      notes,
    }),
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error(data?.error?.description || 'Razorpay order creation failed')
  }
  return data
}

export async function createPaymentTransfer(paymentId: string, accountId: string, amountPaise: number, notes: Record<string, string>) {
  const { header } = razorpayAuthHeader()
  const res = await fetch(`https://api.razorpay.com/v1/payments/${paymentId}/transfers`, {
    method: 'POST',
    headers: {
      Authorization: header,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      transfers: [
        {
          account: accountId,
          amount: amountPaise,
          currency: 'INR',
          notes,
          on_hold: false,
        },
      ],
    }),
  })
  const data = await res.json()
  if (!res.ok) {
    throw new Error(data?.error?.description || 'Razorpay transfer failed')
  }
  const transfer = Array.isArray(data?.items) ? data.items[0] : (Array.isArray(data) ? data[0] : data)
  return transfer
}
