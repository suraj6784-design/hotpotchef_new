import { sendFcm } from "./fcm.ts"

Deno.test("sendFcm no-ops without a service account (no throw)", async () => {
  await sendFcm("token", "title", "body", { alert_id: "unit-test" })
})

Deno.test("sendFcm no-ops on invalid FIREBASE_SERVICE_ACCOUNT JSON", async () => {
  const prev = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")
  Deno.env.set("FIREBASE_SERVICE_ACCOUNT", "{not-json")
  try {
    await sendFcm("token", "title", "body", { alert_id: "unit-test" })
  } finally {
    if (prev === undefined) {
      Deno.env.delete("FIREBASE_SERVICE_ACCOUNT")
    } else {
      Deno.env.set("FIREBASE_SERVICE_ACCOUNT", prev)
    }
  }
})
