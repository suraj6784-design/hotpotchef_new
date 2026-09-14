// Public catalog filter shared by ai-search / ILIKE fallbacks.
// Only `Available` inventory rows are searchable.

export function isAvailableStatus(raw: unknown): boolean {
  return String(raw ?? "").trim().toLowerCase() === "available"
}

export function isSellableMeal(row: Record<string, unknown> | null | undefined): boolean {
  if (!row) return false
  if (!isAvailableStatus(row.status)) return false
  const customerName = String(row.customer_name ?? "").trim()
  return customerName.length === 0
}

export function filterSellableMeals<T extends Record<string, unknown>>(rows: T[] | null | undefined): T[] {
  if (!rows) return []
  return rows.filter((row) => isSellableMeal(row))
}
