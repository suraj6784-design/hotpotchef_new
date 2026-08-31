import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { prompt } = await req.json()
    if (!prompt) {
      throw new Error('Search prompt is required')
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    let matchedMeals = []

    try {
      // 1. Try Google Gemini AI Vector Embedding Search first
      const geminiApiKey = Deno.env.get('GEMINI_API_KEY')
      const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key=${geminiApiKey}`
      
      const embedResponse = await fetch(geminiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          content: { parts: [{ text: prompt }] }
        })
      })

      const embedData = await embedResponse.json()
      const embedding = embedData.embedding?.values

      if (embedding) {
        // Call Postgres vector match function
        const { data: vectorMeals } = await supabase.rpc('match_meals', {
          query_embedding: embedding,
          match_threshold: 0.1, // Very broad threshold
          match_count: 10
        })
        if (vectorMeals && vectorMeals.length > 0) {
          matchedMeals = vectorMeals
        }
      }
    } catch (aiError) {
      console.error("AI Embedding step failed, falling back to text search:", aiError)
    }

    // 2. Fallback or Secondary Check: Direct Text Search if vector search returned nothing
    if (matchedMeals.length === 0) {
      const searchTerm = `%${prompt.trim()}%`
      const { data: textMeals, error: textError } = await supabase
        .from('meals')
        .select('*')
        .or(`title.ilike.${searchTerm},description.ilike.${searchTerm},category.ilike.${searchTerm}`)
        .limit(10)

      if (!textError && textMeals) {
        matchedMeals = textMeals
      }
    }

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