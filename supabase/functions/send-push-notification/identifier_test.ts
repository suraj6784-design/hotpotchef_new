import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts"

// Live BOOT_ERROR: Uncaught SyntaxError: Identifier 'auth' has already been declared
// when authorizeInternalInvoke was stored as `auth` and GoogleAuth was also `auth`.

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
}

function bindingNames(src: string): string[] {
  return [...stripComments(src).matchAll(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\b/g)].map((m) => m[1])
}

Deno.test("send-push-notification does not bind identifier auth (GoogleAuth collision)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url))
  const names = bindingNames(src)
  assertEquals(names.filter((n) => n === "auth"), [])
  assertEquals(names.includes("invokeAuth"), true)
  assertEquals(stripComments(src).includes("GoogleAuth"), false)
  assertEquals(src.includes("npm:google-auth-library"), false)
})

Deno.test("reconstructed historical send-push snippet would declare auth twice", () => {
  const historical = `
    const auth = authorizeInternalInvoke(req.headers)
    const auth = new GoogleAuth({ credentials: serviceAccountJson })
  `
  const names = bindingNames(historical)
  assertEquals(names.filter((n) => n === "auth").length, 2)
})
