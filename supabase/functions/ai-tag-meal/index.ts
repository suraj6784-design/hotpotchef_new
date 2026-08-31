// supabase/functions/ai-tag-meal/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY') ?? '';

serve(async (req) => {
  try {
    const { title, description } = await req.json();

    if (!title) {
      return new Response(JSON.stringify({ error: 'Meal title is required' }), { status: 400 });
    }

    const prompt = `Analyze the following home-cooked meal dish and return a comma-separated list of applicable health tags from this exact set only: ["High Protein", "Low Sodium", "Keto-Friendly", "Gluten-Free", "Vegan", "Organic", "Low Carb"]. 
    
    Dish Title: ${title}
    Description: ${description ?? 'None'}
    
    Return ONLY the matching tags separated by commas, with no extra text or explanations.`;

    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${GEMINI_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }]
      })
    });

    const data = await response.json();
    const rawTags = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    const tags = rawTags.split(',').map((t: string) => t.trim()).filter(Boolean);

    return new Response(JSON.stringify({ tags }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});