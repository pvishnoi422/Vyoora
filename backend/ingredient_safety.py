import json
import openai
import os
from dotenv import load_dotenv

# Load your OpenAI API key
load_dotenv()
openai.api_key = os.getenv("OPENAI_API_KEY")

# Load ingredient safety data
with open('ingredient_safety_dataset.json') as f:
    safety_data = json.load(f)

# Fallback to GPT if not found
def gpt_guess_safety(ingredient):
    try:
        prompt = f"What is the skincare safety classification of '{ingredient}'? (Safe, Irritant, Comedogenic, or Unknown)"
        response = openai.ChatCompletion.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.2
        )
        content = response['choices'][0]['message']['content'].lower()
        if 'safe' in content:
            return 'Safe'
        elif 'irritant' in content:
            return 'Irritant'
        elif 'comedogenic' in content:
            return 'Comedogenic'
        else:
            return 'Unknown'
    except Exception as e:
        print(f"⚠️ GPT fallback error for '{ingredient}':", str(e))
        return "Unknown"

# Main safety function
def analyze_ingredient_safety(ingredients):
    result = {}
    for ingredient in ingredients:
        label = safety_data.get(ingredient.lower())
        if label:
            result[ingredient] = label
        else:
            result[ingredient] = gpt_guess_safety(ingredient)
    return result
