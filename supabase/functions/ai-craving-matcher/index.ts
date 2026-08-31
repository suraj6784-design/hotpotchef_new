import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

// CORS Headers for Flutter Web/App communication
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { prompt } = await req.json()

    if (!prompt) {
      throw new Error('Search prompt is required')
    }

    // 1. Call Google Gemini to convert the text into an AI Vector Embedding
    const geminiApiKey = Deno.env.get('GEMINI_API_KEY')
    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${geminiApiKey}`
    
    // Removed the redundant 'model' field from the body since it is already in the URL path
    const embedResponse = await fetch(geminiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: { parts: [{ text: prompt }] }
      })
    })

    const embedData = await embedResponse.json()

    // Surface detailed error messages from Gemini if the request fails
    if (!embedResponse.ok) {
      throw new Error(`Gemini API Error: ${embedData.error?.message || JSON.stringify(embedData)}`)
    }

    const embedding = embedData.embedding?.values

    if (!embedding) {
      throw new Error('Failed to generate AI embedding from Gemini')
    }

    // 2. Initialize Supabase client using built-in environment variables
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 3. Call the Postgres function to find similar meals
    const { data: matchedMeals, error } = await supabase.rpc('match_meals', {
      query_embedding: embedding,
      match_threshold: 0.3, // Lower threshold = broader matches
      match_count: 10
    })

    if (error) throw error

    // 4. Return the AI-matched meals back to Flutter!
    return new Response(
      JSON.stringify({ success: true, meals: matchedMeals }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})